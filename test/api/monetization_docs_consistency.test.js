const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const read = file => fs.readFileSync(path.join(__dirname, '../..', file), 'utf8');

test('staging runbook lists every Edge Function staged by deployment script', () => {
  const runbook = read('docs/staging_database_deployment.md');
  const deployScript = read('scripts/deploy-staging-db.mjs');
  const array = deployScript.match(/export const FUNCTIONS = \[([^\]]+)\]/);
  assert.ok(array, 'deployment function list exists');
  const functionNames = [...array[1].matchAll(/'([^']+)'/g)].map(match => match[1]);
  assert.ok(functionNames.length >= 7);
  for (const name of functionNames) {
    assert.ok(runbook.includes(String.fromCharCode(96) + name + String.fromCharCode(96)), name + ' must appear in the staging runbook');
  }
  assert.match(runbook, /BILLING_SALES_ENABLED/);
  assert.doesNotMatch(runbook, /上記3関数/);
});

test('ad revenue scenarios distinguish redeemable Ninja points from yen', () => {
  const modelDoc = read('docs/monetization_scenario_model.md');
  assert.match(modelDoc, /忍者ツールズポイント/);
  assert.match(modelDoc, /円換算した発行者手取り額/);
  assert.match(modelDoc, /publisherNetEcpmYen/);
  assert.match(modelDoc, /https:\/\/www\.ninja\.co\.jp\/rule\/admax/);
});
