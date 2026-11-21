// Endpoints that need no account. POST /functions/v1/public-api/<action>.
// The requester proves ownership with ref (public_ref) + token (tracking_token); the RPCs return not_found for
// a wrong ref or token without saying which one was wrong.
import { serveApi } from "../_shared/rpc.ts";

serveApi("public-api", {
  "map":                       { rpc: "map_markers",                 auth: "none" },
  "tracking":                  { rpc: "get_tracking",                auth: "none", spec: { ref: "text", token: "text" } },
  "tracking/otp":              { rpc: "requester_get_otp",           auth: "none", spec: { ref: "text", token: "text", purpose: "text" } },
  "tracking/pickup-qty":       { rpc: "requester_update_pickup_qty", auth: "none", spec: { ref: "text", token: "text", items: "array" } },
  "tracking/confirm-delivery": { rpc: "requester_confirm_delivery",  auth: "none", spec: { ref: "text", token: "text", full: "bool", note: "text?", shortfall: "array?" } },
});