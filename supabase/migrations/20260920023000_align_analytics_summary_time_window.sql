-- Keep Analytics 7/30/90 day controls semantically consistent across all summary metrics.
create or replace function public.analytics_summary(p_days integer default 30)
returns jsonb
language plpgsql
stable
set search_path=''
as $$
declare
  v_cutoff timestamptz := now() - (greatest(1, least(coalesce(p_days,30),365)) || ' days')::interval;
  v jsonb;
begin
  select jsonb_build_object(
    'leads',(select count(*) from public.leads where received_at >= v_cutoff),
    'opportunities',(select count(*) from public.opportunities where created_at >= v_cutoff),
    'pipeline',(select coalesce(sum(estimated_value),0) from public.opportunities where created_at >= v_cutoff and status not in ('won','lost')),
    'revenue',(select coalesce(sum(closed_value),0) from public.opportunities where updated_at >= v_cutoff and status='won'),
    'won',(select count(*) from public.opportunities where updated_at >= v_cutoff and status='won'),
    'queued',(select count(*) from public.events where event_type='promotion.queued' and occurred_at >= v_cutoff),
    'sent',(select count(*) from public.events where event_type='promotion.sent' and occurred_at >= v_cutoff),
    'delivered',(select count(*) from public.events where event_type='promotion.delivered' and occurred_at >= v_cutoff),
    'accepted',(select count(*) from public.events where event_type='opportunity.accepted' and occurred_at >= v_cutoff),
    'attributed_clicks',(select count(*) from public.events where event_type in ('member.clicked','offer.clicked') and occurred_at >= v_cutoff and properties ? 'delivery_id'),
    'organic_clicks',(select count(*) from public.events where event_type in ('member.clicked','offer.clicked') and occurred_at >= v_cutoff and not (properties ? 'delivery_id'))
  ) into v;
  return v;
end
$$;
