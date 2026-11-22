import { useEffect, useMemo, useState } from "react";
import { Link } from "react-router-dom";
import QuickAction from "../components/dashboard/QuickAction";
import EmptyState from "../components/feedback/EmptyState";
import {
  listAssignments,
  type AssignmentRow,
} from "../services/assignmentsService";
import "../styles/assignments.css";

const TABS = [
  "Available",
  "Offered",
  "Accepted",
  "In Progress",
  "Completed",
  "Cancelled",
];
const IN_PROGRESS = [
  "en_route_to_pickup",
  "picked_up",
  "en_route_to_destination",
];
const tabState = (a: AssignmentRow) =>
  a.state === "offered"
    ? a.volunteer
      ? "Offered"
      : "Available"
    : a.state === "accepted"
      ? "Accepted"
      : IN_PROGRESS.includes(a.state)
        ? "In Progress"
        : a.state === "delivered"
          ? "Completed"
          : ["cancelled", "expired", "declined"].includes(a.state)
            ? "Cancelled"
            : a.state;
const title = (a: AssignmentRow) =>
  a.requestKind === "donation_offer"
    ? `Collect donation · ${a.requester}`
    : `${a.assignmentType.replace(/_/g, " ")} · ${a.requester}`;

type RequestAssignmentGroup = {
  requestId: string;
  assignments: AssignmentRow[];
};

const slotSummary = (group: RequestAssignmentGroup) => {
  if (group.assignments.length === 1) return null;
  const counts = new Map<string, number>();
  group.assignments.forEach((assignment) => {
    const state = tabState(assignment);
    counts.set(state, (counts.get(state) ?? 0) + 1);
  });
  const stateSummary = [...counts]
    .map(([state, count]) => `${count} ${state.toLowerCase()}`)
    .join(" · ");
  const kind =
    group.assignments[0].requestKind === "donation_offer"
      ? "pickup assignments"
      : "volunteer slots";
  return `${group.assignments.length} ${kind} · ${stateSummary}`;
};

export default function AssignmentsPage() {
  const [rows, setRows] = useState<AssignmentRow[]>([]),
    [tab, setTab] = useState("Available"),
    [query, setQuery] = useState(""),
    [district, setDistrict] = useState("All"),
    [category, setCategory] = useState("All"),
    [days, setDays] = useState("30"),
    [loading, setLoading] = useState(true),
    [error, setError] = useState("");
  useEffect(() => {
    let active = true;
    void listAssignments()
      .then((r) => {
        if (active) setRows(r);
      })
      .catch((e) => {
        if (active)
          setError(
            e instanceof Error ? e.message : "Could not load assignments",
          );
      })
      .finally(() => {
        if (active) setLoading(false);
      });
    return () => {
      active = false;
    };
  }, []);
  const districts = useMemo(
    () =>
      [
        ...new Set(rows.map((r) => r.district).filter((x) => x && x !== "—")),
      ].sort(),
    [rows],
  );
  const requestGroups = useMemo(() => {
    const groups = new Map<string, AssignmentRow[]>();
    rows.forEach((assignment) => {
      const assignments = groups.get(assignment.requestId) ?? [];
      assignments.push(assignment);
      groups.set(assignment.requestId, assignments);
    });
    return [...groups].map(([requestId, assignments]) => ({
      requestId,
      assignments,
    }));
  }, [rows]);
  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    const since = days === "all" ? 0 : Date.now() - Number(days) * 864e5;
    return requestGroups.flatMap((group) => {
      const matching = group.assignments.filter(
        (a) =>
          (!q ||
            `${title(a)} ${a.requestRef} ${a.volunteer ?? ""} ${a.state}`
              .toLowerCase()
              .includes(q)) &&
          (district === "All" || a.district === district) &&
          (category === "All" || a.assignmentType === category) &&
          (!since || Date.parse(a.offeredAt) >= since),
      );
      const visibleAssignments = matching.filter((a) => tabState(a) === tab);
      return visibleAssignments.length
        ? [{ group, assignment: visibleAssignments[0] }]
        : [];
    });
  }, [requestGroups, tab, query, district, category, days]);
  return (
    <div className="assignments-page">
      <header className="page__head">
        <div>
          <h1>Assignment management</h1>
          <p className="crumbs">
            Sahayogi Nepal&nbsp; / &nbsp;Assignments&nbsp; / &nbsp;Operations
          </p>
        </div>
        <div className="page__actions">
          <QuickAction />
        </div>
      </header>
      <nav className="assignment-tabs" aria-label="Assignment status">
        {TABS.map((t) => (
          <button
            key={t}
            className={tab === t ? "is-active" : ""}
            onClick={() => setTab(t)}
          >
            {t}
            <span>
              {requestGroups.filter((group) =>
                group.assignments.some((a) => tabState(a) === t),
              ).length}
            </span>
          </button>
        ))}
      </nav>
      <div className="assignment-filters">
        <input
          aria-label="Search assignments"
          placeholder="Search records"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
        />
        <select
          aria-label="District"
          value={district}
          onChange={(e) => setDistrict(e.target.value)}
        >
          <option value="All">District: All</option>
          {districts.map((d) => (
            <option key={d}>{d}</option>
          ))}
        </select>
        <select
          aria-label="Category"
          value={category}
          onChange={(e) => setCategory(e.target.value)}
        >
          <option value="All">Category: All</option>
          {[...new Set(rows.map((a) => a.assignmentType))].sort().map((c) => (
            <option key={c} value={c}>
              {c.replace(/_/g, " ")}
            </option>
          ))}
        </select>
        <select
          aria-label="Date range"
          value={days}
          onChange={(e) => setDays(e.target.value)}
        >
          <option value="30">Last 30 days</option>
          <option value="7">Last 7 days</option>
          <option value="1">Today</option>
          <option value="all">All time</option>
        </select>
      </div>
      {error && (
        <p className="assignment-error" role="alert">
          {error}
        </p>
      )}
      {loading ? (
        <p className="empty">Loading assignments…</p>
      ) : (
        <section className="assignment-grid">
          {filtered.map(({ group, assignment: a }) => (
            <Link
              className="assignment-card"
              to={`/assignments/${a.id}`}
              key={group.requestId}
            >
              <h2>{title(a)}</h2>
              <p className="assignment-ref">
                {a.requestRef} · {a.assignmentType.toUpperCase()}
              </p>
              <p className="assignment-route">
                {a.route.map((p) => p.label).join(" → ") || a.district}
              </p>
              <p className="assignment-items">
                {slotSummary(group) ??
                  (a.items
                    .map(
                      (i) =>
                        `${i.item_type.replace(/_/g, " ")} ${i.qty} ${i.unit}`,
                    )
                    .join(" · ") || `Tier ${a.requiredTier}`)}
              </p>
              <p className="assignment-state">
                {a.volunteer ? `${a.volunteer} · ` : ""}
                {tabState(a)} · {new Date(a.offeredAt).toLocaleString()}
              </p>
            </Link>
          ))}
          {!filtered.length && !error && (
            <EmptyState
              title={
                rows.length
                  ? "No assignments match these filters"
                  : "No assignments available"
              }
              description={
                rows.length
                  ? "Try widening your date range or changing the selected district and category."
                  : "There are no eligible assignments in the selected district right now. Check back when a request is ready for assignment."
              }
            />
          )}
        </section>
      )}
    </div>
  );
}
