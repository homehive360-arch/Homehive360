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
