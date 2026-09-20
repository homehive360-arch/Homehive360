-- Campaign communication policy: email is the default monthly channel.
-- SMS is opt-in per campaign, and customer-level cooldown prevents HH360
-- campaign fatigue across Hives/import retries.
alter table public.hive_campaigns
 add column if not exists email_enabled boolean not null default true,
 add column if not exists sms_enabled boolean not null default false,
 add column if not exists min_contact_gap_days integer not null default 21
  check(min_contact_gap_days between 0 and 60);

create or replace function public.campaign_delivery_eligibility(
 p_campaign_id uuid,
 p_lead_id uuid,
 p_channel text
) returns jsonb
language plpgsql
security definer
set search_path=''
stable
as $function$
declare v_campaign public.hive_campaigns; v_lead public.leads; v_customer uuid; v_last timestamptz;
begin
 select * into v_campaign from public.hive_campaigns where id=p_campaign_id;
 if v_campaign.id is null then return jsonb_build_object('eligible',false,'reason','campaign_not_found'); end if;
 select * into v_lead from public.leads where id=p_lead_id;
 if v_lead.id is null then return jsonb_build_object('eligible',false,'reason','audience_record_not_found'); end if;
 if v_lead.hive_id<>v_campaign.hive_id then return jsonb_build_object('eligible',false,'reason','wrong_hive'); end if;
 if p_channel not in('email','sms') then return jsonb_build_object('eligible',false,'reason','unsupported_channel'); end if;
 if p_channel='email' and (not v_campaign.email_enabled or not v_lead.marketing_email_allowed)
 then return jsonb_build_object('eligible',false,'reason','email_not_enabled_or_consented'); end if;
 if p_channel='sms' and (not v_campaign.sms_enabled or not v_lead.marketing_sms_allowed)
 then return jsonb_build_object('eligible',false,'reason','sms_not_enabled_or_consented'); end if;

 v_customer:=v_lead.customer_id;
 select max(pd.created_at) into v_last
 from public.promotion_deliveries pd
 join public.leads l on l.id=pd.lead_id
 where l.customer_id=v_customer and pd.campaign_id is not null
  and pd.status in('queued','sending','sent','delivered');

 if v_last is not null and v_last>now()-(v_campaign.min_contact_gap_days||' days')::interval
 then return jsonb_build_object('eligible',false,'reason','campaign_contact_cooldown','last_contact_at',v_last); end if;
 return jsonb_build_object('eligible',true,'reason','eligible');
end
$function$;

revoke all on function public.campaign_delivery_eligibility(uuid,uuid,text) from public,anon,authenticated;
grant execute on function public.campaign_delivery_eligibility(uuid,uuid,text) to service_role;
