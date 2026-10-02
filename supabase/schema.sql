-- Development schema. Apply locally, test permissions, then generate the deployment migration with the CLI.
create schema if not exists engram_private;
revoke all on schema engram_private from public, anon;
grant usage on schema engram_private to authenticated;
create table public.engram_decks(id text primary key, owner_id uuid not null references auth.users(id), deleted boolean not null default false);
create table public.engram_members(deck_id text references public.engram_decks(id), user_id uuid references auth.users(id), role text not null check(role in ('viewer','editor')), primary key(deck_id,user_id));
create index on public.engram_members(user_id);
create table public.engram_entities(id text not null, kind text not null check(kind in ('deck','note','private')), deck_id text references public.engram_decks(id), learner_id uuid references auth.users(id), version bigint not null, payload jsonb not null, deleted boolean not null default false, primary key(kind,id), check((kind='private' and learner_id is not null and deck_id is null) or (kind<>'private' and deck_id is not null and learner_id is null)));
create index on public.engram_entities(deck_id);
create index on public.engram_entities(learner_id);
create table public.engram_changes(sequence bigint generated always as identity primary key, kind text not null, entity_id text not null, deck_id text, learner_id uuid, version bigint not null, payload jsonb not null, deleted boolean not null);
create index on public.engram_changes(deck_id,sequence);
create index on public.engram_changes(learner_id,sequence);
create table engram_private.operations(user_id uuid not null, operation_id uuid not null, request jsonb not null, result jsonb not null, primary key(user_id,operation_id));
create table engram_private.invitations(id uuid primary key default gen_random_uuid(), deck_id text not null references public.engram_decks(id), digest text unique not null, role text not null check(role in ('viewer','editor')), expires_at timestamptz not null, revoked boolean not null default false);
alter table public.engram_decks enable row level security;
alter table public.engram_members enable row level security;
alter table public.engram_entities enable row level security;
alter table public.engram_changes enable row level security;
alter table engram_private.operations enable row level security;
alter table engram_private.invitations enable row level security;

-- Membership is evaluated in the database on every operation, never from user-editable JWT metadata.
create function engram_private.can_access(target text, editing boolean default false) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.engram_decks d where d.id=target and not d.deleted and (d.owner_id=auth.uid() or exists(select 1 from public.engram_members m where m.deck_id=d.id and m.user_id=auth.uid() and (not editing or m.role='editor'))));
$$;
revoke all on function engram_private.can_access(text,boolean) from public,anon;
grant execute on function engram_private.can_access(text,boolean) to authenticated;
create policy decks_read on public.engram_decks for select to authenticated using(owner_id=(select auth.uid()) or engram_private.can_access(id));
create policy members_read on public.engram_members for select to authenticated using(user_id=(select auth.uid()) or exists(select 1 from public.engram_decks d where d.id=deck_id and d.owner_id=(select auth.uid())));
create policy entities_read on public.engram_entities for select to authenticated using(learner_id=(select auth.uid()) or engram_private.can_access(deck_id) or exists(select 1 from public.engram_decks d where d.id=deck_id and d.owner_id=(select auth.uid())));
create policy changes_read on public.engram_changes for select to authenticated using(learner_id=(select auth.uid()) or engram_private.can_access(deck_id) or exists(select 1 from public.engram_decks d where d.id=deck_id and d.owner_id=(select auth.uid())));
revoke all on public.engram_decks,public.engram_members,public.engram_entities,public.engram_changes from anon,authenticated;
grant select on public.engram_decks,public.engram_members,public.engram_entities,public.engram_changes to authenticated;

-- All writes use the idempotent CAS boundary. Direct table writes are unavailable to app credentials.
create function public.engram_apply(operation_id uuid, entity_kind text, entity_id text, target_deck text, base_version bigint, content jsonb, is_deleted boolean default false) returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid := auth.uid(); current_row public.engram_entities; prior engram_private.operations; result jsonb; request jsonb;
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
 if found and (current_row.deck_id is distinct from target_deck or (entity_kind='private' and current_row.learner_id<>actor)) then raise exception 'Entity cannot change scope'; end if;
 if coalesce(current_row.version,0)<>base_version then
   return jsonb_build_object('status','conflict','version',current_row.version,'payload',current_row.payload,'deleted',current_row.deleted);
 end if;
 insert into public.engram_entities(id,kind,deck_id,learner_id,version,payload,deleted) values(entity_id,entity_kind,target_deck,case when entity_kind='private' then actor end,base_version+1,content,is_deleted)
 on conflict(kind,id) do update set version=excluded.version,payload=excluded.payload,deleted=excluded.deleted;
 insert into public.engram_changes(kind,entity_id,deck_id,learner_id,version,payload,deleted) values(entity_kind,entity_id,target_deck,case when entity_kind='private' then actor end,base_version+1,content,is_deleted);
 if entity_kind='deck' then update public.engram_decks set deleted=is_deleted where id=target_deck; end if;
 result := jsonb_build_object('status','saved','version',base_version+1);
 insert into engram_private.operations(user_id,operation_id,request,result) values(actor,engram_apply.operation_id,request,result);
 return result;
