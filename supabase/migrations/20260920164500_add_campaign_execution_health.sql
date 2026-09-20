-- Campaign execution health for operator recovery and alerting.
create or replace function public.hive_campaign_execution_health(p_campaign_id uuid)
returns jsonb language sql security invoker set search_path='' stable
as $function$
 with c as(select id,status,scheduled_at,updated_at from public.hive_campaigns where id=p_campaign_id),
 r as(select status queue_status,audience_processed,deliveries_queued,deliveries_skipped,deliveries_failed,updated_at run_updated_at from public.hive_campaign_runs where campaign_id=p_campaign_id),
 d as(select count(*) filter(where status in('queued','sending'))::bigint pending,count(*) filter(where status in('failed','bounced'))::bigint provider_failures from public.promotion_deliveries where campaign_id=p_campaign_id)
 select jsonb_build_object(
  'campaign_status',c.status,'queue_status',coalesce(r.queue_status,'not_started'),
  'audience_processed',coalesce(r.audience_processed,0),'queue_failures',coalesce(r.deliveries_failed,0),
  'pending_deliveries',d.pending,'provider_failures',d.provider_failures,
  'last_progress_at',coalesce(r.run_updated_at,c.updated_at),
  'stalled',case when c.status='active' and coalesce(r.queue_status,'')<>'queue_complete' and coalesce(r.run_updated_at,c.updated_at)<now()-interval '30 minutes' then true else false end,
  'needs_attention',case when coalesce(r.deliveries_failed,0)>0 or d.provider_failures>0 or (c.status='active' and coalesce(r.queue_status,'')<>'queue_complete' and coalesce(r.run_updated_at,c.updated_at)<now()-interval '30 minutes') then true else false end
 ) from c left join r on true cross join d
$function$;
revoke all on function public.hive_campaign_execution_health(uuid) from public,anon;
grant execute on function public.hive_campaign_execution_health(uuid) to authenticated;
