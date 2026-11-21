import { useEffect, useRef, useState } from 'react';
import { Link } from 'react-router-dom';

const ACTIONS = [
  { to: '/requests?review=pending', label: 'Review pending requests' },
  { to: '/volunteers?tab=applications', label: 'Review volunteer applications' },
  { to: '/inventory?action=add', label: 'Add inventory' },
  { to: '/assignments?action=new', label: 'Create assignment' },
  { to: '/incidents', label: 'Investigate an incident' },
];

export default function QuickAction() {
  const [open, setOpen] = useState(false);
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!open) return;
    const onDown = (e: MouseEvent) => !ref.current?.contains(e.target as Node) && setOpen(false);
    const onKey = (e: KeyboardEvent) => e.key === 'Escape' && setOpen(false);
    document.addEventListener('mousedown', onDown);
    document.addEventListener('keydown', onKey);
    return () => {
      document.removeEventListener('mousedown', onDown);
      document.removeEventListener('keydown', onKey);
    };
  }, [open]);

  return (
    <div className="quick" ref={ref}>
      <button className="btn" aria-haspopup="menu" aria-expanded={open} onClick={() => setOpen((o) => !o)}>
        + Quick action
      </button>
      {open && (
        <div className="quick__menu" role="menu">
          {ACTIONS.map((a) => (
            <Link key={a.to} to={a.to} role="menuitem" onClick={() => setOpen(false)}>
              {a.label}
            </Link>
          ))}
        </div>
      )}
    </div>
  );
}