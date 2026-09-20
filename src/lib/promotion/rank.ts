export type PromotionCandidate={businessId:string;businessName:string;category:string;offerId?:string;offerTitle?:string;score:number};
export function rankPromotionCandidates(input:{sourceBusinessId:string;serviceRequested?:string|null;members:Array<{businessId:string;businessName:string;category?:string|null;offerId?:string;offerTitle?:string}>}){
 const requested=(input.serviceRequested||'').toLowerCase();
 return input.members.filter(m=>m.businessId!==input.sourceBusinessId).map(m=>{const category=(m.category||'Home Service').toLowerCase();let score=50;if(m.offerId)score+=20;if(requested&&category&&requested.includes(category))score-=30;return{businessId:m.businessId,businessName:m.businessName,category:m.category||'Home Service',offerId:m.offerId,offerTitle:m.offerTitle,score};}).sort((a,b)=>b.score-a.score||a.businessName.localeCompare(b.businessName)).slice(0,3);
}
