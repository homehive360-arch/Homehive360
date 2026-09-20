import {NextRequest,NextResponse} from 'next/server';
import {createClient} from '@supabase/supabase-js';
export async function POST(request:NextRequest){
 const url=process.env.NEXT_PUBLIC_SUPABASE_URL,secret=process.env.SUPABASE_SECRET_KEY;if(!url||!secret)return NextResponse.json({ok:false},{status:503});
 let body:{pid?:string;hiveSlug?:string};try{body=await request.json();}catch{return NextResponse.json({ok:false},{status:400});}if(!body.pid||!body.hiveSlug)return NextResponse.json({ok:false},{status:422});
 const db=createClient(url,secret,{auth:{persistSession:false,autoRefreshToken:false}});const delivery=(await db.from('promotion_deliveries').select('id,lead_id,hive_id,source_business_id,customer_id').eq('tracking_token',body.pid).maybeSingle()).data;if(!delivery)return NextResponse.json({ok:false},{status:404});
 const hive=(await db.from('hives').select('slug').eq('id',delivery.hive_id).maybeSingle()).data;if(!hive||hive.slug!==body.hiveSlug)return NextResponse.json({ok:false},{status:404});
 const event=await db.rpc('record_public_attribution_event',{p_event_key:'visit:'+delivery.id,p_hive_id:delivery.hive_id,p_business_id:delivery.source_business_id,p_customer_id:delivery.customer_id,p_lead_id:delivery.lead_id,p_event_type:'hive_page.visited',p_properties:{delivery_id:delivery.id}});
 if(event.error)return NextResponse.json({ok:false},{status:500});return NextResponse.json({ok:true,recorded:Boolean(event.data)});
}