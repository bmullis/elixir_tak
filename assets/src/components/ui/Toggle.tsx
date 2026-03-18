import { forwardRef, type ReactNode } from "react";
import * as TogglePrimitive from "@radix-ui/react-toggle";
import * as ToggleGroupPrimitive from "@radix-ui/react-toggle-group";
import styles from "./Toggle.module.css";

/* ---------- Single Toggle ---------- */

export type ToggleSize = "sm" | "md";

export interface ToggleProps
  extends React.ComponentPropsWithoutRef<typeof TogglePrimitive.Root> {
  size?: ToggleSize;
  mono?: boolean;
}

export const Toggle = forwardRef<HTMLButtonElement, ToggleProps>(
  ({ size = "md", mono = false, className, ...props }, ref) => {
    const cls = [
      styles.toggle,
      styles[size],
      mono && styles.mono,
      className,
    ]
      .filter(Boolean)
      .join(" ");

    return <TogglePrimitive.Root ref={ref} className={cls} {...props} />;
  },
);

Toggle.displayName = "Toggle";

/* ---------- Toggle Group ---------- */

export interface ToggleGroupSingleProps {
  type: "single";
  value?: string;
  defaultValue?: string;
  onValueChange?: (value: string) => void;
}

export interface ToggleGroupMultipleProps {
  type: "multiple";
  value?: string[];
  defaultValue?: string[];
  onValueChange?: (value: string[]) => void;
}

export type ToggleGroupProps = (ToggleGroupSingleProps | ToggleGroupMultipleProps) & {
  size?: ToggleSize;
  mono?: boolean;
  className?: string;
  children: ReactNode;
};

export function ToggleGroup({
  size = "md",
  mono = false,
  className,
  children,
  ...props
}: ToggleGroupProps) {
  const cls = [styles.group, className].filter(Boolean).join(" ");

  return (
    <ToggleGroupPrimitive.Root className={cls} {...(props as any)}>
      {children}
    </ToggleGroupPrimitive.Root>
  );
}

export interface ToggleGroupItemProps
  extends React.ComponentPropsWithoutRef<typeof ToggleGroupPrimitive.Item> {
  size?: ToggleSize;
  mono?: boolean;
}

export const ToggleGroupItem = forwardRef<
  HTMLButtonElement,
  ToggleGroupItemProps
>(({ size = "md", mono = false, className, ...props }, ref) => {
  const cls = [
    styles.toggle,
    styles[size],
    mono && styles.mono,
    className,
  ]
    .filter(Boolean)
    .join(" ");

  return <ToggleGroupPrimitive.Item ref={ref} className={cls} {...props} />;
});

ToggleGroupItem.displayName = "ToggleGroupItem";
