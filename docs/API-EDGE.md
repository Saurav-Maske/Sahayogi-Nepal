# Edge API over the RPCs (v1)

Three Edge Functions expose every RPC over plain HTTP, so Flutter and the admin web can use `{ data, error }` like the other functions instead of calling `supabase.rpc` directly.

`POST {BASE}/functions/v1/<function>/<action>` with headers `apikey: <ANON_KEY>`, `Content-Type: application/json` and, where noted, `Authorization: Bearer <access_token>`.
Body fields are the RPC parameters without the `p_` prefix. Optional fields can be left out (the SQL default applies). Actions that take no body also accept GET.
Responses: `{ "data": <rpc result>, "error": null }` or `{ "data": null, "error": { "code", "message" } }`.

The caller's JWT is forwarded to Postgres, so `is_admin()`, category checks and ownership checks run inside the RPC exactly as before. The functions add only: auth guard (no, invalid or expired token = `401 unauthenticated`; signed in but wrong role = `403 forbidden`, on admin routes too), input type checks (`invalid_input`, 400), and error mapping.

HTTP status for RPC error codes: `unauthorized` 401, `forbidden` 403, `not_found` 404, 409 for `already_claimed | already_on_request | already_assigned | already_reported | not_available | invalid_state | invalid_transition | otp_required | otp_not_available | lot_reserved | insufficient_stock | already_received | not_received`, `too_many_requests` 429, `hub_not_configured` 500, any other code 400. A non-code Postgres error becomes `db_error` 500 (logged, not shown).
`assignments/verify-otp` takes `purpose` `pickup | hub_dropoff | hub_pickup | delivery` (see API-CONTRACT.md). `driver_verify_otp` wrong codes are still HTTP 200 with `data.ok = false` (see API-CONTRACT.md); check `data.ok`.

## admin-api (admin JWT)

| Action                | RPC                    | Body                                              |
| --------------------- | ---------------------- | ------------------------------------------------- |
| `dashboard`         | admin_dashboard_counts | none                                              |
| `map`               | admin_map_markers      | none                                              |
| `district`                  | get_district_config         | none                                                    |
| `device-token`              | register_public_device_token | `token`, `platform`                                  |
| `requests/list`     | admin_list_requests    | `status?`, `kind?`                            |
| `requests/approve`  | admin_approve_request  | `id`, `items?`                                |
| `requests/decline`  | admin_decline_request  | `id`, `reason`                                |
| `requests/assign`   | create_assignments     | `id`                                            |
| `assignments/receive`   | admin_receive_donation | `id`, `items`                                   |
| `assignments/issue-otp` | admin_issue_otp        | `id`                                              |
| `stock/import`      | admin_import_stock     | `items`                                         |
| `stock/move-lot`    | admin_move_lot         | `id`, `phase`, `qty?`, `reason?`          |
| `stock/reserve-levels`     | admin_list_reserve_levels | none                                        |
| `stock/reserve-levels/set` | admin_set_reserve_level   | `item_type`, `min_qty`                      |
| `stock/reconcile`   | admin_inventory_reconcile | none                                            |
| `incidents/list`    | admin_list_incidents   | `status?`                                       |
| `incidents/resolve` | admin_resolve_incident | `id`, `status`, `resolution?`, `notes?`   |
| `audit/list`        | admin_list_audit       | `limit?`, `before?`, `action?`, `entity?` |

## volunteer-api (volunteer JWT)

| Action                     | RPC                     | Body                                          |
| -------------------------- | ----------------------- | --------------------------------------------- |
| `offers`                 | my_offers               | none                                          |
| `offers/nearby`          | nearby_offers           | `lat`, `lng`, `radius_km?`            |
| `stats`                  | my_stats                | none                                          |
| `device-token`           | register_device_token   | `token`, `platform`                       |
| `assignments/detail`     | my_assignment_detail    | `id`                                        |
| `assignments/claim`      | claim_assignment        | `id`                                        |
| `assignments/decline`    | decline_assignment      | `id`                                        |
| `assignments/state`      | update_assignment_state | `id`, `state`                             |
| `assignments/verify-otp` | driver_verify_otp       | `id`, `purpose`, `code`, `confirmed?` |
| `assignments/report-issue` | driver_report_issue   | `id`, `type`, `note`                          |
| `assignments/location`   | update_my_location      | `id`, `lat`, `lng`                      |

## public-api (no account)

| Action                        | RPC                         | Body                                                    |
| ----------------------------- | --------------------------- | ------------------------------------------------------- |
| `map`                       | map_markers                 | none                                                    |
| `tracking`                  | get_tracking                | `ref`, `token`                                      |
| `tracking/otp`              | requester_get_otp           | `ref`, `token`, `purpose`                         |
| `tracking/pickup-qty`       | requester_update_pickup_qty | `ref`, `token`, `items`                           |
| `tracking/confirm-delivery` | requester_confirm_delivery  | `ref`, `token`, `full`, `note?`, `shortfall?` |

Not in these three: `get-offer-route` (route preview for an offer) and `get-route` are their own Edge Functions, see API-CONTRACT.md. `send-push` is called by the database, not by apps.

Examples:

```bash
curl -X POST "$BASE/functions/v1/volunteer-api/assignments/claim" \
  -H "apikey: $ANON" -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{ "id": "<assignment uuid>" }'

curl -X POST "$BASE/functions/v1/public-api/tracking" \
  -H "apikey: $ANON" -H "Content-Type: application/json" \
  -d '{ "ref": "AB12CD34", "token": "<tracking_token>" }'
```

Known limit: `public-api/tracking*` has no throttle on wrong ref/token guesses (same as the RPCs). The token is two UUIDs, so guessing is impractical; add an IP throttle through `auth_attempts` later (needs a new `kind` value, so a migration).