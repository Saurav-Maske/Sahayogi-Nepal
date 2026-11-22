import { useCallback, useEffect, useRef, useState } from "react";
import { Link, useSearchParams } from "react-router-dom";
import {
  MapContainer,
  Marker,
  Popup,
  TileLayer,
  useMap,
} from "react-leaflet";
import L from "leaflet";
import QuickAction from "../components/dashboard/QuickAction";
import { supabase } from "../supabase";
import { hasSession } from "../services/session";
import "../styles/live-map.css";
import "leaflet/dist/leaflet.css";

type Marker = {
  id: string;
  kind: "request" | "accepted" | "driver" | "hub" | "pickup" | "fulfilled" | "volunteer";
  title: string;
  detail: string;
  lat: number;
  lng: number;
  updated: string;
  to?: string;
  sourceKind?: "request" | "donation";
};
type Position = { lat: number; lng: number };

const isDemoSeed = (value?: string | null) =>
  /^demo(?:\s|$)/i.test(value?.trim() ?? "");
const hasCoordinates = (lat: unknown, lng: unknown) => {
  if (lat == null || lng == null || lat === "" || lng === "") return false;
  const latitude = Number(lat);
  const longitude = Number(lng);
  return Number.isFinite(latitude) && Number.isFinite(longitude) &&
    latitude >= -90 && latitude <= 90 && longitude >= -180 && longitude <= 180;
};

const tabs = [
  ["all", "All activities"],
  ["requests", "Open requests"],
  ["pickups", "Donation pickup requests"],
  ["fulfilled", "Fulfilled · 6h"],
];

const inTab = (m: Marker, t: string) =>
  t === "all" ||
  (t === "requests" && m.kind === "request") ||
  (t === "pickups" && (m.kind === "pickup" || (m.kind === "accepted" && m.sourceKind === "donation"))) ||
  (t === "fulfilled" && m.kind === "fulfilled");

const labels: Record<string, string> = {
  request: "Open request",
  accepted: "Accepted request / donation",
  driver: "Active driver",
  hub: "Central inventory",
  pickup: "Open donation",
  fulfilled: "Fulfilled request",
  volunteer: "Active volunteer",
};

const pinIcon = (kind: string) =>
  L.divIcon({
    className: `leaflet-pin leaflet-pin--${kind}`,
    html: `<span>${kind === "request" ? "R" : kind === "accepted" || kind === "fulfilled" ? "✓" : kind === "driver" ? "D" : kind === "hub" ? "▦" : kind === "pickup" ? "P" : "V"}</span>`,
    iconSize: [28, 28],
    iconAnchor: [14, 14],
  });

function MapFocus({ marker }: { marker: Marker | null }) {
  const map = useMap();
  useEffect(() => {
    if (marker) map.flyTo([marker.lat, marker.lng], 14, { duration: 0.6 });
  }, [map, marker?.id]);
  return null;
}

function FollowAdminLocation({ position }: { position: Position | null }) {
  const map = useMap();
  useEffect(() => {
    if (position) map.flyTo([position.lat, position.lng], Math.max(map.getZoom(), 12), { duration: 0.6 });
  }, [map, position?.lat, position?.lng]);
  return null;
}

function FitActivities({ markers, focusMarkers, enabled }: { markers: Marker[]; focusMarkers: Marker[]; enabled: boolean }) {
  const map = useMap();
  const fitted = useRef(false);
  useEffect(() => {
    if (!enabled || fitted.current || !markers.length) return;
    const visibleMarkers = focusMarkers.length ? focusMarkers : markers;
    const bounds = L.latLngBounds(visibleMarkers.map((marker) => [marker.lat, marker.lng]));
    map.fitBounds(bounds, { padding: [28, 28], maxZoom: 12 });
    fitted.current = true;
  }, [enabled, focusMarkers, map, markers]);
  return null;
}

