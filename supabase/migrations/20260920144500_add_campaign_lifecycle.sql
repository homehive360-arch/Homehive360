-- Campaign lifecycle: validate, snapshot audience reach, and schedule/activate.
create or replace function public.set_hive_campaign_status(
 p_campaign_id uuid,p_status text,p_scheduled_at timestamptz default null
) returns public.hive_campaigns
language plpgsql security definer set search_path=''
as $function$
declare v public.hive_campaigns;v_offer public.offers;
begin
 select * into v from public.hive_campaigns where id=p_campaign_id;
 if v.id is null then raise exception 'Campaign not found'; end if;
 if not exists(select 1 from public.hive_members hm join public.business_users bu on bu.business_id=hm.business_id
  where hm.hive_id=v.hive_id and bu.user_id=(select auth.uid()) and bu.role in('owner','admin'))
 then raise exception 'Not authorized to manage this Hive'; end if;
 if p_status not in('draft','scheduled','active','completed','cancelled') then raise exception 'Invalid campaign status'; end if;
 if p_status in('scheduled','active') then
  if not exists(select 1 from public.hive_members where hive_id=v.hive_id and business_id=v.spotlight_business_id and status='active')
  then raise exception 'Spotlight member is no longer active'; end if;
  if v.spotlight_offer_id is not null then
   select * into v_offer from public.offers where id=v.spotlight_offer_id;
   if v_offer.id is null or v_offer.business_id<>v.spotlight_business_id or v_offer.status<>'active'
    or (v_offer.starts_at is not null and v_offer.starts_at>coalesce(p_scheduled_at,now()))
    or (v_offer.ends_at is not null and v_offer.ends_at<coalesce(p_scheduled_at,now()))
   then raise exception 'Spotlight offer will not be active for campaign launch'; end if;
  end if;
  perform public.refresh_hive_campaign_audiences(p_campaign_id);
 end if;
 update public.hive_campaigns set status=p_status,
  scheduled_at=case when p_status='scheduled' then coalesce(p_scheduled_at,scheduled_at) when p_status='active' then coalesce(scheduled_at,now()) else scheduled_at end,
  updated_at=now()
 where id=p_campaign_id returning * into v;
 return v;
end
$function$;
revoke all on function public.set_hive_campaign_status(uuid,text,timestamptz) from public,anon;
grant execute on function public.set_hive_campaign_status(uuid,text,timestamptz) to authenticated;
