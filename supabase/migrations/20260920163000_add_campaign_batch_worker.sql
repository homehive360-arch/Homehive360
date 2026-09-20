-- Service-role batch queue primitive used by the scheduled worker.
create or replace function public.queue_hive_campaign_batch(p_campaign_id uuid,p_limit integer default 1000)
returns jsonb language plpgsql security definer set search_path=''
as $function$
declare c public.hive_campaigns;r public.hive_campaign_runs;l record;v_channel text;v_last uuid;v_processed int:=0;v_queued int:=0;v_skipped int:=0;v_failed int:=0;v_complete boolean;
begin
 if auth.role()<>'service_role' then raise exception 'Service role required'; end if;
 select * into c from public.hive_campaigns where id=p_campaign_id and status='active';if c.id is null then raise exception 'Campaign must be active';end if;
 select * into r from public.hive_campaign_runs where campaign_id=p_campaign_id;
 if r.status='queue_complete' then return jsonb_build_object('status','queue_complete','processed',0,'queued',0,'skipped',0,'failed',0);end if;
 for l in select cr.lead_id as id,cr.email_eligible as marketing_email_allowed,cr.sms_eligible as marketing_sms_allowed from public.hive_campaign_recipients cr where cr.campaign_id=p_campaign_id and (r.last_lead_id is null or cr.lead_id>r.last_lead_id) order by cr.lead_id limit greatest(1,least(p_limit,1000))
 loop
  v_processed:=v_processed+1;v_last:=l.id;v_channel:=null;
  if c.email_enabled and l.marketing_email_allowed then v_channel:='email';elsif c.sms_enabled and l.marketing_sms_allowed then v_channel:='sms';end if;
  if v_channel is null then v_skipped:=v_skipped+1;continue;end if;
  begin perform public.queue_hive_campaign_delivery(p_campaign_id,l.id,v_channel);v_queued:=v_queued+1;
  exception when others then if sqlerrm ilike '%ineligible%' then v_skipped:=v_skipped+1;else v_failed:=v_failed+1;end if;end;
 end loop;
 v_complete:=v_processed<greatest(1,least(p_limit,1000));
 insert into public.hive_campaign_runs(campaign_id,status,last_lead_id,audience_processed,deliveries_queued,deliveries_skipped,deliveries_failed,completed_at)
 values(p_campaign_id,case when v_complete then 'queue_complete' else 'running' end,v_last,v_processed,v_queued,v_skipped,v_failed,case when v_complete then now() end)
 on conflict(campaign_id) do update set status=excluded.status,last_lead_id=coalesce(excluded.last_lead_id,public.hive_campaign_runs.last_lead_id),
 audience_processed=public.hive_campaign_runs.audience_processed+v_processed,deliveries_queued=public.hive_campaign_runs.deliveries_queued+v_queued,
 deliveries_skipped=public.hive_campaign_runs.deliveries_skipped+v_skipped,deliveries_failed=public.hive_campaign_runs.deliveries_failed+v_failed,
 updated_at=now(),completed_at=excluded.completed_at;
 return jsonb_build_object('status',case when v_complete then 'queue_complete' else 'running' end,'processed',v_processed,'queued',v_queued,'skipped',v_skipped,'failed',v_failed);
end $function$;
revoke all on function public.queue_hive_campaign_batch(uuid,integer) from public,anon,authenticated;grant execute on function public.queue_hive_campaign_batch(uuid,integer) to service_role;
