import { useMemo, useState } from 'react';
import { Link } from 'react-router-dom';
import QuickAction from '../components/dashboard/QuickAction';
import '../styles/assignments.css';

type Assignment = { id:string; ref:string; requestRef:string; title:string; route:string; itemSummary:string; status:string; volunteer:string; created:string; district:string };
const SAMPLE: Assignment[] = [
  {id:'demo-asg-0302',ref:'ASG-0302',requestRef:'REQ-1042',title:'Deliver essential food supplies',route:'Central Inventory → Kirtipur',itemSummary:'Rice 20 kg · Water 12 bottles',status:'In progress',volunteer:'Ramesh Gurung',created:'12 min ago',district:'Kathmandu'},
  {id:'demo-asg-0301',ref:'ASG-0301',requestRef:'DON-0284',title:'Collect a rice donation',route:'Maharajgunj → Central Inventory',itemSummary:'Rice · Expected 50 kg',status:'Offered',volunteer:'',created:'12 min ago',district:'Kathmandu'},
  {id:'demo-asg-0300',ref:'ASG-0300',requestRef:'REQ-1040',title:'Healthcare home visit',route:'Central Inventory → Kirtipur',itemSummary:'Rice 20 kg · Water 12 bottles',status:'Accepted',volunteer:'Asha Tamang',created:'25 min ago',district:'Lalitpur'},
  {id:'demo-asg-0299',ref:'ASG-0299',requestRef:'REQ-1039',title:'Assist shelter setup',route:'Central Inventory → Kirtipur',itemSummary:'Rice 20 kg · Water 12 bottles',status:'Available',volunteer:'',created:'32 min ago',district:'Kathmandu'},
  {id:'demo-asg-0298',ref:'ASG-0298',requestRef:'REQ-1041',title:'Distribute drinking water',route:'Central Inventory → Kirtipur',itemSummary:'Rice 20 kg · Water 12 bottles',status:'Available',volunteer:'',created:'38 min ago',district:'Bhaktapur'},
  {id:'demo-asg-0297',ref:'ASG-0297',requestRef:'REQ-1036',title:'Transport medical supplies',route:'Central Inventory → Kirtipur',itemSummary:'Rice 20 kg · Water 12 bottles',status:'Available',volunteer:'',created:'45 min ago',district:'Kathmandu'},
];
const tabs=['Available','Offered','Accepted','In Progress','Completed','Cancelled'];
export default function AssignmentsPage(){
 const [tab,setTab]=useState('Available'),[query,setQuery]=useState(''),[district,setDistrict]=useState('All'),[category,setCategory]=useState('All');
 const rows=useMemo(()=>SAMPLE.filter(a=> (tab==='Available'?a.status==='Available':tab==='In Progress'?a.status==='In progress':tab==='Completed'?a.status==='Completed':tab==='Cancelled'?a.status==='Cancelled':a.status.toLowerCase()===tab.toLowerCase()) && (district==='All'||a.district===district) && (!query||`${a.title} ${a.ref} ${a.requestRef} ${a.volunteer}`.toLowerCase().includes(query.toLowerCase()))),[tab,query,district]);
 return <div className="assignments-page"><header className="page__head"><div><h1>Assignment management</h1><p className="crumbs">Sahayogi Nepal&nbsp; / &nbsp;Assignments&nbsp; / &nbsp;Kathmandu district</p></div><div className="page__actions"><QuickAction/></div></header>
 <nav className="assignment-tabs" aria-label="Assignment status">{tabs.map((t,i)=><button key={t} className={tab===t?'is-active':''} onClick={()=>setTab(t)}>{t}<span>{[24,12,8,32,6,2][i]}</span></button>)}</nav>
 <div className="assignment-filters"><input aria-label="Search assignments" placeholder="Search records" value={query} onChange={e=>setQuery(e.target.value)}/><select aria-label="District" value={district} onChange={e=>setDistrict(e.target.value)}><option value="All">District: All</option><option>Kathmandu</option><option>Lalitpur</option><option>Bhaktapur</option></select><select aria-label="Category" value={category} onChange={e=>setCategory(e.target.value)}><option value="All">Category: All</option><option>General</option><option>Transport</option><option>Healthcare</option></select><select aria-label="Date range"><option>Last 30 days</option><option>Last 7 days</option><option>Today</option></select></div>
 <section className="assignment-grid">{rows.map(a=><Link className="assignment-card" to={`/assignments/${a.id}`} key={a.id}><h2>{a.title}</h2><p className="assignment-ref">{a.requestRef} · {a.ref}</p><p className="assignment-route">{a.route}</p><p className="assignment-items">{a.itemSummary}</p><p className={`assignment-state ${a.status==='In progress'?'is-progress':''}`}>{a.volunteer?`${a.volunteer} · `:''}{a.status} · {a.created}</p></Link>)}{!rows.length&&<p className="empty">No assignments match these filters.</p>}</section>
 </div>
}
