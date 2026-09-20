import {createClient} from '@supabase/supabase-js';
import {NextRequest,NextResponse} from 'next/server';
import twilio from 'twilio';
import {mapTwilioStatus} from '@/lib/promotion/providers';

export async function POST(request:NextRequest){
 const url=process.env.NEXT_PUBLIC_SUPABASE_URL,secret=process.env.SUPABASE_SECRET_KEY,authToken=process.env.TWILIO_AUTH_TOKEN;
 if(!url||!secret||!authToken)return NextResponse.json({error:'Not configured'},{status:503});
 const form=await request.formData();const payload:Record<string,string>={};form.forEach((v,k)=>{payload[k]=String(v)});
 const signature=request.headers.get('x-twilio-signature')||'';
 const configuredOrigin=(process.env.NEXT_PUBLIC_APP_URL||'').replace(/\/$/,'');const callbackUrl=configuredOrigin?configuredOrigin+new URL(request.url).pathname:request.url;
 if(!signature||!twilio.validateRequest(authToken,signature,callbackUrl,payload))return NextResponse.json({error:'Invalid webhook signature'},{status:401});
 const event=mapTwilioStatus(payload);if(!event)return NextResponse.json({ok:true,ignored:true});
 const db=createClient(url,secret,{auth:{persistSession:false,autoRefreshToken:false}});
 const delivery=(await db.from('promotion_deliveries').select('id,status').eq('provider_message_id',event.providerMessageId).maybeSingle()).data;
 if(!delivery)return NextResponse.json({ok:true,ignored:true});
 if(delivery.status===event.status)return NextResponse.json({ok:true,idempotent:true});
 const r=await db.rpc('update_promotion_delivery_atomic',{p_id:delivery.id,p_expected_status:delivery.status,p_status:event.status,p_provider_message_id:event.providerMessageId});
 if(r.error)return NextResponse.json({error:'Delivery update failed'},{status:409});
 return NextResponse.json({ok:true});
}
