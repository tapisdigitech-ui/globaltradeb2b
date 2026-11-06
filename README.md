# GlobalTradeB2B (frontend demonstration)

Static single-file prototype of a B2B marketplace. All companies, products, prices, enquiries and figures are demonstration data. No company shown is registered or verified.

- `index.html` is the whole app. Data is stored in the browser's localStorage only.
- No backend, authentication or payments are connected.

## Redesign branch notes (redesign/homepage-v2)
- Homepage CSS, copy and icons were redesigned; admin console, storage and marketplace logic are unchanged.
- Category, product and hero photographs are hotlinked from Unsplash (Unsplash licence, free to use). They illustrate product categories only and are not photographs of any listed supplier's products. The footer states this.
- Icons: Lucide (ISC licence), inlined as SVG.
- Typeface: Inter (Google Fonts), Noto Sans Devanagari for Hindi.
- Seller Centre redesigned lead-first: Home, My Enquiries (New / Contacted / Quotation sent / Negotiation / Converted / Lost, notes and follow-up reminders), Buy Leads (filters, save), Messages (share catalogue / quotation text), My Products, Catalogue Views, Company Profile, Orders, Reports, Settings. Mobile bottom navigation. All data remains demonstration data saved in the browser (notes, saved leads and status changes use the existing seller storage key). No backend, Supabase, authentication or admin permission changes.
