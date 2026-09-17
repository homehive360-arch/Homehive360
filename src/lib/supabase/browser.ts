import { createBrowserClient } from '@supabase/ssr';

export function createBrowserSupabase() {
  const projectUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const publishableKey = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;

  if (!projectUrl || !publishableKey) {
    throw new Error('Home Hive 360 is missing its Supabase environment configuration.');
  }

  return createBrowserClient(projectUrl, publishableKey);
}
