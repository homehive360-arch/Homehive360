import {createClient} from '@supabase/supabase-js';
import {NextRequest,NextResponse} from 'next/server';
import {Webhook} from 'svix';
import {mapResendEvent} from '@/lib/promotion/providers';

export async function POST(request:NextRequest){
 const url=process.env.NEXT_PUBLIC_SUPABASE_URL,secret=process.env.SUPABASE_SECRET_KEY,webhookSecret=process.env.RESEND_WEBHOOK_SECRET;
 if(!url||!secret||!webhookSecret)return NextResponse.json({error:'Not configured'},{status:503});
 const raw=await request.text();let body:any;
 try{body=new Webhook(webhookSecret).verify(raw,{'svix-id':request.headers.get('svix-id')||'','svix-timestamp':request.headers.get('svix-timestamp')||'','svix-signature':request.headers.get('svix-signature')||''});}
 catch{return NextResponse.json({error:'Invalid webhook signature'},{status:401});}
 const event=mapResendEvent(body);if(!event)return NextResponse.json({ok:true,ignored:true});
 const db=createClient(url,secret,{auth:{persistSession:false,autoRefreshToken:false}});
 const lookup=await db.from('promotion_deliveries').select('id,status').eq('provider_message_id',event.providerMessageId).maybeSingle();if(lookup.error)return NextResponse.json({error:'Delivery lookup failed'},{status:500});const delivery=lookup.data;
 if(!delivery)return NextResponse.json({ok:true,ignored:true});
 if(delivery.status===event.status)return NextResponse.json({ok:true,idempotent:true});
 const r=await db.rpc('update_promotion_delivery_atomic',{p_id:delivery.id,p_expected_status:delivery.status,p_status:event.status,p_provider_message_id:event.providerMessageId});
 if(r.error){const concurrent=r.error.message?.includes('delivery_changed')||r.error.message?.includes('invalid_delivery_transition');if(concurrent)return NextResponse.json({ok:true,ignored:true,reason:'stale_webhook'});return NextResponse.json({error:'Delivery update failed'},{status:500});}
 return NextResponse.json({ok:true});
}
