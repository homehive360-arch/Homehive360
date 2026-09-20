alter table public.promotion_deliveries
 add column if not exists sending_at timestamptz;

create or replace function public.claim_promotion_delivery_for_send(p_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare d public.promotion_deliveries%rowtype;
begin
 update public.promotion_deliveries
 set status='sending', sending_at=now()
 where id=p_id and status='queued'
 returning * into d;
 if not found then raise exception 'delivery_not_queued'; end if;
 return jsonb_build_object('id',d.id,'status',d.status,'channel',d.channel,'sending_at',d.sending_at);
end $function$;

create index if not exists promotion_deliveries_sending_at_idx
on public.promotion_deliveries(sending_at)
where status='sending';
