"use client";
import { useRef, useState, type FormEvent } from "react";
import type { z } from "zod";
import { validate, type FieldErrors } from "@/lib/validation";

/**
 * Validates a form and, on success, only shows the preview notice.
 * Nothing is sent, stored (no localStorage / cookies) or retained: the form is reset after a valid submit
 * so that contact details do not linger in the page.
 */
export function usePreviewForm<T>(schema: z.ZodType<T>) {
  const [errors, setErrors] = useState<FieldErrors>({});
  const [done, setDone] = useState(false);
  const ref = useRef<HTMLFormElement>(null);

  function onSubmit(e: FormEvent<HTMLFormElement>) {
    e.preventDefault();
    const form = e.currentTarget;
    const raw: Record<string, unknown> = {};
    new FormData(form).forEach((v, k) => { raw[k] = typeof v === "string" ? v : ""; });
    form.querySelectorAll<HTMLInputElement>("input[type=checkbox]").forEach((c) => { raw[c.name] = c.checked; });
    const r = validate(schema, raw);
    if (!r.ok) {
      setErrors(r.errors); setDone(false);
      const first = Object.keys(r.errors)[0];
      const el = first ? form.querySelector<HTMLElement>(`[name="${first}"]`) : null;
      el?.focus();
      return;
    }
    setErrors({}); setDone(true); form.reset();
  }
  return { ref, errors, done, onSubmit };
}
