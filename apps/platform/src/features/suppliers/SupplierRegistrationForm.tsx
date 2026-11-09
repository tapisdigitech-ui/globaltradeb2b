"use client";
import { Alert } from "@/components/ui/States";
import { Button } from "@/components/ui/Button";
import { CheckboxField, SelectField, TextAreaField, TextField } from "@/components/ui/Field";
import { usePreviewForm } from "@/features/forms/usePreviewForm";
import { supplierRegistrationSchema } from "@/lib/validation";
import { PREVIEW_NOTICE } from "@/lib/labels";

export function SupplierRegistrationForm() {
  const { ref, errors, done, onSubmit } = usePreviewForm(supplierRegistrationSchema);
  return (
    <form ref={ref} onSubmit={onSubmit} noValidate aria-label="Supplier registration" className="grid gap-4 sm:grid-cols-2">
      {done ? (
        <div className="sm:col-span-2"><Alert tone="info" title="Preview complete — no company was registered">{PREVIEW_NOTICE} Registering never makes a company “Verified”: verification is a separate, staff-reviewed step.</Alert></div>
      ) : null}
      <div className="sm:col-span-2"><TextField label="Company name" name="companyName" required autoComplete="organization" error={errors.companyName} /></div>
      <SelectField label="Business type" name="businessType" required error={errors.businessType} defaultValue="">
        <option value="" disabled>Choose…</option>
        <option>Manufacturer</option><option>Exporter</option><option>Trader</option><option>Service provider</option>
      </SelectField>
      <TextField label="City" name="city" required error={errors.city} />
      <TextField label="Your name" name="contactName" required autoComplete="name" error={errors.contactName} />
      <TextField label="Work email" name="contactEmail" required type="email" autoComplete="email" error={errors.contactEmail} />
      <TextField label="Mobile number" name="contactPhone" required type="tel" inputMode="tel" autoComplete="tel" error={errors.contactPhone}
        hint="Used only to verify your claim. Never shown on public pages." />
      <div className="sm:col-span-2"><TextAreaField label="Your role and connection to the company" name="statement" required error={errors.statement} maxLength={600} /></div>
      <div className="sm:col-span-2"><CheckboxField name="consent" error={errors.consent} label="I confirm I am authorised to act for this company and agree to the verification process (terms text to be supplied before launch)." /></div>
      <div className="sm:col-span-2"><Button type="submit">Preview registration</Button></div>
    </form>
  );
}
