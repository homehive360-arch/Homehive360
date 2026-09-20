import {createHash} from 'crypto';
import {createClient,SupabaseClient} from '@supabase/supabase-js';
export async function authorizeBusinessKey(request:Request,url:string,secret:string):Promise<{db:SupabaseClient;businessId:string}|null>{
 const raw=request.headers.get('x-hh360-key');if(!raw)return null;const db=createClient(url,secret,{auth:{persistSession:false,autoRefreshToken:false}});const hash=createHash('sha256').update(raw).digest('hex');const key=(await db.from('business_api_keys').select('id,business_id').eq('key_hash',hash).eq('is_active',true).maybeSingle()).data;if(!key)return null;await db.from('business_api_keys').update({last_used_at:new Date().toISOString()}).eq('id',key.id);return{db,businessId:key.business_id};
}