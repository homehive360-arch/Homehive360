import {SupabaseClient} from '@supabase/supabase-js';

export async function consumeRateLimit(db:SupabaseClient,bucketKey:string,limit=60,windowSeconds=60){
 const r=await db.rpc('consume_api_rate_limit',{p_bucket_key:bucketKey,p_window_seconds:windowSeconds,p_limit:limit});
 if(r.error)return{ok:false as const,error:'Rate limiter unavailable'};
 return{ok:Boolean(r.data),error:null};
}
