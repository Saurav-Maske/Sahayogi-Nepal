import { useEffect, useState } from "react";
import { Link, useParams } from "react-router-dom";
import QuickAction from "../components/dashboard/QuickAction";
import {
  getAssignment,
  issueAssignmentOtp,
  receiveDonationAtHub,
} from "../services/assignmentsService";
import type { AssignmentEvent } from "../services/assignmentsService";
import "../styles/assignments.css";

type Detail = Awaited<ReturnType<typeof getAssignment>>;
const label = (s: string) =>
  s.replace(/_/g, " ").replace(/^./, (c) => c.toUpperCase());
const eventText = (e: AssignmentEvent) => label(e.type);
export default function AssignmentDetailPage() {
  const { id = "" } = useParams();
  const [data, setData] = useState<Detail | null>(null),
    [error, setError] = useState(""),
    [loading, setLoading] = useState(true),
    [actionBusy, setActionBusy] = useState(false),
    [actionMessage, setActionMessage] = useState(""),
    [actionError, setActionError] = useState(""),
    [otp, setOtp] = useState<{ code: string; purpose: string; expires_at: string } | null>(null),
    [counts, setCounts] = useState<Record<string, string>>({});
  useEffect(() => {
    let active = true;
    setLoading(true);
    void getAssignment(id)
      .then((x) => {
        if (active) {
          setData(x);
          setCounts(Object.fromEntries(x.requestItems.map((item) => [
            item.id,
            String(item.confirmed_qty ?? item.donor_qty ?? item.approved_qty ?? item.requested_qty ?? 0),
          ])));
          setError("");
        }
      })
      .catch((e) => {
        if (active) {
          setData(null);
          setError(
            e instanceof Error ? e.message : "Could not load assignment",
          );
        }
      })
      .finally(() => {
        if (active) setLoading(false);
      });
    return () => {
      active = false;
    };
  }, [id]);
  if (loading) return <p className="empty">Loading assignment…</p>;
  if (error || !data)
    return (
      <div>
        <p className="assignment-error" role="alert">
          {error || "Assignment not found."}
        </p>
        <Link className="btn" to="/assignments">
          Back to assignments
        </Link>
      </div>
    );
  const active = [
    "accepted",
    "en_route_to_pickup",
    "picked_up",
    "en_route_to_destination",
  ].includes(data.state);
  const pickup = data.route[0]?.label ?? "—",
    destination = data.route[data.route.length - 1]?.label ?? data.district;
  const hubReceived = data.events.some((event) => event.type === "hub_received");
  const canCountDonation = data.assignmentType === "pickup" &&
    ["picked_up", "en_route_to_destination"].includes(data.state) && !hubReceived;
  const canIssueHubPickup = data.assignmentType === "delivery" &&
    ["accepted", "en_route_to_pickup"].includes(data.state) && !!data.volunteerId;
  const canIssueHubDropoff = data.assignmentType === "pickup" && hubReceived &&
    ["picked_up", "en_route_to_destination"].includes(data.state) && !!data.volunteerId;

  const runAction = async (action: () => Promise<void>) => {
    setActionBusy(true);
    setActionError("");
    setActionMessage("");
    setOtp(null);
    try {
      await action();
    } catch (e) {
      setActionError(e instanceof Error ? e.message : "The operation could not be completed.");
    } finally {
      setActionBusy(false);
    }
  };

  const countDonation = () => runAction(async () => {
    const items = data.requestItems.map((item) => {
      const qty = Number(counts[item.id]);
      if (!Number.isInteger(qty) || qty < 0 || qty > 1_000_000) {
        throw new Error(`Enter a whole kit count for ${label(item.item_type)}.`);
      }
      return { item_id: item.id, qty };
    });
    const result = await receiveDonationAtHub(data.id, items);
    setActionMessage(result.shortfall
      ? `Hub count recorded with a discrepancy. Incident ${result.incident_id?.slice(0, 8).toUpperCase() ?? "opened"} is in the incident queue.`
      : `Hub count recorded. ${result.lots_created} inventory lots created.`);
    const refreshed = await getAssignment(id);
    setData(refreshed);
  });

  const issueOtp = () => runAction(async () => {
    const result = await issueAssignmentOtp(data.id);
    setOtp(result);
    setActionMessage("This code is shown once. Read it to the assigned driver.");
  });

  const copyOtp = async () => {
    if (!otp) return;
    try {
      await navigator.clipboard.writeText(otp.code);
      setActionMessage("One-time code copied.");
    } catch {
      setActionError("Clipboard access is unavailable. Copy the displayed code manually.");
    }
  };
  return (
    <div className="assignment-detail-page">
      <header className="page__head">
        <div>
          <h1>Assignment detail · {data.id.slice(0, 8).toUpperCase()}</h1>
          <p className="crumbs">
            <Link to="/">Sahayogi Nepal</Link>&nbsp; / &nbsp;
            <Link to="/assignments">Assignments</Link>&nbsp; / &nbsp;
            {data.district}
          </p>
        </div>
        <div className="page__actions">
          <QuickAction />
        </div>
      </header>
      <div className="assignment-detail-grid">
        <section className="card assignment-resource">
          <h2 className="card__title">
            {label(data.assignmentType)} assignment
          </h2>
          <p className="card__sub">
            <Link to={`/requests/${data.requestId}`}>{data.requestRef}</Link> ·{" "}
            {data.volunteer ?? "Unclaimed"} · {label(data.state)}
          </p>
          <dl>
            <div>
              <dt>Pickup</dt>
              <dd>{pickup}</dd>
            </div>
            <div>
              <dt>Destination</dt>
              <dd>{destination}</dd>
            </div>
            <div>
              <dt>Items</dt>
              <dd>
                {data.items
                  .map(
                    (i) =>
                      `${i.item_type.replace(/_/g, " ")} ${i.qty} ${i.unit}`,
                  )
                  .join(" · ") || "No item quantities"}
              </dd>
            </div>
            <div>
              <dt>Offered</dt>
              <dd>{new Date(data.offeredAt).toLocaleString()}</dd>
            </div>
            <div>
              <dt>Accepted</dt>
              <dd>
                {data.acceptedAt
                  ? new Date(data.acceptedAt).toLocaleString()
                  : "Awaiting acceptance"}
              </dd>
            </div>
            <div>
              <dt>Tier</dt>
              <dd>{data.requiredTier}</dd>
            </div>
          </dl>
          {active && (
            <div className="location-note">
              <strong>Live location sharing</strong>
              <p>
                Location appears on the authorised live map while the volunteer
                sends recent updates.
              </p>
              <Link to="/map?layer=drivers">Open live map</Link>
            </div>
          )}
          {(canCountDonation || canIssueHubPickup || canIssueHubDropoff) && (
            <div className="assignment-hub-actions">
              <h3>Hub handoff</h3>
              {canCountDonation && (
                <>
                  <p>Count the whole kits received from the driver. Items left at zero are recorded as not received.</p>
                  {data.requestItems.map((item) => (
                    <label className="assignment-count-row" key={item.id}>
                      <span>{label(item.item_type)} <small>({item.unit})</small></span>
                      <input
                        type="number"
                        min={0}
                        max={1_000_000}
                        step={1}
                        value={counts[item.id] ?? "0"}
                        onChange={(event) => setCounts((current) => ({ ...current, [item.id]: event.target.value }))}
                      />
                    </label>
                  ))}
                  <button className="btn btn--primary" disabled={actionBusy || !data.requestItems.length} onClick={() => void countDonation()}>
                    {actionBusy ? "Recording count…" : "Record hub count"}
                  </button>
                </>
              )}
              {(canIssueHubPickup || canIssueHubDropoff) && (
                <>
                  <p>{canIssueHubPickup
                    ? "Issue the hub pickup code after handing the reserved items to the driver."
                    : "The donation count is recorded. Issue the hub drop-off code to complete the donation."}</p>
                  <button className="btn btn--primary" disabled={actionBusy} onClick={() => void issueOtp()}>
                    {actionBusy ? "Issuing code…" : canIssueHubPickup ? "Issue hub pickup code" : "Issue hub drop-off code"}
                  </button>
                </>
              )}
              {actionError && <p className="assignment-action-error" role="alert">{actionError}</p>}
              {actionMessage && <p className="assignment-action-message" role="status">{actionMessage}</p>}
              {otp && (
                <div className="assignment-otp" aria-live="polite">
                  <strong>{label(otp.purpose)} code</strong>
                  <code>{otp.code}</code>
                  <span>Expires {new Date(otp.expires_at).toLocaleTimeString()}</span>
                  <button className="btn" onClick={() => void copyOtp()}>Copy code</button>
                </div>
              )}
            </div>
          )}
        </section>
        <section className="card assignment-events">
          <h2 className="card__title">Pickup and delivery events</h2>
          {data.events.length ? (
            <ol className="event-list">
              {data.events.map((e, i) => (
                <li
                  className={
                    i === data.events.length - 1
                      ? "event-current"
                      : "event-done"
                  }
                  key={e.id}
                >
                  <span>{eventText(e)}</span>
                  <p>
                    {e.actor ? `Actor ${e.actor}` : ""}
                    {e.payload ? ` · ${JSON.stringify(e.payload)}` : ""}
                  </p>
                  <time>{new Date(e.createdAt).toLocaleString()}</time>
                </li>
              ))}
            </ol>
          ) : (
            <p className="empty">No assignment events recorded yet.</p>
          )}
          {data.completedAt && (
            <p className="discrepancy">
              Completed {new Date(data.completedAt).toLocaleString()}
            </p>
          )}
        </section>
      </div>
    </div>
  );
}
