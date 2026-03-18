import { useState, useCallback, useEffect } from "react";
import { useDashboardStore } from "../../store";
import { Input, Button, Badge } from "../ui";
import styles from "./SettingsPage.module.css";

interface CertInfo {
  cn: string;
  serial: string;
  fingerprint: string;
  status: string;
  created_at?: string;
}

function getApiHeaders(): HeadersInit {
  const token = localStorage.getItem("elixir_tak_api_token");
  const headers: HeadersInit = { "Content-Type": "application/json" };
  if (token) headers["Authorization"] = `Bearer ${token}`;
  return headers;
}

export default function SettingsPage() {
  const identity = useDashboardStore((s) => s.identity);
  const setCallsign = useDashboardStore((s) => s.setCallsign);

  return (
    <div className={styles.page}>
      <h1 className={styles.title}>Settings</h1>

      <section className={styles.section}>
        <h2 className={styles.sectionTitle}>Identity</h2>
        <div className={styles.field}>
          <label className={styles.label} htmlFor="callsign">
            Callsign
          </label>
          <Input
            id="callsign"
            inputSize="sm"
            mono
            value={identity.callsign}
            onChange={(e) => setCallsign(e.target.value)}
            placeholder="Callsign"
            className={styles.input}
          />
          <span className={styles.hint}>
            Used for chat messages and drawing labels
          </span>
        </div>
        <div className={styles.field}>
          <label className={styles.label}>UID</label>
          <span className={styles.readOnly}>{identity.uid}</span>
        </div>
      </section>

      <CertificatesSection />
    </div>
  );
}

