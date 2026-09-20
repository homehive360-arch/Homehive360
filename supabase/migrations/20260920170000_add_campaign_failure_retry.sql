-- Explicit recovery queue: permanent eligibility suppressions remain skipped;
-- only operational delivery failures are eligible for retry.
create or replace function public.retry_hive_campaign_failures(p_campaign_id uuid,p_limit integer default 250)
returns jsonb language plpgsql security definer set search_path=''
as $function$
declare c public.hive_campaigns;d record;v_retry int:=0;v_failed int:=0;
begin
 if auth.role()<>'service_role' then raise exception 'Service role required'; end if;
 select * into c from public.hive_campaigns where id=p_campaign_id and status='active';if c.id is null then raise exception 'Campaign must be active';end if;
 for d in select id from public.promotion_deliveries where campaign_id=p_campaign_id and status in('failed') order by updated_at limit greatest(1,least(p_limit,500)) for update skip locked
 loop
  begin
   update public.promotion_deliveries set status='queued',error_message=null,updated_at=now() where id=d.id;
   v_retry:=v_retry+1;
  exception when others then v_failed:=v_failed+1;end;
 end loop;
 return jsonb_build_object('retried',v_retry,'retry_failures',v_failed);
end $function$;
revoke all on function public.retry_hive_campaign_failures(uuid,integer) from public,anon,authenticated;grant execute on function public.retry_hive_campaign_failures(uuid,integer) to service_role;
