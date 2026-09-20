-- Campaign readiness is derived from active membership plus an eligible,
-- source-owned audience. Membership alone does not make a business campaign-ready.
create or replace function public.hive_member_campaign_readiness(p_hive_id uuid)
returns table(
 business_id uuid,
 business_name text,
 member_status text,
 audience_customers bigint,
 email_eligible bigint,
 sms_eligible bigint,
 audience_connected boolean,
 campaign_ready boolean
)
language sql security invoker set search_path='' stable
as $function$
 with authorized as(
  select exists(
   select 1 from public.hive_members hm
   join public.business_users bu on bu.business_id=hm.business_id
   where hm.hive_id=p_hive_id and hm.status='active'
    and bu.user_id=(select auth.uid()) and bu.role in('owner','admin')
  ) ok
 ),policy as(
  select true email_enabled,false sms_enabled
 ),eligible as(
  select distinct on(l.customer_id) l.customer_id,l.source_business_id,
   p.email_enabled and bool_or(l.marketing_email_allowed) over(partition by l.customer_id) email_eligible,
   p.sms_enabled and bool_or(l.marketing_sms_allowed) over(partition by l.customer_id) sms_eligible
  from public.leads l
  join public.hive_members hm on hm.hive_id=l.hive_id and hm.business_id=l.source_business_id and hm.status='active'
  cross join policy p
  where l.hive_id=p_hive_id and l.customer_id is not null
   and ((p.email_enabled and l.marketing_email_allowed) or (p.sms_enabled and l.marketing_sms_allowed))
  order by l.customer_id,l.received_at desc nulls last,l.created_at desc,l.id desc
 ),audience as(
  select source_business_id,count(*)::bigint audience_customers,
   count(*) filter(where email_eligible)::bigint email_eligible,
   count(*) filter(where sms_eligible)::bigint sms_eligible
  from eligible group by source_business_id
 )
 select hm.business_id,b.name,hm.status::text,
  coalesce(a.audience_customers,0),
  coalesce(a.email_eligible,0),
  coalesce(a.sms_eligible,0),
  coalesce(a.audience_customers,0)>0,
  hm.status='active' and (coalesce(a.email_eligible,0)>0 or coalesce(a.sms_eligible,0)>0)
 from public.hive_members hm
 join public.businesses b on b.id=hm.business_id
 left join audience a on a.source_business_id=hm.business_id
 where hm.hive_id=p_hive_id and (select ok from authorized)
 order by b.name
$function$;

revoke all on function public.hive_member_campaign_readiness(uuid) from public,anon;
grant execute on function public.hive_member_campaign_readiness(uuid) to authenticated;
