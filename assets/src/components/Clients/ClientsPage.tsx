import { useCallback, useMemo, useState } from "react";
import { useDashboardStore } from "../../store";
import { groupColor } from "../../types";
import { formatCoords, formatDuration, formatSpeed } from "../../utils/formatting";
import styles from "./ClientsPage.module.css";

type SortField = "callsign" | "group" | "connected_at";
type SortDir = "asc" | "desc";

function SortHeader({
  label,
  field,
  currentField,
  currentDir,
  onSort,
}: {
  label: string;
  field: SortField;
  currentField: SortField;
  currentDir: SortDir;
  onSort: (field: SortField) => void;
}) {
  const isActive = currentField === field;
  return (
    <th
      className={styles.sortable}
      onClick={() => onSort(field)}
      aria-sort={isActive ? (currentDir === "asc" ? "ascending" : "descending") : "none"}
    >
      {label}
      {isActive && (
        <span className={styles.sortIndicator}>
          {currentDir === "asc" ? "\u25B2" : "\u25BC"}
        </span>
      )}
    </th>
  );
}

export default function ClientsPage() {
  const clients = useDashboardStore((s) => s.clients);
  const positions = useDashboardStore((s) => s.positions);
  const [sortField, setSortField] = useState<SortField>("callsign");
  const [sortDir, setSortDir] = useState<SortDir>("asc");

  const handleSort = useCallback(
    (field: SortField) => {
      if (field === sortField) {
        setSortDir((d) => (d === "asc" ? "desc" : "asc"));
      } else {
        setSortField(field);
        setSortDir("asc");
      }
    },
    [sortField]
  );

  const sortedClients = useMemo(() => {
    const arr = Array.from(clients.values());
    const dir = sortDir === "asc" ? 1 : -1;

    arr.sort((a, b) => {
      const av = (a[sortField] ?? "").toString().toLowerCase();
      const bv = (b[sortField] ?? "").toString().toLowerCase();
      if (av < bv) return -1 * dir;
      if (av > bv) return 1 * dir;
      return 0;
    });

    return arr;
  }, [clients, sortField, sortDir]);

  return (
    <div className={styles.page}>
      <h2 className={styles.title}>Connected Clients</h2>

      {sortedClients.length === 0 ? (
        <div className={styles.empty}>No clients connected</div>
      ) : (
        <table className={styles.table}>
          <thead>
            <tr>
              <SortHeader
                label="Callsign"
                field="callsign"
                currentField={sortField}
                currentDir={sortDir}
                onSort={handleSort}
              />
              <th>UID</th>
              <SortHeader
                label="Group"
                field="group"
                currentField={sortField}
                currentDir={sortDir}
                onSort={handleSort}
              />
              <th>Position</th>
              <th>Speed</th>
              <SortHeader
                label="Connected"
                field="connected_at"
                currentField={sortField}
                currentDir={sortDir}
                onSort={handleSort}
              />
            </tr>
          </thead>
          <tbody>
            {sortedClients.map((client) => {
              const pos = positions.get(client.uid);
              const point = pos?.point;
              const track = pos?.detail?.track;

              return (
                <tr key={client.uid}>
                  <td>{client.callsign ?? client.uid}</td>
                  <td className={styles.uid}>{client.uid}</td>
                  <td>
                    {client.group ? (
                      <span
                        className={styles.groupBadge}
                        style={{
                          color: groupColor(client.group),
                          backgroundColor: `color-mix(in srgb, ${groupColor(client.group)} 20%, transparent)`,
                        }}
                      >
                        {client.group}
                      </span>
                    ) : (
                      <span style={{ color: "var(--color-text-faint)" }}>-</span>
                    )}
                  </td>
                  <td className={styles.position}>
                    {formatCoords(point?.lat, point?.lon)}
                  </td>
                  <td className={styles.speed}>
                    {formatSpeed(track?.speed)}
                  </td>
                  <td>{formatDuration(client.connected_at)}</td>
                </tr>
              );
            })}
          </tbody>
        </table>
      )}
    </div>
  );
}
