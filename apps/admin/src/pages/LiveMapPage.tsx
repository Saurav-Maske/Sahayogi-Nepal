import { useEffect, useMemo, useRef, useState } from "react";
import { useSearchParams } from "react-router-dom";
import {
  Circle,
  MapContainer,
  Marker,
  Polyline,
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
  kind: "request" | "driver" | "hub" | "pickup" | "fulfilled" | "volunteer";
  title: string;
  detail: string;
  lat: number;
  lng: number;
  updated: string;
  to?: string;
};

type Me = { lat: number; lng: number; accuracy: number; at: number };

const SAMPLE: Marker[] = [
  {
    id: "req1042",
    kind: "request",
    title: "REQ-1042",
    detail: "Open food assistance · Kirtipur",
    lat: 27.675,
    lng: 85.29,
    updated: "2 min ago",
    to: "/requests",
  },
  {
    id: "driver0302",
    kind: "driver",
    title: "Ramesh Gurung",
    detail: "ASG-0302 · Active driver · En route to requester",
    lat: 27.697,
    lng: 85.318,
    updated: "Updated 2 min ago",
    to: "/assignments/demo-asg-0302",
  },
  {
    id: "hub",
    kind: "hub",
    title: "Central inventory",
    detail: "Teku · Main supply hub",
    lat: 27.701,
    lng: 85.33,
    updated: "Current location",
  },
  {
    id: "pickup0284",
    kind: "pickup",
    title: "Pickup completed",
    detail: "DON-0284 · 45 kg rice collected",
    lat: 27.72,
    lng: 85.31,
    updated: "18 Jun · 09:35",
    to: "/donations/demo-don-284",
  },
  {
    id: "done1038",
    kind: "fulfilled",
    title: "Request fulfilled",
    detail: "REQ-1038 · Delivered in Kirtipur",
    lat: 27.665,
    lng: 85.337,
    updated: "18 Jun · 08:40",
    to: "/requests",
  },
  {
    id: "volunteer",
    kind: "volunteer",
    title: "Active volunteer",
    detail: "Volunteer location rounded for privacy",
    lat: 27.705,
    lng: 85.285,
    updated: "Updated 4 min ago",
    to: "/volunteers",
  },
];

const tabs = [
  ["all", "All activities"],
  ["requests", "Open requests"],
  ["volunteers", "Active volunteers"],
  ["drivers", "Active drivers"],
  ["pickups", "Pickups · 6h"],
  ["fulfilled", "Fulfilled · 12h"],
];

const inTab = (m: Marker, t: string) =>
  t === "all" ||
  (t === "requests" && m.kind === "request") ||
  (t === "volunteers" && m.kind === "volunteer") ||
  (t === "drivers" && m.kind === "driver") ||
  (t === "pickups" && m.kind === "pickup") ||
  (t === "fulfilled" && m.kind === "fulfilled");

const labels: Record<string, string> = {
  request: "Open request",
  driver: "Active driver",
  hub: "Central inventory",
  pickup: "Recent pickup",
  fulfilled: "Fulfilled request",
  volunteer: "Active volunteer",
  me: "Your location",
};

const pinIcon = (kind: string) =>
  L.divIcon({
    className: `leaflet-pin leaflet-pin--${kind}`,
    html: `<span>${kind === "request" ? "R" : kind === "driver" ? "D" : kind === "hub" ? "▦" : kind === "pickup" ? "P" : kind === "fulfilled" ? "✓" : "V"}</span>`,
    iconSize: [28, 28],
    iconAnchor: [14, 14],
  });

const youIcon = L.divIcon({
  className: "leaflet-pin leaflet-pin--me",
  html: "<span></span>",
  iconSize: [18, 18],
  iconAnchor: [9, 9],
});

function MapFocus({ marker }: { marker: Marker | null }) {
  const map = useMap();
  useEffect(() => {
    if (marker) map.flyTo([marker.lat, marker.lng], 14, { duration: 0.6 });
  }, [map, marker]);
  return null;
}

