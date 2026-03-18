import { forwardRef, type ButtonHTMLAttributes, type ReactNode } from "react";
import styles from "./IconButton.module.css";

export type IconButtonSize = "sm" | "md" | "lg";

export interface IconButtonProps
  extends ButtonHTMLAttributes<HTMLButtonElement> {
  size?: IconButtonSize;
  active?: boolean;
  label: string; /* required for accessibility */
  children: ReactNode;
}

export const IconButton = forwardRef<HTMLButtonElement, IconButtonProps>(
  ({ size = "md", active = false, label, className, children, ...props }, ref) => {
    const cls = [styles.iconButton, styles[size], className]
      .filter(Boolean)
      .join(" ");

    return (
      <button
        ref={ref}
        className={cls}
        aria-label={label}
        data-active={active}
        {...props}
      >
        {children}
      </button>
    );
  },
);

IconButton.displayName = "IconButton";
