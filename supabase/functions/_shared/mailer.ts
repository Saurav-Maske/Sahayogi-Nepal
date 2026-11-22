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

// Sends the 6-digit code through the Resend HTTP API. Returns false if it could not be sent.
// Local development without Resend: set OTP_DEV_LOG=true and read the code in the `functions serve` terminal.
export async function sendOtpEmail(to: string, code: string, purpose: OtpPurpose, ttlMin: number): Promise<boolean> {
  const apiKey = Deno.env.get("RESEND_API_KEY");
  const fromAddress = Deno.env.get("MAIL_FROM_ADDRESS");

  if (!apiKey || !fromAddress) {
    if (Deno.env.get("OTP_DEV_LOG") === "true") {
      console.log(`[OTP_DEV_LOG] ${purpose} code for ${to}: ${code}`);
      return true;
    }
    console.error("sendOtpEmail: RESEND_API_KEY / MAIL_FROM_ADDRESS not set");
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

  try {
    const res = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        from: `${Deno.env.get("MAIL_FROM_NAME") ?? "Sahayogi Nepal"} <${fromAddress}>`,
        to: [to],
        subject,
        html,
        text,
      }),
      signal: AbortSignal.timeout(10_000),
    });
    if (!res.ok) {
      console.error("sendOtpEmail failed:", res.status, await res.text());
      return false;
    }
    return true;
  } catch (e) {
    console.error("sendOtpEmail failed:", (e as Error).message);
    return false;
  }
}