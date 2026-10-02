revoke all on schema engram_private from public, anon;
grant usage on schema engram_private to authenticated;
insert into storage.buckets(id,name,public) values('engram-private-pdfs','engram-private-pdfs',false) on conflict(id) do nothing;
create policy pdf_owner_read on storage.objects for select to authenticated using(bucket_id='engram-private-pdfs' and (storage.foldername(name))[1]=(select auth.uid())::text);
create policy pdf_owner_insert on storage.objects for insert to authenticated with check(bucket_id='engram-private-pdfs' and (storage.foldername(name))[1]=(select auth.uid())::text);
create policy pdf_owner_update on storage.objects for update to authenticated using(bucket_id='engram-private-pdfs' and (storage.foldername(name))[1]=(select auth.uid())::text) with check(bucket_id='engram-private-pdfs' and (storage.foldername(name))[1]=(select auth.uid())::text);
create policy pdf_owner_delete on storage.objects for delete to authenticated using(bucket_id='engram-private-pdfs' and (storage.foldername(name))[1]=(select auth.uid())::text);
