import {
  Accessibility, AirVent, Armchair, Car, Circle, Coffee, Drum, Mic, MicVocal, Piano, Podcast, SlidersHorizontal, Square, TramFront, Video, Wifi, Cigarette,
  type LucideIcon,
} from "lucide-react";
import type { Facility } from "../lib/types";

export const FACILITY_ICONS: Record<Facility, LucideIcon> = {
  vocal_booth: MicVocal, live_room: Mic, control_room: SlidersHorizontal, isolation_booth: Square, drum_room: Drum, lounge: Armchair,
  kitchen: Coffee, wifi: Wifi, air_conditioning: AirVent, parking: Car, public_transport: TramFront, wheelchair_access: Accessibility,
  smoking_area: Cigarette, podcast_setup: Podcast, video_recording: Video, instruments_available: Piano,
};

export const facilityIcon = (f: string): LucideIcon => FACILITY_ICONS[f as Facility] ?? Circle;
