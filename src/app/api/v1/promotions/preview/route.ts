import {NextRequest,NextResponse} from 'next/server';
import {authorizeBusinessKey} from '@/lib/api/businessKey';
import {buildPromotionMessage} from '@/lib/promotion/message';
export async function POST(request:NextRequest){
 const url=process.env.NEXT_PUBLIC_SUPABASE_URL,secret=process.env.SUPABASE_SECRET_KEY;
 if(!url||!secret)return NextResponse.json({error:'Not configured'},{status:503});
 let body:{lead_id?:string};try{body=await request.json();}catch{return NextResponse.json({error:'Invalid JSON'},{status:400});}
 if(!body.lead_id)return NextResponse.json({error:'Missing lead_id'},{status:422});
 const auth=await authorizeBusinessKey(request,url,secret);if(!auth)return NextResponse.json({error:'Invalid API key'},{status:401});const db=auth.db;
 const lead=(await db.from('leads').select('id,hive_id,source_business_id,customer_id,marketing_email_allowed,marketing_sms_allowed').eq('id',body.lead_id).maybeSingle()).data;
 if(!lead)return NextResponse.json({error:'Lead not found'},{status:404});if(lead.source_business_id!==auth.businessId)return NextResponse.json({error:'Forbidden'},{status:403});
 if(!lead.marketing_email_allowed&&!lead.marketing_sms_allowed)return NextResponse.json({error:'Promotion consent not available'},{status:403});
 const customer=(await db.from('customers').select('first_name,email,phone').eq('id',lead.customer_id).maybeSingle()).data;
 const source=(await db.from('businesses').select('name,slug').eq('id',lead.source_business_id).maybeSingle()).data;
 const hive=(await db.from('hives').select('slug,market_name').eq('id',lead.hive_id).maybeSingle()).data;
 if(!customer||!source||!hive)return NextResponse.json({error:'Promotion context incomplete'},{status:409});
 const message=buildPromotionMessage({firstName:customer.first_name||'there',sourceBusinessName:source.name,hiveSlug:hive.slug,sourceBusinessSlug:source.slug,marketName:hive.market_name,appOrigin:process.env.NEXT_PUBLIC_APP_URL});
 const channels=[] as string[];if(lead.marketing_email_allowed&&customer.email)channels.push('email');if(lead.marketing_sms_allowed&&customer.phone)channels.push('sms');
 return NextResponse.json({lead_id:lead.id,channels,message});
}
