// Volunteer endpoints over the volunteer RPCs. POST /functions/v1/volunteer-api/<action> with a volunteer JWT.
// The RPCs check the role, category and ownership themselves (forbidden / not_found).
import { serveApi } from "../_shared/rpc.ts";

serveApi("volunteer-api", {
  "offers":               { rpc: "my_offers",              auth: "user" },
  "offers/nearby":        { rpc: "nearby_offers",          auth: "user", spec: { lat: "num", lng: "num", radius_km: "num?" } },
  "stats":                { rpc: "my_stats",               auth: "user" },
  "device-token":         { rpc: "register_device_token",  auth: "user", spec: { token: "text", platform: "text" } },

  "assignments/detail":   { rpc: "my_assignment_detail",   auth: "user", spec: { id: "uuid" } },
  "assignments/claim":    { rpc: "claim_assignment",       auth: "user", spec: { id: "uuid" } },
  "assignments/decline":  { rpc: "decline_assignment",     auth: "user", spec: { id: "uuid" } },
  "assignments/state":    { rpc: "update_assignment_state", auth: "user", spec: { id: "uuid", state: "text" } },
  "assignments/verify-otp": { rpc: "driver_verify_otp",    auth: "user", spec: { id: "uuid", purpose: "text", code: "text", confirmed: "bool?" } },
  "assignments/report-issue": { rpc: "driver_report_issue",      auth: "user", spec: { id: "uuid", type: "text", note: "text" } },
  "assignments/location": { rpc: "update_my_location",     auth: "user", spec: { id: "uuid", lat: "num", lng: "num" } },
});