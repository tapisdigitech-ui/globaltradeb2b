# Admin message-read audit — PROPOSAL (not implemented, not applied)

Files: `supabase/proposals/0008_admin_message_audit_PROPOSAL.sql`, `…_DOWN.sql`, tests `supabase/tests/proposals/admin_message_audit_tests.sql`, runner `supabase/tests/run_proposal_admin_audit.sh`. The proposal is **not** in `migrations_draft/` and is **not** run by `run_real.sh`, the legacy suite or the dry runs. Waiting for explicit approval.

## Problem
After 0006, buyer/seller messages and quotations are readable by **any admin through RLS (`is_admin()` in the policy) with no purpose, no time limit and no per-read record**; only non-admin staff go through the audited 10-minute grant (`staff_open_enquiry_comms`).

## Policies that change (4)
| Table | Policy | Change |
|---|---|---|
| `direct_threads` | `dt_read` | `is_admin()` → `admin_comms_grant_active('thread', id)` |
| `direct_messages` | `dm_read` | `is_admin()` → `admin_comms_grant_active('thread', thread_id)` |
| `enquiry_replies` | `replies_read` | `is_admin()` → `admin_comms_grant_active('enquiry', enquiry_id)` |
| `quotations` | `quotes_read` | `is_admin()` → `admin_comms_grant_active('enquiry', enquiry_id)` |

`orders_read` (a fifth policy that also contains `is_admin()`) is **deliberately left unchanged**: orders are an operational/finance record, not message content. Decision for the approver; changing it is a one-line addition.

## Audited function that replaces direct access
`admin_open_comms(scope 'enquiry'|'thread', target uuid, purpose text) → 'ok'|'denied'|'invalid'|'rate_limited'`, admin only, `SECURITY DEFINER`. It creates a **10-minute grant** for that admin and that target only. A separate `thread` scope exists because direct threads that are not linked to an enquiry cannot be covered by the existing enquiry-based staff path.

## How admins retain legitimate access
Call `admin_open_comms` with a purpose of at least 10 characters (dispute id, abuse report id…), then read through the normal tables for 10 minutes; re-call to extend. Non-message admin functions are unaffected.

## What is recorded
`admin_comms_access_log` (immutable via `block_mutation`, admin-readable, no FK so rows outlive deletions): actor, scope, target, purpose, outcome, denial reason, time.
- **Successful** opens: `granted` row.
- **Refused for admins**: `invalid` (short purpose, bad scope, NULL/unknown target) and `rate_limited` rows — the function is deliberately **non-raising** for admins so the log row is not rolled back. Limits: 30 grants/h, 200/day, 20 refusals/h (checked first, so refusal floods are throttled).
- **Non-admins** (reviewer, buyer, seller, anonymous, service role) get a plain error and **no log row** (raising rolls the insert back; logging attempts by arbitrary users would let anyone fill the table). The `denied` outcome value is reserved and currently unused. Limitation to accept or change.
- Individual message *rows* read during a grant are not logged; the grant (who, what, why, when) is.

## Existing workflows that would break
- Any admin screen that lists or previews threads, replies or quotes by direct table query would return nothing until the admin opens the target. The current demo UI is not connected to real data, so nothing breaks today; a real admin console must call `admin_open_comms` first (UI change needed).
- Support/dispute handling gains one step and requires a stated purpose.
- Buyers, sellers, assigned-staff grant flow, orders, and `SECURITY DEFINER` functions are unchanged (tests AP9b/AP10b/AP14/AP15b).
- Rollback: `0008_…_DOWN.sql` restores the 0006 policies exactly (schema diff 0 lines) and drops the log/grants tables (audit history lost; export first).

## Tests (local PG 16.15, proposal only)
Control (current behaviour, 0007 only): 2/2 pass — admin reads everything with no grant and no log. Proposal applied: 26/26 pass (no-grant read blocked; invalid/refused logged; enquiry and thread grants scoped; expiry; immutability; reviewer/buyer/seller/anonymous/service-role refused and still reading only their own data; refusal-flood throttle). Rollback: 0-line diff.
