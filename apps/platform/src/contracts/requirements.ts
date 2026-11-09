import { z } from "zod";
import type { CaseId, CompanyId, EnquiryId, UserId } from "./ids";
import type { EnquiryDelivery, LeadQueue, LeadStatus, MatchRoute } from "./enums";

/** Input a buyer may submit (validated again by the server and by the database). Contact details are separate and never echoed. */
export const requirementInputSchema = z.strictObject({
  product: z.string().trim().min(2).max(160),
  quantity: z.string().trim().min(1).max(80),
  destination: z.string().trim().min(2).max(120),
  details: z.string().trim().max(1000).default(""),
  consentNoticeVersion: z.string().min(1).max(40),
});
export type RequirementInput = z.infer<typeof requirementInputSchema>;

/** The buyer's own view of a requirement. Contains no supplier identities or contact data. */
export type BuyerRequirement = {
  readonly id: EnquiryId;
  readonly ref: string;
  readonly buyerId: UserId;
  readonly product: string;
  readonly quantity: string;
  readonly destination: string;
  readonly delivery: EnquiryDelivery;
  /** Server-written wording; displayed verbatim. */
  readonly notice: string;
  readonly createdAt: string;
};

/**
 * What a verified seller sees for a lead delivered to their company. Deliberately WITHOUT buyerId (audit F-I) and
 * without any contact fields. Buyer contact is a separate, audited reveal after the seller has responded.
 */
export type SellerLeadView = {
  readonly enquiryId: EnquiryId;
  readonly companyId: CompanyId;
  readonly product: string;
  readonly quantity: string;
  readonly destination: string;
  readonly details: string;
  readonly matchReasons: readonly string[];
  readonly responded: boolean;
  readonly receivedAt: string;
};

/** Internal desk case. Lists never carry contact values. */
export type LeadCaseSummary = {
  readonly caseId: CaseId;
  readonly enquiryId: EnquiryId;
  readonly queue: LeadQueue;
  readonly status: LeadStatus;
  readonly assignedTo: UserId | null;
  readonly nextFollowUpAt: string | null;
  readonly matchedVerifiedSuppliers: number;
};

export type LeadAssignment = {
  readonly caseId: CaseId;
  readonly assignedTo: UserId;
  readonly assignedBy: UserId;
  readonly assignedAt: string;
};

export type RequirementMatch = {
  readonly enquiryId: EnquiryId;
  readonly companyId: CompanyId;
  readonly route: MatchRoute;
  readonly reasons: readonly string[];
};
