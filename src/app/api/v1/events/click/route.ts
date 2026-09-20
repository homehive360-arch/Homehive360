import {NextResponse} from 'next/server';
export async function POST(){
 return NextResponse.json({error:'Endpoint retired. Use /api/v1/events/hive-click.'},{status:410});
}
