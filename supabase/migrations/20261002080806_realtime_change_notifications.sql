-- Realtime only prompts an incremental download; RLS still authorizes each notification.
do $$ begin
 if not exists(select 1 from pg_publication where pubname='supabase_realtime') then
   create publication supabase_realtime;
 end if;
 if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='engram_changes') then
   alter publication supabase_realtime add table public.engram_changes;
 end if;
end $$;
