import {NextRequest,NextResponse} from 'next/server';
import {createClient} from '@supabase/supabase-js';
const allowed=['new','accepted','contacted','qualified','won','lost'];
export async function PATCH(request:NextRequest,context:{params:Promise<{id:string}>}){
 const url=process.env.NEXT_PUBLIC_SUPABASE_URL,secret=process.env.SUPABASE_SECRET_KEY,pub=process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;
 if(!url||!secret||!pub)return NextResponse.json({error:'Not configured'},{status:503});
 const token=request.headers.get('authorization')?.replace(/^Bearer\s+/i,'');if(!token)return NextResponse.json({error:'Authentication required'},{status:401});
 const auth=createClient(url,pub,{auth:{persistSession:false,autoRefreshToken:false}});const user=(await auth.auth.getUser(token)).data.user;if(!user)return NextResponse.json({error:'Invalid session'},{status:401});
 const {id}=await context.params;let body:{status?:string;estimated_value?:number;closed_value?:number};try{body=await request.json();}catch{return NextResponse.json({error:'Invalid JSON'},{status:400});}
 if(body.status&&!allowed.includes(body.status))return NextResponse.json({error:'Invalid status'},{status:422});
 const admin=createClient(url,secret,{auth:{persistSession:false,autoRefreshToken:false}});
 const opp=(await admin.from('opportunities').select('id,status,estimated_value,closed_value,hive_id,lead_id,customer_id,receiving_business_id').eq('id',id).maybeSingle()).data;if(!opp)return NextResponse.json({error:'Opportunity not found'},{status:404});
 const membership=(await admin.from('business_users').select('role').eq('business_id',opp.receiving_business_id).eq('user_id',user.id).in('role',['owner','admin','manager']).maybeSingle()).data;if(!membership)return NextResponse.json({error:'Forbidden'},{status:403});
 const patch:Record<string,unknown>={};if(body.status!==undefined)patch.status=body.status;if(body.estimated_value!==undefined)patch.estimated_value=body.estimated_value;if(body.closed_value!==undefined)patch.closed_value=body.closed_value;if(!Object.keys(patch).length)return NextResponse.json({error:'No changes supplied'},{status:422});
 const updated=await admin.from('opportunities').update(patch).eq('id',id).select('id,status,estimated_value,closed_value').single();if(updated.error)return NextResponse.json({error:'Update failed'},{status:500});
 const events:any[]=[];if(body.status&&body.status!==opp.status){const type=body.status==='accepted'?'opportunity.accepted':body.status==='won'?'job.won':body.status==='lost'?'job.lost':'opportunity.status_changed';events.push({hive_id:opp.hive_id,business_id:opp.receiving_business_id,customer_id:opp.customer_id,lead_id:opp.lead_id,event_type:type,actor_type:'business_user',properties:{opportunity_id:id,from_status:opp.status,to_status:body.status,user_id:user.id}});}
 if(body.closed_value!==undefined&&Number(body.closed_value)!==Number(opp.closed_value||0))events.push({hive_id:opp.hive_id,business_id:opp.receiving_business_id,customer_id:opp.customer_id,lead_id:opp.lead_id,event_type:'revenue.recorded',actor_type:'business_user',properties:{opportunity_id:id,amount:body.closed_value,user_id:user.id}});
 if(events.length)await admin.from('events').insert(events);
 return NextResponse.json({opportunity:updated.data,events_recorded:events.length});
}