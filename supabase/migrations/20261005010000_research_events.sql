-- Pending Engram deployment. Do not apply to another project's database.
-- Research is separate from ordinary library sync and tutor projections.
create table public.engram_research_consent (
  user_id uuid primary key references auth.users(id) on delete cascade,
  metrics boolean not null default false,
  answer_content boolean not null default false,
  revision integer not null check (revision > 0),
  updated_at timestamptz not null default now(),
  check (not answer_content or metrics)
);
create table public.engram_research_events (
  user_id uuid not null references auth.users(id) on delete cascade,
  id uuid not null,
  kind text not null check (kind in ('review','review_corrected','question_activity','answer_submitted','ai_completed','batch_completed','ai_failed','transcript_confirmed','feedback_disputed','math_entry','tutor_activated')),
  occurred_at timestamptz not null,
  answered_at timestamptz,
  review_id text,
  corrected_review_id text,
  received_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '12 months'),
  question_id text,
  attempt_id text,
  question_type text,
  subject text check (length(subject) <= 80),
  question_subtype text check (length(question_subtype) <= 80),
  question_schema_version integer,
  input_modality text,
  grading_method text,
  outcome text,
  rating integer check (rating between 1 and 4),
  estimated_recall double precision check (estimated_recall between 0 and 1),
  duration_ms double precision check (duration_ms between 0 and 86400000),
  first_token_ms double precision check (first_token_ms between 0 and 86400000),
  queue_ms double precision check (queue_ms between 0 and 31536000000),
  input_tokens integer check (input_tokens >= 0),
  output_tokens integer check (output_tokens >= 0),
  cached_tokens integer check (cached_tokens >= 0),
  reasoning_tokens integer check (reasoning_tokens >= 0),
  token_measurement text,
  provider text,
  model text,
  batch_size integer check (batch_size between 1 and 10),
  answer_text text check (length(answer_text) <= 4000),
  consent_revision integer not null,
  primary key (user_id,id),
  check (length(question_type) <= 100 and length(model) <= 300),
  check (length(question_id) <= 100 and length(attempt_id) <= 100)
);
create index engram_research_expiry on public.engram_research_events(expires_at);
create index engram_research_question on public.engram_research_events(user_id, question_id, occurred_at);
alter table public.engram_research_consent enable row level security;
alter table public.engram_research_events enable row level security;
revoke all on public.engram_research_consent, public.engram_research_events from anon, authenticated;
grant select on public.engram_research_consent, public.engram_research_events to authenticated;
create policy research_own_consent on public.engram_research_consent for select to authenticated using (user_id = (select auth.uid()));
create policy research_own_events on public.engram_research_events for select to authenticated using (user_id = (select auth.uid()) and expires_at > now());

create function public.engram_research_ingest(consent jsonb, events jsonb)
returns void language plpgsql security definer set search_path = '' as $$
declare
  owner uuid := auth.uid();
  row jsonb;
  permission public.engram_research_consent;
  metrics boolean := coalesce((consent->>'metrics')::boolean,false);
  content boolean := coalesce((consent->>'answerContent')::boolean,false);
  revision integer := (consent->>'revision')::integer;
begin
  if owner is null or events is null or jsonb_typeof(events) <> 'array' or jsonb_array_length(events) > 100 or revision is null or revision < 1 then
    raise exception 'Invalid research request';
  end if;
  insert into public.engram_research_consent(user_id,metrics,answer_content,revision)
    values(owner,metrics,metrics and content,revision)
    on conflict(user_id) do update set metrics = excluded.metrics, answer_content = excluded.answer_content,
      revision = excluded.revision, updated_at = now()
      where public.engram_research_consent.revision <= excluded.revision;
  select * into permission from public.engram_research_consent where user_id = owner for update;
  if permission.revision <> revision then raise exception 'Stale research consent'; end if;
  if not permission.metrics then
    delete from public.engram_research_events where user_id = owner;
    return;
  end if;
  if not permission.answer_content then update public.engram_research_events set answer_text = null where user_id = owner; end if;
  for row in select value from jsonb_array_elements(events) loop
    -- Fixed projection discards unknown keys; client cannot choose owner or expiry.
    if (row->>'consentRevision')::integer is distinct from revision then raise exception 'Stale event consent'; end if;
    if row->>'occurredAt' is null or
       to_timestamp((row->>'occurredAt')::double precision + 978307200) not between now() - interval '12 months' and now() + interval '5 minutes' then
      raise exception 'Invalid event time';
    end if;
    insert into public.engram_research_events(user_id,id,kind,occurred_at,answered_at,review_id,corrected_review_id,expires_at,question_id,attempt_id,question_type,subject,question_subtype,question_schema_version,input_modality,grading_method,outcome,rating,estimated_recall,duration_ms,first_token_ms,queue_ms,input_tokens,output_tokens,cached_tokens,reasoning_tokens,token_measurement,provider,model,batch_size,answer_text,consent_revision)
    values(owner,(row->>'id')::uuid,row->>'kind',to_timestamp((row->>'occurredAt')::double precision + 978307200),
      case when row->>'answeredAt' is null then null else to_timestamp((row->>'answeredAt')::double precision + 978307200) end,
      left(row->>'reviewID',64),left(row->>'correctedReviewID',64),
      least(now() + interval '12 months',to_timestamp((row->>'occurredAt')::double precision + 978307200) + interval '12 months'),
      row->>'questionID',row->>'attemptID',row->>'questionType',left(row->>'subject',80),left(row->>'questionSubtype',80),(row->>'questionSchemaVersion')::integer,
      left(row->>'inputModality',100),left(row->>'gradingMethod',100),left(row->>'outcome',100),(row->>'rating')::integer,
      (row->>'estimatedRecall')::double precision,(row->>'durationMS')::double precision,(row->>'firstTokenMS')::double precision,(row->>'queueMS')::double precision,
      (row->>'inputTokens')::integer,(row->>'outputTokens')::integer,(row->>'cachedTokens')::integer,(row->>'reasoningTokens')::integer,left(row->>'tokenMeasurement',100),
      left(row->>'provider',100),row->>'model',(row->>'batchSize')::integer,
      case when permission.answer_content then row->>'answerText' else null end,revision)
    on conflict(user_id,id) do nothing;
  end loop;
  delete from public.engram_research_events where user_id = owner and expires_at <= now();
end;
$$;
revoke all on function public.engram_research_ingest(jsonb,jsonb) from public, anon;
grant execute on function public.engram_research_ingest(jsonb,jsonb) to authenticated;

create function public.engram_delete_research()
returns void language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  delete from public.engram_research_events where user_id = auth.uid();
  update public.engram_research_consent set metrics = false, answer_content = false, revision = revision + 1, updated_at = now() where user_id = auth.uid();
end;
$$;
revoke all on function public.engram_delete_research() from public, anon;
grant execute on function public.engram_delete_research() to authenticated;

-- Run via the existing server maintenance scheduler, never through a client.
create function public.engram_research_expire()
returns bigint language plpgsql security definer set search_path = '' as $$
declare removed bigint;
begin
  delete from public.engram_research_events where expires_at <= now();
  get diagnostics removed = row_count;
  return removed;
end;
$$;
revoke all on function public.engram_research_expire() from public, anon, authenticated;
grant execute on function public.engram_research_expire() to service_role;
