"use client";
import Link from "next/link";
import { LEGAL_DRAFT_TAG } from "@/components/ui/LegalDraft";
import { Alert } from "@/components/ui/States";
import { Button } from "@/components/ui/Button";
import { CheckboxField, TextAreaField, TextField } from "@/components/ui/Field";
import { usePreviewForm } from "@/features/forms/usePreviewForm";
import { requirementSchema } from "@/lib/validation";
import { PREVIEW_NOTICE } from "@/lib/labels";

export function RequirementForm() {
  const { ref, errors, done, onSubmit } = usePreviewForm(requirementSchema);
  return (
    <form ref={ref} onSubmit={onSubmit} noValidate aria-label="Post a requirement" className="grid gap-4 sm:grid-cols-2">
      {done ? (
        <div className="sm:col-span-2">
          <Alert tone="info" title="Preview complete — nothing was sent">{PREVIEW_NOTICE}</Alert>
        </div>
      ) : null}
      <div className="sm:col-span-2"><TextField label="Product or service needed" name="product" required error={errors.product} placeholder="For example: hand-knotted rugs" /></div>
      <TextField label="Quantity" name="quantity" required error={errors.quantity} placeholder="For example: 500 pieces" />
      <TextField label="Delivery city or country" name="destination" required error={errors.destination} autoComplete="off" />
      <div className="sm:col-span-2">
        <TextAreaField label="Specifications" name="details" error={errors.details} maxLength={1000}
          hint="Describe size, material and quality. Do not type phone numbers or email addresses here: suppliers may read this text." />
      </div>
      <TextField label="Your name" name="buyerName" required autoComplete="name" error={errors.buyerName} />
      <TextField label="Mobile number" name="buyerPhone" required type="tel" inputMode="tel" autoComplete="tel" error={errors.buyerPhone}
        hint="Kept private. In the live service it is shown to a supplier only after they respond." />
      <div className="sm:col-span-2"><TextField label="Email (optional)" name="buyerEmail" type="email" autoComplete="email" error={errors.buyerEmail} /></div>
      <div className="sm:col-span-2">
        <CheckboxField name="consent" error={errors.consent}
          label={<>I agree that my requirement and contact details may be used to find suppliers, as described in the <Link href="/legal/privacy">privacy notice</Link>.<span className="font-semibold text-accent-700"> {LEGAL_DRAFT_TAG}</span></>} />
      </div>
      <div className="sm:col-span-2"><Button type="submit">Preview requirement</Button></div>
    </form>
  );
}
