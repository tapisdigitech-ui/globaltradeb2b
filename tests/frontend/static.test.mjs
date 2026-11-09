// Static checks on index.html. No browser, Docker, network or credentials.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
const html = readFileSync(new URL('../../index.html', import.meta.url), 'utf8');

test('document declares a language and a skip link', () => {
  assert.match(html, /<html lang="en">/);
  assert.match(html, /<a class="skip" href="#top">/);
  assert.match(html, /<main id="top">/);
});
test('setLang marks the switched snippets with their own lang (page stays en)', () => {
  assert.match(html, /e\.setAttribute\('lang',l\)/);
});
test('prototype copy does not promise real delivery', () => {
  for (const bad of ['matching suppliers will send quotations', 'Your details go to each supplier', 'Buyers will contact you on these details'])
    assert.ok(!html.includes(bad), 'misleading copy: ' + bad);
  assert.match(html, /nothing is sent to a real company/);
});
test('demo ribbon is present', () => {
  assert.match(html, /class="demo-ribbon"[^>]*>Prototype with demonstration data/);
});
test('frontend is not wired to Supabase or any secret', () => {
  assert.ok(!/supabase\.co|createClient\(|service_role|SUPABASE_(URL|KEY)|sb_secret|eyJhbGci/i.test(html));
});
test('no real-looking contact data (mailto/tel links)', () => {
  assert.ok(!/href="(mailto|tel):/i.test(html));
});
test('forms that use custom validation opt out of native bubbles', () => {
  assert.match(html, /id="enF" novalidate/);
  assert.match(html, /id="rqForm" novalidate/);
});
