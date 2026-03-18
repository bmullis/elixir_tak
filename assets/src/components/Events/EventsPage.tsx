import { useEffect, useRef, useState } from "react";
import { useDashboardStore } from "../../store";
import { groupColor, type CotEvent } from "../../types";
import { Button } from "../ui";
import { formatTime } from "../../utils/formatting";
import styles from "./EventsPage.module.css";

type Category = "sa" | "chat" | "emergency" | "other";

function categorize(type: string): Category {
  if (type.startsWith("a-")) return "sa";
  if (type === "b-t-f") return "chat";
  if (type.startsWith("b-a-o-")) return "emergency";
  return "other";
}

const CATEGORY_LABEL: Record<Category, string> = {
  sa: "SA",
  chat: "Chat",
  emergency: "Emergency",
  other: "Other",
};

const CATEGORY_CLASS: Record<Category, string> = {
  sa: styles.categorySa,
  chat: styles.categoryChat,
  emergency: styles.categoryEmergency,
  other: styles.categoryOther,
};


function extractCallsign(event: CotEvent): string {
  return event.detail?.contact?.callsign ?? event.uid;
}

export default function EventsPage() {
  const recentEvents = useDashboardStore((s) => s.recentEvents);
  const [paused, setPaused] = useState(false);
  const frozenRef = useRef<CotEvent[]>([]);

  useEffect(() => {
    if (!paused) {
      frozenRef.current = recentEvents;
    }
  }, [paused, recentEvents]);

  const events = paused ? frozenRef.current : recentEvents;

  return (
    <div className={styles.page}>
      <div className={styles.header}>
        <h2 className={styles.title}>Event Feed</h2>
        <Button
          variant="secondary"
          size="sm"
          mono
          onClick={() => setPaused((p) => !p)}
          className={paused ? styles.pauseBtnActive : undefined}
        >
          {paused && <span className={styles.pauseIndicator} />}
          {paused ? "Paused" : "Pause"}
        </Button>
      </div>

      {events.length === 0 ? (
        <div className={styles.empty}>No events received</div>
      ) : (
        <table className={styles.table}>
          <thead>
            <tr>
              <th>Time</th>
              <th>Callsign</th>
              <th>Type</th>
              <th>Group</th>
              <th>UID</th>
            </tr>
          </thead>
          <tbody>
            {events.map((event, i) => {
              const cat = categorize(event.type);
              const isEmergency = cat === "emergency";

              return (
                <tr
                  key={`${event.uid}-${event.time}-${i}`}
                  className={isEmergency ? styles.emergencyRow : undefined}
                >
                  <td className={styles.time}>{formatTime(event.time, { hour12: false })}</td>
                  <td>{extractCallsign(event)}</td>
                  <td>
                    {isEmergency && <span className={styles.emergencyDot} />}
                    <span
                      className={`${styles.categoryBadge} ${CATEGORY_CLASS[cat]}`}
                    >
                      {CATEGORY_LABEL[cat]}
                    </span>
                  </td>
                  <td>
                    {event.group ? (
                      <span
                        className={styles.groupBadge}
                        style={{
                          color: groupColor(event.group),
                          backgroundColor: `color-mix(in srgb, ${groupColor(event.group)} 20%, transparent)`,
                        }}
                      >
                        {event.group}
                      </span>
                    ) : (
                      <span style={{ color: "var(--color-text-faint)" }}>-</span>
                    )}
                  </td>
                  <td className={styles.uid}>{event.uid}</td>
                </tr>
              );
            })}
          </tbody>
        </table>
      )}
    </div>
  );
}
