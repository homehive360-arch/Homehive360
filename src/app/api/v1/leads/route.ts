import { NextRequest, NextResponse } from 'next/server';

const required = ['first_name'] as const;

export async function POST(request: NextRequest) {
  const apiKey = request.headers.get('x-hh360-key');
  if (!apiKey) {
    return NextResponse.json({ error: 'Missing x-hh360-key credential.' }, { status: 401 });
  }

  let body: Record<string, unknown>;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: 'Request body must be valid JSON.' }, { status: 400 });
  }

  for (const field of required) {
    if (!body[field] || typeof body[field] !== 'string') {
      return NextResponse.json({ error: `Missing required field: ${field}` }, { status: 422 });
    }
  }

  const email = typeof body.email === 'string' ? body.email.trim() : '';
  const phone = typeof body.phone === 'string' ? body.phone.trim() : '';
  if (!email && !phone) {
    return NextResponse.json({ error: 'At least one customer contact method (email or phone) is required.' }, { status: 422 });
  }

  // Credential verification and writes are intentionally server-only and are
  // activated once the server secret is provisioned in the deployment environment.
  return NextResponse.json(
    {
      accepted: false,
      status: 'configuration_required',
      message: 'Lead ingestion endpoint is installed. Server credential verification is not yet activated.'
    },
    { status: 503 }
  );
}
