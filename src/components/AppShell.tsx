'use client';
import {useEffect,useState} from 'react';
import Link from 'next/link';
import {usePathname,useRouter} from 'next/navigation';
import {createBrowserSupabase} from '@/lib/supabase/browser';

const items=[['/','Overview'],['/hives','Hives'],['/businesses','Businesses'],['/leads','Lead Hub'],['/opportunities','Opportunities'],['/marketing','Marketing'],['/analytics','Analytics'],['/settings','Settings']];

export default function Shell({children}:{children:React.ReactNode}){
 const pathname=usePathname(),router=useRouter();
 const [email,setEmail]=useState<string|null>(null),[ready,setReady]=useState(false);
 useEffect(()=>{const db=createBrowserSupabase();db.auth.getUser().then(({data})=>{setEmail(data.user?.email||null);setReady(true)});const {data}=db.auth.onAuthStateChange((_event,session)=>{setEmail(session?.user.email||null);setReady(true)});return()=>data.subscription.unsubscribe();},[]);
 async function signOut(){const db=createBrowserSupabase();await db.auth.signOut();setEmail(null);router.push('/onboarding');router.refresh();}
 return <div className="shell"><aside className="sidebar"><div className="brand"><div className="mark">HH</div><div>Home Hive 360</div></div><nav className="nav">{items.map(([href,label])=><Link className={pathname===href?'active':''} key={href} href={href}>{label}</Link>)}</nav><div className="accountBox">{ready&&email?<><span className="accountEmail">{email}</span><button className="accountAction" onClick={signOut}>Sign Out</button></>:ready?<Link className="accountAction" href="/onboarding">Sign In / Create Account</Link>:<span className="accountEmail">Checking account…</span>}</div></aside><main className="main">{children}</main></div>
}