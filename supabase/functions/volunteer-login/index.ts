import { handleLogin } from "../_shared/login.ts";
Deno.serve((req) => handleLogin(req, "volunteer"));