end $$;
revoke all on function public.engram_apply(uuid,text,text,text,bigint,jsonb,boolean) from public,anon;
grant execute on function public.engram_apply(uuid,text,text,text,bigint,jsonb,boolean) to authenticated;

create function public.engram_invite(target_deck text, member_role text, valid_hours integer default 168) returns jsonb language plpgsql security definer set search_path='' as $$
declare secret text := encode(extensions.gen_random_bytes(32),'hex'); invitation uuid;
begin
 if not exists(select 1 from public.engram_decks where id=target_deck and owner_id=auth.uid() and not deleted) then raise exception 'Owner permission required'; end if;
 if member_role not in ('viewer','editor') or valid_hours not between 1 and 168 then raise exception 'Invalid invitation'; end if;
 insert into engram_private.invitations(deck_id,digest,role,expires_at) values(target_deck,encode(extensions.digest(secret,'sha256'),'hex'),member_role,now()+make_interval(hours=>valid_hours)) returning id into invitation;
 return jsonb_build_object('id',invitation,'token',secret);
end $$;
create function public.engram_accept(invitation_token text) returns text language plpgsql security definer set search_path='' as $$
declare invitation engram_private.invitations;
begin
 if auth.uid() is null then raise exception 'Authentication required'; end if;
 select * into invitation from engram_private.invitations where digest=encode(extensions.digest(invitation_token,'sha256'),'hex') and not revoked and expires_at>now() for update;
 if not found or not exists(select 1 from public.engram_decks where id=invitation.deck_id and not deleted) then raise exception 'Invitation expired or revoked'; end if;
 if exists(select 1 from public.engram_decks where id=invitation.deck_id and owner_id=auth.uid()) then return invitation.deck_id; end if;
 insert into public.engram_members(deck_id,user_id,role) values(invitation.deck_id,auth.uid(),invitation.role) on conflict(deck_id,user_id) do update set role=excluded.role;
 return invitation.deck_id;
end $$;
create function public.engram_revoke(target_deck text, member_user uuid default null, invitation_id uuid default null) returns void language plpgsql security definer set search_path='' as $$
begin
 if not exists(select 1 from public.engram_decks where id=target_deck and owner_id=auth.uid()) then raise exception 'Owner permission required'; end if;
 if member_user is not null then delete from public.engram_members where deck_id=target_deck and user_id=member_user; end if;
 if invitation_id is not null then update engram_private.invitations set revoked=true where deck_id=target_deck and id=invitation_id; end if;
end $$;
revoke all on function public.engram_invite(text,text,integer),public.engram_accept(text),public.engram_revoke(text,uuid,uuid) from public,anon;
grant execute on function public.engram_invite(text,text,integer),public.engram_accept(text),public.engram_revoke(text,uuid,uuid) to authenticated;

insert into storage.buckets(id,name,public) values('engram-private-pdfs','engram-private-pdfs',false) on conflict(id) do nothing;
create policy pdf_owner_read on storage.objects for select to authenticated using(bucket_id='engram-private-pdfs' and (storage.foldername(name))[1]=(select auth.uid())::text);
create policy pdf_owner_insert on storage.objects for insert to authenticated with check(bucket_id='engram-private-pdfs' and (storage.foldername(name))[1]=(select auth.uid())::text);
create policy pdf_owner_update on storage.objects for update to authenticated using(bucket_id='engram-private-pdfs' and (storage.foldername(name))[1]=(select auth.uid())::text) with check(bucket_id='engram-private-pdfs' and (storage.foldername(name))[1]=(select auth.uid())::text);
create policy pdf_owner_delete on storage.objects for delete to authenticated using(bucket_id='engram-private-pdfs' and (storage.foldername(name))[1]=(select auth.uid())::text);
