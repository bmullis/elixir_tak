import { useDashboardStore } from "../../store";
import styles from "./StatsBar.module.css";

function formatUptime(seconds: number): string {
  const h = Math.floor(seconds / 3600);
  const m = Math.floor((seconds % 3600) / 60);
  const s = Math.floor(seconds % 60);
  if (h > 0) return `${h}h ${m}m`;
  if (m > 0) return `${m}m ${s}s`;
  return `${s}s`;
}

export default function StatsBar() {
  const metrics = useDashboardStore((s) => s.metrics);
  const hasFederation = metrics.federation_peers !== undefined;

  return (
    <div className={styles.bar}>
      <div className={styles.stat}>
        <span className={styles.label}>Clients</span>
        <span className={styles.accent}>{metrics.connected_clients}</span>
      </div>

      <div className={styles.stat}>
        <span className={styles.label}>Events/s</span>
        <span className={styles.value}>{metrics.events_per_second}</span>
      </div>

      <div className={styles.stat}>
        <span className={styles.label}>Events/m</span>
        <span className={styles.value}>{metrics.events_per_minute}</span>
      </div>

      <div className={styles.stat}>
        <span className={styles.label}>SA</span>
        <span className={styles.value}>{metrics.sa_cached}</span>
      </div>

      <div className={styles.stat}>
        <span className={styles.label}>Chat</span>
        <span className={styles.value}>{metrics.chat_cached}</span>
      </div>

      <div className={styles.stat}>
        <span className={styles.label}>Uptime</span>
        <span className={styles.value}>
          {formatUptime(metrics.uptime_seconds)}
        </span>
      </div>

      <div className={styles.stat}>
        <span className={styles.label}>Mem</span>
        <span className={styles.value}>{metrics.memory_mb.toFixed(1)} MB</span>
      </div>

      {hasFederation && (
        <div className={styles.stat}>
          <span className={styles.label}>Fed</span>
          <span
            className={`${styles.federation} ${
              (metrics.federation_connected ?? 0) > 0
                ? styles.fedConnected
                : styles.fedDisconnected
            }`}
          >
            {metrics.federation_connected ?? 0}/{metrics.federation_peers ?? 0}
          </span>
        </div>
      )}
    </div>
  );
}
