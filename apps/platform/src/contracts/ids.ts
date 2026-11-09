/** Branded identifiers: prevent passing a company id where a user id is expected. Values are opaque UUID strings from the server. */
declare const brand: unique symbol;
export type Brand<T, B extends string> = T & { readonly [brand]: B };

export type UserId = Brand<string, "UserId">;
export type CompanyId = Brand<string, "CompanyId">;
export type ClaimId = Brand<string, "ClaimId">;
export type EnquiryId = Brand<string, "EnquiryId">;
export type CaseId = Brand<string, "CaseId">;

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export const isUuid = (v: unknown): v is string => typeof v === "string" && UUID.test(v);

/** Constructors validate shape only; they do not prove the id exists or belongs to anyone. */
function make<T extends string>(v: string, what: string): T {
  if (!isUuid(v)) throw new TypeError(`${what} must be a UUID`);
  return v as T;
}
export const userId = (v: string) => make<UserId>(v, "UserId");
export const companyId = (v: string) => make<CompanyId>(v, "CompanyId");
export const claimId = (v: string) => make<ClaimId>(v, "ClaimId");
export const enquiryId = (v: string) => make<EnquiryId>(v, "EnquiryId");
export const caseId = (v: string) => make<CaseId>(v, "CaseId");
