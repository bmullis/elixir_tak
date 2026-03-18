import { useEffect, useRef } from "react";
import * as Cesium from "cesium";
import "cesium/Build/Cesium/Widgets/widgets.css";

// Set Cesium base URL for Workers/Assets (defined in vite.config.ts)
declare const CESIUM_BASE_URL: string;
// eslint-disable-next-line @typescript-eslint/no-explicit-any
(window as any).CESIUM_BASE_URL = CESIUM_BASE_URL;
import { useDashboardStore, type BasemapStyle } from "../../store";
import { classifyEntity } from "../../utils/entityClassification";
import {
  syncPositions,
  syncMarkers,
  syncShapes,
  syncRoutes,
  syncGeofences,
  syncTracks,
  syncEmergencyRings,
  flashGeofenceAlerts,
  syncVideoFeeds,
} from "./entitySync";
import { applyLayerFilters } from "./layerFilters";
import { handleDrawingClick, syncDrawingPreview } from "./drawingHandlers";
import styles from "./CesiumMap.module.css";

/** Create an imagery provider for the given basemap style */
function createImageryProvider(style: BasemapStyle): Cesium.ImageryProvider {
  switch (style) {
    case "satellite":
      return new Cesium.UrlTemplateImageryProvider({
        url: "https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}",
        credit: new Cesium.Credit("Esri, Maxar, Earthstar Geographics"),
        maximumLevel: 19,
      });
    case "hybrid":
      // Satellite base -- label overlay added separately in applyBasemap
      return new Cesium.UrlTemplateImageryProvider({
        url: "https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}",
        credit: new Cesium.Credit("Esri, Maxar, Earthstar Geographics"),
        maximumLevel: 19,
      });
    case "dark":
    default:
      return new Cesium.UrlTemplateImageryProvider({
        url: "https://basemaps.cartocdn.com/dark_all/{z}/{x}/{y}@2x.png",
        credit: new Cesium.Credit("CartoDB"),
        maximumLevel: 18,
      });
  }
}

/** Swap all imagery layers on the viewer to match the selected basemap */
function applyBasemap(viewer: Cesium.Viewer, style: BasemapStyle) {
  const layers = viewer.imageryLayers;
  layers.removeAll();
  layers.addImageryProvider(createImageryProvider(style));

  // Hybrid: add translucent label overlay on top of satellite
  if (style === "hybrid") {
    layers.addImageryProvider(
      new Cesium.UrlTemplateImageryProvider({
        url: "https://basemaps.cartocdn.com/dark_only_labels/{z}/{x}/{y}@2x.png",
        credit: new Cesium.Credit("CartoDB"),
        maximumLevel: 18,
      })
    );
  }

  // Adjust globe base color for satellite vs dark
  if (style === "dark") {
    viewer.scene.globe.baseColor = Cesium.Color.fromCssColorString("#18181b");
  } else {
    viewer.scene.globe.baseColor = Cesium.Color.fromCssColorString("#0a1628");
  }
}

/**
 * CesiumJS 3D globe with SA entities and COP overlays.
 * No Cesium Ion, no terrain. CartoDB dark basemap.
 * All entities use the Entity API (no DOM markers).
 */
