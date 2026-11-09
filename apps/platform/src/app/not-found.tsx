import { EmptyState } from "@/components/ui/States";
import { ButtonLink } from "@/components/ui/Button";
export default function NotFound() {
  return (
    <div className="container-page py-10">
      <EmptyState title="Page not found" action={<ButtonLink href="/suppliers">Browse suppliers</ButtonLink>}>
        The page you asked for does not exist in this prototype.
      </EmptyState>
    </div>
  );
}
