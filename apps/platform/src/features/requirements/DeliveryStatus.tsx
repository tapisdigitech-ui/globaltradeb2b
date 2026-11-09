import type { DeliveryState } from "@/lib/domain";
import { DELIVERY_COPY } from "@/lib/labels";
import { Alert } from "@/components/ui/States";

/** Shows the server-defined wording for a delivery state. Never claims receipt. */
export function DeliveryStatus({ state }: { state: DeliveryState }) {
  const c = DELIVERY_COPY[state];
  return <Alert tone="info" title={c.title}>{c.body}</Alert>;
}
