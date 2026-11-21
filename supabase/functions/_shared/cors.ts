export const corsHeaders = {
  "Access-Control-Allow-Origin": "*", // tighten to known origins before any real deployment
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};
export const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, "Content-Type": "application/json" } });
export const ok = (data: unknown, status = 200) => json({ data, error: null }, status);
export const fail = (code: string, message: string, status = 400) => json({ data: null, error: { code, message } }, status);
