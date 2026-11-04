import fs from 'node:fs';
import vm from 'node:vm';

const htmlFiles = ['index.html', 'admin.html', 'business.html', 'my-shop.html', 'promotions.html'];
for (const file of htmlFiles) {
  if (!fs.existsSync(file)) continue;
  const html = fs.readFileSync(file, 'utf8');
  const lower = html.toLowerCase();
  let cursor = 0;
  let checked = 0;
  while (true) {
    const start = lower.indexOf('<script', cursor);
    if (start < 0) break;
    const openEnd = html.indexOf('>', start);
    if (openEnd < 0) throw new Error(file + ': unterminated script opening tag');
    const end = lower.indexOf('</script>', openEnd + 1);
    if (end < 0) throw new Error(file + ': unterminated script block');
    const attrs = html.slice(start + 7, openEnd);
    const body = html.slice(openEnd + 1, end);
    if (!/src\\s*=/i.test(attrs) && !/application\\/(?:ld\\+json|importmap)/i.test(attrs)) {
      new vm.Script(body, { filename: file + '#inline-script-' + (++checked) });
    }
    cursor = end + 9;
  }
  console.log(file + ': ' + checked + ' inline script blocks parsed');
}

const manifest = JSON.parse(fs.readFileSync('manifest.webmanifest', 'utf8'));
if (!Array.isArray(manifest.icons) || !manifest.icons.some(icon => icon.src.includes('icon-192'))) {
  throw new Error('PWA manifest is missing the 192px app icon');
}
const sw = fs.readFileSync('sw.js', 'utf8');
new vm.Script(sw, { filename: 'sw.js' });
if (!sw.includes('/storage/v1/object/public/manbij-images/')) throw new Error('Public image cache route missing');
if (!sw.includes('while (keys.length > 40)')) throw new Error('Public image cache eviction limit missing');
const guest = fs.readFileSync('supabase/functions/guest-listing/index.ts', 'utf8');
if (!guest.includes('cacheControl: "31536000"')) throw new Error('Guest image cache TTL not updated');
const migration = fs.readFileSync('supabase/migrations/20261104090000_analytics_batch_and_throttle.sql', 'utf8');
for (const token of ['track_site_visits_batch', 'track_site_visit', "interval '8 seconds'", 'grant execute']) {
  if (!migration.includes(token)) throw new Error('Migration check failed: ' + token);
}
const index = fs.readFileSync('index.html', 'utf8');
if (!index.includes("db.rpc('track_site_visits_batch'")) throw new Error('Batched analytics client call missing');
if (!index.includes("loading=\"lazy\" decoding=\"async\" fetchpriority=\"low\"")) throw new Error('Lazy image hints missing');
console.log('Manifest, service worker, guest upload cache, and analytics migration checks passed');
