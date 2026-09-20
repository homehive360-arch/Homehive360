-- Preflight a Hive's first/next monthly campaign. This keeps launch readiness,
-- Spotlight rotation and incremental network reach in one operator-facing view.
create or replace function public.hive_campaign_preflight(p_hive_id uuid)
returns jsonb language plpgsql security invoker set search_path=''
as $function$
declare
 v_ready jsonb;v_spotlight uuid;v_owned bigint:=0;v_incremental bigint:=0;v_total bigint:=0;
begin
 v_ready:=public.hive_launch_readiness(p_hive_id);
 if v_ready is null then return null; end if;
 if coalesce((v_ready->>'launch_ready')::boolean,false)=false then
  return jsonb_build_object('launch_ready',false,'readiness',v_ready);
 end if;

 -- Use the existing fair rotation engine rather than ranking businesses by
 -- performance. Spotlight is premium placement, not a winner/leaderboard.
 select public.next_hive_spotlight_member(p_hive_id) into v_spotlight;
 if v_spotlight is null then
  return jsonb_build_object('launch_ready',true,'readiness',v_ready,'spotlight_business_id',null);
 end if;

 select count(distinct l.customer_id) filter(where l.source_business_id=v_spotlight),
        count(distinct l.customer_id) filter(where l.source_business_id<>v_spotlight),
        count(distinct l.customer_id)
 into v_owned,v_incremental,v_total
 from public.leads l
 join public.hive_members hm on hm.hive_id=l.hive_id and hm.business_id=l.source_business_id and hm.status='active'
 where l.hive_id=p_hive_id and (l.marketing_email_allowed or l.marketing_sms_allowed);

 return jsonb_build_object(
  'launch_ready',true,'readiness',v_ready,
  'spotlight_business_id',v_spotlight,
  'owned_audience_reach',coalesce(v_owned,0),
  'incremental_hive_reach',coalesce(v_incremental,0),
  'total_campaign_reach',coalesce(v_total,0)
 );
end
$function$;

revoke all on function public.hive_campaign_preflight(uuid) from public,anon;
grant execute on function public.hive_campaign_preflight(uuid) to authenticated;
