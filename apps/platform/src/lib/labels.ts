import type { DeliveryState, PublicSupplier, VerificationLabel } from "./domain";

export type BadgeTone = "success" | "warning" | "neutral" | "info";

export const LABEL_TONE: Record<VerificationLabel, BadgeTone> = {
  Verified: "success",
  "Verification Pending": "warning",
  "Claimed — Not Verified": "neutral",
  "Claim Requested": "info",
  "Unclaimed — Not Verified": "neutral",
};

/**
 * The label shown to people. "Verified" is only ever produced when the record is
 * verified; every other state keeps its explicit "not verified / pending" wording.
 * Demo records always say so, even when a sample is shaped like a verified one.
 */
export function supplierBadge(s: Pick<PublicSupplier, "label" | "isVerified" | "isDemo">): { text: string; tone: BadgeTone } {
  const label: VerificationLabel = s.label === "Verified" && !s.isVerified ? "Unclaimed — Not Verified" : s.label;
  return { text: s.isDemo ? `${label} · Demo sample` : label, tone: LABEL_TONE[label] };
}

/**
 * Delivery wording. Mirrors the server notices in the integration contract (§4).
 * No state ever says "sent", "delivered" or "received": only the server can confirm that,
 * and even `visible_to_seller` means "visible in the supplier's account", not "read".
 */
export const DELIVERY_COPY: Record<DeliveryState, { title: string; body: string }> = {
  stored: {
    title: "Recorded",
    body: "Your requirement is recorded. No supplier has been contacted yet.",
  },
  awaiting_admin: {
    title: "Held by our team",
    body: "Your requirement is held by our team. It has not been passed to any company directly.",
  },
  visible_to_seller: {
    title: "Visible to the supplier",
    body: "Your requirement is visible in the account of an eligible, verified supplier. We cannot confirm that they have read it.",
  },
};

/** Shown on every form until a backend exists. */
export const PREVIEW_NOTICE =
  "Preview only. This form is not connected to a server, so nothing was sent, stored or delivered to any supplier.";
