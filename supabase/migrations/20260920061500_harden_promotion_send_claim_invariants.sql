create or replace function public.claim_promotion_delivery_for_send(p_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare d public.promotion_deliveries%rowtype; l public.leads%rowtype; c public.customers%rowtype;
begin
 select * into d from public.promotion_deliveries where id=p_id for update;
 if not found or d.status<>'queued' then raise exception 'delivery_not_queued'; end if;
 select * into l from public.leads where id=d.lead_id;
 if not found then raise exception 'lead_not_found'; end if;
 if l.hive_id<>d.hive_id or l.source_business_id<>d.source_business_id or l.customer_id<>d.customer_id then raise exception 'delivery_context_changed'; end if;
 if not exists(select 1 from public.businesses b where b.id=d.source_business_id and b.status='active') then raise exception 'inactive_source_business'; end if;
 if not exists(select 1 from public.hives h where h.id=d.hive_id and h.status='active') then raise exception 'inactive_hive'; end if;
 if not exists(select 1 from public.hive_members hm where hm.hive_id=d.hive_id and hm.business_id=d.source_business_id and hm.status='active') then raise exception 'inactive_source_membership'; end if;
 select * into c from public.customers where id=d.customer_id;
 if not found then raise exception 'customer_not_found'; end if;
 if d.channel='email' and (not coalesce(l.marketing_email_allowed,false) or nullif(btrim(c.email),'') is null) then raise exception 'email_delivery_unavailable'; end if;
 if d.channel='sms' and (not coalesce(l.marketing_sms_allowed,false) or nullif(btrim(c.phone),'') is null) then raise exception 'sms_delivery_unavailable'; end if;
 if d.channel not in ('email','sms') then raise exception 'invalid_channel'; end if;
 update public.promotion_deliveries set status='sending',sending_at=now() where id=d.id returning * into d;
 return jsonb_build_object('id',d.id,'status',d.status,'channel',d.channel,'sending_at',d.sending_at);
end $function$;
