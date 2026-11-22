(() => {
  const cfg = window.SAHAYOGI_CONFIG;
  const $ = (id) => document.getElementById(id);
  const SCREENS = ["s-wait", "s-form", "s-done", "s-email", "s-code"];
  const show = (id) => { for (const s of SCREENS) $(s).hidden = s !== id; };
  const say = (id, text, good = false) => { const el = $(id); el.className = "msg " + (good ? "good" : "err"); el.textContent = text; el.hidden = false; };

  // mode "link": the person came from the invite email link and already holds a Supabase session.
  // mode "otp":  the person proved the email with a 6-digit code and holds a one-time reset_token.
  let mode = null;
  let otpEmail = "";
  let resetToken = "";

  const call = async (fn, body) => {
    const res = await fetch(`${cfg.SUPABASE_URL}/functions/v1/${fn}`, {
      method: "POST",
      headers: { "Content-Type": "application/json", apikey: cfg.SUPABASE_ANON_KEY },
      body: JSON.stringify(body),
    });
    let j = null;
    try { j = await res.json(); } catch { /* not JSON */ }
    return { ok: res.ok, data: j?.data ?? null, error: j?.error ?? { code: "network", message: "Something went wrong. Try again." } };
  };

  const hash = new URLSearchParams(location.hash.replace(/^#/, ""));
  const urlError = hash.get("error_description") || new URLSearchParams(location.search).get("error_description");

  const sb = supabase.createClient(cfg.SUPABASE_URL, cfg.SUPABASE_ANON_KEY, {
    auth: { flowType: "implicit", detectSessionInUrl: true, persistSession: false, autoRefreshToken: false },
  });

  // ---- invite link (set password) -------------------------------------------------------------
  let ready = false;
  const onSession = (session) => {
    if (ready || !session) return;
    ready = true;
    mode = "link";
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
    if (urlError) { $("exp-msg").textContent = urlError.replace(/\+/g, " "); $("exp-msg").hidden = false; }
    show("s-email");
  }, 1500);

  // ---- password rules (shared by both modes) --------------------------------------------------
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

  const finish = async () => {
    if (cfg.ADMIN_LOGIN_URL) { $("admin-href").href = cfg.ADMIN_LOGIN_URL; $("admin-link").hidden = false; }
    show("s-done");
  };

  $("pw-form").addEventListener("submit", async (e) => {
    e.preventDefault();
    $("btn").disabled = true;
    $("form-msg").hidden = true;

    if (mode === "otp") {
      const r = await call("reset-password", { email: otpEmail, reset_token: resetToken, new_password: $("pw").value });
      if (!r.ok) {
        if (r.error.code === "invalid_token") { // the 10-minute window ran out: start again
          resetToken = ""; $("pw").value = ""; $("pw2").value = "";
          show("s-email");
          say("email-msg", r.error.message);
          return;
        }
        say("form-msg", r.error.message || "Could not save the password. Try again.");
        validate();
        return;
      }
      resetToken = "";
      return finish();
    }

    const { error } = await sb.auth.updateUser({ password: $("pw").value });
    if (error) {
      say("form-msg", error.message || "Could not save the password. Try again.");
      validate();
      return;
    }
    await sb.auth.signOut();
    finish();
  });

  // ---- forgot password / expired link: email -> code -> new password --------------------------
  let cooldownTimer = null;
  function startCooldown(seconds) {
    clearInterval(cooldownTimer);
    let left = seconds;
    const btn = $("resend-btn");
    const tick = () => {
      btn.disabled = left > 0;
      btn.textContent = left > 0 ? `Resend code in ${left}s` : "Resend code";
      left -= 1;
      if (left < -1) clearInterval(cooldownTimer);
    };
    tick();
    cooldownTimer = setInterval(tick, 1000);
  }

  async function sendCode(email) {
    const r = await call("request-password-reset", { email });
    if (r.ok) {
      otpEmail = email;
      $("code-who").textContent = `If ${email} has an account, we sent a 6-digit code to it. It works for 10 minutes.`;
      $("code-msg").hidden = true;
      $("otp").value = "";
      show("s-code");
      startCooldown(r.data?.resend_after ?? 60);
      $("otp").focus();
    }
    return r;
  }

  $("email-form").addEventListener("submit", async (e) => {
    e.preventDefault();
    $("email-btn").disabled = true;
    $("email-msg").hidden = true;
    const r = await sendCode($("email").value.trim().toLowerCase());
    if (!r.ok) say("email-msg", r.error.message);
    $("email-btn").disabled = false;
  });

  $("resend-btn").addEventListener("click", async () => {
    $("resend-btn").disabled = true;
    const r = await sendCode(otpEmail);
    if (!r.ok) { say("code-msg", r.error.message); startCooldown(30); }
    else say("code-msg", "A new code was sent.", true);
  });

  $("change-email").addEventListener("click", (e) => {
    e.preventDefault();
    clearInterval(cooldownTimer);
    show("s-email");
  });

  $("code-form").addEventListener("submit", async (e) => {
    e.preventDefault();
    $("code-btn").disabled = true;
    $("code-msg").hidden = true;
    const r = await call("verify-reset-otp", { email: otpEmail, otp: $("otp").value.trim() });
    $("code-btn").disabled = false;
    if (!r.ok) {
      const left = r.error.attempts_left;
      say("code-msg", left !== undefined ? `${r.error.message} ${left} ${left === 1 ? "try" : "tries"} left.` : r.error.message);
      return;
    }
    mode = "otp";
    resetToken = r.data.reset_token;
    clearInterval(cooldownTimer);
    $("who").textContent = `Choose a new password for ${otpEmail}.`;
    $("pw").value = ""; $("pw2").value = "";
    validate();
    show("s-form");
    $("pw").focus();
  });
})();