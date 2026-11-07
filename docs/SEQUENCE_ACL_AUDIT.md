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

---

# Round 9.1 – final sequence privilege review (service_role focus)

Local-only. Sole hosted access: **one read-only catalogue SELECT** on staging (ACLs, owners, default ACLs; no rows read, nothing modified). Result: **migration 0008 stands unchanged; no migration 0009 is needed.**

## 1–3. Inventory, users, service-role workflows
13 sequences ↔ 13 tables (`audit_log`, `categories`, `company_membership_audit`, `enquiry_contact_access`, `product_view_events`, `rate_events` = serial-default, not OWNED BY; `buyer_contact_access_log`, `claim_evidence_access_log`, `company_import_audit`, `contact_access_log`, `lead_distribution_events`, `lead_status_history`, `staff_comms_access_log` = identity). Writers are 20 functions (all SECURITY DEFINER, owner postgres): the audit/rate/gate helpers (`audit_changes`, `audit_membership`, `check_rate`, `_evidence_gate`, `_lead_case_history`, `_match_requirement`) plus the callable RPCs.
**Service-role insert/update workflows: there are none at table level.** `service_role` holds only SELECT (+ delete/truncate/references/trigger) on these tables – no INSERT, no UPDATE – both on the local replica and on staging (catalogue confirmed: `sr_ins=0 sr_upd=0` on the six staging tables; public default ACL for new tables = `service_role=Dxtm`). Its only write paths are definer RPCs it may execute: `record_product_view` (→ `product_view_events`, works – F1), `import_apply`/`import_rollback` (admin uid required → refused for a bare service key, F3), `reveal_buyer_contact`, `submit_enquiry` (member/user uid required, F4). They run as owner `postgres`, so they never need the caller's sequence rights.

## 4–7. Genuine non-owner roles (`tests/jwt/test_sequence_roles.py`, 28 checks, default and classic-default platforms)
Principals: anon, authenticated (buyer), authenticated (admin), service_role, each through the PostgREST emulator (`session_user=authenticator`, `SET LOCAL ROLE`, signed-token claims); R0 proves each is non-superuser and owns no relation.
- All 13 sequences × `nextval/currval/setval/SELECT` × 4 principals: refused, except authenticated `nextval/currval` on `categories_id_seq` (S1).
- Direct INSERT into all 13 tables: anon 13/13 and service_role 13/13 refused at the table ACL; buyer 12/13 at the ACL and `categories` by RLS; admin inserts a category through the sequence default (S2, S2b, S2c, S3). On the classic-default simulation service_role *does* get INSERT on the 7 identity tables – and those inserts still pass the ACL because PostgreSQL does not check sequence privileges for identity columns (W2); serial tables are the only ones where the sequence ACL gates an insert.
- Invariants over real ACLs: I1 every role with INSERT on a serial table has USAGE on its sequence; I2 no role holds a sequence privilege without a table that needs it. Minimum safe ACL = exactly what 0008 leaves.
- What-if (W1): had service_role been granted INSERT on a serial table, the closed sequence ACL would refuse it. **Rule for future migrations: grant USAGE on the sequence in the same migration that grants INSERT on its table; I1 fails otherwise.**
- Legitimate writes by non-owners through definer paths: F1 service_role → `record_product_view`; F2 authenticated → `create_company_request`/`check_rate` → `rate_events`; F5 admin RPC → `audit_log`.

## 8. SECURITY DEFINER ownership / search_path (D1–D6)
All public relations, sequences and functions are owned by `postgres` (staging: 70 functions, all owned by postgres, 52 definer, **0 without pinned search_path**); no definer function is owned by anon/authenticated/service_role/authenticator; every path is `public, pg_temp` (no `extensions`, no `$user`, pg_temp last); the three app roles cannot CREATE in `public`; every writer of the 13 tables has the same owner as every sequence.

## 9. Could existing tests hide missing privileges? Yes – measured
Mutation control (`tests/run_sequence_mutations.sh`, 9 deliberate breakages in throw-away copies): **9/9 detected** by the new genuine-role tests. The older suites alone were weaker:
| Mutation | 404-suite result | New tests |
|---|---|---|
| revoke authenticated USAGE on `categories_id_seq` | **404 pass – missed** (no test inserts a category as a non-owner admin) | S3 fails |
| change owner of `record_product_view` to a role lacking rights | **404 pass – missed** (path not exercised as service_role) | F1, D1, D2, D6 fail |
| change owner of `check_rate` | suite aborts at fixture setup (detected, but as a crash) | F2, D1, D6 fail |
Also: the old `SQ13` ran as table owner; it is now labelled OWNER-CONTROL ONLY. The legacy `app.uid` suite (138) is a synthetic-schema suite and is not evidence for sequence privileges.

## 10. Recommendation
Keep 0008 exactly: revoke all from PUBLIC/anon/authenticated/service_role on the 13 sequences; USAGE on `categories_id_seq` for authenticated only. Do **not** grant service_role sequence rights – it has no INSERT path to use them, and granting them would only widen `nextval/setval` abuse. Staging already has closed *public* sequence defaults for `postgres` (`postgres=rwU` only), so 0008's default-privileges statement is belt-and-braces there; note that objects created by `supabase_admin` (or in the `storage` schema) carry classic defaults and are outside this migration.
Hosted-only remaining: the same ACL/ownership query on the isolated branch after the chain is applied.
