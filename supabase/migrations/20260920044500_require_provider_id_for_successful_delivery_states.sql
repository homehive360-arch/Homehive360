create or replace function public.update_promotion_delivery_atomic(p_id uuid, p_expected_status text, p_status text, p_provider_message_id text default null)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare d public.promotion_deliveries%rowtype;n public.promotion_deliveries%rowtype;ev text;ts timestamptz:=now();effective_provider_id text;
begin
 select * into d from public.promotion_deliveries where id=p_id for update;
 if not found then raise exception 'delivery_not_found'; end if;
 if d.status<>p_expected_status then raise exception 'delivery_changed'; end if;
 if not ((d.status='queued' and p_status in ('sent','failed')) or (d.status='sending' and p_status in ('sent','failed')) or (d.status='sent' and p_status in ('delivered','failed'))) then raise exception 'invalid_delivery_transition'; end if;
 effective_provider_id=coalesce(nullif(btrim(p_provider_message_id),''),d.provider_message_id);
 if p_status in ('sent','delivered') and effective_provider_id is null then raise exception 'provider_message_id_required'; end if;
 update public.promotion_deliveries set status=p_status,provider_message_id=effective_provider_id,sent_at=case when p_status='sent' then ts else sent_at end,delivered_at=case when p_status='delivered' then ts else delivered_at end where id=p_id returning * into n;
 ev=case p_status when 'sent' then 'promotion.sent' when 'delivered' then 'promotion.delivered' else 'promotion.failed' end;
 insert into public.events(hive_id,business_id,customer_id,lead_id,event_type,actor_type,properties) values(d.hive_id,d.source_business_id,d.customer_id,d.lead_id,ev,'system',jsonb_build_object('delivery_id',d.id,'channel',d.channel,'provider_message_id',effective_provider_id,'from_status',d.status,'to_status',p_status));
 return jsonb_build_object('id',n.id,'status',n.status,'channel',n.channel,'provider_message_id',n.provider_message_id,'sent_at',n.sent_at,'delivered_at',n.delivered_at);
end $function$;
