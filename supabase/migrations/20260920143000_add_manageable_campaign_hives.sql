-- Expose manageable Hives to campaign creation UI without leaking other Hives.
create or replace function public.manageable_hives_for_campaigns()
returns table(hive_id uuid,hive_name text,market_name text)
language sql security invoker set search_path='' stable
as $function$
 select distinct h.id,h.name,h.market_name
 from public.hives h
 join public.hive_members hm on hm.hive_id=h.id and hm.status='active'
 join public.business_users bu on bu.business_id=hm.business_id
 where bu.user_id=(select auth.uid()) and bu.role in('owner','admin')
   and h.status='active'
 order by h.name
$function$;
revoke all on function public.manageable_hives_for_campaigns() from public,anon;
grant execute on function public.manageable_hives_for_campaigns() to authenticated;
