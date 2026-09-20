-- Anonymous-safe campaign presentation resolver. Never returns customer, lead, destination or raw delivery data.
create or replace function public.public_hive_campaign_context(p_hive_id uuid,p_tracking_token uuid)
returns table(campaign_id uuid,campaign_name text,spotlight_business_id uuid,spotlight_offer_id uuid,source_business_id uuid)
language sql security definer set search_path='' stable as $function$
 select c.id,c.name,c.spotlight_business_id,c.spotlight_offer_id,d.source_business_id
 from public.promotion_deliveries d join public.hive_campaigns c on c.id=d.campaign_id and c.hive_id=d.hive_id
 where d.hive_id=p_hive_id and d.tracking_token=p_tracking_token and c.status in('active','completed')
 limit 1
$function$;
revoke all on function public.public_hive_campaign_context(uuid,uuid) from public,authenticated;
grant execute on function public.public_hive_campaign_context(uuid,uuid) to anon;