export default function CesiumMap() {
  const containerRef = useRef<HTMLDivElement>(null);
  const viewerRef = useRef<Cesium.Viewer | null>(null);
  const entityTracker = useRef<Set<string>>(new Set());

  // Initialize viewer once
  useEffect(() => {
    if (!containerRef.current) return;

    // Disable Ion
    Cesium.Ion.defaultAccessToken = undefined as unknown as string;

    const viewer = new Cesium.Viewer(containerRef.current, {
      animation: false,
      timeline: false,
      homeButton: false,
      sceneModePicker: false,
      baseLayerPicker: false,
      navigationHelpButton: false,
      fullscreenButton: false,
      geocoder: false,
      infoBox: false,
      selectionIndicator: false,
      sceneMode: Cesium.SceneMode.SCENE3D,
      baseLayer: new Cesium.ImageryLayer(
        new Cesium.UrlTemplateImageryProvider({
          url: "https://basemaps.cartocdn.com/dark_all/{z}/{x}/{y}@2x.png",
          credit: new Cesium.Credit("CartoDB"),
          maximumLevel: 18,
        })
      ),
    });

    // Dark styling
    viewer.scene.backgroundColor = Cesium.Color.fromCssColorString("#09090b");
    viewer.scene.globe.baseColor = Cesium.Color.fromCssColorString("#18181b");

    // Hide credit container
    const creditContainer = viewer.cesiumWidget.creditContainer as HTMLElement;
    creditContainer.style.display = "none";

    // Disable atmosphere/sky
    viewer.scene.skyBox = undefined as unknown as Cesium.SkyBox;
    viewer.scene.sun = undefined as unknown as Cesium.Sun;
    viewer.scene.moon = undefined as unknown as Cesium.Moon;
    viewer.scene.skyAtmosphere = undefined as unknown as Cesium.SkyAtmosphere;

    // Initial camera: Scottsdale, AZ
    viewer.camera.setView({
      destination: Cesium.Cartesian3.fromDegrees(-111.93, 33.49, 50000),
    });

    // Entity click handler (also handles drawing mode clicks)
    const handler = new Cesium.ScreenSpaceEventHandler(viewer.scene.canvas);
    handler.setInputAction((click: { position: Cesium.Cartesian2 }) => {
      const store = useDashboardStore.getState();
      const drawing = store.drawing;

      // If drawing mode is active, handle drawing clicks
      if (drawing.mode) {
        const ray = viewer.camera.getPickRay(click.position);
        if (!ray) return;
        const cartesian = viewer.scene.globe.pick(ray, viewer.scene);
        if (!cartesian) return;
        const carto = Cesium.Cartographic.fromCartesian(cartesian);
        const lat = Cesium.Math.toDegrees(carto.latitude);
        const lon = Cesium.Math.toDegrees(carto.longitude);

        handleDrawingClick(store, drawing, lat, lon);
        return;
      }

      const picked = viewer.scene.pick(click.position);
      if (Cesium.defined(picked) && picked.id && picked.id.id) {
        const cesiumId: string = picked.id.id;
        const classified = classifyEntity(cesiumId);
        if (classified) {
          store.selectEntity({
            uid: classified.uid,
            entityType: classified.entityType,
            cesiumId,
          });
        }
      } else {
        // Clicked empty space -- deselect
        store.selectEntity(null);
      }
    }, Cesium.ScreenSpaceEventType.LEFT_CLICK);

    // Mouse move handler for circle radius preview
    handler.setInputAction((move: { endPosition: Cesium.Cartesian2 }) => {
      const drawing = useDashboardStore.getState().drawing;
      if (drawing.mode !== "circle" || !drawing.center) return;

      const ray = viewer.camera.getPickRay(move.endPosition);
      if (!ray) return;
      const cartesian = viewer.scene.globe.pick(ray, viewer.scene);
      if (!cartesian) return;

      const centerCart = Cesium.Cartesian3.fromDegrees(drawing.center.lon, drawing.center.lat);
      const radius = Cesium.Cartesian3.distance(centerCart, cartesian);
      syncDrawingPreview(viewer, { ...drawing, radius });
    }, Cesium.ScreenSpaceEventType.MOUSE_MOVE);

    viewerRef.current = viewer;

    // Listen for flyTo events from EmergencyBanner
    const handleFlyTo = (e: Event) => {
      const { lon, lat, height } = (e as CustomEvent).detail;
      viewer.camera.flyTo({
        destination: Cesium.Cartesian3.fromDegrees(lon, lat, height || 5000),
        duration: 1.5,
      });
    };
    window.addEventListener("tak:flyTo", handleFlyTo);

    return () => {
      window.removeEventListener("tak:flyTo", handleFlyTo);
      handler.destroy();
      viewer.destroy();
      viewerRef.current = null;
      entityTracker.current.clear();
    };
  }, []);

  // Subscribe to store changes and sync entities
  useEffect(() => {
    const unsub = useDashboardStore.subscribe((state, prevState) => {
      const viewer = viewerRef.current;
      if (!viewer || viewer.isDestroyed()) return;

      if (state.positions !== prevState.positions) {
        syncPositions(viewer, state.positions, entityTracker.current);
      }
      if (state.parsedMarkers !== prevState.parsedMarkers) {
        syncMarkers(viewer, state.parsedMarkers);
      }
      if (state.parsedShapes !== prevState.parsedShapes) {
        syncShapes(viewer, state.parsedShapes);
      }
      if (state.parsedRoutes !== prevState.parsedRoutes) {
        syncRoutes(viewer, state.parsedRoutes);
      }
      if (state.parsedGeofences !== prevState.parsedGeofences) {
        syncGeofences(viewer, state.parsedGeofences);
      }
      if (
        state.tracks !== prevState.tracks ||
        state.trackVisible !== prevState.trackVisible
      ) {
        syncTracks(viewer, state.tracks, state.trackVisible);
      }
      if (state.emergencies !== prevState.emergencies) {
        syncEmergencyRings(viewer, state.emergencies);
      }
      if (state.geofenceAlerts !== prevState.geofenceAlerts) {
        flashGeofenceAlerts(viewer, state.geofenceAlerts, state.parsedGeofences);
      }
      if (state.videoStreams !== prevState.videoStreams) {
        syncVideoFeeds(viewer, state.videoStreams);
      }
      if (state.drawing !== prevState.drawing) {
        syncDrawingPreview(viewer, state.drawing);
      }

      // Re-apply layer filters after any sync
      applyLayerFilters(viewer, state.layerState);
    });

    // Initial sync from snapshot (may already be loaded)
    const viewer = viewerRef.current;
    if (viewer && !viewer.isDestroyed()) {
      const state = useDashboardStore.getState();
      syncPositions(viewer, state.positions, entityTracker.current);
      syncMarkers(viewer, state.parsedMarkers);
      syncShapes(viewer, state.parsedShapes);
      syncRoutes(viewer, state.parsedRoutes);
      syncGeofences(viewer, state.parsedGeofences);
      syncTracks(viewer, state.tracks, state.trackVisible);
      syncEmergencyRings(viewer, state.emergencies);
      syncVideoFeeds(viewer, state.videoStreams);
      applyLayerFilters(viewer, state.layerState);
    }

    return unsub;
  }, []);

  // Stale entity cleanup every 30s
  useEffect(() => {
    const interval = setInterval(() => {
      const viewer = viewerRef.current;
      if (!viewer || viewer.isDestroyed()) return;

      const positions = useDashboardStore.getState().positions;
      const now = Date.now();

      for (const [uid, event] of positions) {
        if (event.stale) {
          const staleTime = new Date(event.stale).getTime();
          if (staleTime < now) {
            viewer.entities.removeById(uid);
            entityTracker.current.delete(uid);
          }
        }
      }
    }, 30_000);

    return () => clearInterval(interval);
  }, []);

  // Apply layer filters whenever layerState changes
  useEffect(() => {
    const unsub = useDashboardStore.subscribe((state, prevState) => {
      if (state.layerState !== prevState.layerState) {
        const viewer = viewerRef.current;
        if (viewer && !viewer.isDestroyed()) {
          applyLayerFilters(viewer, state.layerState);
        }
      }
    });

    // Apply on mount
    const viewer = viewerRef.current;
    if (viewer && !viewer.isDestroyed()) {
      applyLayerFilters(viewer, useDashboardStore.getState().layerState);
    }

    return unsub;
  }, []);

  // Switch basemap imagery when basemap preference changes
  useEffect(() => {
    const unsub = useDashboardStore.subscribe((state, prevState) => {
      if (state.basemap !== prevState.basemap) {
        const viewer = viewerRef.current;
        if (!viewer || viewer.isDestroyed()) return;
        applyBasemap(viewer, state.basemap);
      }
    });

    // Apply on mount (handles persisted non-default selection)
    const viewer = viewerRef.current;
    const basemap = useDashboardStore.getState().basemap;
    if (viewer && !viewer.isDestroyed() && basemap !== "dark") {
      applyBasemap(viewer, basemap);
    }

    return unsub;
  }, []);

  return (
    <div className={styles.container}>
      <div ref={containerRef} className={styles.viewer} />
    </div>
  );
}
