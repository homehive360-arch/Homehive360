-- Single planning RPC for the operator UI: next fair spotlight member,
-- eligible offers, and current source-owned audience reach.
create or replace function public.hive_campaign_planner(p_hive_id uuid)
returns jsonb
language plpgsql
security invoker
set search_path=''
stable
as $function$
declare v_next uuid;v_name text;v_last date;v_owned bigint;v_incremental bigint;v_total bigint;v_offers jsonb;
begin
 if not exists(
  select 1 from public.hive_members hm join public.business_users bu on bu.business_id=hm.business_id
  where hm.hive_id=p_hive_id and hm.status='active' and bu.user_id=(select auth.uid())
 ) then raise exception 'Not authorized to view this Hive'; end if;

 select n.business_id,n.business_name,n.last_spotlight_month
 into v_next,v_name,v_last
 from public.next_hive_spotlight_member(p_hive_id) n limit 1;

 select
  coalesce(count(distinct l.customer_id) filter(where hm.business_id=v_next and (l.marketing_email_allowed or l.marketing_sms_allowed)),0),
  coalesce(count(distinct l.customer_id) filter(where hm.business_id<>v_next and (l.marketing_email_allowed or l.marketing_sms_allowed)),0),
  coalesce(count(distinct l.customer_id) filter(where l.marketing_email_allowed or l.marketing_sms_allowed),0)
 into v_owned,v_incremental,v_total
 from public.hive_members hm
 left join public.leads l on l.hive_id=hm.hive_id and l.source_business_id=hm.business_id
 where hm.hive_id=p_hive_id and hm.status='active';

 select coalesce(jsonb_agg(jsonb_build_object('id',o.id,'title',o.title,'description',o.description,'cta_label',o.cta_label,'ends_at',o.ends_at) order by o.created_at desc),'[]'::jsonb)
 into v_offers
 from public.offers o
 where o.business_id=v_next and o.status='active'
  and (o.hive_id is null or o.hive_id=p_hive_id)
  and (o.starts_at is null or o.starts_at<=now())
  and (o.ends_at is null or o.ends_at>=now());

 return jsonb_build_object(
  'recommended_spotlight',jsonb_build_object('business_id',v_next,'business_name',v_name,'last_spotlight_month',v_last),
  'reach',jsonb_build_object('owned_reach',v_owned,'incremental_hive_reach',v_incremental,'total_reach',v_total),
  'eligible_offers',v_offers
 );
end
$function$;

revoke all on function public.hive_campaign_planner(uuid) from public,anon;
grant execute on function public.hive_campaign_planner(uuid) to authenticated;
