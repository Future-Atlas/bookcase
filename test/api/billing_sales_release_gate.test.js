const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const read = (file) => fs.readFileSync(path.join(__dirname, '../..', file), 'utf8');

test('billing sales only enable for exactly the explicit true runtime value', async () => {
  const { billingSalesEnabled } = await import('../../supabase/functions/_shared/stripe_billing.mjs');
  for (const value of [undefined, null, '', 'false', 'TRUE', '1', ' true ', false, true, '0']) {
    assert.equal(billingSalesEnabled(value), false, String(value));
  }
  assert.equal(billingSalesEnabled('true'), true);
});

test('checkout and plan change refuse sales before secrets and any external calls', () => {
  for (const file of [
    'supabase/functions/billing-checkout/index.ts',
    'supabase/functions/billing-change-plan/index.ts',
  ]) {
    const source = read(file);
    const tokenCheck = source.indexOf("if (!token) return json({ error: 'Unauthorized' }, 401)");
    const gate = source.indexOf("!billingSalesEnabled(Deno.env.get('BILLING_SALES_ENABLED'))");
    const secrets = source.indexOf("const stripeSecretKey = Deno.env.get('STRIPE_SECRET_KEY')");
    const firstRpc = source.indexOf('admin.auth.getUser(token)');
    assert.ok(tokenCheck >= 0 && tokenCheck < gate, file);
    assert.ok(gate > 0 && gate < secrets && gate < firstRpc, file);
    assert.match(source, /Subscriptions are not currently available' }, 503/);
    assert.match(source, /billingSalesEnabled,/);
  }
});

test('cancellation and verified webhooks remain available when new sales are disabled', () => {
  const cancellation = read('supabase/functions/billing-cancel-subscription/index.ts');
  const webhook = read('supabase/functions/billing-webhook/index.ts');
  assert.doesNotMatch(cancellation, /BILLING_SALES_ENABLED/);
  assert.doesNotMatch(webhook, /BILLING_SALES_ENABLED/);
  assert.match(webhook, /verifyStripeSignature\(rawBody, signature, webhookSecret\)/);
});

test('Flutter UI flag alone never constitutes a server-side checkout permission', () => {
  const flutter = read('lib/config/feature_flags.dart');
  const shared = read('supabase/functions/_shared/stripe_billing.mjs');
  assert.match(flutter, /subscriptionUiEnabled = false/);
  assert.match(shared, /value === 'true'/);
});
