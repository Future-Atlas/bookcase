const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const root = path.join(__dirname, '../..');
const read = (file) => fs.readFileSync(path.join(root, file), 'utf8');

test('authenticated users must accept the current legal bundle before using the app', () => {
  const gate = read('lib/screens/legal_consent_screen.dart');
  const main = read('lib/main.dart');

  assert.match(gate, /if \(!service\.isAuthenticated\)[\s\S]*return widget\.child/);
  assert.match(gate, /if \(snapshot\.data == true\) return widget\.child/);
  assert.match(gate, /List<bool>\.filled\(5, false\)/);
  assert.match(gate, /_checked\.every\(\(value\) => value\)/);
  assert.match(gate, /acceptCurrentLegalDocuments\(\)/);
  assert.match(main, /LegalConsentGate\([\s\S]*ProfileOnboardingGate/);
});

test('legal consent stores every document version and checks the current bundle', () => {
  const service = read('lib/services/supabase_service.dart');
  const migration = read(
    'supabase/migrations/20260803090000_add_legal_consents_and_contact_requests.sql',
  );

  assert.match(service, /\.eq\('bundle_version', LegalDocumentVersions\.bundle\)/);
  assert.match(service, /\.eq\('terms_version', LegalDocumentVersions\.terms\)/);
  assert.match(service, /\.eq\('privacy_version', LegalDocumentVersions\.privacy\)/);
  assert.match(service, /community_guidelines_version'[\s\S]*LegalDocumentVersions\.communityGuidelines/);
  assert.match(service, /infringement_policy_version'[\s\S]*LegalDocumentVersions\.infringementPolicy/);
  assert.match(service, /external_transmission_version'[\s\S]*LegalDocumentVersions\.externalTransmission/);
  assert.match(service, /'terms_version': LegalDocumentVersions\.terms/);
  assert.match(service, /'privacy_version': LegalDocumentVersions\.privacy/);
  assert.match(service, /'external_transmission_version':[\s\S]*LegalDocumentVersions\.externalTransmission/);
  assert.match(migration, /UNIQUE \(profile_id, bundle_version\)/);
  assert.match(migration, /auth\.uid\(\) = profile_id/);
});
