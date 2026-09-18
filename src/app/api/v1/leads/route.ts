import { NextRequest, NextResponse } from 'next/server';
import { createClient } from '@supabase/supabase-js';
import { createHash } from 'crypto';

type LeadPayload = { first_name?: string; last_name?: string; email?: string; phone?: string; zip?: string; service?: string; source?: string; external_lead_id?: string; marketing_email_allowed?: boolean; marketing_sms_allowed?: boolean; metadata?: Record<string, unknown> };
const emailOf=(v?:string)=>v?.trim().toLowerCase()||null;
const phoneOf=(v?:string)=>{const d=v?.replace(/\D/g,'')||'';return d.length>=10?d:null;};

export async function POST(request:NextRequest){
  const apiKey=request.headers.get('x-hh360-key');
  if(!apiKey)return NextResponse.json({error:'Missing x-hh360-key credential.'},{status:401});
  const url=process.env.NEXT_PUBLIC_SUPABASE_URL,secret=process.env.SUPABASE_SECRET_KEY;
  if(!url||!secret)return NextResponse.json({error:'Lead ingestion is not configured.'},{status:503});

  let body:LeadPayload;
  try{body=await request.json();}catch{return NextResponse.json({error:'Request body must be valid JSON.'},{status:400});}
  const email=emailOf(body.email),phone=phoneOf(body.phone);
  if(!body.first_name?.trim())return NextResponse.json({error:'Missing required field: first_name'},{status:422});
  if(!email&&!phone)return NextResponse.json({error:'A valid email or phone is required.'},{status:422});

  const admin=createClient(url,secret,{auth:{persistSession:false,autoRefreshToken:false}});
  const keyHash=createHash('sha256').update(apiKey).digest('hex');
  const {data:keyRecord}=await admin.from('business_api_keys').select('id,business_id').eq('key_hash',keyHash).eq('is_active',true).maybeSingle();
  if(!keyRecord)return NextResponse.json({error:'Invalid API key.'},{status:401});
  await admin.from('business_api_keys').update({last_used_at:new Date().toISOString()}).eq('id',keyRecord.id);

  const {data:membership}=await admin.from('hive_members').select('hive_id').eq('business_id',keyRecord.business_id).eq('status','active').limit(1).maybeSingle();
  if(!membership)return NextResponse.json({error:'Business is not an active Hive member.'},{status:403});

  if(body.external_lead_id){
    const {data:existing}=await admin.from('leads').select('id,received_at').eq('source_business_id',keyRecord.business_id).eq('external_lead_id',body.external_lead_id).maybeSingle();
    if(existing)return NextResponse.json({lead_id:existing.id,received_at:existing.received_at,duplicate:true},{status:200});
  }

  let customerId:string|null=null;
  if(email){const {data}=await admin.from('customers').select('id').eq('email',email).limit(1).maybeSingle();customerId=data?.id||null;}
  if(!customerId&&phone){const {data}=await admin.from('customers').select('id').eq('phone',phone).limit(1).maybeSingle();customerId=data?.id||null;}
  if(!customerId){
    const {data,error}=await admin.from('customers').insert({first_name:body.first_name.trim(),last_name:body.last_name?.trim()||null,email,phone,postal_code:body.zip?.trim()||null}).select('id').single();
    if(error)return NextResponse.json({error:'Could not create customer.'},{status:500});
    customerId=data.id;
  }

  const {data:lead,error}=await admin.from('leads').insert({source_business_id:keyRecord.business_id,hive_id:membership.hive_id,customer_id:customerId,external_lead_id:body.external_lead_id||null,source_channel:body.source||'api',service_requested:body.service||null,status:'received',marketing_email_allowed:body.marketing_email_allowed===true,marketing_sms_allowed:body.marketing_sms_allowed===true,metadata:body.metadata||{}}).select('id,received_at').single();
  if(error)return NextResponse.json({error:'Could not create lead.'},{status:500});

  await admin.from('events').insert({hive_id:membership.hive_id,business_id:keyRecord.business_id,customer_id:customerId,lead_id:lead.id,event_type:'lead.received',actor_type:'system',properties:{source:body.source||'api',service:body.service||null}});

  let opportunityCount=0;
  const promotionAllowed=body.marketing_email_allowed===true||body.marketing_sms_allowed===true;
  if(promotionAllowed){
    const {data:members}=await admin.from('hive_members').select('business_id').eq('hive_id',membership.hive_id).eq('status','active').neq('business_id',keyRecord.business_id);
    const receivingIds=(members||[]).map(m=>m.business_id);
    if(receivingIds.length){
      const {data:offers}=await admin.from('offers').select('id,business_id').eq('hive_id',membership.hive_id).eq('status','active').in('business_id',receivingIds);
      const offerByBusiness=new Map((offers||[]).map(o=>[o.business_id,o.id]));
      const rows=receivingIds.map(receiving_business_id=>({hive_id:membership.hive_id,lead_id:lead.id,source_business_id:keyRecord.business_id,receiving_business_id,customer_id:customerId,offer_id:offerByBusiness.get(receiving_business_id)||null}));
      const {data:created}=await admin.from('opportunities').insert(rows).select('id,receiving_business_id');
      opportunityCount=created?.length||0;
      if(created?.length){
        await admin.from('events').insert(created.map(o=>({hive_id:membership.hive_id,business_id:o.receiving_business_id,customer_id:customerId,lead_id:lead.id,event_type:'opportunity.created',actor_type:'system',properties:{source_business_id:keyRecord.business_id,opportunity_id:o.id}})));
      }
    }
  }

  return NextResponse.json({lead_id:lead.id,received_at:lead.received_at,promotion_eligible:promotionAllowed,opportunities_created:opportunityCount},{status:201});
}
