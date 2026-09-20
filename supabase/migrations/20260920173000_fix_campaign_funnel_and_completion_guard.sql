-- Correct campaign funnel linkage: attribution events store delivery_id in JSON properties.
create or replace function public.hive_campaign_funnel(p_campaign_id uuid)
returns jsonb language sql security invoker set search_path='' stable as $function$
 with d as(select pd.id,pd.status from public.promotion_deliveries pd where pd.campaign_id=p_campaign_id),
 e as(select count(*) filter(where ev.event_type='hive_page.visited')::bigint hive_visits,count(*) filter(where ev.event_type='member.clicked')::bigint member_engagements,count(*) filter(where ev.event_type='offer.clicked')::bigint offer_intent from public.events ev where nullif(ev.properties->>'delivery_id','') is not null and exists(select 1 from d where d.id::text=ev.properties->>'delivery_id')),
 o as(select count(*)::bigint opportunities,count(*) filter(where status='won')::bigint wins,coalesce(sum(closed_value) filter(where status='won'),0)::numeric attributed_revenue from public.opportunities where campaign_id=p_campaign_id),
 del as(select count(*)::bigint delivery_total,count(*) filter(where status='queued')::bigint queued,count(*) filter(where status='sending')::bigint sending,count(*) filter(where status='sent')::bigint sent,count(*) filter(where status='delivered')::bigint delivered,count(*) filter(where status in('failed','bounced'))::bigint failed from d),
 r as(select audience_processed,deliveries_skipped,deliveries_failed,status queue_status from public.hive_campaign_runs where campaign_id=p_campaign_id)
 select jsonb_build_object('audience_processed',coalesce(r.audience_processed,0),'eligibility_skipped',coalesce(r.deliveries_skipped,0),'queue_failures',coalesce(r.deliveries_failed,0),'queue_status',coalesce(r.queue_status,'not_started'),'delivery_total',del.delivery_total,'queued',del.queued,'sending',del.sending,'sent',del.sent,'delivered',del.delivered,'failed',del.failed,'hive_visits',coalesce(e.hive_visits,0),'member_engagements',coalesce(e.member_engagements,0),'offer_intent',coalesce(e.offer_intent,0),'opportunities',o.opportunities,'wins',o.wins,'attributed_revenue',o.attributed_revenue) from del cross join e cross join o left join r on true
$function$;
revoke all on function public.hive_campaign_funnel(uuid) from public,anon;grant execute on function public.hive_campaign_funnel(uuid) to authenticated;

-- Completion is intentionally separated from generic lifecycle mutation so delivery completion cannot be bypassed.
create or replace function public.set_hive_campaign_status(p_campaign_id uuid,p_status text,p_scheduled_at timestamptz default null)
returns public.hive_campaigns language plpgsql security definer set search_path='' as $function$
declare v public.hive_campaigns;v_launch_at timestamptz;
begin
 select * into v from public.hive_campaigns where id=p_campaign_id for update;if v.id is null then raise exception 'Campaign not found';end if;
 if not exists(select 1 from public.hive_members hm join public.business_users bu on bu.business_id=hm.business_id where hm.hive_id=v.hive_id and hm.status='active' and bu.user_id=(select auth.uid()) and bu.role in('owner','admin')) then raise exception 'Not authorized to manage this Hive';end if;
 if p_status not in('scheduled','active','cancelled') then raise exception 'Use complete_hive_campaign to complete campaigns';end if;
 if v.status in('completed','cancelled') then raise exception 'Completed or cancelled campaigns are terminal';end if;
 if v.status='draft' and p_status not in('scheduled','active','cancelled') then raise exception 'Invalid transition from draft';end if;
 if v.status='scheduled' and p_status not in('active','cancelled') then raise exception 'Invalid transition from scheduled';end if;
 if v.status='active' and p_status<>'cancelled' then raise exception 'Active campaigns may only be cancelled here; use complete_hive_campaign for completion';end if;
 if p_status='scheduled' then if p_scheduled_at is null or p_scheduled_at<=now() then raise exception 'Scheduled campaigns require a future launch time';end if;v_launch_at:=p_scheduled_at;
 elsif p_status='active' then v_launch_at:=now();else v_launch_at:=v.scheduled_at;end if;
 if p_status in('scheduled','active') then
  if not exists(select 1 from public.hive_members where hive_id=v.hive_id and business_id=v.spotlight_business_id and status='active') then raise exception 'Spotlight member is no longer active';end if;
  if v.spotlight_offer_id is not null and not exists(select 1 from public.offers o where o.id=v.spotlight_offer_id and o.business_id=v.spotlight_business_id and o.status='active' and (o.starts_at is null or o.starts_at<=v_launch_at) and (o.ends_at is null or o.ends_at>=v_launch_at)) then raise exception 'Spotlight offer is not valid at launch time';end if;
  perform public.refresh_hive_campaign_audiences(p_campaign_id);
 end if;
 update public.hive_campaigns set status=p_status,scheduled_at=case when p_status in('scheduled','active') then v_launch_at else scheduled_at end,updated_at=now() where id=p_campaign_id returning * into v;return v;
end $function$;
