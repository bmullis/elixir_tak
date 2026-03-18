import { forwardRef, type InputHTMLAttributes } from "react";
import styles from "./Input.module.css";

export type InputSize = "sm" | "md" | "lg";

export interface InputProps extends InputHTMLAttributes<HTMLInputElement> {
  inputSize?: InputSize;
  mono?: boolean;
}

export const Input = forwardRef<HTMLInputElement, InputProps>(
  ({ inputSize = "md", mono = false, className, ...props }, ref) => {
    const cls = [
      styles.input,
      styles[inputSize],
      mono && styles.mono,
      className,
    ]
      .filter(Boolean)
      .join(" ");

    return <input ref={ref} className={cls} {...props} />;
  },
);

Input.displayName = "Input";
