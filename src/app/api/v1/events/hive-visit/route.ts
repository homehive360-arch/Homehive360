import {NextRequest,NextResponse} from 'next/server';
import {createClient} from '@supabase/supabase-js';
export async function POST(request:NextRequest){
 const url=process.env.NEXT_PUBLIC_SUPABASE_URL,secret=process.env.SUPABASE_SECRET_KEY;if(!url||!secret)return NextResponse.json({ok:false},{status:503});
 let body:{pid?:string;hiveSlug?:string};try{body=await request.json();}catch{return NextResponse.json({ok:false},{status:400});}
 if(!body.pid||!body.hiveSlug)return NextResponse.json({ok:false},{status:422});
 const db=createClient(url,secret,{auth:{persistSession:false,autoRefreshToken:false}});
 const delivery=(await db.from('promotion_deliveries').select('id,lead_id,hive_id,source_business_id,customer_id').eq('tracking_token',body.pid).maybeSingle()).data;if(!delivery)return NextResponse.json({ok:false},{status:404});
 const hive=(await db.from('hives').select('slug').eq('id',delivery.hive_id).maybeSingle()).data;if(!hive||hive.slug!==body.hiveSlug)return NextResponse.json({ok:false},{status:404});
 const exists=(await db.from('events').select('id').eq('lead_id',delivery.lead_id).eq('event_type','hive_page.visited').contains('properties',{delivery_id:delivery.id}).limit(1).maybeSingle()).data;
 if(!exists)await db.from('events').insert({hive_id:delivery.hive_id,business_id:delivery.source_business_id,customer_id:delivery.customer_id,lead_id:delivery.lead_id,event_type:'hive_page.visited',actor_type:'customer',properties:{delivery_id:delivery.id,tracking_token:body.pid}});
 return NextResponse.json({ok:true});
}