export default function LiveMapPage() {
  const [params, setParams] = useSearchParams();
  const requestedTab = params.get("layer") ?? "all";
  const tab = tabs.some(([key]) => key === requestedTab) ? requestedTab : "all";
  const [selected, setSelected] = useState<Marker | null>(null);
  const [markers, setMarkers] = useState<Marker[]>([]),
    [live, setLive] = useState(false),
    [error, setError] = useState("");
  const [activeAssignmentCounts, setActiveAssignmentCounts] = useState({ volunteers: 0, drivers: 0 });

  // The administrator's GPS is used only as the map camera position.
  // It is never added to the activity markers or displayed as a pin.
  const [adminPosition, setAdminPosition] = useState<Position | null>(null);
  const [tracking, setTracking] = useState(false);
  const [geoError, setGeoError] = useState("");
  const watchId = useRef<number | null>(null);

  const stopTracking = useCallback(() => {
    if (watchId.current !== null && "geolocation" in navigator) {
      navigator.geolocation.clearWatch(watchId.current);
    }
    watchId.current = null;
    setTracking(false);
  }, []);

  const startTracking = useCallback(() => {
    if (!("geolocation" in navigator)) {
      setGeoError("This browser does not support live location.");
      return;
    }
    if (watchId.current !== null) return;
    setGeoError("");
    setTracking(true);
    watchId.current = navigator.geolocation.watchPosition(
      (position) => {
        setAdminPosition({ lat: position.coords.latitude, lng: position.coords.longitude });
        setGeoError("");
      },
      (geo) => {
        setGeoError(geo.code === geo.PERMISSION_DENIED
          ? "Location access was blocked. Allow it in browser settings, then try again."
          : "Could not get your location. Activity markers remain available.");
        if (geo.code === geo.PERMISSION_DENIED) stopTracking();
      },
      { enableHighAccuracy: true, maximumAge: 5000, timeout: 20000 },
    );
  }, [stopTracking]);

  // Ask for the administrator's location as soon as the map opens. It is used
  // only to center the camera; activity markers remain the only visible pins.
  useEffect(() => {
    startTracking();
  }, [startTracking]);

  useEffect(() => () => {
    if (watchId.current !== null && "geolocation" in navigator) {
      navigator.geolocation.clearWatch(watchId.current);
      watchId.current = null;
    }
  }, []);

  // ---- admin map data ----
  useEffect(() => {
    let active = true;
    let channel: any;
    const load = async () => {
      if (!(await hasSession())) { setError('Sign in with an administrator account to load live operations.'); return; }
      const { data, error: e } = await supabase.rpc("admin_map_markers");
      if (!active) return;
      if (e) {
        setLive(false);
        setError(e.message || 'Live map data is unavailable.');
        return;
      }
      const hub = data?.hub;
      const requests = Array.isArray(data?.requests) ? data.requests : [];
      const volunteers = Array.isArray(data?.volunteers) ? data.volunteers : [];
      const fulfilledIds = requests.filter((row: any) => row.status === "fulfilled").map((row: any) => row.id);
      let fulfilledAtById = new Map<string, string>();
      if (fulfilledIds.length) {
        const { data: fulfilledRows, error: fulfilledError } = await supabase
          .from("requests")
          .select("id, fulfilled_at")
          .in("id", fulfilledIds);
        if (!fulfilledError) {
          fulfilledAtById = new Map((fulfilledRows ?? []).map((row: any): [string, string] => [row.id, row.fulfilled_at]));
        }
      }
      const fulfilledCutoff = Date.now() - 6 * 60 * 60 * 1000;
      const parsedVolunteers: Marker[] = volunteers
        .filter((x: any) => !isDemoSeed(x.volunteer_name) && hasCoordinates(x.lat, x.lng))
        .map((x: any) => ({
          id: x.assignment_id,
          kind: (["delivery", "pickup", "transport"].includes(x.assignment_type) ? "driver" : "volunteer") as Marker["kind"],
          title: x.volunteer_name ?? "Active volunteer",
          detail: `${x.public_ref} · ${x.state}`,
          lat: Number(x.lat),
          lng: Number(x.lng),
          updated: x.updated_at,
          to: `/assignments/${x.assignment_id}`,
        }));

      // The current mobile driver endpoint stores GPS in driver_latest_location,
      // while older map RPC data comes from volunteer_locations. Fill in active
      // assignment locations through the secured admin endpoint when the RPC
      // does not include that assignment yet.
      let driverFallbacks: Marker[] = [];
      const activeStates = ["accepted", "en_route_to_pickup", "picked_up", "en_route_to_destination"];
      const { data: assignments, error: assignmentsError } = await supabase
        .from("assignments")
        .select("id, request_id, assignment_type, state, volunteer_id, requests!inner(public_ref), volunteer:profiles!volunteer_id(full_name)")
        .in("state", activeStates)
        .not("volunteer_id", "is", null)
        .limit(300);

      if (!assignmentsError) {
        setActiveAssignmentCounts({
          volunteers: (assignments ?? []).filter((row: any) => !["delivery", "pickup", "transport"].includes(row.assignment_type)).length,
          drivers: (assignments ?? []).filter((row: any) => ["delivery", "pickup", "transport"].includes(row.assignment_type)).length,
        });
      }
      if (!assignmentsError && assignments?.length) {
        const alreadyLocated = new Set(parsedVolunteers.map((marker) => marker.id));
        const missing = assignments.filter((row: any) => !alreadyLocated.has(row.id));
        const volunteersToCheck = [...new Set(missing.map((row: any) => row.volunteer_id as string))];
        const locationResults = await Promise.all(volunteersToCheck.map(async (volunteerId) => {
          const result = await supabase.functions.invoke("get-driver-location", {
            body: { volunteer_id: volunteerId },
          });
          return result.error ? null : result.data?.data;
        }));
        const rowsById = new Map(missing.map((row: any) => [row.id, row]));
        const recentCutoff = Date.now() - 30 * 60 * 1000;
        driverFallbacks = locationResults.flatMap((location: any) => {
          const assignment = location?.assign_id ? rowsById.get(location.assign_id) as any : null;
          const point = location?.location;
          const timestamp = location?.updated_at;
          const lat = Number(point?.lat);
          const lng = Number(point?.lon ?? point?.lng);
          if (!assignment || !hasCoordinates(lat, lng) || !timestamp || Date.parse(timestamp) < recentCutoff) return [];
          const volunteer = Array.isArray(assignment.volunteer) ? assignment.volunteer[0] : assignment.volunteer;
          const request = Array.isArray(assignment.requests) ? assignment.requests[0] : assignment.requests;
          return [{
            id: assignment.id,
            kind: (["delivery", "pickup", "transport"].includes(assignment.assignment_type) ? "driver" : "volunteer") as Marker["kind"],
            title: volunteer?.full_name ?? "Active volunteer",
            detail: `${request?.public_ref ?? "Assignment"} · ${assignment.state}`,
            lat,
            lng,
            updated: timestamp,
            to: `/assignments/${assignment.id}`,
          }];
        });
      }
      const parsed: Marker[] = [
        ...(hub && hasCoordinates(hub.lat, hub.lng) && !/placeholder/i.test(`${hub.name ?? ''} ${hub.address_note ?? ''}`)
          ? [{ id: 'hub', kind: 'hub' as const, title: hub.name ?? 'Central inventory', detail: hub.address_note ?? 'Supply hub', lat: Number(hub.lat), lng: Number(hub.lng), updated: 'Configured hub' }]
          : []),
        ...requests
          .filter((x: any) => {
            if (isDemoSeed(x.requester_name) || !hasCoordinates(x.lat, x.lng)) return false;
            if (x.status !== "fulfilled") return true;
            const completedAt = fulfilledAtById.get(x.id) ?? x.updated_at ?? x.created_at;
            return Date.parse(completedAt) >= fulfilledCutoff;
          })
          .map((x: any) => {
            const assignmentSummary = Array.isArray(x.assignments) ? x.assignments[0] : x.assignments;
            const hasClaimedVolunteer = Number(assignmentSummary?.claimed ?? 0) > 0;
            const acceptedStatus = ['assigned', 'in_progress', 'partially_fulfilled', 'fulfilled'].includes(x.status);
            const sourceKind = x.kind === 'donation_offer' ? 'donation' : 'request';
            const kind: Marker['kind'] = x.status === 'fulfilled'
              ? 'fulfilled'
              : hasClaimedVolunteer || acceptedStatus
                ? 'accepted'
                : sourceKind === 'donation' ? 'pickup' : 'request';
            return {
              id: x.id,
              kind,
              sourceKind,
              title: x.public_ref,
              detail: `${x.requester_name} · ${x.district} · ${x.status}`,
              lat: Number(x.lat),
              lng: Number(x.lng),
              updated: x.updated_at ?? x.created_at,
              to: sourceKind === 'donation' ? `/donations/${x.id}` : `/requests/${x.id}`,
            };
          }),
        ...parsedVolunteers,
        ...driverFallbacks.filter((marker) => !parsedVolunteers.some((current) => current.id === marker.id)),
      ];
      setMarkers(parsed);
      setLive(true);
      setError("");
    };
    void load();
    const timer = window.setInterval(() => void load(), 15000);
    void hasSession().then((ok) => {
      if (ok)
        channel = supabase
          .channel("live-map-changes")
          .on(
            "postgres_changes",
            { event: "*", schema: "public", table: "volunteer_locations" },
            () => void load(),
          )
          .on(
            "postgres_changes",
            { event: "*", schema: "public", table: "assignments" },
            () => void load(),
          )
          .on(
            "postgres_changes",
            { event: "*", schema: "public", table: "requests" },
            () => void load(),
          )
          .subscribe();
    });
    return () => {
      active = false;
      window.clearInterval(timer);
      if (channel) supabase.removeChannel(channel);
    };
  }, []);

  const displayMarkers = markers.filter((marker) => inTab(marker, tab));
  const activeTab = tabs.find(([key]) => key === tab);
  const heading = tab === "all" ? "Live operations map" : activeTab?.[1] ?? "Live operations map";
  const liveSelected = selected
    ? (markers.find((m) => m.id === selected.id) ?? selected)
    : null;
  const side = liveSelected;
  const liveVolunteerMarkers = markers
    .filter((marker) => marker.kind === "driver" || marker.kind === "volunteer")
    .sort((a, b) => Date.parse(b.updated) - Date.parse(a.updated));
  const activityCenter: [number, number] | null = liveVolunteerMarkers.length
    ? [liveVolunteerMarkers[0].lat, liveVolunteerMarkers[0].lng]
    : markers.length
      ? [markers[0].lat, markers[0].lng]
      : null;
  const mapCenter = adminPosition
    ? [adminPosition.lat, adminPosition.lng] as [number, number]
    : activityCenter;
  const setLayer = (v: string) => {
    setSelected(null);
    setParams((p) => {
      if (v === "all") p.delete("layer");
      else p.set("layer", v);
      p.delete("view");
      return p;
    });
  };

  return (
    <div className="live-map-page">
      <header className="page__head">
        <div>
          <h1>{heading}</h1>
          <p className="crumbs">
            Sahayogi Nepal&nbsp; / &nbsp;Live Map&nbsp; / &nbsp;Live operations
          </p>
        </div>
        <div className="page__actions">
          <QuickAction />
        </div>
      </header>
      <nav className="map-tabs">
        {tabs.map(([key, label]) => (
          <button
            className={tab === key ? "is-active" : ""}
            key={key}
            onClick={() => setLayer(key)}
          >
            {label}
          </button>
        ))}
      </nav>
      <div className="map-layout">
        <section
          className="map-canvas"
          aria-label="OpenStreetMap operations map"
        >
          {mapCenter ? (
            <MapContainer
              key="operations-activity-map"
              center={mapCenter}
              zoom={13}
              minZoom={8}
              maxZoom={19}
              worldCopyJump
              scrollWheelZoom
            >
              <TileLayer
                attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'
                url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
              />
              <FitActivities
                markers={displayMarkers}
                focusMarkers={displayMarkers.filter((marker) => marker.kind === "driver" || marker.kind === "volunteer")}
                enabled={!adminPosition}
              />
              <FollowAdminLocation position={adminPosition} />
              <MapFocus marker={liveSelected} />
              {displayMarkers.map((m) => (
                <Marker
                  key={m.id}
                  position={[m.lat, m.lng]}
                  icon={pinIcon(m.kind)}
                  eventHandlers={{ click: () => setSelected(m) }}
                >
                  <Popup>
                    <strong>{m.title}</strong>
                    <br />
                    {m.detail}
                    <br />
                    {m.updated}
                    {m.to && <><br /><Link to={m.to}>Open record</Link></>}
                  </Popup>
                </Marker>
              ))}
            </MapContainer>
          ) : (
            <div className="map-location-prompt" role="status">
              {error || "No backend activity locations are available yet."}
            </div>
          )}
        </section>
        <aside className="map-side card">
          <h2 className="card__title">{side?.title ?? "Live activity"}</h2>
          {side ? (
            <>
              <p className="map-side-detail">
                {side.detail}
                <br />
                {side.updated}
              </p>
              {side.to && <Link to={side.to}>Open record</Link>}
            </>
          ) : (
            <div className="map-stats">
              <p>{markers.filter((m) => m.kind === "request").length} open requests</p>
              <p>{markers.filter((m) => m.kind === "accepted").length} requests or donations accepted by volunteers</p>
              <p>{activeAssignmentCounts.volunteers} active volunteers · {markers.filter((m) => m.kind === "volunteer").length} sharing recent location</p>
              <p>{activeAssignmentCounts.drivers} active drivers · {markers.filter((m) => m.kind === "driver").length} sharing recent location</p>
              <p>{markers.filter((m) => m.kind === "pickup").length} donation pickups</p>
              <p>{markers.filter((m) => m.kind === "fulfilled").length} recently fulfilled requests</p>
              <p>{markers.filter((m) => m.kind === "hub").length} central inventory locations</p>
              {!markers.length && <p>No live operations are currently available.</p>}
            </div>
          )}

          {!side && error && <p className="map-source-note" role="alert">{error}</p>}
          {!side && !error && <p className="map-source-note">{live ? "Live map data · refreshes every 15 seconds" : "Connecting to live map data…"}</p>}

          <h3>Map centering</h3>
          <p className="map-side-detail">
            {adminPosition && tracking
              ? "Following your live location. Your location is hidden from the map."
              : tracking
                ? "Requesting your live location to center the map. Your location will stay hidden from the map."
              : adminPosition
                ? "Live centering is paused. Your location is hidden; activity markers remain visible."
                : "Live centering is off. Activity markers remain visible."}
          </p>
          {geoError && <p className="map-source-note" role="alert">{geoError}</p>}
          <div className="map-me-actions">
            <button className="btn" onClick={tracking ? stopTracking : startTracking}>
              {tracking ? "Stop live centering" : "Center on my location"}
            </button>
          </div>

          <h3>Map legend</h3>
          <ul className="map-legend">
            {Object.entries(labels).filter(([key]) => displayMarkers.some((marker) => marker.kind === key)).map(([k, v]) => (
              <li key={k} className={`legend-${k}`}>
                <span />
                {v}
              </li>
            ))}
          </ul>
          <div className="map-privacy">
            <strong>Authorised operations view</strong>
            <p>
              Exact locations are restricted. Public maps show approximate
              district-level activity only.
            </p>
          </div>
        </aside>
      </div>
      {error && <p className="map-source-note">{error}</p>}
      {live && (
        <p className="map-source-note">Live, privacy-rounded activity.</p>
      )}
    </div>
  );
}
