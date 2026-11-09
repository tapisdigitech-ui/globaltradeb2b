# GlobalTradeB2B (frontend demonstration)

Static single-file prototype of a B2B marketplace. All companies, products, prices, enquiries and figures are demonstration data. No company shown is registered or verified.

- `index.html` is the whole app. Data is stored in the browser's localStorage only.
- No backend, authentication or payments are connected.

## Redesign branch notes (redesign/homepage-v2)
- Homepage CSS, copy and icons were redesigned; seller centre, admin console, storage and all marketplace logic are unchanged.
- Category, product and hero photographs are hotlinked from Unsplash (Unsplash licence, free to use). They illustrate product categories only and are not photographs of any listed supplier's products. The footer states this.
- Icons: Lucide (ISC licence), inlined as SVG.
- Typeface: Inter (Google Fonts), Noto Sans Devanagari for Hindi.


## Status
See `docs/NEXT_DEVELOPMENT_READINESS.md` for what is real vs demo, and `docs/PRIORITISED_LAUNCH_CHECKLIST.md` for ranked gaps. Frontend tests: `NODE_PATH=$(npm root -g) node --test tests/frontend/*.test.mjs`.
