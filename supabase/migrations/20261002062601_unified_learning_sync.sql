SET local check_function_bodies = off;

CREATE SCHEMA "engram_private";

CREATE TABLE "engram_private"."invitations" (
  "id"         uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "deck_id"    text                     NOT NULL,
  "digest"     text                     NOT NULL,
  "role"       text                     NOT NULL,
  "expires_at" timestamp with time zone NOT NULL,
  "revoked"    boolean                  NOT NULL DEFAULT false,
  CONSTRAINT "invitations_digest_key" UNIQUE (digest),
  CONSTRAINT "invitations_pkey" PRIMARY KEY (id),
  CONSTRAINT "invitations_role_check" CHECK ((role = ANY (ARRAY['viewer'::text, 'editor'::text])))
);

ALTER TABLE "engram_private"."invitations"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "engram_private"."operations" (
  "user_id"      uuid  NOT NULL,
  "operation_id" uuid  NOT NULL,
  "request"      jsonb NOT NULL,
  "result"       jsonb NOT NULL,
  CONSTRAINT "operations_pkey" PRIMARY KEY (user_id, operation_id)
);

ALTER TABLE "engram_private"."operations"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "public"."engram_changes" (
  "sequence"   bigint  GENERATED ALWAYS AS IDENTITY NOT NULL,
  "kind"       text    NOT NULL,
  "entity_id"  text    NOT NULL,
  "deck_id"    text,
  "learner_id" uuid,
  "version"    bigint  NOT NULL,
  "payload"    jsonb   NOT NULL,
  "deleted"    boolean NOT NULL,
  CONSTRAINT "engram_changes_pkey" PRIMARY KEY (SEQUENCE)
);

ALTER TABLE "public"."engram_changes"
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."engram_changes" FROM "anon";

CREATE TABLE "public"."engram_decks" (
  "id"       text    NOT NULL,
  "owner_id" uuid    NOT NULL,
  "deleted"  boolean NOT NULL DEFAULT false,
  CONSTRAINT "engram_decks_pkey" PRIMARY KEY (id)
);

ALTER TABLE "public"."engram_decks"
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."engram_decks" FROM "anon";

CREATE TABLE "public"."engram_entities" (
  "id"         text    NOT NULL,
  "kind"       text    NOT NULL,
  "deck_id"    text,
  "learner_id" uuid,
  "version"    bigint  NOT NULL,
  "payload"    jsonb   NOT NULL,
  "deleted"    boolean NOT NULL DEFAULT false,
  CONSTRAINT "engram_entities_check" CHECK ((((kind = 'private'::text) AND (learner_id IS NOT NULL) AND (deck_id IS NULL)) OR ((kind <> 'private'::text) AND (deck_id IS
    NOT NULL) AND (learner_id IS NULL)))),
  CONSTRAINT "engram_entities_kind_check" CHECK ((kind = ANY (ARRAY['deck'::text, 'note'::text, 'private'::text]))),
  CONSTRAINT "engram_entities_pkey" PRIMARY KEY (kind, id)
);

ALTER TABLE "public"."engram_entities"
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."engram_entities" FROM "anon";

CREATE TABLE "public"."engram_members" (
  "deck_id" text NOT NULL,
  "user_id" uuid NOT NULL,
  "role"    text NOT NULL,
  CONSTRAINT "engram_members_pkey" PRIMARY KEY (deck_id, user_id),
  CONSTRAINT "engram_members_role_check" CHECK ((role = ANY (ARRAY['viewer'::text, 'editor'::text])))
);

ALTER TABLE "public"."engram_members"
  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE "public"."engram_members" FROM "anon";

