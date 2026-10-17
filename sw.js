const CACHE_NAME = "dalil-manbij-shell-v6";
const CORE_SHELL = [
  "./",
  "./index.html",
  "./manifest.webmanifest"
];
const OPTIONAL_ASSETS = [
  "./icon.svg",
  "./icon-192.svg",
  "./icon-512.svg",
  "./icon-192.png",
  "./icon-512.png"
];

self.addEventListener("install", (event) => {
  event.waitUntil((async () => {
    const cache = await caches.open(CACHE_NAME);
    // Only the core app files are required for installation. A missing icon
    // must not prevent the service worker from installing and enabling PWA install.
    await cache.addAll(CORE_SHELL);
    await Promise.allSettled(
      OPTIONAL_ASSETS.map(async (path) => {
        try {
          const response = await fetch(path, { cache: "reload" });
          if (response.ok) await cache.put(path, response);
        } catch (error) {
          console.warn("Optional PWA asset could not be cached:", path, error);
        }
      })
    );
  })());
  self.skipWaiting();
});

self.addEventListener("activate", (event) => {
  event.waitUntil((async () => {
    const keys = await caches.keys();
    await Promise.all(keys
      .filter(key => key.startsWith("dalil-manbij-shell-") && key !== CACHE_NAME)
      .map(key => caches.delete(key)));
    await self.clients.claim();
  })());
});

self.addEventListener("fetch", (event) => {
  const request = event.request;
  const url = new URL(request.url);
  if (request.method !== "GET" || url.origin !== self.location.origin) return;

  // Do not cache live database, authentication, or storage requests.
  if (url.pathname.includes("/rest/v1/") ||
      url.pathname.includes("/auth/v1/") ||
      url.pathname.includes("/storage/")) return;

  if (request.mode === "navigate") {
    event.respondWith((async () => {
      try {
        const response = await fetch(request);
        if (response.ok) {
          const copy = response.clone();
          caches.open(CACHE_NAME).then(cache => cache.put(request, copy)).catch(()=>{});
        }
        return response;
      } catch (_) {
        return (await caches.match(request)) ||
          (await caches.match("./index.html")) ||
          (await caches.match("./")) ||
          new Response("أنت غير متصل بالإنترنت. حاول مرة أخرى عند توفر الاتصال.", {
            status: 503,
            headers: { "Content-Type": "text/plain; charset=utf-8" }
          });
      }
    })());
    return;
  }

  if (["script", "style", "image", "font"].includes(request.destination) ||
      url.pathname.endsWith(".webmanifest")) {
    event.respondWith((async () => {
      const cached = await caches.match(request);
      if (cached) return cached;
      const response = await fetch(request);
      if (response.ok) {
        const copy = response.clone();
        caches.open(CACHE_NAME).then(cache => cache.put(request, copy)).catch(()=>{});
      }
      return response;
    })());
  }
});
