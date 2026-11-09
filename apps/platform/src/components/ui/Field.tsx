"use client";
import { useId, type InputHTMLAttributes, type ReactNode, type SelectHTMLAttributes, type TextareaHTMLAttributes } from "react";
import { cn } from "@/lib/cn";

type Shared = { label: string; hint?: string; error?: string; required?: boolean };

const control =
  "block w-full rounded-md border bg-surface px-3 py-2 text-base text-ink placeholder:text-muted min-h-11 sm:min-h-10 aria-[invalid=true]:border-danger-700 border-line focus-visible:border-navy-700";

function Wrap({ id, label, hint, error, required, children }: Shared & { id: string; children: ReactNode }) {
  return (
    <div className="flex flex-col gap-1">
      <label htmlFor={id} className="text-sm font-semibold text-navy-900">
        {label}
        {required ? <span aria-hidden="true" className="text-danger-700"> *</span> : null}
        {required ? <span className="sr-only"> (required)</span> : null}
      </label>
      {children}
      {hint ? <p id={`${id}-hint`} className="text-xs text-muted">{hint}</p> : null}
      <p id={`${id}-err`} role={error ? "alert" : undefined} className={cn("text-sm text-danger-700", !error && "hidden")}>{error}</p>
    </div>
  );
}
const describedBy = (id: string, hint?: string, error?: string) => [hint ? `${id}-hint` : "", error ? `${id}-err` : ""].filter(Boolean).join(" ") || undefined;

export function TextField({ label, hint, error, required, className, id, ...rest }: Shared & InputHTMLAttributes<HTMLInputElement>) {
  const gen = useId(); const fid = id ?? gen;
  return (
    <Wrap id={fid} label={label} hint={hint} error={error} required={required}>
      <input id={fid} aria-invalid={error ? true : undefined} aria-required={required || undefined} aria-describedby={describedBy(fid, hint, error)} className={cn(control, className)} {...rest} />
    </Wrap>
  );
}

export function SelectField({ label, hint, error, required, className, id, children, ...rest }: Shared & SelectHTMLAttributes<HTMLSelectElement>) {
  const gen = useId(); const fid = id ?? gen;
  return (
    <Wrap id={fid} label={label} hint={hint} error={error} required={required}>
      <select id={fid} aria-invalid={error ? true : undefined} aria-required={required || undefined} aria-describedby={describedBy(fid, hint, error)} className={cn(control, className)} {...rest}>{children}</select>
    </Wrap>
  );
}

export function TextAreaField({ label, hint, error, required, className, id, ...rest }: Shared & TextareaHTMLAttributes<HTMLTextAreaElement>) {
  const gen = useId(); const fid = id ?? gen;
  return (
    <Wrap id={fid} label={label} hint={hint} error={error} required={required}>
      <textarea id={fid} rows={4} aria-invalid={error ? true : undefined} aria-required={required || undefined} aria-describedby={describedBy(fid, hint, error)} className={cn(control, "min-h-24", className)} {...rest} />
    </Wrap>
  );
}

export function CheckboxField({ label, error, id, ...rest }: { label: ReactNode; error?: string } & InputHTMLAttributes<HTMLInputElement>) {
  const gen = useId(); const fid = id ?? gen;
  return (
    <div className="flex flex-col gap-1">
      <div className="flex items-start gap-3">
        <input id={fid} type="checkbox" aria-invalid={error ? true : undefined} aria-describedby={error ? `${fid}-err` : undefined} className="mt-1 size-5 shrink-0 accent-navy-800" {...rest} />
        <label htmlFor={fid} className="text-sm text-ink">{label}</label>
      </div>
      <p id={`${fid}-err`} role={error ? "alert" : undefined} className={cn("text-sm text-danger-700", !error && "hidden")}>{error}</p>
    </div>
  );
}
