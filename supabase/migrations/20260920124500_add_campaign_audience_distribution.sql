-- Materialize monthly campaign distribution by source-owned audience without
-- exposing customer identities across Hive members.
create table if not exists public.hive_campaign_audiences (
 id uuid primary key default gen_random_uuid(),
 campaign_id uuid not null references public.hive_campaigns(id) on delete cascade,
 source_business_id uuid not null references public.businesses(id),
 eligible_customers bigint not null default 0 check(eligible_customers>=0),
 email_eligible bigint not null default 0 check(email_eligible>=0),
 sms_eligible bigint not null default 0 check(sms_eligible>=0),
 created_at timestamptz not null default now(),
 unique(campaign_id,source_business_id)
);

alter table public.hive_campaign_audiences enable row level security;
create policy "members can view campaign audience summaries" on public.hive_campaign_audiences
for select to authenticated using(exists(
 select 1 from public.hive_campaigns c
 join public.hive_members hm on hm.hive_id=c.hive_id
 join public.business_users bu on bu.business_id=hm.business_id
 where c.id=hive_campaign_audiences.campaign_id and hm.status='active' and bu.user_id=(select auth.uid())
));

create or replace function public.refresh_hive_campaign_audiences(p_campaign_id uuid)
returns void
language plpgsql
security definer
set search_path=''
as $function$
declare v_hive uuid;v_email boolean;v_sms boolean;
begin
 select hive_id,email_enabled,sms_enabled into v_hive,v_email,v_sms from public.hive_campaigns where id=p_campaign_id;
 if v_hive is null then raise exception 'Campaign not found'; end if;
 if not exists(
  select 1 from public.hive_members hm join public.business_users bu on bu.business_id=hm.business_id
  where hm.hive_id=v_hive and hm.status='active' and bu.user_id=(select auth.uid()) and bu.role in('owner','admin')
 ) then raise exception 'Not authorized to manage this Hive'; end if;

 insert into public.hive_campaign_audiences(campaign_id,source_business_id,eligible_customers,email_eligible,sms_eligible)
 with eligible as(
  select distinct on(l.customer_id) l.customer_id,l.source_business_id,
   v_email and bool_or(l.marketing_email_allowed) over(partition by l.customer_id) email_eligible,
   v_sms and bool_or(l.marketing_sms_allowed) over(partition by l.customer_id) sms_eligible
  from public.leads l
  join public.hive_members hm on hm.hive_id=l.hive_id and hm.business_id=l.source_business_id and hm.status='active'
  where l.hive_id=v_hive and l.customer_id is not null
   and ((v_email and l.marketing_email_allowed) or (v_sms and l.marketing_sms_allowed))
  order by l.customer_id,l.received_at desc nulls last,l.created_at desc,l.id desc
 )
 select p_campaign_id,hm.business_id,
  count(e.customer_id),count(e.customer_id) filter(where e.email_eligible),count(e.customer_id) filter(where e.sms_eligible)
 from public.hive_members hm
 left join eligible e on e.source_business_id=hm.business_id
 where hm.hive_id=v_hive and hm.status='active'
 group by hm.business_id
 on conflict(campaign_id,source_business_id) do update set
  eligible_customers=excluded.eligible_customers,
  email_eligible=excluded.email_eligible,
  sms_eligible=excluded.sms_eligible;
end
$function$;

revoke all on function public.refresh_hive_campaign_audiences(uuid) from public,anon;
grant execute on function public.refresh_hive_campaign_audiences(uuid) to authenticated;

create or replace function public.hive_campaign_reach(p_campaign_id uuid)
returns jsonb
language sql
security invoker
set search_path=''
stable
as $function$
 with c as(select spotlight_business_id from public.hive_campaigns where id=p_campaign_id),
 a as(
  select
   coalesce(sum(eligible_customers),0)::bigint total_reach,
   coalesce(sum(eligible_customers) filter(where source_business_id=(select spotlight_business_id from c)),0)::bigint owned_reach,
   coalesce(sum(eligible_customers) filter(where source_business_id<>(select spotlight_business_id from c)),0)::bigint incremental_hive_reach,
   coalesce(sum(email_eligible),0)::bigint email_reach,
   coalesce(sum(sms_eligible),0)::bigint sms_reach
  from public.hive_campaign_audiences where campaign_id=p_campaign_id
 )
 select jsonb_build_object(
  'owned_reach',owned_reach,
  'incremental_hive_reach',incremental_hive_reach,
  'total_reach',total_reach,
  'email_reach',email_reach,
  'sms_reach',sms_reach
 ) from a
$function$;

revoke all on function public.hive_campaign_reach(uuid) from public,anon;
grant execute on function public.hive_campaign_reach(uuid) to authenticated;
