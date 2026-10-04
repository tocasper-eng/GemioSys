// Service Worker：快取 App 外殼供離線開啟；背景同步時上傳待傳佇列
importScripts('outbox.js');
const 版本 = 'gemio-v8';
const 外殼 = ['./', 'index.html', 'app.js', 'outbox.js', 'style.css', 'manifest.json', 'icon.svg'];

self.addEventListener('install', e => {
  e.waitUntil(caches.open(版本).then(c => c.addAll(外殼)).then(() => self.skipWaiting()));
});
self.addEventListener('activate', e => {
  e.waitUntil(caches.keys().then(ks => Promise.all(ks.filter(k => k !== 版本).map(k => caches.delete(k))))
    .then(() => self.clients.claim()));
});
// 靜態檔：先回快取、背景更新（stale-while-revalidate）；/api 一律走網路
self.addEventListener('fetch', e => {
  const u = new URL(e.request.url);
  if (e.request.method !== 'GET' || u.pathname.startsWith('/api/')) return;
  e.respondWith(caches.open(版本).then(async c => {
    const hit = await c.match(e.request, { ignoreSearch: true });
    const net = fetch(e.request).then(r => { if (r.ok) c.put(e.request, r.clone()); return r; }).catch(() => hit);
    return hit || net;
  }));
});
self.addEventListener('sync', e => {
  if (e.tag === 'oav-outbox') e.waitUntil(Outbox.flush().then(async r => {
    for (const c of await self.clients.matchAll()) c.postMessage({ 類型: '已同步', ...r });
  }));
});
