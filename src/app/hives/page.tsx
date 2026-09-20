'use client';
import {useEffect,useState} from 'react';
import Link from 'next/link';
import Shell from '@/components/Shell';
import {createBrowserSupabase} from '@/lib/supabase/browser';
type Hive={id:string;name:string;slug:string;status:string;market_name:string|null;headline:string|null};
type Member={hive_id:string;business_id:string;status:string;businesses:{name:string;slug:string;services:{category:string|null}[]} | null};
export default function Hives(){
 const [hives,setHives]=useState<Hive[]>([]),[members,setMembers]=useState<Member[]>([]),[loading,setLoading]=useState(true),[signedIn,setSignedIn]=useState(false);
 useEffect(()=>{(async()=>{const db=createBrowserSupabase();const auth=await db.auth.getUser();if(!auth.data.user){setLoading(false);return;}setSignedIn(true);const [h,m]=await Promise.all([db.from('hives').select('id,name,slug,status,market_name,headline').order('created_at'),db.from('hive_members').select('hive_id,business_id,status,businesses(name,slug,services(category))').order('display_order')]);setHives((h.data||[]) as Hive[]);setMembers((m.data||[]) as Member[]);setLoading(false);})();},[]);
 return <Shell><div className="eyebrow">Network Builder</div><div className="sectionHead"><div><h1 className="title">Hives</h1><p className="sub">Build local networks of complementary home-service businesses.</p></div><Link className="btn" href="/onboarding">+ Create Hive</Link></div>
 {!signedIn&&!loading?<div className="card"><h2>Sign in to manage Hives</h2></div>:null}
 {loading?<div className="card">Loading Hives…</div>:hives.map(h=>{const hm=members.filter(m=>m.hive_id===h.id&&m.status==='active');const categories=new Set(hm.flatMap(m=>m.businesses?.services||[]).map(s=>s.category).filter(Boolean));return <div key={h.id}><div className="card hiveCard"><div><span className="badge">{h.status.toUpperCase()}</span><h2>{h.name}</h2><p className="sub" style={{margin:0}}>{h.market_name||'Local market'} · {hm.length} members · {categories.size} service categories</p></div><div><Link className="btn secondary" href={'/h/'+h.slug}>Preview Hive</Link></div></div><section className="section two"><div className="card"><b>Hive Members</b><table className="table"><tbody>{hm.map(m=><tr key={m.business_id}><td>{m.businesses?.name||'Business'}</td><td>{m.businesses?.services?.[0]?.category||'Home Service'}</td><td><span className="badge">Active</span></td></tr>)}</tbody></table>{hm.length===0?<p className="sub">No active members yet.</p>:null}</div><div className="card"><b>Public Hive Experience</b><p className="sub" style={{marginTop:10}}>{h.headline||"Each member's customers can discover trusted complementary businesses in this Hive."}</p><div className="field"><label>Hive URL</label><input value={'/h/'+h.slug} readOnly/></div><br/><Link className="btn secondary" href={'/h/'+h.slug}>Open Public Page</Link></div></section></div>})}
 </Shell>;
}
