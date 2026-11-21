import { useEffect, useState } from "react";
import { NavLink, Route, Routes } from "react-router-dom";
import { supabase } from "./supabase";

// Person 3: replace placeholders. Build against mock data until endpoints in docs/API-CONTRACT.md are live.
const Page = ({ title }: { title: string }) => <h2>{title} <small>(TODO)</small></h2>;

function ReviewQueue() {
  const [rows, setRows] = useState<any[]>([]);
  const [err, setErr] = useState<string | null>(null);
  useEffect(() => {
    supabase.from("requests").select("public_ref, kind, status, district, created_at").order("created_at", { ascending: false })
      .then(({ data, error }) => (error ? setErr(error.message) : setRows(data ?? [])));
  }, []);
  return (<div><h2>Review queue</h2>
    {err && <p>⚠ {err}</p>}
    {!err && rows.length === 0 && <p>No rows. RLS returns nothing until you sign in as an admin (auth UI is a TODO for Person 3).</p>}
    <ul>{rows.map(r => <li key={r.public_ref}>{r.public_ref} · {r.kind} · {r.district} · {r.status}</li>)}</ul></div>);
}

export default function App() {
  return (
    <div style={{ fontFamily: "system-ui", display: "flex", minHeight: "100vh" }}>
      <nav style={{ width: 200, padding: 16, borderRight: "1px solid #ddd", display: "flex", flexDirection: "column", gap: 8 }}>
        <strong>Sahayogi Admin</strong>
        <NavLink to="/">Review queue</NavLink>
        <NavLink to="/volunteers">Volunteers</NavLink>
        <NavLink to="/inventory">Inventory</NavLink>
        <NavLink to="/assignments">Assignments</NavLink>
        <NavLink to="/incidents">Incidents</NavLink>
      </nav>
      <main style={{ padding: 24, flex: 1 }}>
        <Routes>
          <Route path="/" element={<ReviewQueue />} />
          <Route path="/volunteers" element={<Page title="Volunteer applications" />} />
          <Route path="/inventory" element={<Page title="Inventory board: Received · Processing · Ready to Ship" />} />
          <Route path="/assignments" element={<Page title="Assignment board" />} />
          <Route path="/incidents" element={<Page title="Incidents" />} />
        </Routes>
      </main>
    </div>
  );
}