CREATE OR REPLACE FUNCTION engram_private.can_access (
  target  text,
  editing boolean DEFAULT false
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
 select exists(select 1 from public.engram_decks d where d.id=target and not d.deleted and (d.owner_id=auth.uid() or exists(select 1 from public.engram_members m where m.deck_id=d.id and m.user_id=auth.uid() and (not editing or m.role='editor'))));
$function$;

CREATE OR REPLACE FUNCTION public.engram_accept (
  invitation_token text
)
  RETURNS text
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare invitation engram_private.invitations;
begin
 if auth.uid() is null then raise exception 'Authentication required'; end if;
 select * into invitation from engram_private.invitations where digest=encode(extensions.digest(invitation_token,'sha256'),'hex') and not revoked and expires_at>now() for update;
 if not found or not exists(select 1 from public.engram_decks where id=invitation.deck_id and not deleted) then raise exception 'Invitation expired or revoked'; end if;
 if exists(select 1 from public.engram_decks where id=invitation.deck_id and owner_id=auth.uid()) then return invitation.deck_id; end if;
 insert into public.engram_members(deck_id,user_id,role) values(invitation.deck_id,auth.uid(),invitation.role) on conflict(deck_id,user_id) do update set role=excluded.role;
 return invitation.deck_id;
end $function$;

REVOKE ALL ON FUNCTION "public"."engram_accept"(text) FROM PUBLIC, "anon";

CREATE OR REPLACE FUNCTION public.engram_apply (
  operation_id uuid,
  entity_kind  text,
  entity_id    text,
  target_deck  text,
  base_version bigint,
  content      jsonb,
  is_deleted   boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
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
   if not engram_private.can_access(target_deck,true) then raise exception 'Editor permission required'; end if;
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
 if entity_kind='deck' and is_deleted then update public.engram_decks set deleted=true where id=target_deck; end if;
 result := jsonb_build_object('status','saved','version',base_version+1);
 insert into engram_private.operations(user_id,operation_id,request,result) values(actor,engram_apply.operation_id,request,result);
 return result;
end $function$;

REVOKE ALL ON FUNCTION "public"."engram_apply"(uuid, text, text, text, bigint, jsonb, boolean) FROM PUBLIC, "anon";

CREATE OR REPLACE FUNCTION public.engram_invite (
  target_deck text,
  member_role text,
  valid_hours integer DEFAULT 168
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare secret text := encode(extensions.gen_random_bytes(32),'hex'); invitation uuid;
begin
 if not exists(select 1 from public.engram_decks where id=target_deck and owner_id=auth.uid() and not deleted) then raise exception 'Owner permission required'; end if;
 if member_role not in ('viewer','editor') or valid_hours not between 1 and 168 then raise exception 'Invalid invitation'; end if;
 insert into engram_private.invitations(deck_id,digest,role,expires_at) values(target_deck,encode(extensions.digest(secret,'sha256'),'hex'),member_role,now()+make_interval(hours=>valid_hours)) returning id into invitation;
 return jsonb_build_object('id',invitation,'token',secret);
end $function$;

REVOKE ALL ON FUNCTION "public"."engram_invite"(text, text, integer) FROM PUBLIC, "anon";

CREATE OR REPLACE FUNCTION public.engram_revoke (
  target_deck   text,
  member_user   uuid DEFAULT NULL::uuid,
  invitation_id uuid DEFAULT NULL::uuid
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
 if not exists(select 1 from public.engram_decks where id=target_deck and owner_id=auth.uid()) then raise exception 'Owner permission required'; end if;
 if member_user is not null then delete from public.engram_members where deck_id=target_deck and user_id=member_user; end if;
 if invitation_id is not null then update engram_private.invitations set revoked=true where deck_id=target_deck and id=invitation_id; end if;
end $function$;

REVOKE ALL ON FUNCTION "public"."engram_revoke"(text, uuid, uuid) FROM PUBLIC, "anon";

ALTER TABLE "public"."engram_decks"
  ADD CONSTRAINT "engram_decks_owner_id_fkey" FOREIGN KEY (owner_id) REFERENCES auth.users(id);

ALTER TABLE "engram_private"."invitations"
  ADD CONSTRAINT "invitations_deck_id_fkey" FOREIGN KEY (deck_id) REFERENCES public.engram_decks(id);

ALTER TABLE "public"."engram_entities"
  ADD CONSTRAINT "engram_entities_deck_id_fkey" FOREIGN KEY (deck_id) REFERENCES public.engram_decks(id);

ALTER TABLE "public"."engram_entities"
  ADD CONSTRAINT "engram_entities_learner_id_fkey" FOREIGN KEY (learner_id) REFERENCES auth.users(id);

ALTER TABLE "public"."engram_members"
  ADD CONSTRAINT "engram_members_deck_id_fkey" FOREIGN KEY (deck_id) REFERENCES public.engram_decks(id);

ALTER TABLE "public"."engram_members"
  ADD CONSTRAINT "engram_members_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id);

CREATE INDEX engram_changes_deck_id_sequence_idx ON public.engram_changes USING btree (deck_id, SEQUENCE);

CREATE INDEX engram_changes_learner_id_sequence_idx ON public.engram_changes USING btree (learner_id, SEQUENCE);

CREATE INDEX engram_entities_deck_id_idx ON public.engram_entities USING btree (deck_id);

CREATE INDEX engram_entities_learner_id_idx ON public.engram_entities USING btree (learner_id);

CREATE INDEX engram_members_user_id_idx ON public.engram_members USING btree (user_id);

CREATE POLICY "changes_read" ON "public"."engram_changes"
  FOR SELECT
  TO "authenticated"
  USING (((learner_id = ( SELECT auth.uid() AS uid)) OR engram_private.can_access(deck_id)));

CREATE POLICY "decks_read" ON "public"."engram_decks"
  FOR SELECT
  TO "authenticated"
  USING (((owner_id = ( SELECT auth.uid() AS uid)) OR engram_private.can_access(id)));

CREATE POLICY "entities_read" ON "public"."engram_entities"
  FOR SELECT
  TO "authenticated"
  USING (((learner_id = ( SELECT auth.uid() AS uid)) OR engram_private.can_access(deck_id)));

CREATE POLICY "members_read" ON "public"."engram_members"
  FOR SELECT
  TO "authenticated"
  USING (((user_id = ( SELECT auth.uid() AS uid)) OR (EXISTS ( SELECT 1
   FROM public.engram_decks d
  WHERE ((d.id = engram_members.deck_id) AND (d.owner_id = ( SELECT auth.uid() AS uid)))))));

REVOKE ALL ON FUNCTION "engram_private"."can_access"(text, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "engram_private"."can_access"(text, boolean) TO "authenticated";

GRANT EXECUTE ON FUNCTION "public"."engram_accept"(text) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."engram_accept"(text) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."engram_accept"(text) TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."engram_accept"(text) TO "service_role";

GRANT EXECUTE ON FUNCTION "public"."engram_apply"(uuid, text, text, text, bigint, jsonb, boolean) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."engram_apply"(uuid, text, text, text, bigint, jsonb, boolean) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."engram_apply"(uuid, text, text, text, bigint, jsonb, boolean) TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."engram_apply"(uuid, text, text, text, bigint, jsonb, boolean) TO "service_role";

GRANT EXECUTE ON FUNCTION "public"."engram_invite"(text, text, integer) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."engram_invite"(text, text, integer) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."engram_invite"(text, text, integer) TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."engram_invite"(text, text, integer) TO "service_role";

GRANT EXECUTE ON FUNCTION "public"."engram_revoke"(text, uuid, uuid) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."engram_revoke"(text, uuid, uuid) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."engram_revoke"(text, uuid, uuid) TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."engram_revoke"(text, uuid, uuid) TO "service_role";

GRANT USAGE ON SCHEMA "engram_private" TO "authenticated";

REVOKE ALL ON SEQUENCE "public"."engram_changes_sequence_seq" FROM "anon";

GRANT SELECT, UPDATE, USAGE ON SEQUENCE "public"."engram_changes_sequence_seq" TO "anon";

REVOKE ALL ON SEQUENCE "public"."engram_changes_sequence_seq" FROM "authenticated";

GRANT SELECT, UPDATE, USAGE ON SEQUENCE "public"."engram_changes_sequence_seq" TO "authenticated";

REVOKE ALL ON SEQUENCE "public"."engram_changes_sequence_seq" FROM "postgres";

GRANT SELECT, UPDATE, USAGE ON SEQUENCE "public"."engram_changes_sequence_seq" TO "postgres";

REVOKE ALL ON SEQUENCE "public"."engram_changes_sequence_seq" FROM "service_role";

GRANT SELECT, UPDATE, USAGE ON SEQUENCE "public"."engram_changes_sequence_seq" TO "service_role";

REVOKE ALL ON TABLE "public"."engram_changes" FROM "authenticated";

GRANT SELECT ON TABLE "public"."engram_changes" TO "authenticated";

REVOKE ALL ON TABLE "public"."engram_changes" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."engram_changes" TO "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."engram_changes" TO "service_role";

REVOKE ALL ON TABLE "public"."engram_decks" FROM "authenticated";

GRANT SELECT ON TABLE "public"."engram_decks" TO "authenticated";

REVOKE ALL ON TABLE "public"."engram_decks" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."engram_decks" TO "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."engram_decks" TO "service_role";

REVOKE ALL ON TABLE "public"."engram_entities" FROM "authenticated";

GRANT SELECT ON TABLE "public"."engram_entities" TO "authenticated";

REVOKE ALL ON TABLE "public"."engram_entities" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."engram_entities" TO "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."engram_entities" TO "service_role";

REVOKE ALL ON TABLE "public"."engram_members" FROM "authenticated";

GRANT SELECT ON TABLE "public"."engram_members" TO "authenticated";

REVOKE ALL ON TABLE "public"."engram_members" FROM "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."engram_members" TO "postgres";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."engram_members" TO "service_role";

