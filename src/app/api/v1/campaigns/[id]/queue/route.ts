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
 const leads=await service.from('leads').select('id,source_business_id,marketing_email_allowed,marketing_sms_allowed').eq('hive_id',campaign.data.hive_id).in('source_business_id',sources).limit(1000);
 if(leads.error)return NextResponse.json({error:'Could not load campaign audience'},{status:500});
 let queued=0,skipped=0,failed=0;
 for(const lead of leads.data||[]){
  const channels:string[]=[];if(campaign.data.email_enabled&&lead.marketing_email_allowed)channels.push('email');if(campaign.data.sms_enabled&&lead.marketing_sms_allowed)channels.push('sms');
  for(const channel of channels){const q=await service.rpc('queue_hive_campaign_delivery',{p_campaign_id:id,p_lead_id:lead.id,p_channel:channel});if(q.error){if(/ineligible/i.test(q.error.message))skipped++;else failed++;}else queued++;}
 }
 return NextResponse.json({campaign_id:id,audience_records:(leads.data||[]).length,queued,skipped,failed,batch_limit:1000});
}
