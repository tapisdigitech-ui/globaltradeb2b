# Admin Lead Desk & Claim Management — Demo Actions Map

Route: `index.html#desk` (linked from the footer as "Lead Desk (demo)"). Branch `feature/supplier-intelligence-phase0`.

**Everything on this screen is demo-only.** All records are fictional ("Demo …"), all actions are simulated, and the only storage is the browser's `localStorage` key `gtb2b-desk-demo`. The screen makes **no network requests**, shows **no contact details** (availability only), and **never sends** email, SMS, invitations or verification codes. "Reset demo data" restores the seed.

## Roles in the demo
| Demo role | What it shows | Planned backend rule |
|---|---|---|
| Demo Admin | All leads, claims, invitations, assign/approve controls | `is_admin()` |
| Vikram / Neha (demo reviewers) | Only leads/claims assigned to them; no assign or invitation-approve controls | `staff_can_see_case`, `staff_can_review_claim` (0002/0005) |

## Status vocabulary
The six desk groups are a simplified view of the 13-value `lead_status` enum in draft migration 0002:

| Demo group | DB statuses (0002) |
|---|---|
| pending | `new` |
| assigned | `assigned`, `contact_pending` |
| contacted | `contacted`, `interested`, `follow_up_required`, `claim_invitation_sent`, `registration_started`, `verification_pending` |
| converted | `seller_activated` |
| rejected | `not_interested`, `closed` |
| unmatched | `no_suitable_supplier` |

Route split in the demo (**direct / admin·claimed-not-verified / admin·unclaimed**) is derived from company state; the DB stores only `match_route` = `direct | admin`.

## Action → eventual backend function
| Screen action | Demo behaviour | Backend function required (draft, not applied) | Status |
|---|---|---|---|
| View requirements, scores, reasons | Static seed | `admin_lead_overview`, `staff_my_leads`, `requirement_matches` | drafted, locally tested |
| Assign lead to staff | Sets assignee, status, history entry | `admin_assign_lead` | drafted, locally tested |
| Re-run matching | History entry only; scores unchanged | `admin_rematch`, `admin_rematch_for_company` | drafted, locally tested |
| Update status | Sets status + history | `staff_update_lead` (writes `lead_status_history`) | drafted, locally tested |
| Log call + follow-up date | Records note; **no call is placed** | `staff_log_call` | drafted, locally tested |
| Direct deliveries list | Read-only filter on eligible suppliers | `_company_lead_eligible`, `seller_lead_visible` | drafted, locally tested |
| Invitation request | Adds queue item | `staff_create_invitation` | drafted, locally tested |
| Invitation approve / reject | Admin only; status change | `admin_approve_invitation` | drafted, locally tested |
| "Mark as sent manually" | Status change; **nothing is sent** | `staff_mark_invitation_sent` | drafted, locally tested |
| Assign claim reviewer | Sets reviewer | needs a new admin RPC (`admin_assign_claim_reviewer`) — **not yet written** | gap |
| Claim approve / reject | Approve gated: email verified and no competing open claim; approval leaves verification unchanged | existing `review_claim` (real body unseen — blocker B2) + `_claim_approval_gate` trigger (0004) | blocked on real staging schema |
| Email / phone state display | Read-only seed values | `claim_verification_summary` (0004); codes via `start_claim_verification` / `confirm_claim_verification` — **not simulated** | drafted, locally tested |
| Evidence viewing | Placeholder file names only | Storage `vd_read` (0005) and `cev_read` (**unresolved, blocker B3**); each view must be audit-logged | blocked |
| Contact availability | Never shows values | `staff_get_contacts` (purpose + audit) | drafted, locally tested |
| Simulated action log | In-page list | `audit_log` / `lead_distribution_events` | n/a |

## Not simulated on purpose
Sending or receiving verification codes, any email/SMS/WhatsApp, real contact reveal, document download, buyer notifications, seller inbox delivery, payments.

## Known demo limits
- Assignment scoping is only enforced by the page; real enforcement is RLS/functions tested locally on a reconstructed baseline, **not** on the real staging schema.
- Seed scores are illustrative and not produced by `_match_requirement`.

## Update — evidence opening (demo)
Claim detail now requires a purpose (min 5 characters) before an evidence file can be "opened"; each simulated open adds a line to a per-claim access log shown in the panel (mirrors the audited-RPC model in 0006). Still purely local demo state, no backend call.
