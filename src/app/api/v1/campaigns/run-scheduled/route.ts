import {NextRequest,NextResponse} from 'next/server';import {createClient} from '@supabase/supabase-js';
export async function POST(request:NextRequest){
 const secret=process.env.CAMPAIGN_CRON_SECRET,url=process.env.NEXT_PUBLIC_SUPABASE_URL,key=process.env.SUPABASE_SECRET_KEY;
 if(!secret||!url||!key)return NextResponse.json({error:'Campaign worker not configured'},{status:503});
 if(request.headers.get('authorization')!==`Bearer ${secret}`)return NextResponse.json({error:'Unauthorized'},{status:401});
 const db=createClient(url,key);const activated=await db.rpc('activate_due_hive_campaigns',{p_limit:25});
 if(activated.error)return NextResponse.json({error:'Activation failed'},{status:500});
 return NextResponse.json({ok:true,activated:(activated.data||[]).map((x:any)=>x.campaign_id),count:(activated.data||[]).length});
}