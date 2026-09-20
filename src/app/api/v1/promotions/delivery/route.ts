import {NextRequest,NextResponse} from 'next/server';
import {authorizeBusinessKey} from '@/lib/api/businessKey';
import {consumeRateLimit} from '@/lib/api/rateLimit';
const allowed:Record<string,string[]>={queued:['sent','failed'],sent:['delivered','failed'],delivered:[],failed:[]};
export async function POST(request:NextRequest){
 const url=process.env.NEXT_PUBLIC_SUPABASE_URL,secret=process.env.SUPABASE_SECRET_KEY;if(!url||!secret)return NextResponse.json({error:'Not configured'},{status:503});
 let body:{delivery_id?:string;provider_message_id?:string;status?:'sent'|'delivered'|'failed'};try{body=await request.json();}catch{return NextResponse.json({error:'Invalid JSON'},{status:400});}
 if(!body.delivery_id||!body.status)return NextResponse.json({error:'Missing delivery fields'},{status:422});if(!['sent','delivered','failed'].includes(body.status))return NextResponse.json({error:'Invalid status'},{status:422});
 const authResult=await authorizeBusinessKey(request,url,secret);if(!authResult.ok)return NextResponse.json({error:authResult.error},{status:authResult.status});const auth=authResult.auth,db=auth.db;const rate=await consumeRateLimit(db,'promotion:delivery:'+auth.keyId,60,60);if(!rate.ok)return NextResponse.json({error:rate.error||'Rate limit exceeded'},{status:rate.error?503:429});
 const delivery=(await db.from('promotion_deliveries').select('id,status,source_business_id').eq('id',body.delivery_id).maybeSingle()).data;if(!delivery)return NextResponse.json({error:'Delivery not found'},{status:404});if(delivery.source_business_id!==auth.businessId)return NextResponse.json({error:'Forbidden'},{status:403});
 if(delivery.status===body.status)return NextResponse.json({ok:true,status:delivery.status,duplicate:true});if(!(allowed[delivery.status]||[]).includes(body.status))return NextResponse.json({error:'Invalid delivery transition',from:delivery.status,to:body.status},{status:409});
 const atomic=await db.rpc('update_promotion_delivery_atomic',{p_id:delivery.id,p_expected_status:delivery.status,p_status:body.status,p_provider_message_id:body.provider_message_id??null});
 if(atomic.error){const changed=atomic.error.message?.includes('delivery_changed');const invalid=atomic.error.message?.includes('invalid_delivery_transition');return NextResponse.json({error:changed?'Delivery changed concurrently; reload and retry':invalid?'Invalid delivery transition':'Atomic delivery update failed'},{status:changed||invalid?409:500});}
 return NextResponse.json({ok:true,delivery:atomic.data,audited:true});
}