-- Additive migration; original id/user_id/content/created_at remain unchanged.
create temporary table memo_preservation_before on commit drop as
 select id,user_id,content,created_at from public.memos;
create table public.folders (
 id uuid primary key default gen_random_uuid(), user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
 name text not null check(char_length(trim(name)) between 1 and 100), sort_order integer not null default 0, created_at timestamptz not null default now(),
 unique(id,user_id),unique(user_id,name)
);
create table public.tags (
 id uuid primary key default gen_random_uuid(),user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
 name text not null check(char_length(trim(name)) between 1 and 50),created_at timestamptz not null default now(),unique(id,user_id),unique(user_id,name)
);
alter table public.memos add column title text not null default '' check(char_length(title)<=150),
 add column folder_id uuid,add column color text not null default 'sage' check(color in ('sage','sand','blue','rose')),
 add column is_pinned boolean not null default false,add column is_favorite boolean not null default false,
 add column updated_at timestamptz not null default now(),add column archived_at timestamptz,add column deleted_at timestamptz,
 add column version integer not null default 1,add constraint memos_id_owner_unique unique(id,user_id),
 add constraint memos_folder_owner_fk foreign key(folder_id,user_id) references public.folders(id,user_id) on delete set null(folder_id);
alter table public.memos drop constraint memos_content_check;
alter table public.memos add constraint memos_content_check check(char_length(trim(content)) between 1 and 20000);
create table public.memo_tags (
 memo_id uuid not null,tag_id uuid not null,user_id uuid not null default auth.uid(),primary key(memo_id,tag_id),
 foreign key(memo_id,user_id) references public.memos(id,user_id) on delete cascade,
 foreign key(tag_id,user_id) references public.tags(id,user_id) on delete cascade
);
create table public.tasks (
 id uuid primary key default gen_random_uuid(),user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
 memo_id uuid,title text not null check(char_length(trim(title)) between 1 and 500),due_date date,
 is_completed boolean not null default false,completed_at timestamptz,sort_order integer not null default 0,
 created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 foreign key(memo_id,user_id) references public.memos(id,user_id) on delete cascade
);
create policy "Users can update own memos" on public.memos for update to authenticated
 using((select auth.uid())=user_id) with check((select auth.uid())=user_id);
do $$ declare t text; begin
 foreach t in array array['folders','tags','memo_tags','tasks'] loop
 execute format('alter table public.%I enable row level security',t);
 execute format('create policy owner_access on public.%I for all to authenticated using ((select auth.uid())=user_id) with check ((select auth.uid())=user_id)',t);
 execute format('revoke all on public.%I from anon',t);
 execute format('grant select,insert,update,delete on public.%I to authenticated',t);
 end loop;
end $$;
create index memos_owner_updated_idx on public.memos(user_id,updated_at desc);
create index memos_folder_owner_idx on public.memos(folder_id,user_id);
create index memo_tags_tag_owner_idx on public.memo_tags(tag_id,user_id);
create index memo_tags_owner_idx on public.memo_tags(user_id);
create index tasks_owner_due_idx on public.tasks(user_id,due_date);
create index tasks_memo_owner_idx on public.tasks(memo_id,user_id);
-- Caller privileges and RLS apply; optimistic version check and tag changes are atomic.
create function public.save_memo_v2(p_id uuid,p_version integer,p_title text,p_content text,p_folder_id uuid,p_color text,p_pinned boolean,p_favorite boolean,p_archived timestamptz,p_deleted timestamptz,p_tags text[])
returns jsonb language plpgsql security invoker set search_path='' as $$
declare saved public.memos; tag_name text; tag_uuid uuid; begin
 if auth.uid() is null then raise exception 'Login required';end if;
 if coalesce(array_length(p_tags,1),0)>20 then raise exception 'Too many tags';end if;
 if p_version=0 then
 insert into public.memos(id,user_id,title,content,folder_id,color,is_pinned,is_favorite,archived_at,deleted_at)
 values(p_id,auth.uid(),p_title,p_content,p_folder_id,p_color,p_pinned,p_favorite,p_archived,p_deleted) returning * into saved;
 else
 update public.memos set title=p_title,content=p_content,folder_id=p_folder_id,color=p_color,is_pinned=p_pinned,is_favorite=p_favorite,
 archived_at=p_archived,deleted_at=p_deleted,version=version+1,updated_at=now()
 where id=p_id and user_id=auth.uid() and version=p_version returning * into saved;
 if not found then raise exception '다른 창에서 수정되었습니다. 내용을 복사한 후 새로고침해 주세요.' using errcode='40001';end if;
 end if;
 delete from public.memo_tags where memo_id=p_id and user_id=auth.uid();
 foreach tag_name in array coalesce(p_tags,array[]::text[]) loop
 tag_name:=trim(tag_name);if tag_name='' then continue;end if;
 insert into public.tags(user_id,name) values(auth.uid(),tag_name) on conflict(user_id,name) do update set name=excluded.name returning id into tag_uuid;
 insert into public.memo_tags(memo_id,tag_id,user_id) values(p_id,tag_uuid,auth.uid()) on conflict do nothing;
 end loop;
 return to_jsonb(saved);
end $$;
revoke all on function public.save_memo_v2(uuid,integer,text,text,uuid,text,boolean,boolean,timestamptz,timestamptz,text[]) from public,anon;
grant execute on function public.save_memo_v2(uuid,integer,text,text,uuid,text,boolean,boolean,timestamptz,timestamptz,text[]) to authenticated;
do $$ begin
 if exists(select id,user_id,content,created_at from memo_preservation_before except select id,user_id,content,created_at from public.memos)
 or (select count(*) from memo_preservation_before)<>(select count(*) from public.memos)
 then raise exception 'Existing memo preservation failed';end if;
end $$;
