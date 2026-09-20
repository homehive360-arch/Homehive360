create or replace function public.my_promotion_delivery_recovery_summary() returns table(recoverable_email bigint,manual_email bigint,stale_sms bigint) language sql security invoker set search_path='' stable as $function$
 select
  count(*) filter(where pd.channel='email' and pd.status='sending' and pd.sending_at < now()-interval '5 minutes' and pd.created_at >= now()-interval '23 hours'),
  count(*) filter(where pd.channel='email' and pd.status='sending' and pd.sending_at < now()-interval '5 minutes' and pd.created_at < now()-interval '23 hours'),
  count(*) filter(where pd.channel='sms' and pd.status='sending' and pd.sending_at < now()-interval '5 minutes')
 from public.promotion_deliveries pd
 where exists(select 1 from public.business_users bu where bu.business_id=pd.source_business_id and bu.user_id=(select auth.uid()))
$function$;
revoke all on function public.my_promotion_delivery_recovery_summary() from public,anon;
grant execute on function public.my_promotion_delivery_recovery_summary() to authenticated;
