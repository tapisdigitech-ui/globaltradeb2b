import type { Metadata } from "next";
import { SupplierRegistrationForm } from "@/features/suppliers/SupplierRegistrationForm";
import { Alert, Card, PageHeader } from "@/components/ui/States";
import { PREVIEW_NOTICE } from "@/lib/labels";

export const metadata: Metadata = { title: "List your company" };

export default function SupplierRegisterPage() {
  return (
    <div className="container-page pb-8">
      <PageHeader title="List or claim your company" lead="Registering creates a claim for review. It does not make a company “Verified”." />
      <Alert tone="warning" title="Preview only">{PREVIEW_NOTICE}</Alert>
      <div className="mt-6 grid gap-6 lg:grid-cols-[minmax(0,2fr)_minmax(0,1fr)]">
        <Card as="section"><SupplierRegistrationForm /></Card>
        <aside aria-label="Verification steps"><Card>
          <h2 className="text-lg">Steps in the live service</h2>
          <ol className="mt-2 list-decimal space-y-1 pl-5 text-sm">
            <li>Create an account.</li>
            <li>Submit a claim with evidence.</li>
            <li>Confirm your contact (provider to be decided).</li>
            <li>A reviewer assigned to your case decides; an administrator publishes.</li>
          </ol>
          <p className="mt-3 text-sm text-muted">Until step 4 is complete your profile is shown as not verified and receives no leads directly.</p>
        </Card></aside>
      </div>
    </div>
  );
}
