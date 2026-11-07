# LEAD ROUTING RULES (as implemented in draft migration 0002; locally tested only)

**Direct delivery (Path A)** requires ALL of: claim `approved`; verification `verified`; company `published` (not suspended); not `lead_delivery_blocked`; an active owner/manager/sales member; company lists the requirement's category; a *verified* business email and phone each verified within `contact_max_age_days` (365). Enforced in the database by `_company_lead_eligible()` and re-checked **at read time** (RLS), so revocation is immediate.
**Admin lead desk (Path B):** everything else that matches — unclaimed, claimed-but-unverified, ineligible contacts, restricted sellers, or eligible sellers beyond the per-requirement cap (5). Never delivered to the supplier.
**Unmatched:** no supplier reaches `min_score` (40) → `unmatched` queue.
**Scoring (explained per match in `reasons`):** category 40, product name/tag 30, destination/export market 15, same city 10, manufacturer 5; a match needs category or product relevance and ≥ min_score. Settings in `lead_routing_settings` (admin only).
**Safeguards:** one match row per (requirement, company); delivery events unique per (requirement, company); duplicate requirement by the same buyer within 24 h rejected; rate limit 10 requirements/day; full immutable delivery and status history; buyer is told only the truth (`buyer_requirement_status`).
**Becoming eligible later:** admin runs `admin_rematch_for_company()`; future requirements evaluate automatically.
No email/SMS is sent by any of this; seller notification is in-app only.
