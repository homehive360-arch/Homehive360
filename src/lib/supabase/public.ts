import { createClient } from '@supabase/supabase-js';

const projectUrl = 'https://jwubracnpdoerasoyykk.supabase.co';
const publishableKey = 'sb_publishable_0ekcsm5Dv1KOh9dq5iD2DA_j1XHnsHT';

export function createPublicClient() {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL || projectUrl;
  const key = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY || publishableKey;
  return createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });
}
