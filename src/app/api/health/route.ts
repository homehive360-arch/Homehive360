import { NextResponse } from 'next/server';
import { createClient } from '@supabase/supabase-js';

export async function GET(){
  const url=process.env.NEXT_PUBLIC_SUPABASE_URL;
  const secret=process.env.SUPABASE_SECRET_KEY;
  if(!url||!secret)return NextResponse.json({status:'degraded',database:false,lead_ingestion:false},{status:503});
  const admin=createClient(url,secret,{auth:{persistSession:false,autoRefreshToken:false}});
  const {error}=await admin.from('hives').select('id',{head:true,count:'exact'}).limit(1);
  if(error)return NextResponse.json({status:'degraded',database:false,lead_ingestion:true},{status:503});
  return NextResponse.json({status:'ok',database:true,lead_ingestion:true});
}
