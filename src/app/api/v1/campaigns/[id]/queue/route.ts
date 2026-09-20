import {NextRequest,NextResponse} from 'next/server';
import {createClient} from '@supabase/supabase-js';

export async function POST(request:NextRequest,{params}:{params:Promise<{id:string}>}){
 const {id}=await params;const url=process.env.NEXT_PUBLIC_SUPABASE_URL,secret=process.env.SUPABASE_SECRET_KEY;
 if(!url||!secret)return NextResponse.json({error:'Not configured'},{status:503});
 const auth=request.headers.get('authorization');if(!auth?.startsWith('Bearer '))return NextResponse.json({error:'Unauthorized'},{status:401});
 const token=auth.slice(7),userDb=createClient(url,process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY||'',{global:{headers:{Authorization:`Bearer ${token}`}}}),service=createClient(url,secret);
 const user=await userDb.auth.getUser(token);if(!user.data.user)return NextResponse.json({error:'Unauthorized'},{status:401});
 const campaign=await userDb.from('hive_campaigns').select('id,hive_id,status,email_enabled,sms_enabled').eq('id',id).maybeSingle();
 if(campaign.error||!campaign.data)return NextResponse.json({error:'Campaign not found or unavailable'},{status:404});
 if(campaign.data.status!=='active')return NextResponse.json({error:'Campaign must be active before queueing'},{status:409});
 const membership=await userDb.from('hive_members').select('business_id').eq('hive_id',campaign.data.hive_id).eq('status','active');
 if(membership.error)return NextResponse.json({error:'Could not load Hive members'},{status:500});
 const sources=(membership.data||[]).map(x=>x.business_id);if(!sources.length)return NextResponse.json({error:'Hive has no active members'},{status:409});
 const existing=await service.from('hive_campaign_runs').select('*').eq('campaign_id',id).maybeSingle();if(existing.error)return NextResponse.json({error:'Could not load campaign progress'},{status:500});if(existing.data?.status==='queue_complete')return NextResponse.json({campaign_id:id,status:'queue_complete',progress:existing.data});
 let query=service.from('leads').select('id,source_business_id,marketing_email_allowed,marketing_sms_allowed').eq('hive_id',campaign.data.hive_id).in('source_business_id',sources).order('id',{ascending:true}).limit(1000);if(existing.data?.last_lead_id)query=query.gt('id',existing.data.last_lead_id);const leads=await query;
 if(leads.error)return NextResponse.json({error:'Could not load campaign audience'},{status:500});
 let queued=0,skipped=0,failed=0;
 for(const lead of leads.data||[]){
  const channels:string[]=[];if(campaign.data.email_enabled&&lead.marketing_email_allowed)channels.push('email');if(campaign.data.sms_enabled&&lead.marketing_sms_allowed)channels.push('sms');
  for(const channel of channels){const q=await service.rpc('queue_hive_campaign_delivery',{p_campaign_id:id,p_lead_id:lead.id,p_channel:channel});if(q.error){if(/ineligible/i.test(q.error.message))skipped++;else failed++;}else queued++;}
 }
 const rows=leads.data||[],lastLeadId=rows.length?rows[rows.length-1].id:existing.data?.last_lead_id||null,complete=rows.length<1000;const totals={audience_processed:Number(existing.data?.audience_processed||0)+rows.length,deliveries_queued:Number(existing.data?.deliveries_queued||0)+queued,deliveries_skipped:Number(existing.data?.deliveries_skipped||0)+skipped,deliveries_failed:Number(existing.data?.deliveries_failed||0)+failed};const progress=await service.from('hive_campaign_runs').upsert({campaign_id:id,status:complete?'queue_complete':'running',last_lead_id:lastLeadId,...totals,updated_at:new Date().toISOString(),completed_at:complete?new Date().toISOString():null},{onConflict:'campaign_id'}).select().single();if(progress.error)return NextResponse.json({error:'Campaign batch processed but progress could not be saved'},{status:500});return NextResponse.json({campaign_id:id,status:complete?'queue_complete':'running',batch:{audience_records:rows.length,queued,skipped,failed},progress:progress.data,next_batch:!complete});
}
