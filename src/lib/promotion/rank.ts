export type PromotionCandidate={businessId:string;businessName:string;category:string;offerId?:string;offerTitle?:string;score:number;reason:string};
const normalize=(v?:string|null)=>String(v||'').toLowerCase().replace(/[^a-z0-9 ]/g,' ').replace(/\s+/g,' ').trim();
const aliases:Record<string,string[]>={
 hvac:['hvac','ac','a c','air conditioning','air conditioner','heating','heat pump','furnace'],
 plumbing:['plumbing','plumber','pipe','drain','water heater','sewer'],
 roofing:['roofing','roofer','roof','shingle','leak'],
 electrical:['electrical','electrician','electric','wiring','breaker','panel'],
 landscaping:['landscaping','landscape','lawn','yard'],
 cleaning:['cleaning','cleaner','maid','house cleaning'],
 handyman:['handyman','repair','maintenance']
};
function sameService(requested:string,category:string){
 if(!requested||!category)return false;
 const categoryTerms=new Set([category,...Object.entries(aliases).filter(([k,v])=>category.includes(k)||v.some(a=>category.includes(a))).flatMap(([k,v])=>[k,...v])]);
 return [...categoryTerms].some(term=>term.length>1&&(requested===term||requested.includes(term)||term.includes(requested)));
}
export function rankPromotionCandidates(input:{sourceBusinessId:string;serviceRequested?:string|null;members:Array<{businessId:string;businessName:string;category?:string|null;offerId?:string;offerTitle?:string}>}){
 const requested=normalize(input.serviceRequested);
 return input.members.filter(m=>m.businessId!==input.sourceBusinessId).map(m=>{const category=normalize(m.category)||'home service';let score=50;const reasons:string[]=[];if(m.offerId){score+=20;reasons.push('active_offer');}if(sameService(requested,category)){score-=40;reasons.push('same_service_suppressed');}else reasons.push('complementary_service');return{businessId:m.businessId,businessName:m.businessName,category:m.category||'Home Service',offerId:m.offerId,offerTitle:m.offerTitle,score,reason:reasons.join(',')};}).sort((a,b)=>b.score-a.score||a.businessName.localeCompare(b.businessName)).slice(0,3);
}
