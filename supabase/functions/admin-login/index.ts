import { handleLogin } from "../_shared/login.ts";

declare const Deno: {
  env: { get(name: string): string | undefined };
  serve(handler: (req: Request) => Response | Promise<Response>): void;
};

Deno.serve((req) => handleLogin(req, "admin"));