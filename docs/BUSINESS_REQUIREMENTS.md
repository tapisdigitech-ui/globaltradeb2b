# BUSINESS REQUIREMENTS (condensed from the master brief)

**Model:** directory-first marketplace. Unclaimed profiles built from lawful public information → buyers discover them → suppliers claim and verify → verified sellers receive eligible leads directly; leads matching unclaimed suppliers go to an internal admin lead desk where staff phone suppliers manually and help them claim.

## Non-negotiables
* Never fabricate suppliers/records/metrics; demo data is always labelled and excluded from reports.
* Three public states, never blurred: **Unclaimed**, **Claimed**, **Verified**. A found email/phone is never a verification.
* Discovered contacts live only in a protected contact vault (admin/staff roles, audited). Never in public views/APIs/JS/exports.
* Path A (claimed + verified + active + verified contact + eligible) → direct to seller. Path B (otherwise) → admin lead desk only; buyer is never told an unregistered supplier received the enquiry; unmatched queue exists.
* No automated emailing, SMS, calling, bulk outreach; individual staff-initiated invitations only, after explicit approval to enable.
* Lawful ingestion only: terms, robots, privacy (DPDP), image licences; no CAPTCHA/anti-bot bypass; small controlled batches (target 1,000–5,000 over time).
* Explainable PostgreSQL matching first (shows *why* a supplier matched); AI optional later.
* Original design; IndiaMART only a usability reference. Seller Centre stays lead-first (Home, Buy Leads, Messages, More).

## Success criteria per phase
Implemented → locally tested → staging tested (with real executed test results in TEST_REPORT.md) → only then reviewed for production. Test scenarios 1–7 (routing), claim, contact-privacy and staff tests are mandatory acceptance gates.
