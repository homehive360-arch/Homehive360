'use client';
type Props={href:string;hiveSlug:string;businessSlug:string;sourceSlug?:string;offerId?:string;eventType?:'member.clicked'|'offer.clicked';className?:string;children:React.ReactNode};
export default function TrackedLink({href,hiveSlug,businessSlug,sourceSlug,offerId,eventType='member.clicked',className,children}:Props){
 const track=()=>{const payload=JSON.stringify({hiveSlug,businessSlug,sourceSlug,offerId,eventType});if(typeof navigator!=='undefined'&&navigator.sendBeacon){navigator.sendBeacon('/api/v1/events/click',new Blob([payload],{type:'application/json'}));}else{fetch('/api/v1/events/click',{method:'POST',headers:{'content-type':'application/json'},body:payload,keepalive:true}).catch(()=>{});}};
 return <a className={className} href={href} rel="noopener noreferrer" onClick={track}>{children}</a>;
}
