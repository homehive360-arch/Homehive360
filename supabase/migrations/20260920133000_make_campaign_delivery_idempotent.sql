-- Enforce one delivery per campaign/audience-record/channel and make campaign
-- queueing safe to retry.
create unique index if not exists promotion_deliveries_campaign_lead_channel_uidx
 on public.promotion_deliveries(campaign_id,lead_id,channel)
 where campaign_id is not null;

create or replace function public.queue_hive_campaign_delivery(
 p_campaign_id uuid,
 p_lead_id uuid,
 p_channel text
) returns public.promotion_deliveries
language plpgsql
security definer
set search_path=''
as $function$
declare v_campaign public.hive_campaigns; v_lead public.leads; v_delivery public.promotion_deliveries;
begin
 select * into v_campaign from public.hive_campaigns where id=p_campaign_id;
 if v_campaign.id is null then raise exception 'Campaign not found'; end if;
 if v_campaign.status not in('scheduled','active') then raise exception 'Campaign is not ready for delivery'; end if;
 select * into v_lead from public.leads where id=p_lead_id;
 if v_lead.id is null then raise exception 'Audience record not found'; end if;
 if v_lead.hive_id<>v_campaign.hive_id then raise exception 'Audience record does not belong to campaign Hive'; end if;
 if not exists(select 1 from public.hive_members where hive_id=v_campaign.hive_id and business_id=v_lead.source_business_id and status='active')
 then raise exception 'Audience source is not an active Hive member'; end if;
 if not ((p_channel='email' and v_lead.marketing_email_allowed) or (p_channel='sms' and v_lead.marketing_sms_allowed))
 then raise exception 'Audience record is not consented for this channel'; end if;

 select * into v_delivery from public.promotion_deliveries
 where campaign_id=p_campaign_id and lead_id=p_lead_id and channel=p_channel
 order by created_at desc limit 1;
 if v_delivery.id is not null then return v_delivery; end if;

 v_delivery:=public.queue_promotion_delivery_atomic(p_lead_id,p_channel);
 if v_delivery.campaign_id is not null and v_delivery.campaign_id<>p_campaign_id
 then raise exception 'Delivery is already assigned to another campaign'; end if;

 begin
  update public.promotion_deliveries set campaign_id=p_campaign_id where id=v_delivery.id
  returning * into v_delivery;
 exception when unique_violation then
  select * into v_delivery from public.promotion_deliveries
  where campaign_id=p_campaign_id and lead_id=p_lead_id and channel=p_channel
  order by created_at desc limit 1;
 end;
 return v_delivery;
end
$function$;
