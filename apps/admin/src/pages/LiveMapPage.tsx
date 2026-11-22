import { useEffect, useMemo, useRef, useState } from "react";
import { Link, useSearchParams } from "react-router-dom";
import {
  Circle,
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
  kind: "request" | "driver" | "hub" | "pickup" | "fulfilled" | "volunteer";
  title: string;
  detail: string;
  lat: number;
  lng: number;
  updated: string;
  to?: string;
};

type Me = { lat: number; lng: number; accuracy: number; at: number };


const tabs = [
  ["all", "All activities"],
  ["requests", "Open requests"],
  ["volunteers", "Active volunteers"],
  ["drivers", "Active drivers"],
  ["pickups", "Donation pickup requests"],
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
  pickup: "Donation pickup",
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
  const [selected, setSelected] = useState<Marker | null>(null);
  const [markers, setMarkers] = useState<Marker[]>([]),
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
      const parsed: Marker[] = [
        ...(hub ? [{ id: 'hub', kind: 'hub' as const, title: hub.name ?? 'Central inventory', detail: hub.address_note ?? 'Supply hub', lat: Number(hub.lat), lng: Number(hub.lng), updated: 'Configured hub' }] : []),
        ...requests.map((x: any) => ({ id: x.id, kind: (x.status === 'fulfilled' ? 'fulfilled' : x.kind === 'donation_offer' ? 'pickup' : 'request') as Marker['kind'], title: x.public_ref, detail: `${x.requester_name} · ${x.district} · ${x.status}`, lat: Number(x.lat), lng: Number(x.lng), updated: x.updated_at ?? x.created_at, to: x.kind === 'donation_offer' ? `/donations/${x.id}` : `/requests/${x.id}` })),
        ...volunteers.map((x: any) => ({ id: x.assignment_id, kind: (x.assignment_type === 'delivery' || x.assignment_type === 'pickup' ? 'driver' : 'volunteer') as Marker['kind'], title: x.volunteer_name ?? 'Active volunteer', detail: `${x.public_ref} · ${x.state}`, lat: Number(x.lat), lng: Number(x.lng), updated: x.updated_at, to: `/assignments/${x.assignment_id}` })),
      ].filter((m) => Number.isFinite(m.lat) && Number.isFinite(m.lng));
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
  const displayMarkers = layerMarkers;
  const activeTab = tabs.find(([key]) => key === tab);
  const heading = tab === "all" ? "Live operations map" : activeTab?.[1] ?? "Live operations map";
  const liveSelected = selected
    ? (markers.find((m) => m.id === selected.id) ?? selected)
    : null;
  const side = liveSelected;
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
                  {m.to && <><br /><Link to={m.to}>Open record</Link></>}
                </Popup>
              </Marker>
            ))}
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
              {side.to && <Link to={side.to}>Open record</Link>}
            </>
          ) : (
            <div className="map-stats">
              <p>{markers.filter((m) => m.kind === "request").length} open requests</p>
              <p>{markers.filter((m) => m.kind === "volunteer").length} active volunteers</p>
              <p>{markers.filter((m) => m.kind === "driver").length} active drivers</p>
              <p>{markers.filter((m) => m.kind === "hub").length} central inventory locations</p>
              {!markers.length && <p>No live locations are currently available.</p>}
            </div>
          )}

          {!side && error && <p className="map-source-note" role="alert">{error}</p>}
          {!side && !error && <p className="map-source-note">{live ? "Live map data · refreshes every 15 seconds" : "Connecting to live map data…"}</p>}

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
      {error && <p className="map-source-note">{error}</p>}
      {live && (
        <p className="map-source-note">Live, privacy-rounded activity.</p>
      )}
    </div>
  );
}
