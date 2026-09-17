import { createBrowserClient } from '@supabase/ssr';
const projectUrl='https://jwubracnpdoerasoyykk.supabase.co';
const publishableKey='sb_publishable_0ekcsm5Dv1KOh9dq5iD2DA_j1XHnsHT';
export function createBrowserSupabase(){return createBrowserClient(process.env.NEXT_PUBLIC_SUPABASE_URL||projectUrl,process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY||publishableKey);}
