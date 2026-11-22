import { useMemo, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import QuickAction from '../components/dashboard/QuickAction';
import '../styles/notifications.css';

type Category='Requests'|'Donations'|'Assignments'|'Inventory';
type Notice={id:number;title:string;detail:string;time:string;category:Category;kind:'alert'|'success'|'normal';unread:boolean;to:string};
const INITIAL:Notice[]=[
 {id:1,title:'Missing quantity reported',detail:'INC-0061 · Received 18 of 20 kg rice',time:'2 min ago',category:'Requests',kind:'alert',unread:true,to:'/incidents/demo-inc-0061'},
 {id:2,title:'Drinking water stock is low',detail:'84 bottles available · Threshold 100',time:'12 min ago',category:'Inventory',kind:'alert',unread:true,to:'/inventory'},
 {id:3,title:'New volunteer application',detail:'Nisha Rai · Healthcare professional',time:'24 min ago',category:'Requests',kind:'normal',unread:false,to:'/volunteers'},
 {id:4,title:'Delivery completed',detail:'REQ-1038 · Kirtipur',time:'42 min ago',category:'Assignments',kind:'success',unread:false,to:'/assignments'},
 {id:5,title:'Pickup completed',detail:'DON-0284 · Actual rice collected: 45 kg',time:'1 hr ago',category:'Donations',kind:'success',unread:false,to:'/donations/demo-don-284'},
 {id:6,title:'Driver accepted assignment',detail:'Ramesh Gurung · ASG-0302',time:'1 hr ago',category:'Assignments',kind:'normal',unread:false,to:'/assignments/demo-asg-0302'},
 {id:7,title:'New donation received',detail:'Kiran Joshi · 120 bottles water',time:'2 hr ago',category:'Donations',kind:'normal',unread:false,to:'/donations'},
 {id:8,title:'New help request submitted',detail:'REQ-1042 · Food assistance',time:'2 hr ago',category:'Requests',kind:'normal',unread:false,to:'/requests'},
];
const TABS=['All notifications','Unread','Requests','Donations','Assignments','Inventory'] as const;
export default function NotificationsPage(){const[items,setItems]=useState(INITIAL);const[tab,setTab]=useState<string>('All notifications');const navigate=useNavigate();const unread=items.filter(n=>n.unread).length;const filtered=useMemo(()=>items.filter(n=>tab==='All notifications'||(tab==='Unread'?n.unread:n.category===tab)),[items,tab]);
 function openNotice(n:Notice){setItems(old=>old.map(x=>x.id===n.id?{...x,unread:false}:x));navigate(n.to)}
 return <div className="notifications-page"><header className="page__head"><div><h1>Notification center</h1><p className="crumbs">Sahayogi Nepal&nbsp; / &nbsp;Notifications&nbsp; / &nbsp;Kathmandu district</p></div><div className="page__actions"><QuickAction/></div></header>
 <nav className="notification-tabs" aria-label="Notification categories">{TABS.map(t=><button key={t} className={tab===t?'is-active':''} onClick={()=>setTab(t)}>{t}{t==='Unread'&&<span>{unread}</span>}</button>)}</nav>
 <section className="notification-feed" aria-label="Notifications">{filtered.map(n=><button type="button" className={`notification-item notification-item--${n.kind}${n.unread?' is-unread':''}`} key={n.id} onClick={()=>openNotice(n)}><span className="notification-symbol" aria-hidden="true">{n.kind==='alert'?'!':n.kind==='success'?'✓':''}</span><span className="notification-copy"><strong>{n.title}</strong><span className="notification-detail">{n.detail} · {n.time}</span></span>{n.unread&&<span className="notification-unread-dot" aria-label="Unread"/>}</button>)}{filtered.length===0&&<p className="empty notification-empty">You’re all caught up.</p>}</section>
 </div>
}
