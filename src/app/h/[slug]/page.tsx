import { notFound } from 'next/navigation';
import { createPublicClient } from '@/lib/supabase/public';
import TrackedLink from '@/components/TrackedLink';
import HiveVisitTracker from '@/components/HiveVisitTracker';

type PageProps = {
  params: Promise<{ slug: string }>;
  searchParams: Promise<{ ref?: string; pid?: string }>;
};

function outboundUrl(url: string, hiveSlug: string, businessSlug: string, sourceSlug?: string) {
  try {
    const target = new URL(url);
    target.searchParams.set('utm_source', 'homehive360');
    target.searchParams.set('utm_medium', 'hive');
    target.searchParams.set('utm_campaign', hiveSlug);
    target.searchParams.set('utm_content', businessSlug);
    if (sourceSlug) target.searchParams.set('hh360_ref', sourceSlug);
    return target.toString();
  } catch {
    return url;
  }
}

export default async function HivePage({ params, searchParams }: PageProps) {
  const { slug } = await params;
  const { ref, pid } = await searchParams;
  const db = createPublicClient();

  const { data: hive } = await db
    .from('hives')
    .select('id,name,market_name,headline,description')
    .eq('slug', slug)
    .eq('status', 'active')
    .maybeSingle();

  if (!hive) notFound();

  const { data: members } = await db
    .from('hive_members')
    .select('display_order,businesses(id,name,slug,phone,website_url,logo_url,description,google_rating,google_review_count,services(name,category,description,is_active),offers(id,title,description,cta_label,cta_url,status,starts_at,ends_at))')
    .eq('hive_id', hive.id)
    .eq('status', 'active')
    .order('display_order');

  const activeMembers = (members || []).filter((member: any) => member.businesses);
  const source = ref
    ? activeMembers.map((member: any) => member.businesses).find((business: any) => business.slug === ref)
    : null;

  return (
    <main style={{ maxWidth: 1180, margin: '0 auto', padding: '52px 22px' }}>
      <HiveVisitTracker hiveSlug={slug} pid={pid} />
      <div className="eyebrow">HOME HIVE 360 · {hive.market_name}</div>
      <h1 className="title" style={{ fontSize: 46, maxWidth: 850 }}>
        {source ? `${source.name}'s Trusted Home Service Network` : hive.headline || hive.name}
      </h1>
      <p className="sub" style={{ fontSize: 18, maxWidth: 760 }}>
        {hive.description || `Trusted independent home-service professionals serving ${hive.market_name || 'your community'}.`}
      </p>

      {source ? (
        <div className="card" style={{ marginTop: 24, padding: 18 }}>
          <b>Referred by {source.name}</b>
          <div className="label" style={{ marginTop: 5 }}>Explore trusted businesses in the same local Home Hive network.</div>
        </div>
      ) : null}

      <div className="sectionHead" style={{ marginTop: 34 }}>
        <h2>Meet your Home Hive</h2>
        <span className="badge">{activeMembers.length} MEMBERS · LOCAL · CONNECTED</span>
      </div>

      <div className="grid">
        {activeMembers.map((member: any) => {
          const business = member.businesses;
          const service = business.services?.find((item: any) => item.category) || business.services?.[0];
          const offer = business.offers?.find((item: any) => item.status === 'active');
          const primaryUrl = offer?.cta_url || business.website_url;
          const trackedPrimary = primaryUrl ? outboundUrl(primaryUrl, slug, business.slug, source?.slug) : null;
          const trackedWebsite = business.website_url ? outboundUrl(business.website_url, slug, business.slug, source?.slug) : null;

          return (
            <article className="card" key={business.id}>
              {business.logo_url ? <img src={business.logo_url} alt={business.name+' logo'} style={{maxWidth:150,maxHeight:58,objectFit:'contain',marginBottom:14}}/> : null}
              <div className="eyebrow">{service?.category || service?.name || 'Home Service'}</div>
              <h2>{business.name}</h2>
              {business.google_rating ? (
                <p><b>★ {business.google_rating}</b> <span className="label">({business.google_review_count || 0} Google reviews)</span></p>
              ) : null}
              <p className="sub" style={{ minHeight: 60 }}>{business.description || service?.description || 'A trusted member of this local Home Hive.'}</p>

              {offer ? (
                <div className="step">
                  <span className="label">HOME HIVE OFFER</span>
                  <b style={{ fontSize: 18 }}>{offer.title}</b>
                  {offer.description ? <p className="label">{offer.description}</p> : null}
                </div>
              ) : null}

              <div style={{ display: 'flex', gap: 8, marginTop: 16, flexWrap: 'wrap' }}>
                {trackedPrimary ? <TrackedLink className="btn" href={trackedPrimary} hiveSlug={slug} businessSlug={business.slug} sourceSlug={source?.slug} pid={pid} offerId={offer?.id} eventType={offer ? "offer.clicked" : "member.clicked"}>{offer?.cta_label || "Request Service"}</TrackedLink> : null}
                {trackedWebsite && trackedWebsite !== trackedPrimary ? <TrackedLink className="btn secondary" href={trackedWebsite} hiveSlug={slug} businessSlug={business.slug} sourceSlug={source?.slug} pid={pid}>Visit Website</TrackedLink> : null}
                {business.phone ? <TrackedLink className="btn secondary" href={`tel:${business.phone.replace(/[^+\d]/g, '')}`} hiveSlug={slug} businessSlug={business.slug} sourceSlug={source?.slug} pid={pid} eventType="member.clicked">Call</TrackedLink> : null}
              </div>
            </article>
          );
        })}
      </div>

      {!activeMembers.length ? (
        <section className="section card"><h2>This Hive is getting ready.</h2><p className="sub">Member businesses will appear here as they join the network.</p></section>
      ) : null}

      <section className="section card" style={{ marginTop: 30, textAlign: 'center' }}>
        <div className="eyebrow">THE HOME HIVE DIFFERENCE</div>
        <h2>One trusted network. More ways to care for your home.</h2>
        <p className="sub" style={{ maxWidth: 720, margin: '0 auto' }}>
          Home Hive 360 connects customers with complementary local home-service professionals while each business remains independent.
        </p>
      </section>
    </main>
  );
}
