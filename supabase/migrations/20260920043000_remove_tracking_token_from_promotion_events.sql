create or replace function public.queue_promotion_delivery_atomic(p_lead_id uuid, p_channel text)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare l public.leads%rowtype; d public.promotion_deliveries%rowtype; inserted_new boolean:=false;
begin
 if p_channel not in ('email','sms') then raise exception 'invalid_channel'; end if;
 select * into l from public.leads where id=p_lead_id; if not found then raise exception 'lead_not_found'; end if;
 insert into public.promotion_deliveries(lead_id,hive_id,source_business_id,customer_id,channel,status)
 values(l.id,l.hive_id,l.source_business_id,l.customer_id,p_channel,'queued')
 on conflict(lead_id,channel) do nothing returning * into d;
 if found then inserted_new:=true; else select * into d from public.promotion_deliveries where lead_id=l.id and channel=p_channel; end if;
 if inserted_new then insert into public.events(hive_id,business_id,customer_id,lead_id,event_type,actor_type,properties)
 values(l.hive_id,l.source_business_id,l.customer_id,l.id,'promotion.queued','system',jsonb_build_object('channel',d.channel,'delivery_id',d.id)); end if;
 return jsonb_build_object('id',d.id,'channel',d.channel,'tracking_token',d.tracking_token,'status',d.status,'created',inserted_new);
end $function$;
