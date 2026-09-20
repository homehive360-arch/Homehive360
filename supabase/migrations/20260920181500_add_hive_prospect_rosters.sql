-- Prospective Hive rosters let operators construct a Hive from Directory candidates
-- without treating selection or invitation as active Hive membership.
create table if not exists public.hive_prospects (
 id uuid primary key default gen_random_uuid(),
 hive_id uuid not null references public.hives(id) on delete cascade,
 business_id uuid not null references public.businesses(id) on delete cascade,
 category text not null,
 roster_state text not null default 'prospective' check(roster_state in('prospective','invited','accepted','declined')),
 invited_at timestamptz,
 accepted_at timestamptz,
 declined_at timestamptz,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(hive_id,business_id),
 unique(hive_id,category)
);

create index if not exists hive_prospects_hive_state_idx on public.hive_prospects(hive_id,roster_state,category);

alter table public.hive_prospects enable row level security;

create policy "active hive admins can view prospects" on public.hive_prospects
for select to authenticated using(exists(
 select 1 from public.hive_members hm
 join public.business_users bu on bu.business_id=hm.business_id
 where hm.hive_id=hive_prospects.hive_id
  and hm.status='active'
  and bu.user_id=(select auth.uid())
  and bu.role in('owner','admin')
));

create or replace function public.set_hive_prospect(
 p_hive_id uuid,
 p_business_id uuid,
 p_category text
) returns public.hive_prospects
language plpgsql security definer set search_path=''
as $function$
declare v public.hive_prospects;
begin
 if nullif(trim(p_category),'') is null then raise exception 'Category is required'; end if;
 if not exists(
  select 1 from public.hive_members hm
  join public.business_users bu on bu.business_id=hm.business_id
  where hm.hive_id=p_hive_id and hm.status='active'
   and bu.user_id=(select auth.uid()) and bu.role in('owner','admin')
 ) then raise exception 'Not authorized to build this Hive'; end if;
 if not exists(select 1 from public.businesses where id=p_business_id)
 then raise exception 'Business not found'; end if;
 if exists(select 1 from public.hive_members where hive_id=p_hive_id and business_id=p_business_id and status='active')
 then raise exception 'Business is already an active Hive member'; end if;

 insert into public.hive_prospects(hive_id,business_id,category)
 values(p_hive_id,p_business_id,trim(p_category))
 on conflict(hive_id,business_id) do update set
  category=excluded.category,updated_at=now()
 returning * into v;
 return v;
end
$function$;

revoke all on function public.set_hive_prospect(uuid,uuid,text) from public,anon;
grant execute on function public.set_hive_prospect(uuid,uuid,text) to authenticated;

create or replace function public.remove_hive_prospect(p_hive_id uuid,p_business_id uuid)
returns void language plpgsql security definer set search_path=''
as $function$
begin
 if not exists(
  select 1 from public.hive_members hm
  join public.business_users bu on bu.business_id=hm.business_id
  where hm.hive_id=p_hive_id and hm.status='active'
   and bu.user_id=(select auth.uid()) and bu.role in('owner','admin')
 ) then raise exception 'Not authorized to build this Hive'; end if;
 delete from public.hive_prospects where hive_id=p_hive_id and business_id=p_business_id and roster_state='prospective';
end
$function$;

revoke all on function public.remove_hive_prospect(uuid,uuid) from public,anon;
grant execute on function public.remove_hive_prospect(uuid,uuid) to authenticated;
