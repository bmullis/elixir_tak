import { type ReactNode } from "react";
import { X } from "lucide-react";
import { IconButton } from "./IconButton";
import styles from "./PanelHeader.module.css";

export interface PanelHeaderProps {
  title: string;
  onClose: () => void;
  /** Optional content rendered between title and close button */
  children?: ReactNode;
}

export function PanelHeader({ title, onClose, children }: PanelHeaderProps) {
  return (
    <div className={styles.header}>
      <span className={styles.title}>{title}</span>
      {children && <div className={styles.extra}>{children}</div>}
      <IconButton size="sm" label={`Close ${title.toLowerCase()}`} onClick={onClose}>
        <X size={14} />
      </IconButton>
    </div>
  );
}
