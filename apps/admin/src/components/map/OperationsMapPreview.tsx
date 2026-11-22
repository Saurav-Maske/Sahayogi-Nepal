import { useEffect, useState } from "react";
import { Link } from "react-router-dom";
import { MapContainer, Marker, Popup, TileLayer, useMap } from "react-leaflet";
import L from "leaflet";
import { supabase } from "../../supabase";
import "../../styles/map-preview.css";
import "leaflet/dist/leaflet.css";

type MapMarker = {
  id: string;
  kind: "request" | "driver" | "hub" | "pickup" | "fulfilled" | "volunteer";
  title: string;
  detail: string;
  lat: number;
  lng: number;
  to?: string;
};

type Position = { lat: number; lng: number };

const isDemoSeed = (value?: string | null) =>
  /^demo(?:\s|$)/i.test(value?.trim() ?? "");

const markerIcon = (kind: MapMarker["kind"] | "me") => {
  const glyph = kind === "request" ? "R" : kind === "driver" ? "D" : kind === "hub" ? "▦" : kind === "pickup" ? "P" : kind === "fulfilled" ? "✓" : kind === "me" ? "" : "V";
  return L.divIcon({
    className: `leaflet-pin leaflet-pin--${kind}`,
    html: `<span>${glyph}</span>`,
    iconSize: kind === "me" ? [18, 18] : [28, 28],
    iconAnchor: kind === "me" ? [9, 9] : [14, 14],
  });
};

function FollowCenter({ center }: { center: Position }) {
  const map = useMap();
  useEffect(() => {
    map.setView([center.lat, center.lng], map.getZoom(), { animate: false });
  }, [center.lat, center.lng, map]);
  return null;
}

export default function OperationsMapPreview({
  requestId,
  followLiveLocation = false,
}: {
  requestId?: string;
  followLiveLocation?: boolean;
}) {
  const [markers, setMarkers] = useState<MapMarker[]>([]);
  const [requestPosition, setRequestPosition] = useState<Position | null>(null);
  const [livePosition, setLivePosition] = useState<Position | null>(null);
  const [error, setError] = useState("");
  const [mapError, setMapError] = useState("");

  useEffect(() => {
    let active = true;
    void supabase.rpc("admin_map_markers").then(({ data, error: rpcError }) => {
      if (!active) return;
      if (rpcError) {
        setError(rpcError.message || "Live map activity is unavailable.");
        return;
      }
      const hub = data?.hub;
      const requests = Array.isArray(data?.requests) ? data.requests : [];
      const volunteers = Array.isArray(data?.volunteers) ? data.volunteers : [];
      const selected = requestId ? requests.find((row: any) => row.id === requestId) : null;
      if (selected && !isDemoSeed(selected.requester_name) && Number.isFinite(Number(selected.lat)) && Number.isFinite(Number(selected.lng))) {
        setRequestPosition({ lat: Number(selected.lat), lng: Number(selected.lng) });
      }
      const parsed: MapMarker[] = [
        ...(hub && !/placeholder/i.test(`${hub.name ?? ""} ${hub.address_note ?? ""}`)
          ? [{ id: "hub", kind: "hub" as const, title: hub.name ?? "Central inventory", detail: hub.address_note ?? "Supply hub", lat: Number(hub.lat), lng: Number(hub.lng) }]
          : []),
        ...requests
          .filter((row: any) => !isDemoSeed(row.requester_name))
          .map((row: any) => ({
            id: row.id,
            kind: (row.id === requestId ? "request" : row.status === "fulfilled" ? "fulfilled" : row.kind === "donation_offer" ? "pickup" : "request") as MapMarker["kind"],
            title: row.public_ref ?? "Request",
            detail: `${row.requester_name ?? "Requester"} · ${row.district ?? ""} · ${row.status ?? ""}`,
            lat: Number(row.lat), lng: Number(row.lng),
            to: `/requests/${row.id}`,
          })),
        ...volunteers
          .filter((row: any) => !isDemoSeed(row.volunteer_name))
          .map((row: any) => ({
            id: row.assignment_id,
            kind: (row.assignment_type === "delivery" || row.assignment_type === "pickup" ? "driver" : "volunteer") as MapMarker["kind"],
            title: row.volunteer_name ?? "Active volunteer",
            detail: `${row.public_ref ?? ""} · ${row.state ?? ""}`,
            lat: Number(row.lat), lng: Number(row.lng),
            to: `/assignments/${row.assignment_id}`,
          })),
      ].filter((marker) => Number.isFinite(marker.lat) && Number.isFinite(marker.lng));
      setMarkers(parsed);
      setError("");
    });
    return () => { active = false; };
  }, [requestId]);

  useEffect(() => {
    if (!followLiveLocation) return;
    if (!navigator.geolocation) {
      setMapError("This browser does not support live location.");
      return;
    }
    const watchId = navigator.geolocation.watchPosition(
      (position) => {
        setLivePosition({ lat: position.coords.latitude, lng: position.coords.longitude });
        setMapError("");
      },
      (geoError) => {
        setMapError(geoError.code === geoError.PERMISSION_DENIED
          ? "Allow location access to show this map around your live position."
          : "Waiting for your live location. Check your device location settings." );
      },
      { enableHighAccuracy: true, maximumAge: 5000, timeout: 20000 },
    );
    return () => navigator.geolocation.clearWatch(watchId);
  }, [followLiveLocation]);

  const center = followLiveLocation ? livePosition : requestPosition;
  if (!center) {
    return <div className="operations-map-preview__message" role="status">
      {mapError || error || (followLiveLocation ? "Getting your live location…" : "This request has no current map location.")}
    </div>;
  }

  return <div className="operations-map-preview" aria-label="OpenStreetMap live operations preview">
    <MapContainer center={[center.lat, center.lng]} zoom={13} minZoom={8} maxZoom={19} scrollWheelZoom>
      <TileLayer
        attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'
        url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
      />
      <FollowCenter center={center} />
      {followLiveLocation && <Marker position={[center.lat, center.lng]} icon={markerIcon("me")} zIndexOffset={1000}><Popup>Your live location</Popup></Marker>}
      {markers.map((marker) => <Marker key={`${marker.kind}-${marker.id}`} position={[marker.lat, marker.lng]} icon={markerIcon(marker.kind)}>
        <Popup><strong>{marker.title}</strong><br />{marker.detail}{marker.to && <><br /><Link to={marker.to}>Open record</Link></>}</Popup>
      </Marker>)}
    </MapContainer>
    {error && <span className="operations-map-preview__note" role="status">Showing map without activity markers: {error}</span>}
  </div>;
}
