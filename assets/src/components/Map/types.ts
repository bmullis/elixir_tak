/** Pre-parsed marker data for map display */
export interface MapMarker {
  uid: string;
  lat: number;
  lon: number;
  callsign: string;
  remarks: string | null;
  stale: boolean;
}

/** Vertex coordinate pair */
export interface Vertex {
  lat: number;
  lon: number;
}

/** Pre-parsed shape data for map display */
export interface MapShape {
  uid: string;
  name: string | null;
  shape_type: string;
  vertices: Vertex[];
  stroke_color: string | null;
  fill_color: string | null;
  remarks: string | null;
  center: Vertex | null;
  radius: number | null;
  stale: boolean;
}

/** Pre-parsed route data for map display */
export interface MapRoute {
  uid: string;
  name: string | null;
  waypoints: Vertex[];
  waypoint_count: number;
  total_distance_m: number;
  stroke_color: string | null;
  remarks: string | null;
  stale: boolean;
}

/** Pre-parsed geofence data for map display */
export interface MapGeofence {
  uid: string;
  name: string | null;
  shape_type: string;
  vertices: Vertex[];
  stroke_color: string | null;
  fill_color: string | null;
  remarks: string | null;
  center: Vertex | null;
  radius: number | null;
  trigger: string | null;
  monitor_type: string | null;
  boundary_type: string | null;
  stale: boolean;
}
