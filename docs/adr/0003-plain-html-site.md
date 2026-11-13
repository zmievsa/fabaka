# The site is plain HTML, not Vue

fabaka.dev is one static page, `site/public/index.html`, with its CSS and JS inline and no build step. The default stack for a static site is Vue 3 + Vite + TypeScript; the owner chose plain HTML for this one, and the page needs nothing Vue adds: no routing, no components shared with anything else, no data. Hosting follows the default: Cloudflare Workers static assets with fabaka.dev as a custom domain (`site/wrangler.jsonc`), deployed locally with `just deploy`.
