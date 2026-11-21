
# Sahayogi Nepal – Auth & Account API

Owner: Person 2 (Rujan Dhamala, Aakash Thakur). Status: **v1 – auth layer**. Every change goes through a PR + a message in team chat.

Base URL: `https://<project-ref>.supabase.co` (local: `http://127.0.0.1:54321`)
Edge Functions: `POST {BASE}/functions/v1/<name>`
Required header on every call: `apikey: <ANON_KEY>` and `Content-Type: application/json`.
Protected calls also send `Authorization: Bearer <access_token>`.

> Only the **anon/publishable key** goes into Flutter and the admin web. The service-role key never leaves the backend.

---

## 0. Response format

```json
{ "data": { ... }, "error": null }
{ "data": null, "error": { "code": "invalid_credentials", "message": "Incorrect email or password." } }
```

| HTTP      | Meaning                                          |
| --------- | ------------------------------------------------ |
| 200 / 201 | success                                          |
| 400       | validation error (`error.code` says which)     |
| 401       | not signed in / wrong credentials                |
| 403       | signed in but not allowed (not admin, suspended) |
| 404 / 409 | not found / state conflict                       |
| 429       | throttled                                        |

### Error codes

| code                                                                                                     | Where                       | Show to user                                                                      |
| -------------------------------------------------------------------------------------------------------- | --------------------------- | --------------------------------------------------------------------------------- |
| `invalid_credentials`                                                                                  | both logins                 | "Incorrect email or password." (also returned for the wrong portal – on purpose) |
| `too_many_attempts`                                                                                    | login, reset, apply, upload | "Too many tries, wait and retry."                                                 |
| `account_suspended`                                                                                    | login, auth-me              | "Account suspended. Contact an admin."                                            |
| `unauthenticated`                                                                                      | auth-me                     | go to login                                                                       |
| `forbidden`                                                                                            | admin functions             | caller is not an active admin                                                     |
| `invalid_email` / `invalid_name` / `invalid_phone` / `invalid_type` / `invalid_citizenship_no` | apply                       | field error                                                                       |
| `license_required` / `service_card_required`                                                         | apply                       | field error                                                                       |
| `invalid_files` / `invalid_path` / `document_missing`                                              | upload / apply              | re-upload                                                                         |
| `application_exists`                                                                                   | apply                       | "An application or account with this email already exists."                       |
| `invalid_state`                                                                                        | approve                     | already decided                                                                   |
| `reason_required`                                                                                      | approve (decline)           | admin must type a reason                                                          |
| `invite_failed`                                                                                        | approve                     | email could not be sent (check SMTP)                                              |
| `already_active`                                                                                       | approve (resend_invite)     | volunteer already has a password → use Forgot password                           |

---

## 1. Roles and who can call what

| Caller            | Can use                                                                                                         |
| ----------------- | --------------------------------------------------------------------------------------------------------------- |
| Anyone (no login) | `create-upload-urls`, `submit-volunteer-application`, `request-password-reset`, the set-password web page |
| Volunteer         | `volunteer-login`, `auth-me`, all volunteer RPCs (`my_offers`, `claim_assignment`, …)                  |
| Admin             | `admin-login`, `auth-me`, `approve-volunteer`, `admin-set-account-status`, all `admin_*` RPCs         |

Admin and volunteer have **separate login endpoints**. A volunteer's credentials sent to `admin-login` (and vice-versa) fail with the same `invalid_credentials` message.

> **Important for everyone:** the real protection is on the data, not the login screen. Every admin RPC/table is guarded by `is_admin()` and every volunteer RPC checks the caller's profile inside the database. A token from the volunteer login cannot approve anything.

---

## 2. Login

### POST `/functions/v1/admin-login`   (admin web only)

### POST `/functions/v1/volunteer-login`   (Flutter volunteer app)

Request

```json
{ "email": "driver1@demo.test", "password": "••••••••••" }
```

Response 200

```json
{
  "data": {
    "session": {
      "access_token": "eyJ...",
      "refresh_token": "abc...",
      "expires_in": 3600,
      "expires_at": 1795000000,
      "token_type": "bearer"
    },
    "profile": {
      "id": "uuid",
      "full_name": "Demo Driver 1",
      "email": "driver1@demo.test",
      "phone": "9800000001",
      "role": "volunteer",
      "volunteer_type": "driver",
      "categories": ["A", "B"]
    }
  },
  "error": null
}
```

