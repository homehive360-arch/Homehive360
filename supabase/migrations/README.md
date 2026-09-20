# Home Hive 360 database

The production database is managed in Supabase project `jwubracnpdoerasoyykk`.

## Migration discipline

Supabase is the authoritative migration ledger. Database changes must be applied as named migrations, followed by the Supabase Security Advisor. A clean security pass is required after DDL.

The application depends on Row Level Security for tenant isolation. Browser-facing management RPCs use SECURITY INVOKER. SECURITY DEFINER functions are reserved for server-only atomic operations and must have a locked empty search_path and no anon/authenticated EXECUTE grant.

## Current baseline

Core domains: profiles, businesses, business_users, hives, hive_members, services, offers, customers, leads, events, opportunities, promotion_deliveries, and business_api_keys.

Important invariants include source-owned customer identity, idempotent external lead ingestion, unique lead/receiver opportunities, nonnegative opportunity values, constrained offer URLs/windows, controlled lifecycle enums, and least-privilege mutation grants.

## Source parity

The live Supabase migration history currently predates this repository migration directory. Do not fabricate historical SQL from the final schema. New migrations should be committed here at the same time they are applied so the repository becomes the durable source for future database evolution.
