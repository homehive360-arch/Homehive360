import {NextRequest,NextResponse} from 'next/server';
import {createClient} from '@supabase/supabase-js';
import {buildPromotionMessage} from '@/lib/promotion/message';
export async function POST(request:NextRequest){
 const url=process.env.NEXT_PUBLIC_SUPABASE_URL,secret=process.env.SUPABASE_SECRET_KEY;
 if(!url||!secret)return NextResponse.json({error:'Not configured'},{status:503});
 let body:{lead_id?:string};try{body=await request.json();}catch{return NextResponse.json({error:'Invalid JSON'},{status:400});}
 if(!body.lead_id)return NextResponse.json({error:'Missing lead_id'},{status:422});
 const db=createClient(url,secret,{auth:{persistSession:false,autoRefreshToken:false}});
 const lead=(await db.from('leads').select('id,hive_id,source_business_id,customer_id,marketing_email_allowed,marketing_sms_allowed').eq('id',body.lead_id).maybeSingle()).data;
 if(!lead)return NextResponse.json({error:'Lead not found'},{status:404});
 const customer=(await db.from('customers').select('first_name,email,phone').eq('id',lead.customer_id).maybeSingle()).data;
 const source=(await db.from('businesses').select('name,slug').eq('id',lead.source_business_id).maybeSingle()).data;
 const hive=(await db.from('hives').select('slug,market_name').eq('id',lead.hive_id).maybeSingle()).data;
 if(!customer||!source||!hive)return NextResponse.json({error:'Promotion context incomplete'},{status:409});
 const message=buildPromotionMessage({firstName:customer.first_name||'there',sourceBusinessName:source.name,hiveSlug:hive.slug,sourceBusinessSlug:source.slug,marketName:hive.market_name,appOrigin:process.env.NEXT_PUBLIC_APP_URL});
 const queued:string[]=[];
 if(lead.marketing_email_allowed&&customer.email)queued.push('email');
 if(lead.marketing_sms_allowed&&customer.phone)queued.push('sms');
 if(!queued.length)return NextResponse.json({error:'No consented delivery channel available'},{status:403});
 const eventRows=queued.map(channel=>({hive_id:lead.hive_id,business_id:lead.source_business_id,customer_id:lead.customer_id,lead_id:lead.id,event_type:'promotion.queued',actor_type:'system',properties:{channel,source_business_id:lead.source_business_id,hive_url:message.hiveUrl,delivery_status:'awaiting_provider'}}));
 const inserted=await db.from('events').insert(eventRows);if(inserted.error)return NextResponse.json({error:'Could not queue promotion'},{status:500});
 return NextResponse.json({lead_id:lead.id,status:'queued',channels:queued,message});
}