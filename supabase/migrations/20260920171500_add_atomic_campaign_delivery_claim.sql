-- Atomic worker claim prevents overlapping cron invocations from selecting the same queued campaign deliveries.
create or replace function public.claim_campaign_deliveries_for_worker(p_limit integer default 50)
returns setof public.promotion_deliveries
language plpgsql security definer set search_path=''
as $function$
begin
 if auth.role()<>'service_role' then raise exception 'service_role_required'; end if;
 return query
 with picked as (
  select pd.id from public.promotion_deliveries pd
  where pd.campaign_id is not null and pd.status='queued'
  order by pd.created_at,pd.id
  limit greatest(1,least(p_limit,100))
  for update skip locked
 ), claimed as (
  update public.promotion_deliveries pd set status='sending',sending_at=now()
  from picked where pd.id=picked.id
  returning pd.*
 )
 select * from claimed;
end $function$;
revoke all on function public.claim_campaign_deliveries_for_worker(integer) from public,anon,authenticated;
grant execute on function public.claim_campaign_deliveries_for_worker(integer) to service_role;
