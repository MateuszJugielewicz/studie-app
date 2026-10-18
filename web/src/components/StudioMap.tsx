import { useEffect, useMemo } from "react";
import L from "leaflet";
import { MapContainer, Marker, TileLayer, useMap } from "react-leaflet";
import type { GeoPoint } from "../lib/core";

export interface MapPin { id: string; point: GeoPoint; label: string }

function Fit({ pins, center }: { pins: MapPin[]; center: GeoPoint }) {
  const map = useMap();
  useEffect(() => {
    if (pins.length > 1) map.fitBounds(L.latLngBounds(pins.map((p) => [p.point.latitude, p.point.longitude])), { padding: [40, 40], maxZoom: 14 });
    else map.setView([pins[0]?.point.latitude ?? center.latitude, pins[0]?.point.longitude ?? center.longitude], pins.length ? 15 : 11);
  }, [map, pins, center]);
  return null;
}

/** OpenStreetMap with price markers (no API key needed). */
export function StudioMap({ pins, center, height = 480, onSelect, interactive = true }: {
  pins: MapPin[]; center: GeoPoint; height?: number | string; onSelect?: (id: string) => void; interactive?: boolean;
}) {
  const icons = useMemo(() => new Map(pins.map((p) => [p.id, L.divIcon({ className: "", html: `<span class="map-pin">${p.label.replace(/</g, "&lt;")}</span>`, iconSize: [0, 0] })])), [pins]);
  return (
    <MapContainer center={[center.latitude, center.longitude]} zoom={12} className="map" style={{ height }}
      scrollWheelZoom={interactive} dragging={interactive} zoomControl={interactive} doubleClickZoom={interactive} touchZoom={interactive}>
      <TileLayer attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>' url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png" />
      {pins.map((p) => (
        <Marker key={p.id} position={[p.point.latitude, p.point.longitude]} icon={icons.get(p.id)!} eventHandlers={{ click: () => onSelect?.(p.id) }} />
      ))}
      <Fit pins={pins} center={center} />
    </MapContainer>
  );
}
