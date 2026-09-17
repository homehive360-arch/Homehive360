import { notFound } from 'next/navigation';
import { createPublicClient } from '@/lib/supabase/public';

type PageProps = {
  params: Promise<{ slug: string }>;
  searchParams: Promise<{ ref?: string }>;
};

export default async function HivePage({ params, searchParams }: PageProps) {
  const { slug } = await params;
  const { ref } = await searchParams;
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
    .select('display_order,businesses(id,name,slug,phone,website_url,description,google_rating,google_review_count,services(name,category,description),offers(title,description,cta_label,cta_url,status))')
    .eq('hive_id', hive.id)
    .eq('status', 'active')
    .order('display_order');

  const source = ref
    ? members?.map((member: any) => member.businesses).find((business: any) => business?.slug === ref)
    : null;

  return (
    <main style={{ maxWidth: 1180, margin: '0 auto', padding: '52px 22px' }}>
      <div className="eyebrow">HOME HIVE 360 · {hive.market_name}</div>
      <h1 className="title" style={{ fontSize: 46, maxWidth: 850 }}>
        {source ? `${source.name}'s Trusted Home Service Network` : hive.headline || hive.name}
      </h1>
      <p className="sub" style={{ fontSize: 18, maxWidth: 760 }}>{hive.description}</p>

      <div className="sectionHead">
        <h2>Meet your Home Hive</h2>
        <span className="badge">LOCAL · TRUSTED · CONNECTED</span>
      </div>

      <div className="grid">
        {members?.map((member: any) => {
          const business = member.businesses;
          if (!business) return null;
          const service = business.services?.[0];
          const offer = business.offers?.find((item: any) => item.status === 'active');

          return (
            <article className="card" key={business.id}>
              <div className="eyebrow">{service?.category || 'Home Service'}</div>
              <h2>{business.name}</h2>
              {business.google_rating ? (
                <p><b>★ {business.google_rating}</b> <span className="label">({business.google_review_count || 0} Google reviews)</span></p>
              ) : null}
              <p className="sub" style={{ minHeight: 60 }}>{business.description}</p>

              {offer ? (
                <div className="step">
                  <span className="label">HOME HIVE OFFER</span>
                  <b style={{ fontSize: 18 }}>{offer.title}</b>
                  <p className="label">{offer.description}</p>
                </div>
              ) : null}

              <div style={{ display: 'flex', gap: 8, marginTop: 16, flexWrap: 'wrap' }}>
                {offer?.cta_url ? <a className="btn" href={offer.cta_url}>{offer.cta_label || 'Request Service'}</a> : null}
                {business.website_url ? <a className="btn secondary" href={business.website_url}>Visit Website</a> : null}
              </div>
            </article>
          );
        })}
      </div>

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
