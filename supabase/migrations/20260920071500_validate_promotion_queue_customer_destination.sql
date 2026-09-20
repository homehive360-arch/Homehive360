create or replace function public.queue_promotion_delivery_atomic(p_lead_id uuid,p_channel text) returns jsonb language plpgsql security definer set search_path='' as $function$
declare l public.leads%rowtype; d public.promotion_deliveries%rowtype; c public.customers%rowtype; inserted_new boolean:=false;
begin
 if p_channel not in ('email','sms') then raise exception 'invalid_channel'; end if;
 select * into l from public.leads where id=p_lead_id; if not found then raise exception 'lead_not_found'; end if;
 if not exists(select 1 from public.businesses b where b.id=l.source_business_id and b.status='active') then raise exception 'inactive_source_business'; end if;
 if not exists(select 1 from public.hives h where h.id=l.hive_id and h.status='active') then raise exception 'inactive_hive'; end if;
 if not exists(select 1 from public.hive_members hm where hm.hive_id=l.hive_id and hm.business_id=l.source_business_id and hm.status='active') then raise exception 'inactive_source_membership'; end if;
 select * into c from public.customers where id=l.customer_id and source_business_id=l.source_business_id; if not found then raise exception 'customer_source_mismatch'; end if;
 if p_channel='email' and (not coalesce(l.marketing_email_allowed,false) or nullif(btrim(c.email),'') is null) then raise exception 'email_consent_or_destination_unavailable'; end if;
 if p_channel='sms' and (not coalesce(l.marketing_sms_allowed,false) or nullif(btrim(c.phone),'') is null) then raise exception 'sms_consent_or_destination_unavailable'; end if;
 insert into public.promotion_deliveries(lead_id,hive_id,source_business_id,customer_id,channel,status)
 values(l.id,l.hive_id,l.source_business_id,l.customer_id,p_channel,'queued')
 on conflict(lead_id,channel) do nothing returning * into d;
 if found then inserted_new:=true; else select * into d from public.promotion_deliveries where lead_id=l.id and channel=p_channel; end if;
 if inserted_new then insert into public.events(hive_id,business_id,customer_id,lead_id,event_type,actor_type,properties)
 values(l.hive_id,l.source_business_id,l.customer_id,l.id,'promotion.queued','system',jsonb_build_object('channel',d.channel,'delivery_id',d.id)); end if;
 return jsonb_build_object('id',d.id,'channel',d.channel,'tracking_token',d.tracking_token,'status',d.status,'created',inserted_new);
end $function$;
