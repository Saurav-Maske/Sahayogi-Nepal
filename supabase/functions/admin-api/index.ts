// Admin endpoints over the admin RPCs. POST /functions/v1/admin-api/<action> with an admin JWT.
// Body fields are the RPC parameters without `p_`. See docs/API-CONTRACT.md ("Edge API over the RPCs").
import { serveApi } from "../_shared/rpc.ts";

serveApi("admin-api", {
  "dashboard":          { rpc: "admin_dashboard_counts", auth: "admin" },
  "map":                { rpc: "admin_map_markers", auth: "admin" },

  "requests/list":      { rpc: "admin_list_requests",   auth: "admin", spec: { status: "text?", kind: "text?" } },
  "requests/approve":   { rpc: "admin_approve_request", auth: "admin", spec: { id: "uuid", items: "array?" } },
  "requests/decline":   { rpc: "admin_decline_request", auth: "admin", spec: { id: "uuid", reason: "text" } },
  "requests/assign":    { rpc: "create_assignments",    auth: "admin", spec: { id: "uuid" } },

  "stock/import":       { rpc: "admin_import_stock",    auth: "admin", spec: { items: "array" } },
  "stock/move-lot":     { rpc: "admin_move_lot",        auth: "admin", spec: { id: "uuid", phase: "text", qty: "num?", reason: "text?" } },

  "incidents/list":     { rpc: "admin_list_incidents",  auth: "admin", spec: { status: "text?" } },
  "incidents/resolve":  { rpc: "admin_resolve_incident", auth: "admin", spec: { id: "uuid", status: "text", resolution: "text?", notes: "text?" } },

  "audit/list":         { rpc: "admin_list_audit",      auth: "admin", spec: { limit: "int?", before: "int?", action: "text?", entity: "text?" } },
});