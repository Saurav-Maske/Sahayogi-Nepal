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
import VolunteersPage from "./pages/VolunteerPage";
import VolunteerProfilePage from "./pages/VolunteerProfilePage";
import AssignmentsPage from "./pages/AssignmentsPage";
import AssignmentDetailPage from "./pages/AssignmentDetailPage";
import IncidentsPage from "./pages/IncidentsPage";
import IncidentDetailPage from "./pages/IncidentDetailPage";

// Swap each PlaceholderPage for the real page as you build it.
const PAGES: [path: string, title: string][] = [
  ["volunteers", "Volunteer Management"],
  ["inventory", "Central Inventory"],
  ["map", "Live Map"],
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
          <Route path="volunteers" element={<VolunteersPage />} />
          <Route path="volunteers/:id" element={<VolunteerProfilePage />} />
          <Route path="assignments" element={<AssignmentsPage />} />
          <Route path="assignments/:id" element={<AssignmentDetailPage />} />
          <Route path="incidents" element={<IncidentsPage />} />
          <Route path="incidents/:id" element={<IncidentDetailPage />} />
          {PAGES.map(([path, title]) => (
            <Route key={path} path={path} element={<PlaceholderPage title={title} />} />
          ))}
          <Route path="*" element={<PlaceholderPage title="Page not found" />} />
        </Route>
      </Route>
    </Routes>
  );
}
