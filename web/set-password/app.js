(() => {
  const cfg = window.SAHAYOGI_CONFIG;
  const $ = (id) => document.getElementById(id);
  const show = (id) => { for (const s of ["s-wait", "s-form", "s-done", "s-expired"]) $(s).hidden = s !== id; };

  const hash = new URLSearchParams(location.hash.replace(/^#/, ""));
  const urlError = hash.get("error_description") || new URLSearchParams(location.search).get("error_description");

  const sb = supabase.createClient(cfg.SUPABASE_URL, cfg.SUPABASE_ANON_KEY, {
    auth: { flowType: "implicit", detectSessionInUrl: true, persistSession: false, autoRefreshToken: false },
  });

  let ready = false;
  const onSession = (session) => {
    if (ready || !session) return;
    ready = true;
    $("who").textContent = session.user?.email ? `Choose a password for ${session.user.email}.` : "Choose a password for your account.";
    show("s-form");
    history.replaceState(null, "", location.pathname);
    $("pw").focus();
  };

  sb.auth.onAuthStateChange((event, session) => {
    if (event === "PASSWORD_RECOVERY" || event === "SIGNED_IN" || event === "INITIAL_SESSION") onSession(session);
  });

  setTimeout(async () => {
    if (ready) return;
    const { data } = await sb.auth.getSession();
    if (data.session) return onSession(data.session);
    if (urlError) $("exp-msg").textContent = urlError.replace(/\+/g, " ");
    show("s-expired");
  }, 1500);

  const checks = {
    len: (p) => p.length >= 10, low: (p) => /[a-z]/.test(p), up: (p) => /[A-Z]/.test(p),
    dig: (p) => /[0-9]/.test(p), sym: (p) => /[^A-Za-z0-9]/.test(p),
  };
  function validate() {
    const p = $("pw").value, p2 = $("pw2").value;
    let all = true;
    document.querySelectorAll("#rules li").forEach((li) => {
      const r = li.dataset.r;
      const okay = r === "match" ? p.length > 0 && p === p2 : checks[r](p);
      li.classList.toggle("ok", okay);
      if (!okay) all = false;
    });
    $("btn").disabled = !all;
  }
  $("pw").addEventListener("input", validate);
  $("pw2").addEventListener("input", validate);

  $("pw-form").addEventListener("submit", async (e) => {
    e.preventDefault();
    $("btn").disabled = true;
    $("form-msg").hidden = true;
    const { error } = await sb.auth.updateUser({ password: $("pw").value });
    if (error) {
      $("form-msg").textContent = error.message || "Could not save the password. Try again.";
      $("form-msg").hidden = false;
      $("btn").disabled = false;
      return;
    }
    await sb.auth.signOut(); 
    if (cfg.ADMIN_LOGIN_URL) { $("admin-href").href = cfg.ADMIN_LOGIN_URL; $("admin-link").hidden = false; }
    show("s-done");
  });

  $("reset-form").addEventListener("submit", async (e) => {
    e.preventDefault();
    $("reset-btn").disabled = true;
    try {
      const res = await fetch(`${cfg.SUPABASE_URL}/functions/v1/request-password-reset`, {
        method: "POST",
        headers: { "Content-Type": "application/json", apikey: cfg.SUPABASE_ANON_KEY },
        body: JSON.stringify({ email: $("email").value.trim() }),
      });
      const j = await res.json();
      $("reset-msg").className = "msg " + (res.ok ? "good" : "err");
      $("reset-msg").textContent = res.ok ? j.data.message : (j.error?.message || "Something went wrong.");
    } catch {
      $("reset-msg").className = "msg err";
      $("reset-msg").textContent = "Network error. Try again.";
    }
    $("reset-msg").hidden = false;
    $("reset-btn").disabled = false;
  });
})();