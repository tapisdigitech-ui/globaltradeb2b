import { readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";
import * as enums from "@/contracts/enums";

// Reads the SQL migrations as TEXT (never executes them). Fails when an enum in SQL and its TypeScript twin diverge.
const dir = join(process.cwd(), "..", "..", "supabase", "migrations");
const sql = readdirSync(dir).filter((f) => f.endsWith(".sql")).sort().map((f) => readFileSync(join(dir, f), "utf8")).join("\n");

function sqlEnum(name: string): string[] {
  const m = new RegExp(`create type public\\.${name} as enum \\(([^)]*)\\)`, "i").exec(sql);
  if (!m) throw new Error(`enum ${name} not found in migrations`);
  return [...m[1]!.matchAll(/'([^']+)'/g)].map((x) => x[1]!);
}

describe("TypeScript enums match the SQL enums", () => {
  const pairs: [string, readonly string[]][] = [
    ["app_role", enums.APP_ROLES], ["member_role", enums.MEMBER_ROLES], ["member_status", enums.MEMBER_STATUSES],
    ["claim_status", enums.CLAIM_STATUSES], ["verification_status", enums.VERIFICATION_STATUSES], ["directory_status", enums.DIRECTORY_STATUSES],
    ["enquiry_kind", enums.ENQUIRY_KINDS], ["enquiry_delivery", enums.ENQUIRY_DELIVERIES], ["lead_status", enums.LEAD_STATUSES], ["match_route", enums.MATCH_ROUTES],
  ];
  it.each(pairs)("%s", (name, ts) => { expect([...ts]).toEqual(sqlEnum(name)); });

  it("lead_cases.queue check constraint matches LEAD_QUEUES", () => {
    const m = /queue text not null check \(queue in \(([^)]*)\)\)/.exec(sql)!;
    expect([...m[1]!.matchAll(/'([^']+)'/g)].map((x) => x[1])).toEqual([...enums.LEAD_QUEUES]);
  });
  it("public_companies view produces exactly the five public labels", () => {
    const view = /create view public\.public_companies[\s\S]*?END AS public_label/.exec(sql)![0];
    const labels = [...view.matchAll(/THEN '([^']+)'::text/g)].map((x) => x[1]!);
    const elseLabel = /ELSE '([^']+)'::text/.exec(view)![1]!;
    expect(new Set([...labels, elseLabel])).toEqual(new Set(enums.PUBLIC_LABELS));
  });
});
