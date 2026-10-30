begin;
select set_config('test.a',gen_random_uuid()::text,true),set_config('test.b',gen_random_uuid()::text,true),set_config('test.memo',gen_random_uuid()::text,true),set_config('test.folder',gen_random_uuid()::text,true);
insert into auth.users(id) values(current_setting('test.a')::uuid),(current_setting('test.b')::uuid);
set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('test.a'),true);
insert into public.folders(id,name) values(current_setting('test.folder')::uuid,'TEST_A');
select public.save_memo_v2(current_setting('test.memo')::uuid,0,'TEST_A','test body',current_setting('test.folder')::uuid,'sage',false,false,null,null,array['test-tag']);
select public.save_memo_v2(current_setting('test.memo')::uuid,1,'TEST_A updated','test body',current_setting('test.folder')::uuid,'sage',false,false,null,null,array['test-tag']);
do $$ begin
 if (select version from public.memos where id=current_setting('test.memo')::uuid)<>2 then raise exception 'version failed';end if;
 begin
 perform public.save_memo_v2(current_setting('test.memo')::uuid,1,'stale','stale',null,'sage',false,false,null,null,array[]::text[]);
 raise exception 'stale write allowed';
 exception when serialization_failure then null;end;
end $$;
select set_config('request.jwt.claim.sub',current_setting('test.b'),true);
do $$ declare n integer; begin
 if exists(select 1 from public.memos where id=current_setting('test.memo')::uuid) then raise exception 'read leak';end if;
 update public.memos set content='attack' where id=current_setting('test.memo')::uuid;get diagnostics n=row_count;if n<>0 then raise exception 'update leak';end if;
 delete from public.memos where id=current_setting('test.memo')::uuid;get diagnostics n=row_count;if n<>0 then raise exception 'delete leak';end if;
 begin
 insert into public.memos(content,folder_id) values('cross owner',current_setting('test.folder')::uuid);
 raise exception 'cross owner link allowed';exception when foreign_key_violation then null;end;
 begin
 insert into public.tasks(title,memo_id) values('cross task',current_setting('test.memo')::uuid);
 raise exception 'cross owner task allowed';exception when foreign_key_violation then null;end;
 begin
 insert into public.memos(content,user_id) values('spoofed',current_setting('test.a')::uuid);
 raise exception 'spoof allowed';exception when insufficient_privilege then null;end;
end $$;
set local role anon;
do $$ begin
 begin
 if exists(select 1 from public.memos) then raise exception 'anonymous leak';end if;
 exception when insufficient_privilege then null;end;
end $$;
rollback;
select 'PASS: own CRUD, version conflict, cross-user read/update/delete, folder/task ownership, owner spoof, anon access; test data rolled back' as result;
