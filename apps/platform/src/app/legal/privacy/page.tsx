import type { Metadata } from "next";
import { LegalDraftNotice } from "@/components/ui/LegalDraft";
import { PageHeader } from "@/components/ui/States";

export const metadata: Metadata = { title: "Privacy notice (draft placeholder)" };

const TOPICS = [
  "Identity and contact details of the data controller",
  "Which laws apply (for example India’s DPDP Act, and GDPR if EU residents are involved): counsel to confirm",
  "What personal data is collected: buyer name, phone, email, requirement text; supplier contacts; claim evidence",
  "Purpose and lawful basis for each use, including supplier-contact outreach (open decision P2-9)",
  "Who can see what: suppliers, staff, administrators; when buyer contact is revealed",
  "Retention periods and deletion/anonymisation process (open decisions P1-5, P1-6)",
  "Processors and cross-border transfers (hosting, email/SMS providers if any)",
  "User rights and how to exercise them; grievance contact",
  "Cookies and storage (none are used by this prototype)",
  "Children’s data and security-incident handling",
];

export default function PrivacyPage() {
  return (
    <div className="container-page pb-8">
      <PageHeader title="Privacy notice — draft placeholder" lead="Topics to be decided by qualified counsel. This is not a policy." />
      <LegalDraftNotice />
      <h2 className="mt-6">Questions counsel must settle</h2>
      <ul className="mt-2 list-disc space-y-1 pl-5">{TOPICS.map((t) => <li key={t}>{t}</li>)}</ul>
      <p className="mt-4 text-sm text-muted">This prototype stores nothing: forms discard their input and no cookies or browser storage are used.</p>
    </div>
  );
}
