# Buyer-contact access architecture (0006 ROUND 4 C) - local validation only

- `enquiry_private` is no longer readable by staff directly. Policy `epriv_read` = the buyer, OR `buyer_contact_grant_active(enquiry)`.
- Staff call `staff_open_buyer_contact(enquiry, purpose)` (SECURITY DEFINER). It requires: staff role; purpose >= 5 chars; admin or the lead case for that enquiry assigned to the caller and not closed. It writes an immutable `buyer_contact_access_log` row (actor, role, enquiry, buyer reference, action, purpose, timestamp) and a 10-minute grant.
- Every read re-checks assignment and case status, plus an unexpired grant, so reassignment, closure, expiry and `admin_revoke_buyer_contact_access` take effect immediately. A planted grant without assignment is useless.
- Admins have no table bypass: they also open through the audited function; they read the log (`bcal_admin_read`).
- Tests BC0-BC20 (unauthorised, expired, revoked, cross-enquiry, reassigned, closed, immutable log, anon execute denied).
- Note: `actor_role` records the definer's `current_user`; the staff identity is `actor_id`. Pre-0006 control BC0 showed "not exposed" for the fixture, so the staging exposure for assigned staff is established by policy review, not by that test.