Rules: 5 failed attempts per email (or 30 per IP) in 15 min → `429 too_many_attempts`. Suspended accounts get `403 account_suspended`.

**After login, hand the session to the SDK** so refresh + RPC calls work automatically:

Flutter (volunteer app)

```dart
final res = await supabase.functions.invoke('volunteer-login',
    body: {'email': email, 'password': password});
final d = (res.data as Map)['data'];
await supabase.auth.setSession(d['session']['refresh_token']);   // SDK refreshes tokens from now on
final profile = d['profile'];                                    // role, categories, volunteer_type

// errors
try { ... } on FunctionException catch (e) {
  final code = (e.details as Map?)?['error']?['code'];          // invalid_credentials, too_many_attempts, ...
}
```

Admin web (supabase-js)

```js
const r = await fetch(`${SUPABASE_URL}/functions/v1/admin-login`, {
  method: 'POST',
  headers: { 'Content-Type': 'application/json', apikey: ANON_KEY },
  body: JSON.stringify({ email, password }),
});
const j = await r.json();
if (j.error) return showError(j.error.code);
await supabase.auth.setSession({
  access_token: j.data.session.access_token,
  refresh_token: j.data.session.refresh_token,
});
```

Logout: `supabase.auth.signOut()` (both apps).

### POST `/functions/v1/auth-me`

Header: `Authorization: Bearer <access_token>`. Returns `{ data: { profile } }` (same fields + `account_status`, `last_login_at`). Use on app start to confirm the saved session is still valid and still the right role. `401 unauthenticated` → send to login.

---

## 3. Volunteer sign-up (two steps, no account yet)

Applicants are stored in `volunteer_applications` (staging). **No auth user exists until an admin approves.**

### Step 1 – POST `/functions/v1/create-upload-urls`

```json
{
  "volunteer_type": "driver",
  "files": [
    { "kind": "citizenship", "content_type": "image/jpeg" },
    { "kind": "license",     "content_type": "image/jpeg" }
  ]
}
```

Allowed kinds: `manpower` → citizenship · `driver` → citizenship + license · `doctor` → citizenship + service_card.
Images only: jpeg / png / webp, max 5 MB.

Response

```json
{ "data": { "uploads": [
  { "kind": "citizenship", "path": "docs/9f1c....jpg", "token": "eyJ...", "signed_url": "https://...", "content_type": "image/jpeg" },
  { "kind": "license",     "path": "docs/77ab....jpg", "token": "eyJ...", "signed_url": "https://...", "content_type": "image/jpeg" }
 ], "max_bytes": 5242880 }, "error": null }
```

Upload each file with its **token** (not a normal upload – anon users have no storage policy). Flutter:

```dart
await supabase.storage.from('volunteer-docs').uploadBinaryToSignedUrl(
    path, token, bytes, const FileOptions(contentType: 'image/jpeg'));
```

(Method name per `storage_client` in recent supabase_flutter; if your version differs, look for "signed upload URL" in its docs.)
(supabase-js: `supabase.storage.from('volunteer-docs').uploadToSignedUrl(path, token, file)`)

### Step 2 – POST `/functions/v1/submit-volunteer-application`

```json
{
  "full_name": "Sita Sharma",
  "email": "sita@gmail.com",
  "phone": "9801234567",
  "volunteer_type": "driver",
  "citizenship_no": "12-34-56-78901",
  "citizenship_photo_path": "docs/9f1c....jpg",
  "license_no": "01-06-00123456",
  "license_photo_path": "docs/77ab....jpg"
}
```

Doctor: send `service_card_no` + `service_card_photo_path` instead of the licence fields.
Phone must be a Nepal mobile (`98XXXXXXXX` or `+97798XXXXXXXX`).

Response 201

```json
{ "data": { "application_id": "uuid", "status": "submitted" }, "error": null }
```

Limits: 5 per IP and 3 per phone per 24 h. One live application per email (`409 application_exists`).

Show the applicant: *"Application received. You will get an email with a link to set your password once an admin approves it."*

---

## 4. Admin reviews applications

### Read the queue (table, admin JWT)

```js
supabase.from('volunteer_applications').select('*').eq('review_status', 'submitted').order('created_at')
```

### View ID photos (admin JWT, short-lived URL)

```js
const { data } = await supabase.storage.from('volunteer-docs').createSignedUrl(path, 60); // seconds
```

Non-admins get nothing from this bucket.

### POST `/functions/v1/approve-volunteer`   (admin JWT)

