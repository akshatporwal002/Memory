\set ON_ERROR_STOP on
begin;
insert into auth.users(id,email) values ('10000000-0000-0000-0000-000000000001','owner@engram.test'),('10000000-0000-0000-0000-000000000002','editor@engram.test'),('10000000-0000-0000-0000-000000000003','viewer@engram.test'),('10000000-0000-0000-0000-000000000004','outsider@engram.test');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
select public.engram_apply('20000000-0000-0000-0000-000000000001','deck','test-deck','test-deck',0,'{"id":"test-deck","name":"Test"}');
select public.engram_apply('20000000-0000-0000-0000-000000000002','note','test-note','test-deck',0,'{"id":"test-note","front":"Question","back":"Answer"}');
select public.engram_apply('20000000-0000-0000-0000-000000000002','note','test-note','test-deck',0,'{"id":"test-note","front":"Question","back":"Answer"}');
select public.engram_apply('20000000-0000-0000-0000-000000000003','private','10000000-0000-0000-0000-000000000001:attempt',null,0,'{"answer":"Private attempt"}');
do $$ begin
 if (select version from public.engram_entities where id='test-note')<>1 then raise exception 'Retry duplicated mutation'; end if;
 if public.engram_apply('20000000-0000-0000-0000-000000000004','note','test-note','test-deck',0,'{}')->>'status'<>'conflict' then raise exception 'Stale version accepted'; end if;
end $$;
reset role;
insert into public.engram_members(deck_id,user_id,role) values('test-deck','10000000-0000-0000-0000-000000000002','editor'),('test-deck','10000000-0000-0000-0000-000000000003','viewer');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
do $$ begin
 if (select count(*) from public.engram_members where deck_id='test-deck')<>2 then raise exception 'Owner cannot inspect members'; end if;
end $$;
reset role;
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}',true);
do $$ begin
 if (select count(*) from public.engram_entities where kind='private')<>0 then raise exception 'Private attempts exposed to editor'; end if;
 if (select count(*) from public.engram_entities where kind='note')<>1 then raise exception 'Editor cannot read deck'; end if;
 if (select count(*) from public.engram_members where deck_id='test-deck')<>1 then raise exception 'Editor sees other memberships'; end if;
end $$;
select public.engram_apply('20000000-0000-0000-0000-000000000005','note','test-note','test-deck',1,'{"id":"test-note","front":"Edited","back":"Answer"}');
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000003","role":"authenticated"}',true);
do $$ begin
 if (select count(*) from public.engram_entities where kind='note')<>1 then raise exception 'Viewer cannot read'; end if;
 begin
   perform public.engram_apply('20000000-0000-0000-0000-000000000006','note','test-note','test-deck',2,'{}');
   raise exception 'Viewer wrote';
 exception when others then if sqlerrm='Viewer wrote' then raise; end if; end;
end $$;
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000004","role":"authenticated"}',true);
do $$ begin
 if (select count(*) from public.engram_entities)<>0 or (select count(*) from public.engram_changes)<>0 then raise exception 'Outsider content exposure'; end if;
end $$;
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
select public.engram_revoke('test-deck','10000000-0000-0000-0000-000000000002');
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}',true);
do $$ begin
 if (select count(*) from public.engram_entities)<>0 then raise exception 'Revoked member still reads'; end if;
 begin
   perform public.engram_apply('20000000-0000-0000-0000-000000000005','note','test-note','test-deck',1,'{"id":"test-note","front":"Edited","back":"Answer"}');
   raise exception 'Revoked retry authorized';
 exception when others then if sqlerrm='Revoked retry authorized' then raise; end if; end;
end $$;
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
do $$ declare invite jsonb; joined text; begin
 invite := public.engram_invite('test-deck','editor',1);
 perform set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000004","role":"authenticated"}',true);
 joined := public.engram_accept(invite->>'token');
 if joined<>'test-deck' then raise exception 'Invitation did not grant deck'; end if;
 perform set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
 perform public.engram_revoke('test-deck',null,(invite->>'id')::uuid);
 perform set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}',true);
 begin
   perform public.engram_accept(invite->>'token'); raise exception 'Revoked invitation accepted';
 exception when others then if sqlerrm='Revoked invitation accepted' then raise; end if; end;
end $$;
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
insert into storage.objects(bucket_id,name) values('engram-private-pdfs','10000000-0000-0000-0000-000000000001/source.pdf');
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000004","role":"authenticated"}',true);
do $$ begin
 if exists(select 1 from storage.objects where bucket_id='engram-private-pdfs') then raise exception 'Shared editor sees original PDF'; end if;
 begin
   insert into storage.objects(bucket_id,name) values('engram-private-pdfs','10000000-0000-0000-0000-000000000001/outsider.pdf'); raise exception 'Editor wrote owner PDF';
 exception when others then if sqlerrm='Editor wrote owner PDF' then raise; end if; end;
end $$;
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
select public.engram_apply('20000000-0000-0000-0000-000000000011','deck','destination-deck','destination-deck',0,'{"id":"destination-deck","name":"Destination"}');
select public.engram_apply('20000000-0000-0000-0000-000000000012','note','moving-note','test-deck',0,'{"id":"moving-note","deckID":"test-deck","front":"Original","back":"Answer"}');
select public.engram_apply('20000000-0000-0000-0000-000000000013','note','moving-note','destination-deck',1,'{"id":"moving-note","deckID":"destination-deck","front":"Destination-private content","back":"Answer"}');
select public.engram_apply('20000000-0000-0000-0000-000000000013','note','moving-note','destination-deck',1,'{"id":"moving-note","deckID":"destination-deck","front":"Destination-private content","back":"Answer"}');
do $$ begin
 if (select version from public.engram_entities where id='moving-note')<>3 then raise exception 'Move retry duplicated mutation'; end if;
end $$;
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000003","role":"authenticated"}',true);
do $$ begin
 if exists(select 1 from public.engram_entities where id='moving-note') then raise exception 'Source-only viewer sees moved question'; end if;
 if exists(select 1 from public.engram_changes where entity_id='moving-note' and payload->>'front'='Destination-private content') then raise exception 'Source-only viewer sees destination content'; end if;
 if not exists(select 1 from public.engram_changes where entity_id='moving-note' and deleted=true) then raise exception 'Source-only viewer did not receive removal'; end if;
end $$;
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
select public.engram_apply('20000000-0000-0000-0000-000000000008','deck','test-deck','test-deck',1,'{"id":"test-deck","name":"Test","deleted":true}',true);
select public.engram_apply('20000000-0000-0000-0000-000000000008','deck','test-deck','test-deck',1,'{"id":"test-deck","name":"Test","deleted":true}',true);
do $$ begin
 if not exists(select 1 from public.engram_entities where id='test-deck' and deleted=true) then raise exception 'Owner tombstone hidden'; end if;
end $$;
select public.engram_apply('20000000-0000-0000-0000-000000000009','deck','test-deck','test-deck',2,'{"id":"test-deck","name":"Restored","deleted":false}',false);
rollback;
select 'Engram permissions and idempotency checks passed' as result;
