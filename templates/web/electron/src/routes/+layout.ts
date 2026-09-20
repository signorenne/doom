// An Electron application has no server: the window loads files from
// disk and every route is resolved in the browser. That is a single
// page application, which is `fallback: index.html' in vite.config.ts
// and these two here. Prerendering the root as well would only write a
// page the fallback then overwrites.
export const prerender = false;
export const ssr = false;
