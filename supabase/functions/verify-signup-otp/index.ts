import { handleVerify } from "../_shared/otp.ts";

declare const Deno: {
  env: { get(name: string): string | undefined };
  serve(handler: (req: Request) => Response | Promise<Response>): void;
};

Deno.serve((req) => handleVerify(req, "signup"));