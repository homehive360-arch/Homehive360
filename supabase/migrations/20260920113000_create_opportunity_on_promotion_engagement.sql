-- Create an opportunity only after a customer engages with a promoted Hive member.
-- The unique lookup makes repeated tracked clicks idempotent at the application layer.
create or replace function public.create_promotion_engagement_opportunity(
 p_lead_id uuid,
 p_hive_id uuid,
 p_source_business_id uuid,
 p_receiving_business_id uuid,
 p_offer_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path=''
as $function$
declare
 v_id uuid;
begin
 if p_source_business_id=p_receiving_business_id then
  raise exception 'Promotion source cannot receive its own opportunity';
 end if;

 if not exists(
  select 1 from public.hive_members
  where hive_id=p_hive_id and business_id=p_source_business_id and status='active'
 ) or not exists(
  select 1 from public.hive_members
  where hive_id=p_hive_id and business_id=p_receiving_business_id and status='active'
 ) then
  raise exception 'Both businesses must be active Hive members';
 end if;

 select id into v_id
 from public.opportunities
 where lead_id=p_lead_id and receiving_business_id=p_receiving_business_id
 limit 1;
 if v_id is not null then return v_id; end if;

 insert into public.opportunities(
  lead_id,hive_id,source_business_id,receiving_business_id,offer_id,status
 ) values(
  p_lead_id,p_hive_id,p_source_business_id,p_receiving_business_id,p_offer_id,'new'
 )
 returning id into v_id;
 return v_id;
end
$function$;

revoke all on function public.create_promotion_engagement_opportunity(uuid,uuid,uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function public.create_promotion_engagement_opportunity(uuid,uuid,uuid,uuid,uuid) to service_role;
