export type PromotionMessageInput={firstName:string;sourceBusinessName:string;hiveSlug:string;sourceBusinessSlug:string;marketName?:string|null;appOrigin?:string};
export function buildPromotionMessage(input:PromotionMessageInput){
 const origin=(input.appOrigin||'https://home-hive-360-app.vercel.app').replace(/\/$/,'');
 const hiveUrl=origin+'/h/'+encodeURIComponent(input.hiveSlug)+'?ref='+encodeURIComponent(input.sourceBusinessSlug);
 const market=input.marketName?(' in '+input.marketName):'';
 return {
  hiveUrl,
  emailSubject:'Trusted local home services from '+input.sourceBusinessName,
  emailText:'Hi '+input.firstName+', thanks for choosing '+input.sourceBusinessName+'. As a customer, you can explore their trusted Home Hive network'+market+': '+hiveUrl,
  smsText:'Hi '+input.firstName+' — '+input.sourceBusinessName+' is part of a trusted local Home Hive. Explore their recommended home-service network: '+hiveUrl
 };
}
