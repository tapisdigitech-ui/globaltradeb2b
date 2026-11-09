import { SUPPLIERS } from "@/data/demo";
import { FORBIDDEN_PUBLIC_KEYS, assertNoForbiddenKeys, publicSupplierSchema, toPublicSupplier, type PublicCompaniesRow } from "@/contracts/public-supplier";

const row = (o: Partial<PublicCompaniesRow> = {}): PublicCompaniesRow => ({
  id: "11111111-1111-4111-8111-111111111111", slug: "example-co", name: "Example Co", business_type: "Manufacturer", about: "Invented.",
  city: "Sampletown", state: "Demo", country: "India", website: null, logo_path: null, public_label: "Unclaimed — Not Verified",
  is_claimed: false, is_verified: false, data_as_of: null, updated_at: "2026-11-09T00:00:00Z", ...o,
});

describe("public supplier contract", () => {
  it("maps an allow-listed row to the DTO", () => {
    const d = toPublicSupplier(row());
    expect(Object.keys(d).sort()).toEqual(["about", "businessType", "city", "country", "dataAsOf", "id", "isClaimed", "isVerified", "logoPath", "name", "publicLabel", "slug", "state", "updatedAt", "website"]);
  });
  it("drops private columns that a careless SELECT * might return (mapper is an allow-list)", () => {
    const leaky = { ...row(), phone: "+000", email: "x@example.invalid", contact_person: "N/A", gst: "X" } as unknown as PublicCompaniesRow;
    const d = toPublicSupplier(leaky);
    expect(JSON.stringify(d)).not.toMatch(/phone|email|contact_person|gst|\+000/);
    expect(() => assertNoForbiddenKeys(d)).not.toThrow();
  });
  it("strict schema REJECTS a DTO that carries any extra (possibly private) key", () => {
    const d = { ...toPublicSupplier(row()), phone: "+000" };
    expect(publicSupplierSchema.safeParse(d).success).toBe(false);
  });
  it.each(FORBIDDEN_PUBLIC_KEYS)("tripwire rejects key %s at any depth", (k) => {
    expect(() => assertNoForbiddenKeys({ a: [{ b: { [k]: "x" } }] })).toThrow(/forbidden public key/);
  });
  it("label and flags must agree: Verified label needs isVerified, verified needs claimed", () => {
    expect(() => toPublicSupplier(row({ public_label: "Verified", is_verified: false }))).toThrow();
    expect(() => toPublicSupplier(row({ public_label: "Claimed — Not Verified", is_verified: true, is_claimed: true }))).toThrow();
    expect(() => toPublicSupplier(row({ public_label: "Verified", is_verified: true, is_claimed: false }))).toThrow();
    expect(toPublicSupplier(row({ public_label: "Verified", is_verified: true, is_claimed: true })).publicLabel).toBe("Verified");
  });
  it("unknown labels are rejected (client never invents a badge)", () => {
    expect(() => toPublicSupplier(row({ public_label: "Gold Verified" as never }))).toThrow();
  });
  it("website must be http(s): javascript:, data: and mailto: are refused", () => {
    for (const w of ["javascript:alert(1)", "data:text/html,x", "mailto:a@b.c", "tel:123"]) expect(() => toPublicSupplier(row({ website: w }))).toThrow();
    expect(toPublicSupplier(row({ website: "https://example.com" })).website).toBe("https://example.com");
  });
  it("the shipped demo data contains none of the forbidden keys", () => {
    expect(() => assertNoForbiddenKeys(SUPPLIERS)).not.toThrow();
  });
});
