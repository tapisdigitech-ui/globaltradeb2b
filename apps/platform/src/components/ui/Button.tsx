import Link from "next/link";
import type { ButtonHTMLAttributes, ComponentProps } from "react";
import { cn } from "@/lib/cn";

type Variant = "primary" | "secondary" | "ghost" | "danger";
type Size = "sm" | "md";

const base =
  "inline-flex items-center justify-center gap-2 rounded-md font-semibold no-underline transition-colors disabled:cursor-not-allowed disabled:opacity-60 min-h-11 sm:min-h-10";
const variants: Record<Variant, string> = {
  primary: "bg-accent-600 text-white hover:bg-accent-700 hover:text-white",
  secondary: "border border-navy-800 bg-surface text-navy-900 hover:bg-navy-50 hover:text-navy-900",
  ghost: "text-navy-800 hover:bg-navy-50 hover:text-navy-900",
  danger: "bg-danger-700 text-white hover:bg-red-900 hover:text-white",
};
const sizes: Record<Size, string> = { sm: "px-3 text-sm", md: "px-4 text-base" };

type Common = { variant?: Variant; size?: Size };

export function Button({ variant = "primary", size = "md", className, type = "button", ...rest }: Common & ButtonHTMLAttributes<HTMLButtonElement>) {
  return <button type={type} className={cn(base, variants[variant], sizes[size], className)} {...rest} />;
}

export function ButtonLink({ variant = "primary", size = "md", className, ...rest }: Common & ComponentProps<typeof Link>) {
  return <Link className={cn(base, variants[variant], sizes[size], className)} {...rest} />;
}
