import { type HTMLAttributes, type ReactNode } from "react";
import styles from "./Badge.module.css";

export type BadgeVariant = "default" | "accent" | "success" | "warning" | "error";
export type BadgeSize = "sm" | "md";

export interface BadgeProps extends HTMLAttributes<HTMLSpanElement> {
  variant?: BadgeVariant;
  size?: BadgeSize;
  children: ReactNode;
}

export function Badge({
  variant = "default",
  size = "sm",
  className,
  children,
  ...props
}: BadgeProps) {
  const cls = [styles.badge, styles[variant], styles[size], className]
    .filter(Boolean)
    .join(" ");

  return (
    <span className={cls} {...props}>
      {children}
    </span>
  );
}

/** Notification count dot (position: absolute, place on a relative parent) */
export function NotificationBadge({
  count,
  className,
  ...props
}: { count: number } & HTMLAttributes<HTMLSpanElement>) {
  if (count <= 0) return null;

  const cls = [styles.dot, className].filter(Boolean).join(" ");

  return (
    <span className={cls} {...props}>
      {count > 99 ? "99+" : count}
    </span>
  );
}
