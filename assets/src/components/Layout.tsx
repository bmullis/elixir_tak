import { NavLink, Outlet } from "react-router-dom";
import { useDashboardStore } from "../store";
import StatsBar from "./ui/StatsBar";
import ChatPanel, { ChatFab } from "./Chat/ChatPanel";
import EmergencyBanner from "./ui/EmergencyBanner";
import styles from "./Layout.module.css";

export default function Layout() {
  const status = useDashboardStore((s) => s.status);

  const dotClass =
    status === "connected"
      ? styles.dotConnected
      : status === "connecting"
        ? styles.dotConnecting
        : styles.dotError;

  return (
    <div className={styles.layout}>
      <header className={styles.header}>
        <div className={styles.titleGroup}>
          <NavLink to="/dashboard" end className={styles.title}>
            ElixirTAK
          </NavLink>
          <nav className={styles.nav}>
            <NavLink
              to="/dashboard"
              end
              className={({ isActive }) =>
                `${styles.navLink} ${isActive ? styles.navLinkActive : ""}`
              }
            >
              Map
            </NavLink>
            <NavLink
              to="/dashboard/clients"
              className={({ isActive }) =>
                `${styles.navLink} ${isActive ? styles.navLinkActive : ""}`
              }
            >
              Clients
            </NavLink>
            <NavLink
              to="/dashboard/events"
              className={({ isActive }) =>
                `${styles.navLink} ${isActive ? styles.navLinkActive : ""}`
              }
            >
              Events
            </NavLink>
            <NavLink
              to="/dashboard/video"
              className={({ isActive }) =>
                `${styles.navLink} ${isActive ? styles.navLinkActive : ""}`
              }
            >
              Video
            </NavLink>
            <NavLink
              to="/dashboard/settings"
              className={({ isActive }) =>
                `${styles.navLink} ${isActive ? styles.navLinkActive : ""}`
              }
            >
              Settings
            </NavLink>
          </nav>
        </div>

        <div className={styles.statusRow}>
          <span className={`${styles.dot} ${dotClass}`} />
          <span className={styles.statusText}>{status}</span>
        </div>
      </header>

      <EmergencyBanner />

      <div className={styles.contentRow}>
        <div className={styles.content}>
          <Outlet />
          <ChatFab />
        </div>
        <ChatPanel />
      </div>
      <StatsBar />
    </div>
  );
}
