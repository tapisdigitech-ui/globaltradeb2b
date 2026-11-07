# Privacy review proposal (Round 9 · G) – NOT implemented, NOT in the migration chain

Nothing in this file is applied locally or hosted. It sits beside `docs/ADMIN_MESSAGE_AUDIT_PROPOSAL.md` (admin reads of message content, already prototyped under `supabase/proposals/`). No SQL for this document exists in `migrations_draft/` or `migrations/`; sketches below are descriptions to be reviewed, not tested code.

## Current behaviour (verified on the local replica built from the staging extract)
| Access | Mechanism today | Purpose required | Logged |
|---|---|---|---|
| Admin reads any `profiles` row incl. `phone` | policy `profiles_self_read`: `id = auth.uid() OR is_admin() OR (is_staff() AND app_role IN ('admin','reviewer'))` (test J21–J22b) | no | no |
| Reviewer (non-admin staff) reads buyer profiles | **No** (0006 F-R8 removed it) | – | – |
| Admin reads all `orders` | policy `orders_read`: buyer, company owner/manager/sales, **or `is_admin()`** | no | no |
| Staff open enquiry messages | `staff_open_enquiry_comms(enquiry, purpose)`: staff + `staff_can_see_enquiry`, purpose ≥ 5 chars, 200/day, row in `staff_comms_access_log`, 10-minute grant | free text only | granted opens only |
| Admin reads message content | `is_admin()` inside message policies | no | no (see ADMIN_MESSAGE_AUDIT_PROPOSAL) |
| Denied attempts | RLS denials return empty/«permission denied» and leave no record; RPC denials are logged only in the evidence gate (non-raising) | – | partly |

## Proposals (each independently approvable)
**P1 – `profiles.phone` for admins.** Preferred: remove `is_admin()` from the *row* policy for private columns by exposing a staff directory view (id, full_name, app_role, company_name, city) and moving phone access to an audited RPC `admin_get_profile_contact(profile_id, purpose)` (admin only, purpose ≥ 10 chars from a short list, immutable log, 30/h cap, non-raising for admins so the log row survives, plain error and no row for non-admins). Admin screens that only need names use the view. Alternative (smaller): column privilege `REVOKE SELECT (phone)` from `authenticated` + the RPC; own-phone reads then also need a `my_profile()` RPC – more app change, so not preferred.
**P2 – orders for admins.** Orders hold buyer/supplier/amount data and are finance records. Options: (a) keep `is_admin()` but log (needs an RPC wrapper because RLS reads can't be logged); (b) recommended: admin-visible *metadata* only (id, status, timestamps, company ids) via a view, full order through `admin_open_order(order_id, purpose)` with the same grant/log pattern as admin comms. Decision needed from the owner of the finance process (support/dispute workflow).
**P3 – `staff_open_enquiry_comms` purpose requirements.** Today any 5-character string passes. Proposed: a fixed purpose code (`dispute`, `abuse_report`, `routing_review`, `support_ticket`, `quality_audit`) plus a mandatory reference (ticket/case id, ≥ 4 chars) stored in dedicated columns; reject free-text-only purposes; keep the 10-minute grant and 200/day cap but add a per-enquiry cap (e.g. 5 opens/day) and a daily digest of opens per staff member to a second admin; same shape as `admin_open_comms` so both paths share one log view. Existing rows keep their free-text purpose.
**P4 – denied-access logging.** RLS cannot log its own refusals (a policy is an expression, not a procedure). Realistic options: (a) route sensitive reads through RPCs that log denied attempts non-raisingly for *authenticated* callers, with a per-user cap (≤ 20/h) to prevent log flooding and a single `rate_limited` row per minute – the pattern already used in `_evidence_gate`; (b) at platform level, rely on API/Postgres logs (hosted-only; retention and query access to be confirmed). Anonymous and arbitrary-user denials should not write rows (flooding vector; already the rule in the admin-audit prototype). Retention and who may read the log (admin only, immutable via `block_mutation`) to be decided.

## Risks / things for the reviewer
- Each change removes a direct-table path used by the current frontend: the front-end (`index.html`) needs inventorying before approval (not done here).
- Logs contain purposes and ids, themselves personal data: retention period and access need a decision.
- Break-glass: if the audited RPC is broken, admins lose access; keep a documented trusted-session procedure.

## Tests to write once approved
JWT-claim tests (same emulator) for admin vs reviewer vs buyer vs anon on each path; grant expiry; log immutability; flood caps; confirmation that the view exposes no phone/email; rollback file.
