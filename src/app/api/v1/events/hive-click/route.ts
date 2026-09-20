import {NextRequest,NextResponse} from 'next/server';
import {createClient} from '@supabase/supabase-js';
export async function POST(request:NextRequest){
 const url=process.env.NEXT_PUBLIC_SUPABASE_URL,secret=process.env.SUPABASE_SECRET_KEY;if(!url||!secret)return NextResponse.json({error:'Not configured'},{status:503});
 let body:{hiveSlug?:string;businessSlug?:string;sourceSlug?:string;pid?:string;offerId?:string;eventType?:string};try{body=await request.json();}catch{return NextResponse.json({error:'Invalid JSON'},{status:400});}
 if(!body.hiveSlug||!body.businessSlug)return NextResponse.json({error:'Missing target'},{status:422});
 const db=createClient(url,secret,{auth:{persistSession:false,autoRefreshToken:false}});
 const hive=(await db.from('hives').select('id').eq('slug',body.hiveSlug).eq('status','active').maybeSingle()).data,business=(await db.from('businesses').select('id').eq('slug',body.businessSlug).eq('status','active').maybeSingle()).data;if(!hive||!business)return NextResponse.json({error:'Not found'},{status:404});
 const member=(await db.from('hive_members').select('business_id').eq('hive_id',hive.id).eq('business_id',business.id).eq('status','active').maybeSingle()).data;if(!member)return NextResponse.json({error:'Not found'},{status:404});
 if(body.offerId){const offer=(await db.from('offers').select('id').eq('id',body.offerId).eq('business_id',business.id).eq('hive_id',hive.id).eq('status','active').maybeSingle()).data;if(!offer)return NextResponse.json({error:'Invalid offer'},{status:422});}
 let delivery:any=null;if(body.pid){delivery=(await db.from('promotion_deliveries').select('id,lead_id,hive_id,source_business_id,customer_id').eq('tracking_token',body.pid).maybeSingle()).data;if(!delivery||delivery.hive_id!==hive.id)return NextResponse.json({error:'Invalid promotion token'},{status:422});}
 let sourceId=delivery?.source_business_id||null;if(!sourceId&&body.sourceSlug)sourceId=(await db.from('businesses').select('id').eq('slug',body.sourceSlug).maybeSingle()).data?.id||null;
 const eventType=body.eventType==='offer.clicked'?'offer.clicked':'member.clicked';
 const eventKey=delivery?'click:'+delivery.id+':'+business.id+':'+(body.offerId||'member')+':'+eventType:'organic:'+hive.id+':'+business.id+':'+(body.offerId||'member')+':'+eventType+':'+new Date().toISOString().slice(0,13);
 const result=await db.rpc('record_public_attribution_event',{p_event_key:eventKey,p_hive_id:hive.id,p_business_id:business.id,p_customer_id:delivery?.customer_id||null,p_lead_id:delivery?.lead_id||null,p_event_type:eventType,p_properties:{delivery_id:delivery?.id||null,source_business_id:sourceId,source_slug:body.sourceSlug||null,target_business_id:business.id,offer_id:body.offerId||null,channel:'hive_page'}});
 if(result.error)return NextResponse.json({error:'Event not recorded'},{status:500});return NextResponse.json({ok:true,attributed:Boolean(delivery),recorded:Boolean(result.data)});
}