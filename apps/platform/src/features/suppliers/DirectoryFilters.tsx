import { CATEGORIES } from "@/data/demo";
import { VERIFICATION_LABELS } from "@/lib/domain";
import { Button, ButtonLink } from "@/components/ui/Button";
import { SelectField, TextField } from "@/components/ui/Field";

/** Plain GET form: works without JavaScript, state lives in the URL (never put personal data in it). */
export function DirectoryFilters({ q, category, label }: { q: string; category: string; label: string }) {
  return (
    <form method="get" action="/suppliers" role="search" aria-label="Filter suppliers" className="grid gap-3 rounded-lg border border-line bg-surface p-4 sm:grid-cols-2 lg:grid-cols-[2fr_2fr_2fr_auto] lg:items-end">
      <TextField label="Search by name or product" name="q" defaultValue={q} maxLength={80} />
      <SelectField label="Category" name="category" defaultValue={category}>
        <option value="">All categories</option>
        {CATEGORIES.map((c) => <option key={c.slug} value={c.slug}>{c.name}</option>)}
      </SelectField>
      <SelectField label="Verification status" name="label" defaultValue={label}>
        <option value="">Any status</option>
        {VERIFICATION_LABELS.map((l) => <option key={l} value={l}>{l}</option>)}
      </SelectField>
      <div className="flex gap-2">
        <Button type="submit">Apply</Button>
        <ButtonLink href="/suppliers" variant="secondary">Reset</ButtonLink>
      </div>
    </form>
  );
}
