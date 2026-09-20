-- Monthly Hive campaigns coordinate whole-Hive promotion while rotating a
-- featured member and exclusive offer. Customer lists remain source-owned.
create table if not exists public.hive_campaigns (
 id uuid primary key default gen_random_uuid(),
 hive_id uuid not null references public.hives(id) on delete cascade,
 campaign_month date not null,
 name text not null,
 spotlight_business_id uuid not null references public.businesses(id),
 spotlight_offer_id uuid references public.offers(id),
 status text not null default 'draft' check(status in('draft','scheduled','active','completed','cancelled')),
 scheduled_at timestamptz,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(hive_id,campaign_month)
);

create index if not exists hive_campaigns_hive_month_idx on public.hive_campaigns(hive_id,campaign_month desc);

alter table public.hive_campaigns enable row level security;

create policy "members can view hive campaigns" on public.hive_campaigns
for select to authenticated
using(exists(
 select 1 from public.hive_members hm
 join public.business_users bu on bu.business_id=hm.business_id
 where hm.hive_id=hive_campaigns.hive_id and hm.status='active' and bu.user_id=(select auth.uid())
));

create or replace function public.create_monthly_hive_campaign(
 p_hive_id uuid,
 p_campaign_month date,
 p_spotlight_business_id uuid,
 p_spotlight_offer_id uuid default null,
 p_name text default null
) returns uuid
language plpgsql
security definer
set search_path=''
as $function$
declare v_id uuid; v_offer_business uuid; v_offer_status text; v_starts timestamptz; v_ends timestamptz;
begin
 if not exists(
  select 1 from public.hive_members hm join public.business_users bu on bu.business_id=hm.business_id
  where hm.hive_id=p_hive_id and hm.status='active' and bu.user_id=(select auth.uid()) and bu.role in('owner','admin')
 ) then raise exception 'Not authorized to manage this Hive'; end if;
 if not exists(select 1 from public.hive_members where hive_id=p_hive_id and business_id=p_spotlight_business_id and status='active')
 then raise exception 'Spotlight business must be an active Hive member'; end if;
 if p_campaign_month is null then raise exception 'Campaign month is required'; end if;
 if date_trunc('month',p_campaign_month)::date < date_trunc('month',current_date)::date then raise exception 'Campaign month cannot be in the past'; end if;
 if p_spotlight_offer_id is not null then
  select business_id,status,starts_at,ends_at into v_offer_business,v_offer_status,v_starts,v_ends
  from public.offers where id=p_spotlight_offer_id;
  if v_offer_business is distinct from p_spotlight_business_id or v_offer_status is distinct from 'active'
  then raise exception 'Spotlight offer must be an active offer for the spotlight member'; end if;
  -- Offer date validity is intentionally checked against the actual launch time
  -- by set_hive_campaign_status / scheduled activation, not against creation time.
 end if;
 insert into public.hive_campaigns(hive_id,campaign_month,name,spotlight_business_id,spotlight_offer_id)
 values(p_hive_id,date_trunc('month',p_campaign_month)::date,coalesce(nullif(trim(p_name),''),to_char(p_campaign_month,'FMMonth YYYY')||' Home Hive Spotlight'),p_spotlight_business_id,p_spotlight_offer_id)
 returning id into v_id;
 return v_id;
end
$function$;

revoke all on function public.create_monthly_hive_campaign(uuid,date,uuid,uuid,text) from public,anon;
grant execute on function public.create_monthly_hive_campaign(uuid,date,uuid,uuid,text) to authenticated;

create or replace function public.next_hive_spotlight_member(p_hive_id uuid)
returns table(business_id uuid,business_name text,last_spotlight_month date)
language sql
security invoker
set search_path=''
stable
as $function$
 select b.id,b.name,max(c.campaign_month)
 from public.hive_members hm
 join public.businesses b on b.id=hm.business_id
  left join public.hive_campaigns c on c.hive_id=hm.hive_id and c.spotlight_business_id=hm.business_id and c.status<>'cancelled'
 where hm.hive_id=p_hive_id and hm.status='active'
 group by b.id,b.name
 order by max(c.campaign_month) asc nulls first,b.name
 limit 1
$function$;

revoke all on function public.next_hive_spotlight_member(uuid) from public,anon;
grant execute on function public.next_hive_spotlight_member(uuid) to authenticated;
