import { vi } from "vitest";
vi.mock("next/navigation", () => ({ usePathname: () => "/suppliers", useRouter: () => ({ push: vi.fn() }) }));
