import { Route, Routes } from "react-router-dom";
import RequireAdmin from "./components/RequireAdmin";
import AdminLayout from "./layouts/AdminLayout";
import AnalyticsPage from "./pages/AnalyticsPage";
import DashboardPage from "./pages/DashboardPage";
import LoginPage from "./pages/LoginPage";
import PlaceholderPage from "./pages/PlaceholderPage";
import RequestsPage from "./pages/RequestPage";
import RequestReviewPage from "./pages/RequestReviewPage";
import DonationsPage from "./pages/DonationsPage";
import DonationDetailPage from "./pages/DonationDetailPage";

// Swap each PlaceholderPage for the real page as you build it.
const PAGES: [path: string, title: string][] = [
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
          <Route path="requests" element={<RequestsPage />} />
          <Route path="requests/:id" element={<RequestReviewPage />} />
          <Route path="donations" element={<DonationsPage />} />
          <Route path="donations/:id" element={<DonationDetailPage />} />
          {PAGES.map(([path, title]) => (
            <Route key={path} path={path} element={<PlaceholderPage title={title} />} />
          ))}
          <Route path="*" element={<PlaceholderPage title="Page not found" />} />
        </Route>
      </Route>
    </Routes>
  );
}