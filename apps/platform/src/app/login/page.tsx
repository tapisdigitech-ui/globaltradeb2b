import type { Metadata } from "next";
import { LoginForm } from "@/features/auth/LoginForm";
import { Alert, Card } from "@/components/ui/States";

export const metadata: Metadata = { title: "Sign in" };

export default function LoginPage() {
  return (
    <div className="container-page mx-auto max-w-md py-8">
      <h1>Sign in</h1>
      <div className="my-4"><Alert tone="warning" title="Not connected">Authentication has not been built yet. This form checks your input and discards it.</Alert></div>
      <Card><LoginForm /></Card>
    </div>
  );
}
