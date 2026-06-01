"use strict";

const CACHE_NAME = "remote-controller-shell-v79";
const SHELL_ASSETS = [
  "/",
  "/index.html",
  "/styles.css",
  "/app.js",
  "/manifest.json",
  "/icon.svg"
];

self.addEventListener("install", (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME)
      .then((cache) => cache.addAll(SHELL_ASSETS))
      .then(() => self.skipWaiting())
  );
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(keys.filter((key) => key !== CACHE_NAME).map((key) => caches.delete(key))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener("fetch", (event) => {
  if (event.request.method !== "GET") return;
  const url = new URL(event.request.url);
  if (
    url.origin !== location.origin ||
    url.search ||
    url.pathname === "/host" ||
    url.pathname === "/host.html" ||
    url.pathname === "/host.js" ||
    url.pathname === "/capture" ||
    url.pathname === "/capture.html" ||
    url.pathname === "/capture.js" ||
    url.pathname.startsWith("/api/") ||
    url.pathname.startsWith("/ws")
  ) {
    return;
  }
  event.respondWith(
    fetch(event.request)
      .then((response) => {
        const clone = response.clone();
        caches.open(CACHE_NAME).then((cache) => cache.put(event.request, clone));
        return response;
      })
      .catch(() => caches.match(event.request).then((cached) => cached || caches.match("/")))
  );
});
