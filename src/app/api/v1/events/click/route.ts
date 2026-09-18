import { NextRequest, NextResponse } from 'next/server';
import { createClient } from '@supabase/supabase-js';

export async function POST(request:NextRequest){
 const url=process.env.NEXT_PUBLIC_SUPABASE_URL;
 const secret=process.env.SUPABASE_SECRET_KEY;
 if(!url||!secret)return NextResponse.json({ok:false},{status:503});
 let body:{hiveSlug?:string;businessSlug?:string;sourceSlug?:string;offerId?:string;eventType?:string};
 try{body=await request.json();}catch{return NextResponse.json({ok:false},{status:400});}
 if(!body.hiveSlug||!body.businessSlug)return NextResponse.json({ok:false},{status:422});
 const db=createClient(url,secret,{auth:{persistSession:false,autoRefreshToken:false}});
 const {data:hive}=await db.from('hives').select('id').eq('slug',body.hiveSlug).eq('status','active').maybeSingle();
 const {data:business}=await db.from('businesses').select('id').eq('slug',body.businessSlug).eq('status','active').maybeSingle();
 if(!hive||!business)return NextResponse.json({ok:false},{status:404});
 const {data:member}=await db.from('hive_members').select('business_id').eq('hive_id',hive.id).eq('business_id',business.id).eq('status','active').maybeSingle();
 if(!member)return NextResponse.json({ok:false},{status:404});
 let sourceId:string|null=null;
 if(body.sourceSlug){const {data:source}=await db.from('businesses').select('id').eq('slug',body.sourceSlug).maybeSingle();sourceId=source?.id||null;}
 const eventType=body.eventType==='offer.clicked'?'offer.clicked':'member.clicked';
 await db.from('events').insert({hive_id:hive.id,business_id:business.id,event_type:eventType,actor_type:'customer',properties:{source_business_id:sourceId,source_slug:body.sourceSlug||null,target_business_id:business.id,offer_id:body.offerId||null,channel:'hive_page'}});
 return NextResponse.json({ok:true});
}
