import {NextRequest,NextResponse} from 'next/server';
import {createClient} from '@supabase/supabase-js';
export async function POST(request:NextRequest){
 const url=process.env.NEXT_PUBLIC_SUPABASE_URL,secret=process.env.SUPABASE_SECRET_KEY;if(!url||!secret)return NextResponse.json({error:'Not configured'},{status:503});
 let body:{lead_id?:string;channel?:'email'|'sms';provider_message_id?:string;status?:'sent'|'delivered'|'failed'};
 try{body=await request.json();}catch{return NextResponse.json({error:'Invalid JSON'},{status:400});}
 if(!body.lead_id||!body.channel||!body.status)return NextResponse.json({error:'Missing delivery fields'},{status:422});
 if(!['sent','delivered','failed'].includes(body.status))return NextResponse.json({error:'Invalid status'},{status:422});
 const db=createClient(url,secret,{auth:{persistSession:false,autoRefreshToken:false}});
 const lead=(await db.from('leads').select('id,hive_id,source_business_id,customer_id').eq('id',body.lead_id).maybeSingle()).data;if(!lead)return NextResponse.json({error:'Lead not found'},{status:404});
 const eventType=body.status==='sent'?'promotion.sent':body.status==='delivered'?'promotion.delivered':'promotion.failed';
 const result=await db.from('events').insert({hive_id:lead.hive_id,business_id:lead.source_business_id,customer_id:lead.customer_id,lead_id:lead.id,event_type:eventType,actor_type:'system',properties:{channel:body.channel,provider_message_id:body.provider_message_id||null}});
 if(result.error)return NextResponse.json({error:'Could not record delivery'},{status:500});
 return NextResponse.json({ok:true,event_type:eventType});
}