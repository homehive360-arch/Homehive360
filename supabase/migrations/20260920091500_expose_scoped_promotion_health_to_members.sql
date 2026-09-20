create or replace function public.promotion_delivery_recovery_summary() returns table(recoverable_email bigint,manual_email bigint,stale_sms bigint) language sql security invoker set search_path='' stable as $function$
 select
  count(*) filter(where pd.channel='email' and pd.status='sending' and pd.sending_at < now()-interval '5 minutes' and pd.created_at >= now()-interval '23 hours'),
  count(*) filter(where pd.channel='email' and pd.status='sending' and pd.sending_at < now()-interval '5 minutes' and pd.created_at < now()-interval '23 hours'),
  count(*) filter(where pd.channel='sms' and pd.status='sending' and pd.sending_at < now()-interval '5 minutes')
 from public.promotion_deliveries pd
$function$;
revoke all on function public.promotion_delivery_recovery_summary() from public,anon;
grant execute on function public.promotion_delivery_recovery_summary() to authenticated,service_role;
