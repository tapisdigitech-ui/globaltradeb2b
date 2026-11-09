import "./helpers";
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { RequirementForm } from "@/features/requirements/RequirementForm";
import { SupplierRegistrationForm } from "@/features/suppliers/SupplierRegistrationForm";
import { LoginForm } from "@/features/auth/LoginForm";
import { AccountForm } from "@/features/auth/AccountForm";
import { requirementSchema, validate, CONTACT_IN_TEXT } from "@/lib/validation";

describe("requirement form validation", () => {
  it("rejects an empty submit, flags fields, focuses the first invalid one", async () => {
    render(<RequirementForm />);
    await userEvent.click(screen.getByRole("button", { name: /preview requirement/i }));
    const product = screen.getByLabelText(/product or service needed/i);
    expect(product).toHaveAttribute("aria-invalid", "true");
    expect(product).toHaveFocus();
    expect(screen.getAllByRole("alert").length).toBeGreaterThanOrEqual(4);
    expect(screen.queryByText(/preview complete/i)).toBeNull();
  });
  it("rejects a bad phone number", async () => {
    render(<RequirementForm />);
    await userEvent.type(screen.getByLabelText(/mobile number/i), "abc");
    await userEvent.click(screen.getByRole("button", { name: /preview requirement/i }));
    expect(screen.getByText(/valid mobile number/i)).toBeInTheDocument();
  });
  it("valid input shows the preview notice (nothing sent) and clears the form", async () => {
    render(<RequirementForm />);
    await userEvent.type(screen.getByLabelText(/product or service needed/i), "Hand tufted rugs");
    await userEvent.type(screen.getByLabelText(/^quantity/i), "500 pieces");
    await userEvent.type(screen.getByLabelText(/delivery city/i), "Sample City");
    await userEvent.type(screen.getByLabelText(/your name/i), "Asha Rao");
    await userEvent.type(screen.getByLabelText(/mobile number/i), "+91 98765 43210");
    await userEvent.click(screen.getByRole("checkbox"));
    await userEvent.click(screen.getByRole("button", { name: /preview requirement/i }));
    expect(screen.getByText(/preview complete/i)).toBeInTheDocument();
    expect(screen.getByLabelText(/mobile number/i)).toHaveValue("");
    expect(screen.getByLabelText(/your name/i)).toHaveValue("");
  });
  it("persists nothing in browser storage", async () => {
    localStorage.clear(); sessionStorage.clear();
    render(<RequirementForm />);
    await userEvent.type(screen.getByLabelText(/your name/i), "Asha Rao");
    await userEvent.click(screen.getByRole("button", { name: /preview requirement/i }));
    expect(localStorage.length).toBe(0); expect(sessionStorage.length).toBe(0); expect(document.cookie).toBe("");
  });
});

describe("other forms", () => {
  it("supplier registration requires fields and consent", async () => {
    render(<SupplierRegistrationForm />);
    await userEvent.click(screen.getByRole("button", { name: /preview registration/i }));
    expect(screen.getByLabelText(/company name/i)).toHaveAttribute("aria-invalid", "true");
    expect(screen.getByText("Please confirm consent to proceed.")).toBeInTheDocument();
  });
  it("login does not create a session and says so", async () => {
    render(<LoginForm />);
    await userEvent.type(screen.getByLabelText(/email/i), "not-an-email");
    await userEvent.click(screen.getByRole("button", { name: /sign in/i }));
    expect(screen.getByText(/does not look right/i)).toBeInTheDocument();
    await userEvent.clear(screen.getByLabelText(/email/i));
    await userEvent.type(screen.getByLabelText(/email/i), "a@example.com");
    await userEvent.type(screen.getByLabelText(/^password/i), "x");
    await userEvent.click(screen.getByRole("button", { name: /sign in/i }));
    expect(screen.getByText(/no session was created/i)).toBeInTheDocument();
  });
  it("account form enforces 12-char password and matching confirmation", async () => {
    render(<AccountForm />);
    await userEvent.type(screen.getByLabelText(/full name/i), "Asha Rao");
    await userEvent.type(screen.getByLabelText(/^email/i), "a@example.com");
    await userEvent.type(screen.getByLabelText(/^password/i), "short");
    await userEvent.type(screen.getByLabelText(/confirm password/i), "different");
    await userEvent.click(screen.getByRole("button", { name: /create account/i }));
    expect(screen.getByText(/at least 12 characters/i, { selector: "p[role=alert]" })).toBeInTheDocument();
    expect(screen.getByText(/do not match/i)).toBeInTheDocument();
  });
  it("account form never offers a role choice", () => {
    render(<AccountForm />);
    expect(screen.queryByLabelText(/role|account type|admin|seller/i)).toBeNull();
  });
});

describe("schema helpers", () => {
  it("requirement schema returns first message per field", () => {
    const r = validate(requirementSchema, {});
    expect(r.ok).toBe(false);
    if (!r.ok) expect(Object.keys(r.errors)).toEqual(expect.arrayContaining(["product", "quantity", "destination", "buyerName", "buyerPhone", "consent"]));
  });
  it("contact-in-text heuristic spots phone numbers and emails", () => {
    expect(CONTACT_IN_TEXT.test("call me on +91 98765 43210")).toBe(true);
    expect(CONTACT_IN_TEXT.test("write to a@b.com")).toBe(true);
    expect(CONTACT_IN_TEXT.test("500 pieces, 8x10 ft")).toBe(false);
  });
});
