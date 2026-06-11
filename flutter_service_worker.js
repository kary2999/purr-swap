'use strict';
// Purr Swap 自定义 SW — 网络优先 + 缓存兜底, 带 fetch handler 以满足 PWA 可安装条件。
const CACHE = 'purr-swap-runtime-v2';
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (event) => event.waitUntil((async () => {
  // 清掉旧版本缓存(含被缓存的旧 main.dart.js), 避免残留旧代码
  const keys = await caches.keys();
  await Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k)));
  await self.clients.claim();
})()));
self.addEventListener('fetch', (event) => {
  const req = event.request;
  if (req.method !== 'GET') return;
  event.respondWith((async () => {
    try {
      const fresh = await fetch(req);
      if (fresh && fresh.status === 200 && req.url.startsWith(self.location.origin)) {
        const cache = await caches.open(CACHE);
        cache.put(req, fresh.clone());
      }
      return fresh;
    } catch (err) {
      const cached = await caches.match(req);
      if (cached) return cached;
      throw err;
    }
  })());
});
