create or replace function public.claim_stale_email_delivery_recovery(p_id uuid,p_stale_seconds integer default 300) returns jsonb language plpgsql security definer set search_path='' as $function$
declare d public.promotion_deliveries%rowtype;
begin
 if p_stale_seconds < 60 then raise exception 'stale_window_too_short'; end if;
 select * into d from public.promotion_deliveries where id=p_id for update;
 if not found then raise exception 'delivery_not_found'; end if;
 if d.channel<>'email' then raise exception 'email_only_recovery'; end if;
 if d.status<>'sending' then raise exception 'delivery_not_sending'; end if;
 if d.provider_message_id is not null then raise exception 'provider_message_id_already_recorded'; end if;
 if d.sending_at is null or d.sending_at > now()-make_interval(secs=>p_stale_seconds) then raise exception 'delivery_not_stale'; end if;
 update public.promotion_deliveries set sending_at=now() where id=d.id;
 return jsonb_build_object('id',d.id,'status',d.status,'channel',d.channel,'recovery_claimed',true);
end $function$;
revoke all on function public.claim_stale_email_delivery_recovery(uuid,integer) from public,anon,authenticated;
grant execute on function public.claim_stale_email_delivery_recovery(uuid,integer) to service_role;
drop function if exists public.recover_stale_email_delivery(uuid,integer);
