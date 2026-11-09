import { Alert } from "@/components/ui/States";

/** Shown wherever legal wording would appear. No legal policy exists yet; none is invented here. */
export function LegalDraftNotice() {
  return (
    <Alert tone="warning" title="DRAFT placeholder — not legal advice">
      No terms, privacy policy or consent wording has been written or reviewed by a lawyer. This page only lists the questions that qualified counsel must decide. Do not rely on it, and do not collect real personal data until approved texts replace it.
    </Alert>
  );
}

export const LEGAL_DRAFT_TAG = "[Draft wording — pending legal review]";
