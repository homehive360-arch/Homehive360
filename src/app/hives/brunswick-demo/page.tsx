'use client';
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
 return <Shell>
  <div className="eyebrow">Reference Hive · Demo Data</div>
  <div className="sectionHead"><div><h1 className="title">Brunswick / Golden Isles Hive</h1><p className="sub">Build-board example using businesses already represented in the Home Hive 360 Directory. Selection does not imply membership.</p></div><Link className="btn secondary" href="/hives">Back to Hives</Link></div>
  <section className="section two">
   <div className="card"><div className="sectionHead"><div><b>Prospective Roster</b><div className="label">5 category seats selected · 11 seats open</div></div><span className="badge">DEMO</span></div>
    <table className="table"><thead><tr><th>Category</th><th>Directory Candidate</th><th>Status</th></tr></thead><tbody>{selected.map(([category,name])=><tr key={category}><td>{category}</td><td><b>{name}</b></td><td><span className="badge">PROSPECT</span></td></tr>)}</tbody></table>
   </div>
   <div className="card"><b>Open Recruiting Seats</b><p className="sub">Complementary categories still needed to build out the Brunswick network.</p><div style={{display:'flex',gap:8,flexWrap:'wrap',marginTop:14}}>{open.map(x=><span className="badge" key={x}>{x} · OPEN</span>)}</div><hr style={{margin:'20px 0',border:0,borderTop:'1px solid #e4eae4'}}/><b>Hive Readiness</b><div className="funnel" style={{marginTop:14}}><div className="step"><span className="label">Selected seats</span><b>5</b></div><div className="step"><span className="label">Accepted members</span><b>0</b></div><div className="step"><span className="label">Audiences connected</span><b>0</b></div><div className="step"><span className="label">Campaign ready</span><b>0</b></div></div></div>
  </section>
  <section className="section card"><div className="sectionHead"><div><b>Directory → Hive Activation</b><div className="label">Prospects remain outside live campaign reach until they accept membership and connect an eligible audience.</div></div><span className="badge">BUILDING</span></div><div className="funnel" style={{marginTop:14}}>{['Directory Company','Selected Seat','Invitation','Accepted Member','Audience Connected','Campaign Ready'].map((x,i)=><div className="step" key={x}><span className="label">STEP {i+1}</span><b>{x}</b></div>)}</div></section>
  <section className="section card"><b>Reference Monthly Campaign</b><p className="sub">When this Hive becomes campaign-ready, the entire network is promoted every month while one active member receives the rotating Spotlight. Any audience, engagement, opportunity, job, or revenue figures used on this reference page must remain explicitly marked DEMO/SIMULATED.</p></section>
 </Shell>;
}
