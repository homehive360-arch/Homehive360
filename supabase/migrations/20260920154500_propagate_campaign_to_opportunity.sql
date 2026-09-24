-- Preserve monthly campaign attribution when offer intent creates an opportunity.
create or replace function public.create_promotion_engagement_opportunity(
 p_lead_id uuid,p_hive_id uuid,p_source_business_id uuid,p_receiving_business_id uuid,p_offer_id uuid default null,p_campaign_id uuid default null
) returns uuid
language plpgsql security definer set search_path=''
as $function$
declare v_id uuid; v_customer_id uuid;
begin
 if p_source_business_id=p_receiving_business_id then raise exception 'Self-attribution is not allowed'; end if;
 select l.customer_id into v_customer_id from public.leads l where l.id=p_lead_id and l.hive_id=p_hive_id and l.source_business_id=p_source_business_id;
 if v_customer_id is null then raise exception 'Lead attribution context is invalid'; end if;
 if not exists(select 1 from public.hive_members hm where hm.hive_id=p_hive_id and hm.business_id=p_source_business_id and hm.status='active') or
    not exists(select 1 from public.hive_members hm where hm.hive_id=p_hive_id and hm.business_id=p_receiving_business_id and hm.status='active')
 then raise exception 'Businesses must be active members of the Hive'; end if;
 if p_offer_id is not null and not exists(select 1 from public.offers o where o.id=p_offer_id and o.business_id=p_receiving_business_id and o.status='active' and (o.starts_at is null or o.starts_at<=now()) and (o.ends_at is null or o.ends_at>=now()))
 then raise exception 'Offer is not eligible'; end if;
 if p_campaign_id is not null and not exists(select 1 from public.hive_campaigns c where c.id=p_campaign_id and c.hive_id=p_hive_id and c.status in('active','completed'))
 then raise exception 'Campaign attribution context is invalid'; end if;
 select id into v_id from public.opportunities
 where lead_id=p_lead_id and receiving_business_id=p_receiving_business_id
  and campaign_id is not distinct from p_campaign_id
 order by created_at limit 1;
 if v_id is not null then
  update public.opportunities set offer_id=coalesce(offer_id,p_offer_id),updated_at=now() where id=v_id;
  return v_id;
 end if;
 insert into public.opportunities(lead_id,hive_id,source_business_id,receiving_business_id,customer_id,offer_id,campaign_id,status)
 values(p_lead_id,p_hive_id,p_source_business_id,p_receiving_business_id,v_customer_id,p_offer_id,p_campaign_id,'new') returning id into v_id;
 return v_id;
end
$function$;
revoke all on function public.create_promotion_engagement_opportunity(uuid,uuid,uuid,uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function public.create_promotion_engagement_opportunity(uuid,uuid,uuid,uuid,uuid,uuid) to service_role;
