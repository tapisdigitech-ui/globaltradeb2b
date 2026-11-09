"use client";
import Link from "next/link";
import { Alert } from "@/components/ui/States";
import { Button } from "@/components/ui/Button";
import { CheckboxField, TextField } from "@/components/ui/Field";
import { usePreviewForm } from "@/features/forms/usePreviewForm";
import { accountSchema } from "@/lib/validation";

export function AccountForm() {
  const { ref, errors, done, onSubmit } = usePreviewForm(accountSchema);
  return (
    <form ref={ref} onSubmit={onSubmit} noValidate aria-label="Create account" className="flex flex-col gap-4">
      {done ? <Alert tone="warning" title="Registration is not available yet">Authentication is not connected, so no account was created and your details were discarded.</Alert> : null}
      <TextField label="Full name" name="fullName" required autoComplete="name" error={errors.fullName} />
      <TextField label="Email" name="email" type="email" required autoComplete="email" error={errors.email} />
      <TextField label="Password" name="password" type="password" required autoComplete="new-password" error={errors.password} hint="At least 12 characters." />
      <TextField label="Confirm password" name="confirm" type="password" required autoComplete="new-password" error={errors.confirm} />
      <CheckboxField name="consent" error={errors.consent} label="I accept the terms and privacy notice (texts to be supplied before launch)." />
      <p className="text-xs text-muted">Every new account is a buyer account. Supplier, staff and admin access is granted only by the platform, never chosen here.</p>
      <Button type="submit">Create account</Button>
      <p className="text-sm text-muted">Already registered? <Link href="/login">Sign in</Link></p>
    </form>
  );
}
