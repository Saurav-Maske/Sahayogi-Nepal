import type { ReactNode } from "react";

export default function EmptyState({
  title,
  description,
  action,
}: {
  title: string;
  description: string;
  action?: ReactNode;
}) {
  return <section className="admin-empty-state" role="status">
    <span className="admin-empty-state__mark" aria-hidden="true">—</span>
    <h2>{title}</h2>
    <p>{description}</p>
    {action && <div className="admin-empty-state__action">{action}</div>}
  </section>;
}
