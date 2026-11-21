import { useEffect, useState } from "react";
import { Route, Routes } from "react-router-dom";
import { supabase } from "./supabase";
import RequireAdmin from "./components/RequireAdmin";
import AdminLayout from "./layouts/AdminLayout";
import AnalyticsPage from "./pages/AnalyticsPage";
import DashboardPage from "./pages/DashboardPage";
import LoginPage from "./pages/LoginPage";
import PlaceholderPage from "./pages/PlaceholderPage";

// Temporary review queue at /requests. Move it into pages/ when you build that page.
function ReviewQueue() {
  const [rows, setRows] = useState<any[]>([]);
  const [err, setErr] = useState<string | null>(null);
  useEffect(() => {
    supabase
      .from("requests")
      .select("public_ref, kind, status, districts(name), created_at")
      .order("created_at", { ascending: false })
      .then(({ data, error }) => (error ? setErr(error.message) : setRows(data ?? [])));
  }, []);
  return (
    <div className="card">
      <h2 className="card__title">Review queue</h2>
      {err && <p className="empty">⚠ {err}</p>}
      {!err && rows.length === 0 && <p className="empty">No requests yet.</p>}
      <ul>
        {rows.map((r) => (
          <li key={r.public_ref}>
            {r.public_ref} · {r.kind} · {(r.districts as any)?.name ?? "—"} · {r.status}
          </li>
        ))}
      </ul>
    </div>
  );
}

// Swap each PlaceholderPage for the real page as you build it.
const PAGES: [path: string, title: string][] = [
  ["donations", "Donations"],
  ["volunteers", "Volunteer Management"],
  ["assignments", "Assignments"],
  ["inventory", "Central Inventory"],
  ["map", "Live Map"],
  ["incidents", "Incidents & Reports"],
  ["notifications", "Notifications"],
  ["settings", "Settings"],
];

export default function App() {
  return (
    <Routes>
      <Route path="/login" element={<LoginPage />} />

      <Route element={<RequireAdmin />}>
        <Route element={<AdminLayout />}>
          <Route index element={<DashboardPage />} />
          <Route path="analytics" element={<AnalyticsPage />} />
          <Route path="requests" element={<ReviewQueue />} />
          {PAGES.map(([path, title]) => (
            <Route key={path} path={path} element={<PlaceholderPage title={title} />} />
          ))}
          <Route path="*" element={<PlaceholderPage title="Page not found" />} />
        </Route>
      </Route>
    </Routes>
  );
}