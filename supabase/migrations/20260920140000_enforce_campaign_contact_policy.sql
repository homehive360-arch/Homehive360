-- Apply campaign contact policy inside the queue invariant.
create or replace function public.queue_hive_campaign_delivery(
 p_campaign_id uuid,p_lead_id uuid,p_channel text
) returns public.promotion_deliveries
language plpgsql security definer set search_path=''
as $function$
declare v_campaign public.hive_campaigns;v_lead public.leads;v_delivery public.promotion_deliveries;v_elig jsonb;
begin
 if auth.role()<>'service_role' then raise exception 'Service role required'; end if;
 select * into v_campaign from public.hive_campaigns where id=p_campaign_id;
 if v_campaign.id is null then raise exception 'Campaign not found'; end if;
 if v_campaign.status<>'active' then raise exception 'Campaign is not active'; end if;
 select * into v_lead from public.leads where id=p_lead_id;
 if v_lead.id is null then raise exception 'Audience record not found'; end if;
 if v_lead.hive_id<>v_campaign.hive_id then raise exception 'Audience record does not belong to campaign Hive'; end if;
 if not exists(select 1 from public.hive_members where hive_id=v_campaign.hive_id and business_id=v_lead.source_business_id and status='active')
 then raise exception 'Audience source is not an active Hive member'; end if;

 select * into v_delivery from public.promotion_deliveries
 where campaign_id=p_campaign_id and lead_id=p_lead_id and channel=p_channel order by created_at desc limit 1;
 if v_delivery.id is not null then return v_delivery; end if;

 v_elig:=public.campaign_delivery_eligibility(p_campaign_id,p_lead_id,p_channel);
 if coalesce((v_elig->>'eligible')::boolean,false)=false
 then raise exception 'Campaign delivery ineligible: %',coalesce(v_elig->>'reason','unknown'); end if;

 begin
  -- Revalidate the same production invariants as the legacy atomic queue before
  -- creating a campaign-specific delivery.
  if not exists(select 1 from public.businesses b where b.id=v_lead.source_business_id and b.status='active') then raise exception 'Campaign delivery ineligible: inactive_source_business'; end if;
  if not exists(select 1 from public.hives h where h.id=v_lead.hive_id and h.status='active') then raise exception 'Campaign delivery ineligible: inactive_hive'; end if;
  if not exists(select 1 from public.customers cu where cu.id=v_lead.customer_id and cu.source_business_id=v_lead.source_business_id and ((p_channel='email' and nullif(btrim(cu.email),'') is not null) or (p_channel='sms' and nullif(btrim(cu.phone),'') is not null))) then raise exception 'Campaign delivery ineligible: customer_source_or_destination'; end if;
  insert into public.promotion_deliveries(lead_id,hive_id,source_business_id,customer_id,channel,status,campaign_id)
  values(v_lead.id,v_lead.hive_id,v_lead.source_business_id,v_lead.customer_id,p_channel,'queued',p_campaign_id)
  returning * into v_delivery;
  insert into public.events(hive_id,business_id,customer_id,lead_id,event_type,actor_type,properties)
  values(v_lead.hive_id,v_lead.source_business_id,v_lead.customer_id,v_lead.id,'promotion.queued','system',jsonb_build_object('channel',v_delivery.channel,'delivery_id',v_delivery.id,'campaign_id',p_campaign_id));
 exception when unique_violation then
  select * into v_delivery from public.promotion_deliveries
  where campaign_id=p_campaign_id and lead_id=p_lead_id and channel=p_channel order by created_at desc limit 1;
 end;
 return v_delivery;
end
$function$;

revoke all on function public.queue_hive_campaign_delivery(uuid,uuid,text) from public,anon,authenticated;
grant execute on function public.queue_hive_campaign_delivery(uuid,uuid,text) to service_role;
