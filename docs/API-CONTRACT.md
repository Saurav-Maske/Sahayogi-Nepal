# API Contract (v0 — Person 2 owns; update via PR)

All responses: `{ "data": <obj|null>, "error": { "code": string, "message": string } | null }`
IDs: UUID. `public_ref`: random, non-sequential. Timestamps: ISO-8601 UTC.

## Enums
- request_kind: `resource_request | manpower_request | donation_offer | healthcare_request | transport_request`
- request_status: `pending_admin_review | approved | declined | awaiting_assignment | assigned | in_progress | fulfilled | partially_fulfilled | cancelled`
- assignment_state: `offered | accepted | declined | expired | en_route_to_pickup | picked_up | en_route_to_destination | delivered | disputed | cancelled`
- inventory_phase: `received | processing | ready_to_ship | reserved | dispatched | consumed | returned | adjusted`
- volunteer categories: A=general, B=driver, C=healthcare. driver = A+B, doctor = A+C.

## Endpoints
### POST /functions/v1/submit-request  (anonymous allowed; rate limiting TODO)
Request:
```json
{ "kind": "resource_request", "requester_name": "Test Person", "requester_phone": "+9779800000000",
  "district": "Kavrepalanchok", "lat": 27.62, "lng": 85.55, "urgency": "high", "notes": "optional",
  "items": [ { "item_type": "rice", "qty": 50, "unit": "kg" } ] }
```
Response (201):
```json
{ "data": { "public_ref": "SN-AB12CD34", "tracking_token": "<shown once>", "status": "pending_admin_review" }, "error": null }
```

### RPC claim_assignment(p_assignment_id uuid)  (authenticated volunteer)
Atomic; one winner. Errors: `already_claimed | not_eligible | not_found`.

### View public_map_markers (anon read)
`id, district, lat, lng (rounded ~1km), marker_type: open_request|pickup|fulfilled, event_at` — pickup ≤6h, fulfilled ≤12h.

### TODO (Person 2) — publish request/response examples here before UI work depends on them
- admin_review_request(request_id, decision, approved_items[], reason)
- reserve_stock / inventory movement RPCs
- issue_otp / verify_otp (server only; hash+expiry+attempts; never in push/logs)
- track-request (public_ref + tracking_token)
- register_device_token
- 60s escalation job (A → B/C)
