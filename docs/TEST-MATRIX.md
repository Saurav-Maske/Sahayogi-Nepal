# Test matrix (Person 4) — mark ✅/❌ per checkpoint
| Test | Expected | H24 | H30 | H36 | H42 |
|---|---|---|---|---|---|
| Anonymous submit | Created `pending_admin_review`; no PII/other requests readable | | | | |
| Admin approval | Admin only; approved qty ≤ available stock | | | | |
| Volunteer eligibility | A: general; B: +transport; C: +healthcare | | | | |
| 60s escalation | Server expands A-only offer after 60s | | | | |
| Double accept | Only one claim succeeds | | | | |
| Donation pickup | Donor can amend qty before OTP; confirmed qty → inventory | | | | |
| Delivery OTP | Single-use, expires, bound to assignment/action | | | | |
| Short delivery | Incident in admin queue; not marked fully fulfilled | | | | |
| Map windows | Pickup >6h / fulfilled >12h disappear | | | | |
| Document privacy | Unauthorised cannot read ID objects | | | | |
| Stock concurrency | Available never < 0 | | | | |
