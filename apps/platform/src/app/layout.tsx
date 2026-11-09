import type { Metadata, Viewport } from "next";
import type { ReactNode } from "react";
import "./globals.css";
import { DemoBanner } from "@/components/layout/DemoBanner";
import { SiteHeader } from "@/components/layout/SiteHeader";
import { SiteFooter } from "@/components/layout/SiteFooter";

export const metadata: Metadata = {
  title: { default: "GlobalTradeB2B — prototype", template: "%s · GlobalTradeB2B (prototype)" },
  description: "Directory-first B2B marketplace — prototype with synthetic demonstration data.",
  robots: { index: false, follow: false },
};
export const viewport: Viewport = { width: "device-width", initialScale: 1 };

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="en">
      <body>
        <a className="skip-link" href="#main">Skip to main content</a>
        <DemoBanner />
        {/* No session exists, so the header always renders the anonymous navigation. */}
        <SiteHeader role="anonymous" />
        <main id="main" tabIndex={-1}>{children}</main>
        <SiteFooter />
      </body>
    </html>
  );
}