function CertificatesSection() {
  const [certs, setCerts] = useState<CertInfo[]>([]);
  const [loading, setLoading] = useState(false);
  const [cn, setCn] = useState("");
  const [generating, setGenerating] = useState(false);
  const [lastGenerated, setLastGenerated] = useState<CertInfo | null>(null);
  const [error, setError] = useState("");

  const fetchCerts = useCallback(async () => {
    setLoading(true);
    try {
      const resp = await fetch("/api/admin/certs", {
        headers: getApiHeaders(),
      });
      if (resp.ok) {
        const data = await resp.json();
        setCerts(data.certs || []);
      }
    } catch {
      // ignore fetch errors
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    fetchCerts();
  }, [fetchCerts]);

  const handleGenerate = useCallback(
    async (e: React.FormEvent) => {
      e.preventDefault();
      if (!cn.trim()) return;
      setGenerating(true);
      setError("");
      setLastGenerated(null);

      try {
        const resp = await fetch("/api/admin/certs/client", {
          method: "POST",
          headers: getApiHeaders(),
          body: JSON.stringify({ cn: cn.trim() }),
        });
        const data = await resp.json();
        if (resp.ok) {
          setLastGenerated(data);
          setCn("");
          fetchCerts();
        } else {
          setError(data.error || "Failed to generate certificate");
        }
      } catch {
        setError("Network error");
      } finally {
        setGenerating(false);
      }
    },
    [cn, fetchCerts],
  );

  const handleRevoke = useCallback(
    async (serial: string) => {
      try {
        const resp = await fetch(`/api/admin/certs/${serial}/revoke`, {
          method: "POST",
          headers: getApiHeaders(),
        });
        if (resp.ok) fetchCerts();
      } catch {
        // ignore
      }
    },
    [fetchCerts],
  );

  return (
    <>
      <section className={styles.section}>
        <h2 className={styles.sectionTitle}>Generate Client Certificate</h2>
        <form onSubmit={handleGenerate} className={styles.formRow}>
          <Input
            inputSize="sm"
            mono
            value={cn}
            onChange={(e) => setCn(e.target.value)}
            placeholder="Callsign / CN (e.g. SGT.Smith)"
            className={styles.cnInput}
            disabled={generating}
          />
          <Button
            type="submit"
            variant="primary"
            size="sm"
            disabled={generating || !cn.trim()}
          >
            {generating ? "Generating..." : "Generate"}
          </Button>
        </form>
        {error && <p className={styles.error}>{error}</p>}
        {lastGenerated && (
          <div className={styles.successCard}>
            <p className={styles.successTitle}>Certificate created</p>
            <div className={styles.detailGrid}>
              <span className={styles.detailLabel}>CN</span>
              <span className={styles.detailValue}>{lastGenerated.cn}</span>
              <span className={styles.detailLabel}>Serial</span>
              <span className={styles.detailValue}>{lastGenerated.serial}</span>
              <span className={styles.detailLabel}>Fingerprint</span>
              <span className={styles.detailValue}>
                {lastGenerated.fingerprint}
              </span>
            </div>
            <ProfileDownload cn={lastGenerated.cn} />
          </div>
        )}
      </section>

      <section className={styles.section}>
        <h2 className={styles.sectionTitle}>Client Certificates</h2>
        {loading && certs.length === 0 ? (
          <p className={styles.hint}>Loading...</p>
        ) : certs.length === 0 ? (
          <p className={styles.hint}>No client certificates generated yet.</p>
        ) : (
          <div className={styles.tableWrap}>
            <table className={styles.table}>
              <thead>
                <tr>
                  <th>CN</th>
                  <th>Serial</th>
                  <th>Fingerprint</th>
                  <th>Status</th>
                  <th></th>
                </tr>
              </thead>
              <tbody>
                {certs.map((c) => (
                  <CertRow
                    key={c.serial}
                    cert={c}
                    onRevoke={handleRevoke}
                  />
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>
    </>
  );
}

function CertRow({
  cert,
  onRevoke,
}: {
  cert: CertInfo;
  onRevoke: (serial: string) => void;
}) {
  const [showProfile, setShowProfile] = useState(false);
  const isRevoked = cert.status === "revoked";

  return (
    <>
      <tr className={isRevoked ? styles.rowRevoked : undefined}>
        <td className={styles.cellMono}>{cert.cn}</td>
        <td className={styles.cellMono}>{cert.serial}</td>
        <td className={styles.cellFingerprint}>{cert.fingerprint}</td>
        <td>
          <Badge
            variant={isRevoked ? "error" : "success"}
            size="sm"
          >
            {cert.status}
          </Badge>
        </td>
        <td className={styles.cellActions}>
          {!isRevoked && (
            <>
              <Button
                variant="ghost"
                size="sm"
                onClick={() => setShowProfile(!showProfile)}
              >
                Profile
              </Button>
              <Button
                variant="danger"
                size="sm"
                onClick={() => onRevoke(cert.serial)}
              >
                Revoke
              </Button>
            </>
          )}
        </td>
      </tr>
      {showProfile && (
        <tr>
          <td colSpan={5} className={styles.profileCell}>
            <ProfileDownload cn={cert.cn} />
          </td>
        </tr>
      )}
    </>
  );
}

function ProfileDownload({ cn }: { cn: string }) {
  const [host, setHost] = useState(window.location.hostname);
  const [port, setPort] = useState("8089");

  const handleDownload = useCallback(() => {
    const params = new URLSearchParams({ cn, host, port });
    const token = localStorage.getItem("elixir_tak_api_token");
    const url = `/api/admin/certs/profile?${params}${token ? `&token=${token}` : ""}`;
    window.open(url, "_blank");
  }, [cn, host, port]);

  return (
    <div className={styles.profileForm}>
      <span className={styles.profileLabel}>Connection Profile</span>
      <div className={styles.profileFields}>
        <Input
          inputSize="sm"
          mono
          value={host}
          onChange={(e) => setHost(e.target.value)}
          placeholder="Server host"
          className={styles.hostInput}
        />
        <Input
          inputSize="sm"
          mono
          value={port}
          onChange={(e) => setPort(e.target.value)}
          placeholder="Port"
          className={styles.portInput}
        />
        <Button variant="secondary" size="sm" onClick={handleDownload}>
          Download .zip
        </Button>
      </div>
    </div>
  );
}
