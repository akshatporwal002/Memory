create or replace function public.engram_apply(operation_id uuid, entity_kind text, entity_id text, target_deck text, base_version bigint, content jsonb, is_deleted boolean default false) returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid := auth.uid(); current_row public.engram_entities; prior engram_private.operations; result jsonb; request jsonb; next_version bigint;
begin
 if actor is null then raise exception 'Authentication required'; end if;
 if entity_kind not in ('deck','note','private') or entity_id='' or octet_length(content::text)>2000000 then raise exception 'Invalid entity'; end if;
 if entity_kind='private' then
   if entity_id not like actor::text || ':%' or target_deck is not null then raise exception 'Private scope mismatch'; end if;
 else
   if target_deck is null then raise exception 'Deck required'; end if;
   if entity_kind='deck' and entity_id<>target_deck then raise exception 'Deck ID mismatch'; end if;
   if entity_kind='deck' and not exists(select 1 from public.engram_decks where id=target_deck) then
     if base_version<>0 then raise exception 'Unknown deck'; end if;
     insert into public.engram_decks(id,owner_id) values(target_deck,actor);
   end if;
   if not engram_private.can_access(target_deck,true) and not exists(select 1 from public.engram_decks where id=target_deck and owner_id=actor) then raise exception 'Editor permission required'; end if;
   if is_deleted and entity_kind='deck' and not exists(select 1 from public.engram_decks where id=target_deck and owner_id=actor) then raise exception 'Owner permission required'; end if;
   -- Shared payloads have an explicit allowlist; original/extracted PDF records stay private.
   if entity_kind='deck' and content - array['id','name','deleted','createdAt','modifiedAt','sourceDocument','notebookBlocks','documentFormatVersion','desiredRetention'] <> '{}'::jsonb then raise exception 'Unsupported shared deck fields'; end if;
   if entity_kind='note' and content - array['id','deckID','kind','front','back','tags','source','deleted','modifiedAt','multipleChoice'] <> '{}'::jsonb then raise exception 'Unsupported shared question fields'; end if;
 end if;
 -- Serialize duplicate operation IDs and concurrent first inserts before checking versions.
 perform pg_advisory_xact_lock(hashtextextended(actor::text || operation_id::text,0));
 perform pg_advisory_xact_lock(hashtextextended(entity_kind || ':' || entity_id,1));
 request := jsonb_build_object('kind',entity_kind,'id',entity_id,'deck',target_deck,'base',base_version,'content',content,'deleted',is_deleted);
 select * into prior from engram_private.operations where user_id=actor and operations.operation_id=engram_apply.operation_id;
 if found then
   if prior.request<>request then raise exception 'Operation ID reused with different content'; end if;
   return prior.result;
 end if;
 select * into current_row from public.engram_entities where kind=entity_kind and id=entity_id for update;
 if found and entity_kind='private' and current_row.learner_id<>actor then raise exception 'Private scope mismatch'; end if;
 if found and current_row.deck_id is distinct from target_deck then
   if entity_kind<>'note' or not engram_private.can_access(current_row.deck_id,true) then raise exception 'Editor permission required in both decks'; end if;
 end if;
 if coalesce(current_row.version,0)<>base_version then
   return jsonb_build_object('status','conflict','version',current_row.version,'payload',current_row.payload,'deleted',current_row.deleted);
 end if;
 next_version := base_version+1;
 if entity_kind='note' and current_row.id is not null and current_row.deck_id is distinct from target_deck then
   -- Old members receive only removal from their deck, never the destination's content.
   insert into public.engram_changes(kind,entity_id,deck_id,version,payload,deleted)
   values('note',entity_id,current_row.deck_id,next_version,jsonb_set(current_row.payload,'{deleted}','true'::jsonb),true);
   next_version := next_version+1;
 end if;
 insert into public.engram_entities(id,kind,deck_id,learner_id,version,payload,deleted) values(entity_id,entity_kind,target_deck,case when entity_kind='private' then actor end,next_version,content,is_deleted)
 on conflict(kind,id) do update set deck_id=excluded.deck_id,version=excluded.version,payload=excluded.payload,deleted=excluded.deleted;
 insert into public.engram_changes(kind,entity_id,deck_id,learner_id,version,payload,deleted) values(entity_kind,entity_id,target_deck,case when entity_kind='private' then actor end,next_version,content,is_deleted);
 if entity_kind='deck' then update public.engram_decks set deleted=is_deleted where id=target_deck; end if;
 result := jsonb_build_object('status','saved','version',next_version);
 insert into engram_private.operations(user_id,operation_id,request,result) values(actor,engram_apply.operation_id,request,result);
 return result;
end $$;
