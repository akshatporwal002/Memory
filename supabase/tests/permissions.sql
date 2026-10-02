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
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}',true);
do $$ begin
 if (select count(*) from public.engram_entities where kind='private')<>0 then raise exception 'Private attempts exposed to editor'; end if;
 if (select count(*) from public.engram_entities where kind='note')<>1 then raise exception 'Editor cannot read deck'; end if;
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
rollback;
select 'Engram permissions and idempotency checks passed' as result;
