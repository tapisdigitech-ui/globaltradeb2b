import "server-only";
import type { DataAccess } from "./repositories";

/** Thrown by the only implementation that exists. Carries no details, so it cannot leak anything. */
export class NotConnectedError extends Error {
  readonly code = "NOT_CONNECTED" as const;
  constructor() {
    super("The data layer is not connected.");
    this.name = "NotConnectedError";
  }
}

const fail = async (): Promise<never> => { throw new NotConnectedError(); };

/**
 * Performs NO database, network, file or cache operation: every method rejects. It exists so that application code can
 * be written against `DataAccess` today and tested for what it does when the backend is absent.
 */
export const notConnectedDataAccess: DataAccess = {
  suppliers: { listPublic: fail, getPublicBySlug: fail, getOwnCompanyState: fail, openSupplierContacts: fail },
  claims: { getClaimFacts: fail, submitClaim: fail, listOwnClaims: fail, reviewClaim: fail, requestEvidenceLinks: fail },
  requirements: { create: fail, listOwn: fail },
  leads: { getLeadAccessFacts: fail, listDeliveredToCompany: fail, respond: fail, revealBuyerContact: fail, listCases: fail, updateCase: fail, assignCase: fail, openBuyerContact: fail },
  staffActions: { listRecent: fail },
};
