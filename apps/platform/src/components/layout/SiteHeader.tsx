"use client";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { useId, useState } from "react";
import type { Role } from "@/lib/domain";
import { navigationFor } from "@/lib/roles";
import { cn } from "@/lib/cn";

export function SiteHeader({ role = "anonymous" }: { role?: Role }) {
  const pathname = usePathname();
  const [open, setOpen] = useState(false);
  const menuId = useId();
  const items = navigationFor(role);
  const isCurrent = (href: string) => (href === "/" ? pathname === "/" : pathname === href || pathname.startsWith(href + "/"));

  return (
    <header className="border-b border-navy-800 bg-navy-900 text-white">
      <div className="container-page flex items-center justify-between gap-3 py-3">
        <Link href="/" className="text-lg font-extrabold tracking-tight text-white no-underline hover:text-white">
          GlobalTrade<span className="text-accent-100">B2B</span>
        </Link>
        <button
          type="button"
          className="inline-flex min-h-11 items-center rounded-md border border-white/40 px-3 text-sm font-semibold md:hidden"
          aria-expanded={open}
          aria-controls={menuId}
          onClick={() => setOpen((v) => !v)}
        >
          {open ? "Close menu" : "Menu"}
        </button>
        <nav id={menuId} aria-label="Main" className={cn("w-full md:w-auto", open ? "block" : "hidden", "md:block")}>
          <ul className="flex flex-col gap-1 pt-2 md:flex-row md:items-center md:gap-1 md:pt-0">
            {items.map((i) => (
              <li key={i.href}>
                <Link
                  href={i.href}
                  aria-current={isCurrent(i.href) ? "page" : undefined}
                  className={cn("block rounded-md px-3 py-2 text-sm font-semibold text-white no-underline hover:bg-navy-800 hover:text-white md:py-1.5", isCurrent(i.href) && "bg-navy-700")}
                >
                  {i.label}
                </Link>
              </li>
            ))}
            {role === "anonymous" ? (
              <li>
                <Link href="/login" aria-current={isCurrent("/login") ? "page" : undefined} className="block rounded-md border border-white/50 px-3 py-2 text-sm font-semibold text-white no-underline hover:bg-navy-800 hover:text-white md:py-1.5">
                  Sign in
                </Link>
              </li>
            ) : null}
          </ul>
        </nav>
      </div>
    </header>
  );
}
