# Sequence privilege audit (Round 9 · B5)

## Inventory (local replica after baseline + 0001–0007; same objects as staging's 6 serial sequences + 7 added identity sequences)
13 sequences in `public`: 7 identity (buyer_contact_access_log, claim_evidence_access_log, company_import_audit, contact_access_log, lead_distribution_events, lead_status_history, staff_comms_access_log) and 6 serial-style that are *not* `OWNED BY` their column (audit_log, categories, company_membership_audit, enquiry_contact_access, product_view_events, rate_events – as in the hosted catalogue).

## Findings before 0008
| Sequence group | anon | authenticated | service_role |
|---|---|---|---|
| 6 serial-style | – | `SELECT, USAGE` | – |
| 7 identity | – | – | – |
| **Classic Supabase default ACLs** (simulated: `load_baseline_classic.sh`) – any sequence created later by `postgres` | `ALL` | `ALL` | `ALL` |

Why it matters: `USAGE` lets a caller burn ids with `nextval()` (gaps/exhaustion, side-channel on insert volume); `SELECT` exposes `currval`/`last_value` (activity counts); `UPDATE` lets `setval()` reset an audit sequence and collide ids. Default privileges cannot be assumed safe: on a platform with classic defaults a new sequence is world-usable.

## Decision (migration `0008_sequence_privileges.sql`)
- `REVOKE ALL` on all 13 from `PUBLIC, anon, authenticated, service_role` (explicit; not relying on defaults).
- `GRANT USAGE` on `categories_id_seq` to `authenticated` only – the single sequence an application role advances directly (an admin inserts categories via PostgREST; RLS `categories_admin` limits who).
- `ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public REVOKE ALL ON SEQUENCES FROM anon, authenticated, service_role` so future sequences start closed.
- Every other writer is SECURITY DEFINER / trigger / owner-run (tests SQ12, SQ12c: `create_company_request` and its `check_rate()` write `rate_events` while the caller has no privilege on the sequence).
- Behaviour change: authenticated loses `SELECT` on `categories_id_seq` (not needed to insert) and all rights on the 5 other serial sequences. Rollback `down/0008_down.sql` restores the grants of the original six; it does **not** re-open default privileges (deliberately; documented in the file). After rollback the 7 identity sequences show an explicit owner-only ACL instead of NULL – equivalent privileges, different catalogue fingerprint (reported by `dry_run_0008.sh`).

## Tests (`tests/sequence_acl_tests.sql`, run by `tests/run_sequence_acl.sh default|classic`) – 16 checks, both platforms pass
SQ1 inventory (13; 7 identity + 6 serial) · SQ2–SQ5 `has_sequence_privilege` for anon / service_role / authenticated / PUBLIC · SQ6 raw `relacl` (`aclexplode`) holds only owner + authenticated-on-categories · SQ7 no default ACL grants the three roles sequences · **SQ8 actual attempts**: `nextval`, `currval`, `setval`, direct `SELECT` by each role on all 13 (only authenticated `nextval`/`currval` on `categories_id_seq` allowed) · SQ9 `pg_sequences.last_value` hidden from anon · **legitimate use**: SQ10 admin inserts a category (default `nextval`), SQ11 non-admin still refused by RLS, SQ12/12b/12c `create_company_request` and rate limiting write through definer paths, SQ13 owner insert, SQ14 no direct INSERT grant on rate/view event tables.
Control: the same file run on the classic-default platform **without** 0008 fails 7 checks (SQ2, 3, 4, 6, 7, 8, 9) – the tests have teeth. The full 404 suite passes with 0008 applied on both platforms.

Hosted-only: staging's actual sequence ACLs for objects the migration will not recreate; platform default privileges of `supabase_admin`-created objects.
