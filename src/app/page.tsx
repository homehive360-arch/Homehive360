import Shell from '@/components/Shell';
import { createPublicClient } from '@/lib/supabase/public';

export const dynamic = 'force-dynamic';

const money = (value: number) => new Intl.NumberFormat('en-US', {
  style: 'currency', currency: 'USD', maximumFractionDigits: 0,
}).format(value);

export default async function Page() {
  const db = createPublicClient();

  const [hivesResult, membersResult] = await Promise.all([
    db.from('hives').select('id,name,slug,status').eq('status','active'),
    db.from('hive_members').select('hive_id,business_id,display_order,businesses(id,name,slug)').eq('status','active').order('display_order'),
  ]);

  const hives = hivesResult.data || [];
  const members = membersResult.data || [];
  const golden = hives.find((h:any) => h.slug === 'golden-isles') || hives[0];
  const goldenMembers = golden ? members.filter((m:any) => m.hive_id === golden.id) : [];

  // Sensitive lead/opportunity/revenue rows stay behind RLS. The public command center
  // intentionally shows zero until an authenticated business dashboard is introduced.
  const leads = 0;
  const opportunities = 0;
  const revenue = 0;

  return <Shell>
    <div className="eyebrow">Command Center</div>
    <h1 className="title">Home Hive 360</h1>
    <p className="sub">Live network data from the Home Hive 360 Hub. Customer and opportunity data remains private to authorized members.</p>

    <div className="grid">
      <div className="card"><span className="label">Active Hives</span><div className="metric">{hives.length}</div></div>
      <div className="card"><span className="label">Active Members</span><div className="metric">{members.length}</div></div>
      <div className="card"><span className="label">Opportunities Created</span><div className="metric">{opportunities}</div></div>
      <div className="card"><span className="label">Attributed Revenue</span><div className="metric">{money(revenue)}</div></div>
    </div>

    <section className="section two">
      <div className="card">
        <div className="sectionHead"><div><b>{golden?.name || 'No active Hive yet'}</b><div className="label">Live network status</div></div>{golden && <span className="badge">ACTIVE</span>}</div>
        <div className="funnel">
          <div className="step"><span className="label">Members</span><b>{goldenMembers.length}</b></div>
          <div className="step"><span className="label">Leads</span><b>{leads}</b></div>
          <div className="step"><span className="label">Opportunities</span><b>{opportunities}</b></div>
          <div className="step"><span className="label">Revenue</span><b>{money(revenue)}</b></div>
        </div>
      </div>
      <div className="card"><b>What HH360 measures</b><p className="sub" style={{marginTop:10}}>Every member should be able to see the economic value created by participating in the Hive.</p><div className="label">Lead → Exposure → Action → Opportunity → Revenue</div></div>
    </section>

    <section className="section card">
      <div className="sectionHead"><div><b>{golden?.name || 'Hive'} Members</b><div className="label">Live member records from Supabase</div></div></div>
      {goldenMembers.length ? <table className="table"><thead><tr><th>Business</th><th>Status</th><th>Hive</th></tr></thead><tbody>{goldenMembers.map((m:any)=><tr key={`${m.hive_id}-${m.business_id}`}><td>{m.businesses?.name || 'Business'}</td><td><span className="badge">ACTIVE</span></td><td>{golden?.name}</td></tr>)}</tbody></table> : <p className="sub">No active members found.</p>}
    </section>
  </Shell>;
}
