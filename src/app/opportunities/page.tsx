import Shell from '@/components/Shell';

export default function Opportunities() {
  return (
    <Shell>
      <div className="eyebrow">Revenue Attribution</div>
      <h1 className="title">Opportunities</h1>
      <p className="sub">Track the business value created when one member's customer engages another Hive member.</p>

      <div className="grid">
        <div className="card"><span className="label">New</span><div className="metric">—</div></div>
        <div className="card"><span className="label">Accepted</span><div className="metric">—</div></div>
        <div className="card"><span className="label">Won</span><div className="metric">—</div></div>
        <div className="card"><span className="label">Attributed Revenue</span><div className="metric">—</div></div>
      </div>

      <section className="section card">
        <div className="sectionHead"><div><b>Opportunity Pipeline</b><div className="label">Member-specific records appear after secure sign-in</div></div><span className="badge">PRIVATE</span></div>
        <div style={{padding:'34px 0',textAlign:'center'}}>
          <h2>No public opportunity data</h2>
          <p className="sub" style={{maxWidth:680,margin:'8px auto 0'}}>Opportunity details are intentionally protected. Authenticated members will see only opportunities they originated or are authorized to receive.</p>
        </div>
      </section>
    </Shell>
  );
}
