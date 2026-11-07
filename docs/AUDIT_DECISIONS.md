# Audit improvements: decisions (round 6)

## D1 Admin reads of messages/orders are not individually logged
Today `dt_read`, `dm_read`, `replies_read`, `quotes_read` (and the order/quotation policies) contain `or is_admin()`. Reviewers already go through `staff_open_enquiry_comms` (purpose, immutable log, 10-minute grant, assignment re-check).
**Smallest safe change (recommended, NOT yet implemented, needs approval):** delete the `or is_admin()` branch from those 4-5 policies and let `comms_grant_active()` treat admins as eligible, so admins open a thread with the same audited function. No new tables; ~5 policy edits + ~8 tests. Cost: admins lose silent oversight of live messages; dispute handling needs a purpose line (one extra call). Orders: buyer/seller/admin policy stays (orders hold commercial terms, status changes are already audited by `trg_audit_orders`; verified in SF17d).

## D2 Denied access attempts
Implemented for evidence (round 6): non-raising gate, outcome logged. Same pattern is recommended for `staff_open_buyer_contact` and `staff_open_enquiry_comms` (return empty + log `denied`), ~2 functions, reuse the log tables with an `outcome` column. Direct-table RLS denials cannot be logged by Postgres; they are protected by the fact that staff have no direct table path (buyer contact, evidence, comms). Not logging anonymous/non-staff failures is deliberate (log-flooding control).

## D3 Separate audit-personnel role
**Not necessary now.** Only admins read the audit tables, the logs are immutable even for admins (trigger), and there is a single operating company. A new `app_role` value touches enum, every `is_admin()`/`is_staff()` helper and the tests. Revisit when there are >= 3 admins or an external auditor: add a read-only `auditor` role limited to the `*_access_log`, `audit_log`, `moderation_actions` tables via dedicated policies (no helper changes).
