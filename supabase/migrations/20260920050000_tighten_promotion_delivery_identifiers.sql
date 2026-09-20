drop index if exists public.promotion_deliveries_token_idx;
create unique index if not exists promotion_deliveries_provider_message_id_unique
on public.promotion_deliveries(provider_message_id)
where provider_message_id is not null;