```json
{ "application_id": "uuid", "decision": "approve", "note": "Documents verified" }
```

| decision          | Effect                                                                                                     | Extra                                         |
| ----------------- | ---------------------------------------------------------------------------------------------------------- | --------------------------------------------- |
| `approve`       | creates the auth user, profile (categories A / A+B / A+C by type) and **emails a set-password link** | `note` optional                             |
| `decline`       | stores reason; no account created                                                                          | `note` **required** (min 3 chars)     |
| `resend_invite` | re-sends the link to an approved volunteer who never set a password                                        | if they already did → `409 already_active` |

Response: `{ "data": { "application_id": "...", "decision": "approve", "profile_id": "uuid" }, "error": null }`

> Declined applicants are not emailed automatically (Supabase only sends auth emails). Show the status in the admin panel; add an email provider later if needed.

### POST `/functions/v1/admin-set-account-status`   (admin JWT)

```json
{ "user_id": "uuid", "status": "suspended", "reason": "Under investigation" }
```

`status`: `suspended` | `active`. Suspended users cannot log in or refresh tokens, and all volunteer RPCs stop working for them immediately. An admin cannot change their own status.

---

## 5. Set password / forgot password (web page)

Hosted page: `web/set-password/` → `https://<host>/set-password/`

Flow

1. Admin approves → volunteer gets an email from **Sahayogi Nepal** (sent through Gmail SMTP) with a **Set my password** button.
2. Button opens the web page → they choose a password (≥ 10 chars with upper, lower, digit, symbol).
3. Page says "Open the app and sign in". They log in via `volunteer-login`.
4. Link expired or already used? The same page shows **Send me a new link**.

### POST `/functions/v1/request-password-reset`   (public)

Used by the Flutter "Forgot password?" screen, the admin web, and the set-password page.

```json
{ "email": "sita@gmail.com" }
```

Always answers `200` with the same message, whether or not the account exists:

```json
{ "data": { "message": "If that email belongs to an account, a link to set your password has been sent." }, "error": null }
```

Limits: 3 per email and 10 per IP per hour. Works for admins too (same page, same flow).

Flutter

```dart
await supabase.functions.invoke('request-password-reset', body: {'email': email});
// always show: "If that email has an account, we sent a link."
```

---

## 6. Demo accounts (local / demo project only)

Created by `node --env-file=.env scripts/seed_demo.mjs` (or the users-only `scripts/seed_users.mjs`). For a hosted project see [`REMOTE-SEED.md`](REMOTE-SEED.md).

| Email                                | Role                 | Categories |
| ------------------------------------ | -------------------- | ---------- |
| admin@demo.test                      | admin                | –         |
| driver1@demo.test, driver2@demo.test | volunteer (driver)   | A, B       |
| general@demo.test                    | volunteer (manpower) | A          |
| doctor@demo.test                     | volunteer (doctor)   | A, C       |

Password: the `DEMO_PASSWORD` from `.env`, shared in the team chat (not in Git). Demo emails do not receive mail; use the real flow only with real Gmail addresses.

---

## 7. Quick tests (curl)

```bash
export SUPABASE_URL="http://127.0.0.1:54321"; export KEY="<anon key>"

# admin login
curl -s -X POST "$SUPABASE_URL/functions/v1/admin-login" -H "apikey: $KEY" -H "Content-Type: application/json" \
  -d '{"email":"admin@demo.test","password":"<demo password>"}'

# volunteer token must NOT work on the admin portal -> invalid_credentials
curl -s -X POST "$SUPABASE_URL/functions/v1/admin-login" -H "apikey: $KEY" -H "Content-Type: application/json" \
  -d '{"email":"driver1@demo.test","password":"<demo password>"}'

# volunteer calling an admin function -> 403 forbidden
curl -s -X POST "$SUPABASE_URL/functions/v1/approve-volunteer" -H "apikey: $KEY" \
  -H "Authorization: Bearer <volunteer access_token>" -H "Content-Type: application/json" \
  -d '{"application_id":"00000000-0000-0000-0000-000000000000","decision":"approve"}'

# me
curl -s -X POST "$SUPABASE_URL/functions/v1/auth-me" -H "apikey: $KEY" -H "Authorization: Bearer <access_token>"
```

On Windows PowerShell, use `$env:KEY="..."` instead of `export`. Local emails (invite / reset) appear in Inbucket: http://127.0.0.1:54324 (unless Gmail SMTP is enabled).

---
