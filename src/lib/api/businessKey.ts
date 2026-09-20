import {createHash,timingSafeEqual} from 'crypto';
import {createClient,SupabaseClient} from '@supabase/supabase-js';
export type BusinessKeyAuth={db:SupabaseClient;businessId:string;keyId:string};
export type BusinessKeyAuthResult={ok:true;auth:BusinessKeyAuth}|{ok:false;status:401|500;error:string};
export async function authorizeBusinessKey(request:Request,url:string,secret:string):Promise<BusinessKeyAuthResult>{
 const raw=request.headers.get('x-hh360-key');if(!raw)return{ok:false,status:401,error:'Missing API key'};
 const db=createClient(url,secret,{auth:{persistSession:false,autoRefreshToken:false}}),hash=createHash('sha256').update(raw).digest('hex');
 const lookup=await db.from('business_api_keys').select('id,business_id,key_hash').eq('key_hash',hash).eq('is_active',true).maybeSingle();
 if(lookup.error)return{ok:false,status:500,error:'API key authorization unavailable'};
 const key=lookup.data;if(!key)return{ok:false,status:401,error:'Invalid API key'};
 const a=Buffer.from(hash),b=Buffer.from(String(key.key_hash));if(a.length!==b.length||!timingSafeEqual(a,b))return{ok:false,status:401,error:'Invalid API key'};
 db.from('business_api_keys').update({last_used_at:new Date().toISOString()}).eq('id',key.id).then(()=>{});
 return{ok:true,auth:{db,businessId:key.business_id,keyId:key.id}};
}
