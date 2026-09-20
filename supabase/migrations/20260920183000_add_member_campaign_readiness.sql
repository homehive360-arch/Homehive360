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
  select email_enabled,sms_enabled from public.hive_campaign_policy where hive_id=p_hive_id
 ),audience as(
  select l.source_business_id,
   count(distinct l.customer_id)::bigint audience_customers,
   count(distinct l.customer_id) filter(where p.email_enabled and l.marketing_email_allowed)::bigint email_eligible,
   count(distinct l.customer_id) filter(where p.sms_enabled and l.marketing_sms_allowed)::bigint sms_eligible
  from public.leads l
  cross join policy p
  where l.hive_id=p_hive_id
  group by l.source_business_id
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
