import type { Metadata } from "next";
import { AccountForm } from "@/features/auth/AccountForm";
import { Alert, Card } from "@/components/ui/States";

export const metadata: Metadata = { title: "Create account" };

export default function RegisterPage() {
  return (
    <div className="container-page mx-auto max-w-md py-8">
      <h1>Create an account</h1>
      <div className="my-4"><Alert tone="warning" title="Not connected">Authentication has not been built yet. This form checks your input and discards it.</Alert></div>
      <Card><AccountForm /></Card>
    </div>
  );
}
