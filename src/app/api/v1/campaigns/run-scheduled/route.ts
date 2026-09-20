import {NextRequest,NextResponse} from 'next/server';import {createClient} from '@supabase/supabase-js';
export async function GET(request:NextRequest){return run(request)}export async function POST(request:NextRequest){return run(request)}
async function run(request:NextRequest){
 const secret=process.env.CAMPAIGN_CRON_SECRET,url=process.env.NEXT_PUBLIC_SUPABASE_URL,key=process.env.SUPABASE_SECRET_KEY;
 if(!secret||!url||!key)return NextResponse.json({error:'Campaign worker not configured'},{status:503});
 if(request.headers.get('authorization')!==`Bearer ${secret}`)return NextResponse.json({error:'Unauthorized'},{status:401});
 const db=createClient(url,key),errors:any[]=[];let activatedIds:string[]=[];
 const activated=await db.rpc('activate_due_hive_campaigns',{p_limit:25});
 if(activated.error)errors.push({stage:'activation',error:activated.error.message});else activatedIds=(activated.data||[]).map((x:any)=>x.campaign_id);
 const active=await db.from('hive_campaigns').select('id').eq('status','active').limit(25);
 if(active.error)errors.push({stage:'active_lookup',error:active.error.message});
 const batches=[];for(const campaign of active.data||[]){try{const q=await db.rpc('queue_hive_campaign_batch',{p_campaign_id:campaign.id,p_limit:1000});if(q.error){errors.push({stage:'queue',campaign_id:campaign.id,error:q.error.message});batches.push({campaign_id:campaign.id,error:q.error.message});}else batches.push({campaign_id:campaign.id,result:q.data});}catch(e){const message=e instanceof Error?e.message:'Unknown queue error';errors.push({stage:'queue',campaign_id:campaign.id,error:message});batches.push({campaign_id:campaign.id,error:message});}}
 return NextResponse.json({ok:errors.length===0,activated:activatedIds,activation_count:activatedIds.length,batches,errors},{status:errors.length?207:200});
}