# CLAIM AND VERIFICATION FLOW (draft migrations 0004/0005; locally tested only)

1. Claimant (signed in) submits a claim (existing `submit_claim`, rate-limited).
2. `start_claim_verification(email|phone)`: random token (email, 24 h) or 6-digit OTP (phone, 10 min), stored only as a salted SHA-256 hash; the plaintext goes to a service-role-only outbox that **nothing reads until a delivery provider is separately approved**; the API never returns the code. Email-domain-matches-website is recorded as *evidence only*.
3. `confirm_claim_verification`: max 5 attempts, expiry, claimant-only; success deletes the outbox row.
4. Evidence upload: private `verification-docs` bucket; claimant sees own; reviewers only for **open** claims; admin all.
5. Review: `review_claim` approve is blocked by trigger unless claimant email is verified and no conflicting open claim by another claimant exists.
6. **Approval ≠ verification.** An approved claim stays `not_verified` (so no direct leads) until an admin sets verification and the business contacts are verified in the vault.
**Invitations:** individual, staff-created for an assigned lead, one active per company, admin approval required, delivery stays `logged_manual` (no provider), single-use token, redeeming approves nothing.
