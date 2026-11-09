"use client";
import { Alert } from "@/components/ui/States";
import { Button } from "@/components/ui/Button";
export default function ErrorPage({ reset }: { error: Error; reset: () => void }) {
  // The error object is intentionally not rendered or logged here: it could contain user input.
  return (
    <div className="container-page space-y-4 py-10">
      <Alert tone="danger" alert title="Something went wrong">This page could not be displayed. Try again.</Alert>
      <Button onClick={reset}>Try again</Button>
    </div>
  );
}
