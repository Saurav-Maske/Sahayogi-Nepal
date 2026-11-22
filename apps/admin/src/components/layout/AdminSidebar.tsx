import { NavLink } from 'react-router-dom';

export const NAV_ITEMS = [
  { to: '/', label: 'Overview', icon: 'overview', end: true },
  { to: '/requests', label: 'Requests', icon: 'requests' },
  { to: '/donations', label: 'Donations', icon: 'donations' },
  { to: '/volunteers', label: 'Volunteer Management', icon: 'volunteers' },
  { to: '/assignments', label: 'Assignments', icon: 'assignments' },
  { to: '/inventory', label: 'Central Inventory', icon: 'inventory' },
  { to: '/map', label: 'Live Map', icon: 'map' },
  { to: '/incidents', label: 'Incidents & Reports', icon: 'incidents' },
  { to: '/analytics', label: 'Analytics', icon: 'analytics' },
  { to: '/notifications', label: 'Notifications', icon: 'notifications' },
  { to: '/settings', label: 'Settings', icon: 'settings' },
];

const ICON_PATHS: Record<string, string[]> = {
  overview: ['M3 10.5 12 3l9 7.5', 'M5 9.5V21h14V9.5', 'M9 21v-6h6v6'],
  requests: ['M6 3.5h8l4 4V20a1 1 0 0 1-1 1H6a1 1 0 0 1-1-1V4.5a1 1 0 0 1 1-1Z', 'M14 3.5V8h4', 'M8.5 12h7', 'M8.5 16h7'],
  donations: ['M4 6.5h16v13H4z', 'M4 8l8 5 8-5', 'M7 4h10'],
  volunteers: ['M16 20v-1.5a4 4 0 0 0-4-4H7a4 4 0 0 0-4 4V20', 'M9.5 11a3.5 3.5 0 1 0 0-7 3.5 3.5 0 0 0 0 7Z', 'M17 4.5a3.5 3.5 0 0 1 0 6.8', 'M18 14.5a4 4 0 0 1 3 4V20'],
  assignments: ['M8 4h8', 'M9 3h6a1 1 0 0 1 1 1v2H8V4a1 1 0 0 1 1-1Z', 'M6 5H4v16h16V5h-2', 'M8 12h8', 'M8 16h5'],
  inventory: ['m12 3 9 5-9 5-9-5 9-5Z', 'm3 8 9 5 9-5', 'M3 8v9l9 5 9-5V8', 'M12 13v9'],
  map: ['M20 10c0 5-8 11-8 11S4 15 4 10a8 8 0 1 1 16 0Z', 'M12 10a2.5 2.5 0 1 0 0-5 2.5 2.5 0 0 0 0 5Z'],
  incidents: ['M12 3 22 21H2L12 3Z', 'M12 9v5', 'M12 17.5h.01'],
  analytics: ['M4 20V11', 'M10 20V5', 'M16 20v-8', 'M22 20H2'],
  notifications: ['M18 9a6 6 0 0 0-12 0c0 7-3 7-3 9h18c0-2-3-2-3-9', 'M10 21h4'],
  settings: ['M12 8.5a3.5 3.5 0 1 0 0 7 3.5 3.5 0 0 0 0-7Z', 'm19.4 15 .1.1 1.1.9-1.4 2.4-1.4-.5a7.6 7.6 0 0 1-1.7 1l-.2 1.5h-2.8l-.2-1.5a7.6 7.6 0 0 1-1.7-1l-1.4.5-1.4-2.4 1.1-.9a7.4 7.4 0 0 1 0-2l-1.1-.9 1.4-2.4 1.4.5a7.6 7.6 0 0 1 1.7-1l.2-1.5h2.8l.2 1.5a7.6 7.6 0 0 1 1.7 1l1.4-.5 1.4 2.4-1.1.9a7.4 7.4 0 0 1-.1 1.9Z'],
};

function SidebarIcon({ name }: { name: string }) {
  return <svg className="sidebar__icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
    {ICON_PATHS[name].map((path) => <path key={path} d={path} />)}
  </svg>;
}

export default function AdminSidebar() {
  return (
    <aside className="sidebar" aria-label="Admin navigation">
      <div className="sidebar__brand">
        <img className="sidebar__logo" src={`${import.meta.env.BASE_URL}images/VerticalLogo.svg`} alt="Sahayogi Nepal" />
        <div className="sidebar__console">OPERATIONS CONSOLE</div>
      </div>
      <nav className="sidebar__nav">
        {NAV_ITEMS.map((item) => (
          <NavLink
            key={item.to}
            to={item.to}
            end={item.end}
            className={({ isActive }) => `sidebar__link ${isActive ? 'sidebar__link--active' : ''}`}
          >
            <SidebarIcon name={item.icon} />
            <span>{item.label}</span>
          </NavLink>
        ))}
      </nav>
      <p className="sidebar__tagline">Support that reaches further.</p>
    </aside>
  );
}
