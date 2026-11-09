"use client";
import Link from "next/link";
import { Alert } from "@/components/ui/States";
import { Button } from "@/components/ui/Button";
import { TextField } from "@/components/ui/Field";
import { usePreviewForm } from "@/features/forms/usePreviewForm";
import { loginSchema } from "@/lib/validation";

export function LoginForm() {
  const { ref, errors, done, onSubmit } = usePreviewForm(loginSchema);
  return (
    <form ref={ref} onSubmit={onSubmit} noValidate aria-label="Sign in" className="flex flex-col gap-4">
      {done ? <Alert tone="warning" title="Sign-in is not available yet">Authentication is not connected, so no session was created and your details were discarded.</Alert> : null}
      <TextField label="Email" name="email" type="email" required autoComplete="username" error={errors.email} />
      <TextField label="Password" name="password" type="password" required autoComplete="current-password" error={errors.password} />
      <Button type="submit">Sign in</Button>
      <p className="text-sm text-muted">New here? <Link href="/register">Create an account</Link></p>
    </form>
  );
}
