-- Service-role worker primitive: activate due campaigns after revalidating launch state.
create or replace function public.activate_due_hive_campaigns(p_limit integer default 25)
returns table(campaign_id uuid)
language plpgsql security definer set search_path=''
as $function$
declare c public.hive_campaigns;
begin
 if auth.role()<>'service_role' then raise exception 'Service role required'; end if;
 for c in select * from public.hive_campaigns where status='scheduled' and scheduled_at<=now() order by scheduled_at for update skip locked limit greatest(1,least(p_limit,100))
 loop
  if not exists(select 1 from public.hive_members hm where hm.hive_id=c.hive_id and hm.business_id=c.spotlight_business_id and hm.status='active') then continue; end if;
  if c.spotlight_offer_id is not null and not exists(select 1 from public.offers o where o.id=c.spotlight_offer_id and o.business_id=c.spotlight_business_id and o.status='active' and (o.starts_at is null or o.starts_at<=now()) and (o.ends_at is null or o.ends_at>=now())) then continue; end if;
  perform public.refresh_hive_campaign_audiences(c.id);perform public.snapshot_hive_campaign_recipients(c.id);
  update public.hive_campaigns set status='active',updated_at=now() where id=c.id;
  campaign_id:=c.id;return next;
 end loop;
end
$function$;
revoke all on function public.activate_due_hive_campaigns(integer) from public,anon,authenticated;
grant execute on function public.activate_due_hive_campaigns(integer) to service_role;
