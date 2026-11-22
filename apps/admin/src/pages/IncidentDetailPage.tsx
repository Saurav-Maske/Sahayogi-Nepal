import { useEffect, useState } from 'react';
import { Link, useParams } from 'react-router-dom';
import QuickAction from '../components/dashboard/QuickAction';
import { listIncidents, resolveIncident, type Incident } from '../services/incidentsService';
import '../styles/incidents.css';
const label=(s:string)=>s.replace(/_/g,' ').replace(/^./,c=>c.toUpperCase());
const shortfall=(value:unknown,items:any[])=>{
 if(value==null)return '—';
 const rows=Array.isArray(value)?value:typeof value==='object'?[value]:[];
 if(rows.length){
  const formatted=rows.map((row:any)=>{
   if(!row||typeof row!=='object')return String(row);
   const item=items.find((candidate:any)=>candidate.id===row.item_id);
   const name=row.item_type??item?.item_type;
   const received=row.received_qty??row.quantity;
   const approved=row.approved_qty??item?.approved_qty??item?.requested_qty;
   if(name&&received!=null&&approved!=null)return `${label(String(name))}: ${received} ${row.unit??item?.unit??''} received of ${approved}`.trim();
   if(name&&received!=null)return `${label(String(name))}: ${received} ${row.unit??item?.unit??''} received`.trim();
   return Object.entries(row).map(([key,val])=>`${label(key.replace(/_/g,' '))}: ${String(val)}`).join(' · ');
  });
  return formatted.join(' · ')||'—';
 }
 return typeof value==='object'?Object.entries(value as Record<string,unknown>).map(([key,val])=>`${label(key.replace(/_/g,' '))}: ${String(val)}`).join(' · '):String(value);
};
export default function IncidentDetailPage(){const{id=''}=useParams();const[incident,setIncident]=useState<Incident|null>(null),[note,setNote]=useState(''),[resolution,setResolution]=useState(''),[busy,setBusy]=useState(false),[error,setError]=useState('');
 useEffect(()=>{let active=true;void listIncidents().then(rows=>{const item=rows.find(x=>x.id===id);if(!item)throw new Error('Incident not found');if(active){setIncident(item);setNote(item.adminNotes??'');setResolution(item.resolution??'')}}).catch(e=>{if(active)setError(e instanceof Error?e.message:'Could not load incident')});return()=>{active=false}},[id]);
 async function save(next:'under_review'|'resolved'|'dismissed'){if((next==='resolved'||next==='dismissed')&&resolution.trim().length<2){setError('Enter a resolution before closing the incident.');return;}setBusy(true);setError('');try{await resolveIncident(id,next,resolution.trim()||null,note.trim()||null);const rows=await listIncidents();setIncident(rows.find(x=>x.id===id)??null)}catch(e){setError(e instanceof Error?e.message:'Could not save incident decision')}finally{setBusy(false)}}
 if(!incident)return <div>{error?<p className="incident-error" role="alert">{error}</p>:<p className="empty">Loading incident…</p>}<Link className="btn" to="/incidents">Back to incidents</Link></div>;
 const req=incident.request,asg=incident.assignment,items=req?.items??[],closed=incident.status==='resolved'||incident.status==='dismissed';
 return <div className="incident-detail-page"><header className="page__head"><div><h1>{closed?'Incident review':'Investigate incident'} · {incident.id.slice(0,8).toUpperCase()}</h1><p className="crumbs"><Link to="/">Sahayogi Nepal</Link>&nbsp; / &nbsp;<Link to="/incidents">Incidents &amp; Reports</Link>&nbsp; / &nbsp;{req?.district??'Operations'}</p></div><div className="page__actions"><QuickAction/></div></header><div className="incident-detail-grid"><section className="card incident-report"><h2 className="card__title">{label(incident.type)} reported</h2><p className="card__sub"><Link to={`/requests/${req?.id}`}>{req?.public_ref??'Request'}</Link> · {asg?.id?.slice(0,8).toUpperCase()??'No assignment'} · {new Date(incident.createdAt).toLocaleString()}</p><div className="reporter-details"><p><strong>Requester</strong>{req?.requester_name??'—'}</p><p><strong>Volunteer</strong>{asg?.volunteer_name??'—'}</p><blockquote>{incident.reporterNote||'No reporter note was provided.'}</blockquote></div><dl className="quantity-review"><div><dt>Reported discrepancy</dt><dd>{shortfall(incident.reportedShortfall,items)}</dd></div>{items.map((i:any)=><div key={i.id}><dt>{label(i.item_type)} approved</dt><dd>{i.approved_qty??i.requested_qty} {i.unit}</dd></div>)}<div><dt>Assignment status</dt><dd>{asg?label(asg.state):'—'}</dd></div></dl><div className="incident-alert incident-guidance"><strong>Review the records</strong><p>Check assignment events and inventory history before deciding whether the report is valid.</p></div>{asg?.id&&<Link className="btn incident-history" to={`/assignments/${asg.id}`}>View assignment history</Link>}</section><section className="card incident-resolution"><h2 className="card__title">Review and resolve</h2><div className="incident-activity"><strong>{label(incident.status)}</strong><p>{incident.resolution??'Review the report and record your investigation.'}</p><time>{new Date(incident.createdAt).toLocaleString()}</time></div><label className="incident-input-card"><span>Investigation notes</span><textarea value={note} onChange={e=>setNote(e.target.value)} placeholder="Record who you contacted and what you found." disabled={closed}/></label><label className="incident-input-card incident-outcome"><span>Resolution outcome</span><input value={resolution} onChange={e=>setResolution(e.target.value)} placeholder="Describe the resolution" disabled={closed}/><small>Required to resolve or dismiss.</small></label>{error&&<p className="incident-error" role="alert">{error}</p>}{!closed&&<div className="incident-actions"><button className="btn" disabled={busy||incident.status==='under_review'} onClick={()=>void save('under_review')}>Mark investigating</button><button className="btn btn--primary" disabled={busy} onClick={()=>void save('resolved')}>Resolve incident</button><button className="btn incident-dismiss" disabled={busy} onClick={()=>void save('dismissed')}>Dismiss report</button></div>}</section></div></div>
}
