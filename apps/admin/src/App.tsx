import { Route, Routes } from 'react-router-dom';
import AdminLayout from './layouts/AdminLayout';
import DashboardPage from './pages/DashboardPage';
import PlaceholderPage from './pages/PlaceholderPage';

// Swap each PlaceholderPage for the real page as it gets built.
const PAGES: [path: string, title: string][] = [
  ['requests', 'Requests'],
  ['donations', 'Donations'],
  ['volunteers', 'Volunteer Management'],
  ['assignments', 'Assignments'],
  ['inventory', 'Central Inventory'],
  ['map', 'Live Map'],
  ['incidents', 'Incidents & Reports'],
  ['analytics', 'Analytics'],
  ['notifications', 'Notifications'],
  ['settings', 'Settings'],
];

export default function App() {
  return (
    <Routes>
      <Route element={<AdminLayout />}>
        <Route index element={<DashboardPage />} />
        {PAGES.map(([path, title]) => (
          <Route key={path} path={path} element={<PlaceholderPage title={title} />} />
        ))}
        <Route path="*" element={<PlaceholderPage title="Page not found" />} />
      </Route>
    </Routes>
  );
}