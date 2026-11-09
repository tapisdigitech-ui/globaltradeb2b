import type { Metadata } from "next";
import { LegalDraftNotice } from "@/components/ui/LegalDraft";
import { PageHeader } from "@/components/ui/States";

export const metadata: Metadata = { title: "Terms (draft placeholder)" };

const TOPICS = [
  "Who operates the platform (legal entity, registered address)",
  "What the platform is and is not (directory and introduction service; not a party to trades)",
  "Account rules and eligibility",
  "What “Verified” means and does not mean, and the liability position",
  "Supplier listing, content and image-rights rules",
  "Buyer requirements and how suppliers may use them",
  "Prohibited conduct and enforcement",
  "Fees, if any",
  "Disclaimers, limits of liability, governing law and dispute resolution",
  "Changes to the terms and notice versioning (the backend records a notice version)",
];

export default function TermsPage() {
  return (
    <div className="container-page pb-8">
      <PageHeader title="Terms of use — draft placeholder" lead="Topics to be decided by qualified counsel. This is not a policy." />
      <LegalDraftNotice />
      <h2 className="mt-6">Questions counsel must settle</h2>
      <ul className="mt-2 list-disc space-y-1 pl-5">{TOPICS.map((t) => <li key={t}>{t}</li>)}</ul>
    </div>
  );
}
