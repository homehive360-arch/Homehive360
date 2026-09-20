alter table public.promotion_deliveries
 drop constraint if exists promotion_deliveries_provider_state_check,
 add constraint promotion_deliveries_provider_state_check check (
   (status in ('queued','sending') and provider_message_id is null and sent_at is null and delivered_at is null)
   or (status='sent' and provider_message_id is not null and sent_at is not null and delivered_at is null)
   or (status='delivered' and provider_message_id is not null and sent_at is not null and delivered_at is not null)
   or (status='failed' and delivered_at is null)
 );
