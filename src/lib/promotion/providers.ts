export type SendResult={ok:true;providerMessageId:string}|{ok:false;error:string};
export type EmailInput={to:string;subject:string;text:string};
export type SmsInput={to:string;text:string};
export type ProviderEvent={providerMessageId:string;status:'delivered'|'failed'};

export async function sendEmail(input:EmailInput):Promise<SendResult>{
 const key=process.env.RESEND_API_KEY,from=process.env.RESEND_FROM_EMAIL;
 if(!key||!from)return{ok:false,error:'Email provider not configured'};
 try{const r=await fetch('https://api.resend.com/emails',{method:'POST',headers:{Authorization:'Bearer '+key,'Content-Type':'application/json'},body:JSON.stringify({from,to:[input.to],subject:input.subject,text:input.text})});const data=await r.json().catch(()=>({}));if(!r.ok)return{ok:false,error:String(data?.message||'Email provider rejected request')};if(!data?.id)return{ok:false,error:'Email provider response missing message ID'};return{ok:true,providerMessageId:String(data.id)};}catch{return{ok:false,error:'Email provider unavailable'};}
}

export async function sendSms(input:SmsInput):Promise<SendResult>{
 const sid=process.env.TWILIO_ACCOUNT_SID,token=process.env.TWILIO_AUTH_TOKEN,from=process.env.TWILIO_FROM_NUMBER;
 if(!sid||!token||!from)return{ok:false,error:'SMS provider not configured'};
 try{const body=new URLSearchParams({To:input.to,From:from,Body:input.text});const r=await fetch('https://api.twilio.com/2010-04-01/Accounts/'+encodeURIComponent(sid)+'/Messages.json',{method:'POST',headers:{Authorization:'Basic '+Buffer.from(sid+':'+token).toString('base64'),'Content-Type':'application/x-www-form-urlencoded'},body});const data=await r.json().catch(()=>({}));if(!r.ok)return{ok:false,error:String(data?.message||'SMS provider rejected request')};if(!data?.sid)return{ok:false,error:'SMS provider response missing message ID'};return{ok:true,providerMessageId:String(data.sid)};}catch{return{ok:false,error:'SMS provider unavailable'};}
}

export function mapResendEvent(payload:any):ProviderEvent|null{
 const id=payload?.data?.email_id||payload?.data?.id,type=String(payload?.type||'');
 if(!id)return null;
 if(type==='email.delivered')return{providerMessageId:String(id),status:'delivered'};
 if(['email.bounced','email.delivery_delayed','email.failed'].includes(type))return{providerMessageId:String(id),status:'failed'};
 return null;
}
export function mapTwilioStatus(payload:Record<string,string>):ProviderEvent|null{
 const id=payload.MessageSid,status=String(payload.MessageStatus||'').toLowerCase();if(!id)return null;
 if(status==='delivered')return{providerMessageId:id,status:'delivered'};
 if(['failed','undelivered'].includes(status))return{providerMessageId:id,status:'failed'};
 return null;
}
