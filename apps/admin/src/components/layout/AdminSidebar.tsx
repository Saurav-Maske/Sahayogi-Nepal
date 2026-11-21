import { NavLink } from 'react-router-dom';

export const NAV_ITEMS = [
  { to: '/', label: 'Overview', end: true },
  { to: '/requests', label: 'Requests' },
  { to: '/donations', label: 'Donations' },
  { to: '/volunteers', label: 'Volunteer Management' },
  { to: '/assignments', label: 'Assignments' },
  { to: '/inventory', label: 'Central Inventory' },
  { to: '/map', label: 'Live Map' },
  { to: '/incidents', label: 'Incidents & Reports' },
  { to: '/analytics', label: 'Analytics' },
  { to: '/notifications', label: 'Notifications' },
  { to: '/settings', label: 'Settings' },
];

interface Props {
  open: boolean;
  onNavigate: () => void;
}

export default function AdminSidebar({ open, onNavigate }: Props) {
  return (
    <aside className={`sidebar ${open ? 'sidebar--open' : ''}`} aria-label="Admin navigation">
      <div className="sidebar__brand">
        <div className="sidebar__name">SAHAYOGI NEPAL</div>
        <div className="sidebar__console">OPERATIONS CONSOLE</div>
      </div>
      <nav className="sidebar__nav">
        {NAV_ITEMS.map((item) => (
          <NavLink
            key={item.to}
            to={item.to}
            end={item.end}
            onClick={onNavigate}
            className={({ isActive }) => `sidebar__link ${isActive ? 'sidebar__link--active' : ''}`}
          >
            {item.label}
          </NavLink>
        ))}
      </nav>
      <p className="sidebar__tagline">Support that reaches further.</p>
    </aside>
  );
}