function FlyToMe({ me, nonce }: { me: Me | null; nonce: number }) {
  const map = useMap();
  useEffect(() => {
    if (me && nonce > 0) map.flyTo([me.lat, me.lng], 15, { duration: 0.6 });
    // only fly when nonce changes, not on every GPS update
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [nonce, map]);
  return null;
}

export default function LiveMapPage() {
  const [params, setParams] = useSearchParams();
  const tab = params.get("layer") ?? "all";
  const mode = params.get("view") ?? "";
  const [selected, setSelected] = useState<Marker | null>(null);
  const [markers, setMarkers] = useState(SAMPLE),
    [live, setLive] = useState(false),
    [error, setError] = useState("");

  // ---- my live location ----
  const [me, setMe] = useState<Me | null>(null);
  const [tracking, setTracking] = useState(false);
  const [geoError, setGeoError] = useState("");
  const [meNonce, setMeNonce] = useState(0);
  const watchId = useRef<number | null>(null);
  const gotFirstFix = useRef(false);

  const stopTracking = () => {
    if (watchId.current !== null)
      navigator.geolocation.clearWatch(watchId.current);
    watchId.current = null;
    gotFirstFix.current = false;
    setTracking(false);
    setMe(null);
  };

  const startTracking = () => {
    if (!("geolocation" in navigator)) {
      setGeoError("This browser doesn't support location.");
      return;
    }
    if (watchId.current !== null) return;
    setGeoError("");
    setTracking(true);
    watchId.current = navigator.geolocation.watchPosition(
      (pos) => {
        setMe({
          lat: pos.coords.latitude,
          lng: pos.coords.longitude,
          accuracy: pos.coords.accuracy,
          at: pos.timestamp,
        });
        if (!gotFirstFix.current) {
          gotFirstFix.current = true;
          setMeNonce((n) => n + 1); // fly to the user on the first fix
        }
      },
      (err) => {
        if (err.code === err.PERMISSION_DENIED) {
          setGeoError(
            "Location is blocked. Allow it in your browser's site settings, then tap Enable.",
          );
          stopTracking();
        } else if (err.code === err.POSITION_UNAVAILABLE) {
          setGeoError("Your location is unavailable right now.");
        } else {
          setGeoError("Getting your location is taking too long. Still trying…");
        }
      },
      { enableHighAccuracy: true, maximumAge: 5000, timeout: 20000 },
    );
  };

  useEffect(() => {
    startTracking(); // asks for permission on load
    return () => {
      if (watchId.current !== null)
        navigator.geolocation.clearWatch(watchId.current);
      watchId.current = null; // keeps React StrictMode's double-run working
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // ---- admin map data ----
  useEffect(() => {
    let active = true;
    let channel: any;
    const load = async () => {
      if (!(await hasSession())) return;
      const { data, error: e } = await supabase.rpc("admin_map_markers");
      if (!active) return;
      if (e) {
        setError(
          "Live map data is unavailable. Apply the admin_map_markers migration.",
        );
        return;
      }
      const rows = Array.isArray(data) ? data : [];
      const parsed: Marker[] = rows
        .map((x: any, i: number) => ({
          id: String(x.id ?? i),
          kind: (x.kind ?? x.type ?? "request") as Marker["kind"],
          title: x.title ?? x.public_ref ?? x.name ?? "Map activity",
          detail: x.detail ?? x.status ?? "",
          lat: Number(x.lat ?? x.latitude),
          lng: Number(x.lng ?? x.longitude),
          updated: x.updated_at ?? "Recently",
          to:
            x.kind === "driver"
              ? "/assignments"
              : x.kind === "request"
                ? "/requests"
                : undefined,
        }))
        .filter((m) => Number.isFinite(m.lat) && Number.isFinite(m.lng));
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

  const layerMarkers = useMemo(
    () => markers.filter((m) => inTab(m, tab)),
    [markers, tab],
  );
  const displayMarkers =
    mode === "pickup-expired" || mode === "fulfilled-expired"
      ? []
      : layerMarkers;
  const heading =
    mode === "driver"
      ? "Driver route · Ramesh Gurung"
      : mode === "pickup"
        ? "Recent pickups · Last 6 hours"
        : mode === "fulfilled"
          ? "Fulfilled requests · Last 12 hours"
          : mode === "pickup-expired"
            ? "Pickup layer · Expired at 15:36"
            : mode === "fulfilled-expired"
              ? "Fulfillment layer · Expired at 20:41"
              : "Live operations map";
  const liveSelected = selected
    ? (markers.find((m) => m.id === selected.id) ?? selected)
    : null;
  const side =
    liveSelected ??
    (mode === "driver"
      ? (markers.find((m) => m.kind === "driver") ?? null)
      : mode === "pickup"
        ? SAMPLE[3]
        : mode === "fulfilled"
          ? SAMPLE[4]
          : null);
  const setLayer = (v: string) => {
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
            Sahayogi Nepal&nbsp; / &nbsp;Live Map&nbsp; / &nbsp;Kathmandu
            district
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
          <MapContainer center={[27.7172, 85.324]} zoom={12} scrollWheelZoom>
            <TileLayer
              attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'
              url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
            />
            <MapFocus marker={liveSelected} />
            <FlyToMe me={me} nonce={meNonce} />
            {me && (
              <>
                <Circle
                  center={[me.lat, me.lng]}
                  radius={me.accuracy}
                  pathOptions={{
                    color: "#3686b7",
                    weight: 1,
                    fillOpacity: 0.12,
                  }}
                />
                <Marker
                  position={[me.lat, me.lng]}
                  icon={youIcon}
                  zIndexOffset={1000}
                >
                  <Popup>
                    <strong>You are here</strong>
                    <br />
                    Accuracy ±{Math.round(me.accuracy)} m
                  </Popup>
                </Marker>
              </>
            )}
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
                </Popup>
              </Marker>
            ))}
            {mode === "driver" && (
              <Polyline
                positions={displayMarkers
                  .filter(
                    (m) =>
                      m.kind === "hub" ||
                      m.kind === "driver" ||
                      m.kind === "request",
                  )
                  .map((m) => [m.lat, m.lng] as [number, number])}
                pathOptions={{ color: "#24728a", weight: 4 }}
              />
            )}
          </MapContainer>
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
              {mode === "driver" && (
                <p className="driver-meta">
                  ASG-0302 · Active driver
                  <br />
                  Current: Teku, Kathmandu
                  <br />
                  Destination: Kirtipur
                  <br />
                  Route: Inventory → Request
                  <br />
                  4.8 km · ETA 18 min
                  <br />
                  Progress: Delivery in progress
                </p>
              )}
              {mode === "pickup" && (
                <p className="driver-meta">
                  DON-0284 · 18 Jun, 09:35
                  <br />
                  45 kg rice collected
                  <br />
                  Expires from layer at 15:35
                </p>
              )}
              {mode === "fulfilled" && (
                <p className="driver-meta">
                  REQ-1038 · 18 Jun, 08:40
                  <br />
                  Delivery and quantity confirmed
                  <br />
                  Expires from layer at 20:40
                </p>
              )}
            </>
          ) : (
            <div className="map-stats">
              <p>48 open requests</p>
              <p>124 active volunteers</p>
              <p>8 drivers en route</p>
              <p>1 central inventory location</p>
            </div>
          )}

          <h3>My location</h3>
          <p className="map-side-detail">
            {me ? (
              <>
                Live · ±{Math.round(me.accuracy)} m
                <br />
                {me.lat.toFixed(5)}, {me.lng.toFixed(5)}
              </>
            ) : tracking ? (
              "Waiting for GPS…"
            ) : (
              "Live location is off"
            )}
          </p>
          {geoError && (
            <p className="map-source-note" style={{ color: "var(--bad)" }}>
              {geoError}
            </p>
          )}
          <div className="map-me-actions">
            <button
              className="btn"
              onClick={tracking ? stopTracking : startTracking}
            >
              {tracking ? "Stop tracking" : "Enable live location"}
            </button>
            {me && (
              <button className="btn" onClick={() => setMeNonce((n) => n + 1)}>
                Center on me
              </button>
            )}
          </div>

          <h3>Map legend</h3>
          <ul className="map-legend">
            {Object.entries(labels).map(([k, v]) => (
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
      {mode.endsWith("expired") && (
        <button
          className="btn map-expired-action"
          onClick={() => {
            setSelected(null);
            setParams({});
          }}
        >
          Back to current time
        </button>
      )}
      {mode === "pickup" && (
        <button
          className="btn map-expired-action"
          onClick={() => setParams({ view: "pickup-expired" })}
        >
          Preview 15:36 · marker expired
        </button>
      )}
      {mode === "fulfilled" && (
        <button
          className="btn map-exyypired-action"
          onClick={() => setParams({ view: "fulfilled-expired" })}
        >
          Preview 20:41 · marker expired
        </button>
      )}
      {error && <p className="map-source-note">{error}</p>}
      {live && (
        <p className="map-source-note">Live, privacy-rounded activity.</p>
      )}
    </div>
  );
}