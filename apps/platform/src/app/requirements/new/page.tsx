import type { Metadata } from "next";
import { RequirementForm } from "@/features/requirements/RequirementForm";
import { Alert, Card, PageHeader } from "@/components/ui/States";
import { DELIVERY_COPY, PREVIEW_NOTICE } from "@/lib/labels";
import { DELIVERY_STATES } from "@/lib/domain";

export const metadata: Metadata = { title: "Post a requirement" };

export default function NewRequirementPage() {
  return (
    <div className="container-page pb-8">
      <PageHeader title="Post a requirement" lead="Tell us what you need. Only verified suppliers can receive it directly." />
      <Alert tone="warning" title="Preview only">{PREVIEW_NOTICE}</Alert>
      <div className="mt-6 grid gap-6 lg:grid-cols-[minmax(0,2fr)_minmax(0,1fr)]">
        <Card as="section"><RequirementForm /></Card>
        <aside aria-label="What happens next" className="space-y-3">
          <Card>
            <h2 className="text-lg">What you will be told</h2>
            <p className="mt-1 text-sm text-muted">When the service is live, you will see one of these statuses, as reported by the server. None of them says a supplier has received or read your requirement.</p>
            <ul className="mt-3 space-y-2 text-sm">
              {DELIVERY_STATES.map((d) => <li key={d}><strong>{DELIVERY_COPY[d].title}.</strong> {DELIVERY_COPY[d].body}</li>)}
            </ul>
          </Card>
        </aside>
      </div>
    </div>
  );
}
