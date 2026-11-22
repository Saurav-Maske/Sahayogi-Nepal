import { useEffect, useMemo, useState } from 'react';
import { Link } from 'react-router-dom';
import QuickAction from '../components/dashboard/QuickAction';
import { listIncidents, type Incident } from '../services/incidentsService';
import '../styles/incidents.css';
const incidentLabels:Record<string,string>={
 short_delivery:'Short delivery to requester',
 hub_shortfall:'Hub intake quantity mismatch',
 pickup_refused:'Driver refused donation pickup',
 items_mismatch:'Donation pickup quantity mismatch',
 hub_pickup_refused:'Driver refused hub handoff',
 hub_items_mismatch:'Driver reports hub handoff shortage',
};
const label=(s:string)=>incidentLabels[s]??s.replace(/_/g,' ').replace(/^./,c=>c.toUpperCase());
const statusLabel=(s:string)=>s==='under_review'?'Investigating':label(s);
const shortfall=(v:unknown)=>{
 if(v==null)return 'See driver note';
 const rows=Array.isArray(v)?v:typeof v==='object'?[v]:[];
 if(rows.length)return rows.map((row:any)=>{
  if(!row||typeof row!=='object')return String(row);
  const name=String(row.item_type??'Item').replace(/_/g,' '),unit=row.unit??'kit';
  const expected=row.expected_qty??row.approved_qty,actual=row.counted_qty??row.received_qty??row.quantity;
  if(expected!=null&&actual!=null)return `${name}: ${actual}/${expected} ${unit}`;
  if(actual!=null)return `${name}: ${actual} ${unit}`;
  return 'See driver note';
 }).join('; ');
 return typeof v==='object'?Object.entries(v as Record<string,unknown>).map(([k,x])=>`${x} ${k}`).join(', '):String(v);
};
export default function IncidentsPage(){const[rows,setRows]=useState<Incident[]>([]),[query,setQuery]=useState(''),[status,setStatus]=useState(''),[category,setCategory]=useState('All'),[loading,setLoading]=useState(true),[error,setError]=useState('');
 const refresh=()=>{setLoading(true);void listIncidents(status).then(setRows).catch(e=>setError(e instanceof Error?e.message:'Could not load incidents')).finally(()=>setLoading(false))};useEffect(refresh,[status]);
 const filtered=useMemo(()=>rows.filter(r=>(!query||`${r.id} ${r.request?.public_ref??''} ${r.reporter?.name??''} ${r.assignment?.volunteer_name??''} ${r.request?.requester_name??''} ${r.type}`.toLowerCase().includes(query.toLowerCase()))&&(category==='All'||label(r.type).toLowerCase().includes(category.toLowerCase()))),[rows,query,category]);
 const openCount=rows.filter(r=>r.status==='open'||r.status==='under_review').length;
 return <div className="incidents-page"><header className="page__head"><div><h1>Incidents &amp; reports</h1><p className="crumbs">Sahayogi Nepal&nbsp; / &nbsp;Incidents &amp; Reports&nbsp; / &nbsp;Operations</p></div><div className="page__actions"><QuickAction/></div></header><div className="incident-alert"><strong>{openCount} {openCount===1?'incident requires':'incidents require'} review</strong><p>Driver handoff concerns and quantity differences are recorded here from the field and hub count.</p></div><div className="incident-filters"><input placeholder="Search records" aria-label="Search incidents" value={query} onChange={e=>setQuery(e.target.value)}/><select value={status} onChange={e=>setStatus(e.target.value)} aria-label="Status"><option value="">Status: All</option><option value="open">Open</option><option value="under_review">Investigating</option><option value="resolved">Resolved</option><option value="dismissed">Dismissed</option></select><select value={category} onChange={e=>setCategory(e.target.value)} aria-label="Category"><option>All</option><option>Hub intake quantity mismatch</option><option>Driver reports hub handoff shortage</option><option>Driver refused hub handoff</option><option>Short delivery to requester</option><option>Donation pickup quantity mismatch</option><option>Driver refused donation pickup</option></select><span className="incident-filter-note">Newest and urgent cases first</span></div>{error&&<p className="incident-error" role="alert">Could not load incidents: {error}</p>}{loading?<p className="empty">Loading incidents…</p>:<div className="incident-table-wrap"><table className="incident-table"><thead><tr><th>Incident</th><th>Assignment</th><th>Reporting driver / requester</th><th>Issue</th><th>Quantity</th><th>Reported</th><th>Status</th><th>Action</th></tr></thead><tbody>{filtered.map(r=><tr key={r.id}><td>{r.id.slice(0,8).toUpperCase()}</td><td>{r.assignment?.id?.slice(0,8).toUpperCase()??'—'}</td><td>{r.reporter?.name??r.assignment?.volunteer_name??'—'} / {r.request?.requester_name??'—'}</td><td>{label(r.type)}</td><td>{shortfall(r.reportedShortfall)}</td><td>{new Date(r.createdAt).toLocaleString()}</td><td><span className={`incident-status incident-status--${r.status}`}>{statusLabel(r.status)}</span></td><td><Link to={`/incidents/${r.id}`}>{r.status==='resolved'||r.status==='dismissed'?'View →':'Review →'}</Link></td></tr>)}</tbody></table>{!filtered.length&&<p className="empty">No incidents match these filters.</p>}</div>}</div>
}
