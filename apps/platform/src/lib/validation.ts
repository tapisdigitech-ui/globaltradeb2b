import { z } from "zod";

// zod's JIT probes `new Function`, which a strict CSP reports as a violation. Our schemas are tiny: disable it.
z.config({ jitless: true });

const phone = z
  .string()
  .trim()
  .regex(/^[0-9+\-\s()]{7,16}$/, "Enter a valid mobile number (digits, spaces, + or -).");
const email = z.string().trim().email("That email address does not look right.");
const name = z.string().trim().min(2, "Enter at least 2 characters.").max(120, "Keep this under 120 characters.");

/** Warn buyers not to put contact details in free text (sellers can read it before any reveal). Heuristic, never a block. */
export const CONTACT_IN_TEXT = /(\+?\d[\d\s().-]{8,}\d)|([^\s@]+@[^\s@]+\.[^\s@]+)/;

export const requirementSchema = z.object({
  product: z.string().trim().min(2, "Enter the product or service you need.").max(160),
  quantity: z.string().trim().min(1, "Enter the quantity you need.").max(80),
  destination: z.string().trim().min(2, "Enter the delivery city or country.").max(120),
  details: z.string().trim().max(1000, "Keep details under 1000 characters.").optional().default(""),
  buyerName: name,
  buyerPhone: phone,
  buyerEmail: email.or(z.literal("")).optional().default(""),
  consent: z.literal(true, { error: "Please confirm consent to proceed." }),
});

export const supplierRegistrationSchema = z.object({
  companyName: name,
  businessType: z.enum(["Manufacturer", "Exporter", "Trader", "Service provider"], { error: "Choose a business type." }),
  city: z.string().trim().min(2, "Enter the city.").max(80),
  contactName: name,
  contactEmail: email,
  contactPhone: phone,
  statement: z.string().trim().min(10, "Describe your role in the company (at least 10 characters).").max(600),
  consent: z.literal(true, { error: "Please confirm consent to proceed." }),
});

export const loginSchema = z.object({
  email,
  password: z.string().min(1, "Enter your password."),
});

export const accountSchema = z
  .object({
    fullName: name,
    email,
    password: z.string().min(12, "Use at least 12 characters."),
    confirm: z.string(),
    consent: z.literal(true, { error: "Please accept the terms to continue." }),
  })
  .refine((v) => v.password === v.confirm, { path: ["confirm"], message: "Passwords do not match.", when: () => true });

export type FieldErrors = Record<string, string>;

/** Flatten a zod result to {field: first message}. */
export function validate<T>(schema: z.ZodType<T>, input: unknown): { ok: true; data: T } | { ok: false; errors: FieldErrors } {
  const r = schema.safeParse(input);
  if (r.success) return { ok: true, data: r.data };
  const errors: FieldErrors = {};
  for (const issue of r.error.issues) {
    const k = String(issue.path[0] ?? "form");
    if (!(k in errors)) errors[k] = issue.message;
  }
  return { ok: false, errors };
}
