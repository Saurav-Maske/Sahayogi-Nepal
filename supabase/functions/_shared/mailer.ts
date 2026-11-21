// Deno resolves this URL at runtime. The editor's TypeScript server cannot (TS2307), so the check is skipped for this one line.
// @ts-ignore
import { SMTPClient } from "https://deno.land/x/denomailer@1.6.0/mod.ts";

declare const Deno: {
  env: { get(name: string): string | undefined };
  serve(handler: (req: Request) => Response | Promise<Response>): void;
};

export type OtpPurpose = "signup" | "reset";

const COPY: Record<OtpPurpose, { subject: string; lead: string }> = {
  signup: {
    subject: "Your Sahayogi Nepal verification code",
    lead: "Use this code to verify your email and continue your volunteer application.",
  },
  reset: {
    subject: "Your Sahayogi Nepal password reset code",
    lead: "Use this code to reset your password.",
  },
};

// Sends the 6-digit code through Gmail SMTP (port 465, TLS). Returns false if it could not be sent.
// Local development without SMTP: set OTP_DEV_LOG=true and read the code in the `functions serve` terminal.
export async function sendOtpEmail(to: string, code: string, purpose: OtpPurpose, ttlMin: number): Promise<boolean> {
  const user = Deno.env.get("GMAIL_ADDRESS");
  const pass = Deno.env.get("GMAIL_APP_PASSWORD");

  if (!user || !pass) {
    if (Deno.env.get("OTP_DEV_LOG") === "true") {
      console.log(`[OTP_DEV_LOG] ${purpose} code for ${to}: ${code}`);
      return true;
    }
    console.error("sendOtpEmail: GMAIL_ADDRESS / GMAIL_APP_PASSWORD not set");
    return false;
  }

  const { subject, lead } = COPY[purpose];
  const html = `<div style="font-family:Arial,Helvetica,sans-serif;max-width:480px;margin:0 auto;padding:24px;color:#1b1b1b">
  <h2 style="margin:0 0 12px;color:#b3261e">Sahayogi Nepal</h2>
  <p>${lead}</p>
  <p style="margin:24px 0;font-size:32px;letter-spacing:8px;font-weight:bold">${code}</p>
  <p style="font-size:13px;color:#555">The code expires in ${ttlMin} minutes and works once. Never share it with anyone.
     If you did not ask for it, ignore this email.</p>
</div>`;
  const text = `${lead}\n\nYour code: ${code}\n\nIt expires in ${ttlMin} minutes. If you did not ask for it, ignore this email.`;

  const client = new SMTPClient({
    connection: {
      hostname: Deno.env.get("SMTP_HOST") ?? "smtp.gmail.com",
      port: Number(Deno.env.get("SMTP_PORT") ?? "465"),
      tls: true,
      auth: { username: user, password: pass },
    },
  });
  try {
    await client.send({
      from: `${Deno.env.get("MAIL_FROM_NAME") ?? "Sahayogi Nepal"} <${user}>`,
      to,
      subject,
      content: text,
      html,
    });
    return true;
  } catch (e) {
    console.error("sendOtpEmail failed:", (e as Error).message);
    return false;
  } finally {
    try { await client.close(); } catch { /* ignore */ }
  }
}