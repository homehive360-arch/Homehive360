import {createClient} from '@supabase/supabase-js';
import {NextRequest,NextResponse} from 'next/server';
import {mapResendEvent} from '@/lib/promotion/providers';

export async function POST(request:NextRequest){
 const url=process.env.NEXT_PUBLIC_SUPABASE_URL,secret=process.env.SUPABASE_SECRET_KEY,webhookSecret=process.env.RESEND_WEBHOOK_SECRET;
 if(!url||!secret||!webhookSecret)return NextResponse.json({error:'Not configured'},{status:503});
 const supplied=request.headers.get('x-hh360-webhook-secret');
 if(!supplied||supplied!==webhookSecret)return NextResponse.json({error:'Unauthorized'},{status:401});
 let body:any;try{body=await request.json();}catch{return NextResponse.json({error:'Invalid JSON'},{status:400});}
 const event=mapResendEvent(body);if(!event)return NextResponse.json({ok:true,ignored:true});
 const db=createClient(url,secret,{auth:{persistSession:false,autoRefreshToken:false}});
 const delivery=(await db.from('promotion_deliveries').select('id,status').eq('provider_message_id',event.providerMessageId).maybeSingle()).data;
 if(!delivery)return NextResponse.json({ok:true,ignored:true});
 if(delivery.status===event.status)return NextResponse.json({ok:true,idempotent:true});
 const r=await db.rpc('update_promotion_delivery_atomic',{p_id:delivery.id,p_expected_status:delivery.status,p_status:event.status,p_provider_message_id:event.providerMessageId});
 if(r.error)return NextResponse.json({error:'Delivery update failed'},{status:409});
 return NextResponse.json({ok:true});
}
