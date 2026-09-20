'use client';
import {useMemo,useState} from 'react';
import Link from 'next/link';
import Shell from '@/components/Shell';

const selected=[
 ['Roofing','Platinum Roofing'],
 ['Electrical','Certified Electric, Inc'],
 ['General Contractor','G Core Construction'],
 ['Landscaping','Ground Effects Landscaping'],
 ['Pool Service',"Jeff's Pool and Spa Service"],
];
const open=['HVAC','Plumbing','Pest Control','House Cleaning','Painting','Handyman','Pressure Washing','Windows & Doors','Garage Doors','Flooring','Restoration'];

export default function BrunswickDemoHive(){
 const [seats,setSeats]=useState<Record<string,string>>(()=>Object.fromEntries(selected));
 const [states,setStates]=useState<Record<string,string>>(()=>Object.fromEntries(selected.map(x=>[x[0],'prospective'])));
 const [query,setQuery]=useState('');
 const categories=useMemo(()=>[...selected.map(x=>x[0]),...open].filter(x=>x.toLowerCase().includes(query.toLowerCase())),[query]);
 const filled=Object.values(seats).filter(Boolean).length;
 function clearSeat(category:string){setSeats(s=>({...s,[category]:''}));setStates(s=>({...s,[category]:'prospective'}));}
 function restoreSeat(category:string){const found=selected.find(x=>x[0]===category);if(found){setSeats(s=>({...s,[category]:found[1]}));setStates(s=>({...s,[category]:'prospective'}));}}
 function advance(category:string){const order=['prospective','invited','accepted'];const current=states[category]||'prospective';const next=order[Math.min(order.indexOf(current)+1,order.length-1)];setStates(s=>({...s,[category]:next}));}
 return <Shell>
  <div className="eyebrow">Reference Hive · Demo Data</div>
  <div className="sectionHead"><div><h1 className="title">Brunswick / Golden Isles Hive</h1><p className="sub">Build-board example using businesses already represented in the Home Hive 360 Directory. Selection does not imply membership.</p></div><Link className="btn secondary" href="/hives">Back to Hives</Link></div>
  <section className="section two">
   <div className="card"><div className="sectionHead"><div><b>Prospective Roster</b><div className="label">5 category seats selected · 11 seats open</div></div><span className="badge">DEMO</span></div>
    <table className="table"><thead><tr><th>Category</th><th>Directory Candidate</th><th>Status</th></tr></thead><tbody>{selected.map(([category,name])=><tr key={category}><td>{category}</td><td><b>{name}</b></td><td><span className="badge">PROSPECT</span></td></tr>)}</tbody></table>
   </div>
   <div className="card"><b>Open Recruiting Seats</b><p className="sub">Complementary categories still needed to build out the Brunswick network.</p><div style={{display:'flex',gap:8,flexWrap:'wrap',marginTop:14}}>{open.map(x=><span className="badge" key={x}>{x} · OPEN</span>)}</div><hr style={{margin:'20px 0',border:0,borderTop:'1px solid #e4eae4'}}/><b>Hive Readiness</b><div className="funnel" style={{marginTop:14}}><div className="step"><span className="label">Selected seats</span><b>5</b></div><div className="step"><span className="label">Accepted members</span><b>0</b></div><div className="step"><span className="label">Audiences connected</span><b>0</b></div><div className="step"><span className="label">Campaign ready</span><b>0</b></div></div></div>
  </section>
  <section className="section card"><div className="sectionHead"><div><b>Build from Directory</b><div className="label">Prototype seat planner · changes on this demo page are not saved and do not create memberships.</div></div><span className="badge">{filled} SELECTED</span></div><div className="field" style={{marginTop:14}}><label>Filter service categories</label><input value={query} onChange={e=>setQuery(e.target.value)} placeholder="Roofing, plumbing, HVAC…"/></div><table className="table" style={{marginTop:14}}><thead><tr><th>Category Seat</th><th>Selected Directory Company</th><th>Action</th></tr></thead><tbody>{categories.map(category=>{const company=seats[category]||'';return <tr key={category}><td><b>{category}</b></td><td>{company?<><b>{company}</b><div className="label">{(states[category]||'prospective').toUpperCase()}</div></>:<span className="label">Open seat</span>}</td><td>{company?<div style={{display:'flex',gap:8,flexWrap:'wrap'}}>{states[category]!=='accepted'?<button className="btn secondary" onClick={()=>advance(category)}>{states[category]==='invited'?'Mark Accepted':'Mark Invited'}</button>:<span className="badge">ACCEPTED</span>}<button className="btn secondary" onClick={()=>clearSeat(category)}>Clear</button></div>:selected.some(x=>x[0]===category)?<button className="btn secondary" onClick={()=>restoreSeat(category)}>Restore prospect</button>:<span className="badge">RECRUIT</span>}</td></tr>})}</tbody></table><p className="sub" style={{marginTop:14}}>The production version will source candidates from the Directory by market and category, then create invitations rather than memberships.</p></section>
  <section className="section card"><div className="sectionHead"><div><b>Directory → Hive Activation</b><div className="label">Prospects remain outside live campaign reach until they accept membership and connect an eligible audience.</div></div><span className="badge">BUILDING</span></div><div className="funnel" style={{marginTop:14}}>{['Directory Company','Selected Seat','Invitation','Accepted Member','Audience Connected','Campaign Ready'].map((x,i)=><div className="step" key={x}><span className="label">STEP {i+1}</span><b>{x}</b></div>)}</div></section>
  <section className="section card"><b>Reference Monthly Campaign</b><p className="sub">When this Hive becomes campaign-ready, the entire network is promoted every month while one active member receives the rotating Spotlight. Any audience, engagement, opportunity, job, or revenue figures used on this reference page must remain explicitly marked DEMO/SIMULATED.</p></section>
 </Shell>;
}
