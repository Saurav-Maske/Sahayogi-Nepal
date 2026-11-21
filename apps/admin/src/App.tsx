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
import NotificationsPage from "./pages/NotificationsPage";
import SettingsPage from "./pages/SettingsPage";
import InventoryPage from "./pages/InventoryPage";
import InventoryDetailPage from "./pages/InventoryDetailPage";
import InventoryMovementPage from "./pages/InventoryMovementPage";
import InventoryTimelinePage from "./pages/InventoryTimelinePage";
import InventoryMovementDetailPage from "./pages/InventoryMovementDetailPage";

// Swap each PlaceholderPage for the real page as you build it.
const PAGES: [path: string, title: string][] = [
  ["volunteers", "Volunteer Management"],
  ["map", "Live Map"],
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
          <Route path="notifications" element={<NotificationsPage />} />
          <Route path="settings" element={<SettingsPage />} />
          <Route path="inventory" element={<InventoryPage />} />
          <Route path="inventory/timeline" element={<InventoryTimelinePage />} />
          <Route path="inventory/movement/new" element={<InventoryMovementPage />} />
          <Route path="inventory/movements/:movementId" element={<InventoryMovementDetailPage />} />
          <Route path="inventory/:id" element={<InventoryDetailPage />} />
          {PAGES.map(([path, title]) => (
            <Route key={path} path={path} element={<PlaceholderPage title={title} />} />
          ))}
          <Route path="*" element={<PlaceholderPage title="Page not found" />} />
        </Route>
      </Route>
    </Routes>
  );
}
