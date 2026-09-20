-- Campaign workers deliberately claim deliveries one at a time through
-- claim_promotion_delivery_for_send(). That canonical RPC revalidates the
-- lead, Hive, source membership, customer ownership, consent and destination
-- immediately before provider dispatch. Keep no weaker batch-claim bypass.
drop function if exists public.claim_campaign_deliveries_for_worker(integer);
