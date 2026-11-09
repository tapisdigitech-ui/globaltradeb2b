// Browser tests (Playwright + bundled Chromium). All external requests are blocked;
// images get a 1x1 PNG. No Docker, Supabase or network is used.
import test, { before, after } from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
const { chromium } = createRequire(import.meta.url)('playwright');
const URL_ = fileURLToPath(new URL('../../index.html', import.meta.url));
const PNG = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==', 'base64');
let b;
before(async () => { b = await chromium.launch(); });
after(async () => { await b.close(); });
async function page(w = 1280, h = 900) {
  const ctx = await b.newContext({ viewport: { width: w, height: h } });
  const p = await ctx.newPage(); const errs = [];
  p.on('pageerror', e => errs.push(String(e)));
  await p.route(/^https?:/, r => r.request().resourceType() === 'image'
    ? r.fulfill({ contentType: 'image/png', body: PNG }) : r.abort());
  await p.goto('file://' + URL_); await p.waitForTimeout(300);
  return { p, errs, ctx };
}
for (const w of [320, 390, 768, 1280]) {
  test(`no horizontal overflow at ${w}px on main views`, async () => {
    const { p, errs, ctx } = await page(w);
    for (const v of ['home', 'buy', 'list', 'enquiries', 'seller', 'admin', 'desk', 'signin']) {
      await p.evaluate(x => go(x), v); await p.waitForTimeout(150);
      const over = await p.evaluate(() => document.documentElement.scrollWidth - innerWidth);
      assert.ok(over <= 0, `${v} overflows by ${over}px at ${w}px`);
    }
    assert.deepEqual(errs, []); await ctx.close();
  });
}
test('language toggle labels switched text; page language stays en', async () => {
  const { p, ctx } = await page();
  await p.click('#langBtn');
  assert.equal(await p.evaluate(() => document.documentElement.lang), 'en');
  assert.equal(await p.evaluate(() => document.querySelector('[data-hi]').getAttribute('lang')), 'en');
  await p.click('#langBtn');
  assert.equal(await p.evaluate(() => document.querySelector('[data-hi]').getAttribute('lang')), 'hi');
  await ctx.close();
});
test('skip link is first focusable element and targets main', async () => {
  const { p, ctx } = await page();
  await p.keyboard.press('Tab');
  assert.equal(await p.evaluate(() => document.activeElement.className), 'skip');
  assert.equal(await p.evaluate(() => !!document.getElementById('top')), true); await ctx.close();
});
test('enquiry form: invalid input is announced and focused', async () => {
  const { p, ctx } = await page();
  await p.evaluate(() => { enqTarget = { product: 'Test', supplier: '', img: '' }; });
  await p.evaluate(() => document.getElementById('enqDlg').hidden = false);
  await p.fill('#enQty', '10'); await p.fill('#enName', 'A');
  await p.click('#enF button[type=submit]');
  assert.match(await p.textContent('#enErr'), /name/i);
  assert.equal(await p.getAttribute('#enName', 'aria-invalid'), 'true');
  assert.equal(await p.evaluate(() => document.activeElement.id), 'enName');
  await p.fill('#enName', 'Asha'); await p.fill('#enTel', 'abc'); await p.click('#enF button[type=submit]');
  assert.equal(await p.evaluate(() => document.activeElement.id), 'enTel'); await ctx.close();
});
test('requirement form: validation messages are alerts and focus the field', async () => {
  const { p, ctx } = await page();
  await p.evaluate(() => document.getElementById('rqForm').closest('.ov').hidden = false);
  await p.click('#rqForm button[type=submit]');
  assert.match(await p.textContent('#rqMsg'), /product/i);
  assert.equal(await p.getAttribute('#rqMsg', 'role'), 'alert');
  assert.equal(await p.evaluate(() => document.activeElement.id), 'rqProd'); await ctx.close();
});
