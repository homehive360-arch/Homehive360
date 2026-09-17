import Shell from '@/components/Shell';

export default function Leads() {
  return (
    <Shell>
      <div className="eyebrow">Demand Engine</div>
      <h1 className="title">Lead Hub</h1>
      <p className="sub">Every member-generated lead enters the Hub, keeps its source attribution and can create new Hive exposure.</p>

      <div className="grid">
        <div className="card"><span className="label">Leads Received</span><div className="metric">—</div><span className="label">Visible after member sign-in</span></div>
        <div className="card"><span className="label">Validated</span><div className="metric">—</div><span className="label">Protected business data</span></div>
        <div className="card"><span className="label">Hive Eligible</span><div className="metric">—</div><span className="label">Consent-aware</span></div>
        <div className="card"><span className="label">Opportunities</span><div className="metric">—</div><span className="label">Attributed to source</span></div>
      </div>

      <section className="section card">
        <div className="sectionHead"><div><b>Universal Lead Flow</b><div className="label">The ingestion pipeline HH360 will use for every member source</div></div><span className="badge">SECURE BY DEFAULT</span></div>
        <div className="funnel" style={{marginTop:14}}>
          <div className="step"><span className="label">Member Marketing</span><b>Lead</b></div>
          <div className="step"><span className="label">HH360 Hub</span><b>Validate</b></div>
          <div className="step"><span className="label">Consent + Rules</span><b>Eligible</b></div>
          <div className="step"><span className="label">Home Hive</span><b>Expose</b></div>
          <div className="step"><span className="label">Opportunity</span><b>Attribute</b></div>
        </div>
      </section>

      <section className="section two">
        <div className="card"><b>Source ownership stays intact</b><p className="sub" style={{marginTop:10}}>A member can see leads it generated. Other Hive members do not receive unrestricted access to that member's customer database.</p></div>
        <div className="card"><b>Next: universal ingestion</b><p className="sub" style={{marginTop:10}}>Website forms, CRMs and automation platforms will send normalized lead data into one secure HH360 endpoint.</p></div>
      </section>
    </Shell>
  );
}
