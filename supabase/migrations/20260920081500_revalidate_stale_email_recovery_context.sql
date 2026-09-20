create or replace function public.claim_stale_email_delivery_recovery(p_id uuid,p_stale_seconds integer default 300) returns jsonb language plpgsql security definer set search_path='' as $function$
declare d public.promotion_deliveries%rowtype; l public.leads%rowtype; c public.customers%rowtype;
begin
 if p_stale_seconds < 60 then raise exception 'stale_window_too_short'; end if;
 select * into d from public.promotion_deliveries where id=p_id for update;
 if not found then raise exception 'delivery_not_found'; end if;
 if d.channel<>'email' then raise exception 'email_only_recovery'; end if;
 if d.status<>'sending' then raise exception 'delivery_not_sending'; end if;
 if d.provider_message_id is not null then raise exception 'provider_message_id_already_recorded'; end if;
 if d.sending_at is null or d.sending_at > now()-make_interval(secs=>p_stale_seconds) then raise exception 'delivery_not_stale'; end if;
 select * into l from public.leads where id=d.lead_id and source_business_id=d.source_business_id and hive_id=d.hive_id and customer_id=d.customer_id;
 if not found then raise exception 'lead_context_mismatch'; end if;
 select * into c from public.customers where id=d.customer_id and source_business_id=d.source_business_id;
 if not found then raise exception 'customer_source_mismatch'; end if;
 if not l.marketing_email_allowed or nullif(btrim(c.email),'') is null then raise exception 'email_consent_or_destination_unavailable'; end if;
 if not exists(select 1 from public.businesses b where b.id=d.source_business_id and b.status='active') then raise exception 'source_business_inactive'; end if;
 if not exists(select 1 from public.hives h where h.id=d.hive_id and h.status='active') then raise exception 'hive_inactive'; end if;
 if not exists(select 1 from public.hive_members hm where hm.hive_id=d.hive_id and hm.business_id=d.source_business_id and hm.status='active') then raise exception 'source_membership_inactive'; end if;
 update public.promotion_deliveries set sending_at=now() where id=d.id;
 return jsonb_build_object('id',d.id,'status',d.status,'channel',d.channel,'recovery_claimed',true);
end $function$;
revoke all on function public.claim_stale_email_delivery_recovery(uuid,integer) from public,anon,authenticated;
grant execute on function public.claim_stale_email_delivery_recovery(uuid,integer) to service_role;
