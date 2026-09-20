create or replace function public.promotion_delivery_recovery_summary() returns table(recoverable_email bigint,manual_email bigint,stale_sms bigint) language sql security invoker set search_path='' stable as $function$
 select
  count(*) filter(where channel='email' and status='sending' and sending_at < now()-interval '5 minutes' and created_at >= now()-interval '23 hours'),
  count(*) filter(where channel='email' and status='sending' and sending_at < now()-interval '5 minutes' and created_at < now()-interval '23 hours'),
  count(*) filter(where channel='sms' and status='sending' and sending_at < now()-interval '5 minutes')
 from public.promotion_deliveries
$function$;
revoke all on function public.promotion_delivery_recovery_summary() from public,anon;
grant execute on function public.promotion_delivery_recovery_summary() to authenticated,service_role;
