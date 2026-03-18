import { useEffect, useRef } from "react";
import { useDashboardStore } from "../../store";
import type { EmergencyAlert, GeofenceAlert } from "../../types";
import { formatCoords, formatTime } from "../../utils/formatting";
import styles from "./EmergencyBanner.module.css";

/** Request notification permission on first emergency */
let notifPermissionRequested = false;

function requestNotifPermission() {
  if (notifPermissionRequested) return;
  notifPermissionRequested = true;
  if ("Notification" in window && Notification.permission === "default") {
    Notification.requestPermission();
  }
}

function showNotification(title: string, body: string) {
  if ("Notification" in window && Notification.permission === "granted") {
    new Notification(title, {
      body,
      icon: "/favicon.ico",
      tag: "elixirtak-emergency",
    } as NotificationOptions);
  }
}


/** Dispatch a custom event that CesiumMap listens for to fly to a location */
function flyToEmergency(alert: EmergencyAlert) {
  if (alert.lat != null && alert.lon != null) {
    window.dispatchEvent(
      new CustomEvent("tak:flyTo", {
        detail: { lon: alert.lon, lat: alert.lat, height: 5000 },
      })
    );
  }
}

export default function EmergencyBanner() {
  const emergencies = useDashboardStore((s) => s.emergencies);
  const geofenceAlerts = useDashboardStore((s) => s.geofenceAlerts);
  const prevEmergencyCount = useRef(0);

  // Browser notification on new emergency
  useEffect(() => {
    if (emergencies.size > prevEmergencyCount.current) {
      requestNotifPermission();
      // Find the newest emergency (last added)
      const alerts = Array.from(emergencies.values());
      const newest = alerts[alerts.length - 1];
      if (newest) {
        showNotification(
          `EMERGENCY: ${newest.callsign}`,
          `${newest.emergency_type}${newest.message ? " - " + newest.message : ""}`
        );
      }
    }
    prevEmergencyCount.current = emergencies.size;
  }, [emergencies]);

  // Auto-expire geofence alerts after 10s
  const addGeofenceAlert = useDashboardStore((s) => s.addGeofenceAlert);
  void addGeofenceAlert; // referenced for reactivity only

  const hasEmergencies = emergencies.size > 0;
  const hasGeofenceAlerts = geofenceAlerts.length > 0;

  if (!hasEmergencies && !hasGeofenceAlerts) return null;

  const emergencyList = Array.from(emergencies.values());

  return (
    <>
      {hasEmergencies && (
        <div className={styles.banner} role="alert">
          {emergencyList.map((alert) => (
            <EmergencyRow key={alert.uid} alert={alert} />
          ))}
        </div>
      )}
      {hasGeofenceAlerts && (
        <div className={styles.geofenceBanner} role="status">
          {geofenceAlerts.slice(0, 3).map((alert, i) => (
            <GeofenceRow key={`${alert.uid}-${i}`} alert={alert} />
          ))}
        </div>
      )}
    </>
  );
}

function EmergencyRow({ alert }: { alert: EmergencyAlert }) {
  return (
    <div className={styles.alert}>
      <div className={styles.alertLeft}>
        <div className={styles.pulsingDot} />
        <span className={styles.label}>EMERGENCY</span>
        <span className={styles.callsign}>{alert.callsign}</span>
        <span className={styles.type}>{alert.emergency_type}</span>
        {alert.message && (
          <span className={styles.message}>{alert.message}</span>
        )}
      </div>
      <div className={styles.alertRight}>
        <span className={styles.coords}>
          {formatCoords(alert.lat, alert.lon)}
        </span>
        <span className={styles.time}>{formatTime(alert.time)}</span>
        <button
          className={styles.flyTo}
          onClick={() => flyToEmergency(alert)}
          title="Fly to location"
        >
          Locate
        </button>
      </div>
    </div>
  );
}

function GeofenceRow({ alert }: { alert: GeofenceAlert }) {
  return (
    <div className={styles.geofenceAlert}>
      <span className={styles.geofenceLabel}>GEOFENCE</span>
      <span className={styles.geofenceCallsign}>{alert.callsign}</span>
      {alert.remarks && (
        <span className={styles.geofenceRemarks}>{alert.remarks}</span>
      )}
      <span className={styles.coords}>
        {formatCoords(alert.lat, alert.lon)}
      </span>
      <span className={styles.time}>{formatTime(alert.time)}</span>
    </div>
  );
}
