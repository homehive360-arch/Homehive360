-- Durable campaign execution progress for resumable audience queueing.
create table if not exists public.hive_campaign_runs(
 id uuid primary key default gen_random_uuid(),
 campaign_id uuid not null references public.hive_campaigns(id) on delete cascade,
 status text not null default 'running' check(status in('running','queue_complete','failed')),
 last_lead_id uuid,
 audience_processed bigint not null default 0,
 deliveries_queued bigint not null default 0,
 deliveries_skipped bigint not null default 0,
 deliveries_failed bigint not null default 0,
 started_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 completed_at timestamptz,
 unique(campaign_id)
);
alter table public.hive_campaign_runs enable row level security;
create policy "members can view campaign runs" on public.hive_campaign_runs for select to authenticated using(exists(
 select 1 from public.hive_campaigns c join public.hive_members hm on hm.hive_id=c.hive_id
 join public.business_users bu on bu.business_id=hm.business_id
 where c.id=hive_campaign_runs.campaign_id and bu.user_id=(select auth.uid())
));


-- Freeze the eligible audience at campaign activation so resumable batches
-- operate on a stable recipient set.
create table if not exists public.hive_campaign_recipients(
 campaign_id uuid not null references public.hive_campaigns(id) on delete cascade,
 lead_id uuid not null references public.leads(id) on delete cascade,
 source_business_id uuid not null references public.businesses(id),
 customer_id uuid not null references public.customers(id) on delete cascade,
 email_eligible boolean not null default false,
 sms_eligible boolean not null default false,
 created_at timestamptz not null default now(),
 primary key(campaign_id,lead_id),
 unique(campaign_id,customer_id)
);
alter table public.hive_campaign_recipients enable row level security;
create policy "members can view campaign recipient counts" on public.hive_campaign_recipients for select to authenticated using(false);
create or replace function public.snapshot_hive_campaign_recipients(p_campaign_id uuid)
returns bigint language plpgsql security definer set search_path='' as $function$
declare v_hive uuid;v_count bigint;
begin
 select hive_id into v_hive from public.hive_campaigns where id=p_campaign_id;if v_hive is null then raise exception 'Campaign not found';end if;
 delete from public.hive_campaign_recipients where campaign_id=p_campaign_id;
 insert into public.hive_campaign_recipients(campaign_id,lead_id,source_business_id,customer_id,email_eligible,sms_eligible)
 select p_campaign_id,l.id,l.source_business_id,l.customer_id,l.marketing_email_allowed,l.marketing_sms_allowed from public.leads l
 join public.hive_members hm on hm.hive_id=l.hive_id and hm.business_id=l.source_business_id and hm.status='active'
 where l.hive_id=v_hive and (l.marketing_email_allowed or l.marketing_sms_allowed)
 on conflict(campaign_id,customer_id) do update set
  email_eligible=hive_campaign_recipients.email_eligible or excluded.email_eligible,
  sms_eligible=hive_campaign_recipients.sms_eligible or excluded.sms_eligible;
 get diagnostics v_count=row_count;return v_count;
end $function$;
revoke all on function public.snapshot_hive_campaign_recipients(uuid) from public,anon,authenticated;grant execute on function public.snapshot_hive_campaign_recipients(uuid) to service_role;

create or replace function public.hive_campaign_recipient_count(p_campaign_id uuid)
returns bigint language sql security definer set search_path='' stable as $function$
 select count(*)::bigint from public.hive_campaign_recipients r
 where r.campaign_id=p_campaign_id and exists(
  select 1 from public.hive_campaigns c join public.hive_members hm on hm.hive_id=c.hive_id
  join public.business_users bu on bu.business_id=hm.business_id
  where c.id=r.campaign_id and hm.status='active' and bu.user_id=(select auth.uid())
 );
$function$;
revoke all on function public.hive_campaign_recipient_count(uuid) from public,anon;
grant execute on function public.hive_campaign_recipient_count(uuid) to authenticated;
