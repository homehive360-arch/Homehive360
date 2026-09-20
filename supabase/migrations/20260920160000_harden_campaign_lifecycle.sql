-- Enforce a one-way monthly campaign lifecycle and require real future scheduling.
create or replace function public.set_hive_campaign_status(
 p_campaign_id uuid,p_status text,p_scheduled_at timestamptz default null
) returns public.hive_campaigns
language plpgsql security definer set search_path=''
as $function$
declare v public.hive_campaigns;v_launch_at timestamptz;
begin
 select * into v from public.hive_campaigns where id=p_campaign_id for update;
 if v.id is null then raise exception 'Campaign not found'; end if;
 if not exists(select 1 from public.hive_members hm join public.business_users bu on bu.business_id=hm.business_id
  where hm.hive_id=v.hive_id and hm.status='active' and bu.business_id=hm.business_id and bu.user_id=(select auth.uid()) and bu.role in('owner','admin'))
 then raise exception 'Not authorized to manage this Hive'; end if;
 if p_status not in('scheduled','active','completed','cancelled') then raise exception 'Invalid campaign status'; end if;
 if v.status in('completed','cancelled') then raise exception 'Completed or cancelled campaigns are terminal'; end if;
 if v.status='draft' and p_status not in('scheduled','active','cancelled') then raise exception 'Invalid transition from draft'; end if;
 if v.status='scheduled' and p_status not in('active','cancelled') then raise exception 'Invalid transition from scheduled'; end if;
 if v.status='active' and p_status not in('completed','cancelled') then raise exception 'Invalid transition from active'; end if;
 if p_status='scheduled' then
  if p_scheduled_at is null or p_scheduled_at<=now() then raise exception 'Scheduled campaigns require a future launch time'; end if;
  v_launch_at:=p_scheduled_at;
 elsif p_status='active' then
  v_launch_at:=now();
 else v_launch_at:=v.scheduled_at;
 end if;
 if p_status in('scheduled','active') then
  if not exists(select 1 from public.hive_members where hive_id=v.hive_id and business_id=v.spotlight_business_id and status='active') then raise exception 'Spotlight member is no longer active'; end if;
  if v.spotlight_offer_id is not null and not exists(select 1 from public.offers o where o.id=v.spotlight_offer_id and o.business_id=v.spotlight_business_id and o.status='active' and (o.starts_at is null or o.starts_at<=v_launch_at) and (o.ends_at is null or o.ends_at>=v_launch_at))
  then raise exception 'Spotlight offer is not valid at launch time'; end if;
  perform public.refresh_hive_campaign_audiences(p_campaign_id);
 end if;
 update public.hive_campaigns set status=p_status,scheduled_at=case when p_status in('scheduled','active') then v_launch_at else scheduled_at end,updated_at=now()
 where id=p_campaign_id returning * into v;
 return v;
end
$function$;
