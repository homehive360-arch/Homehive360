'use client';
import {useEffect,useState} from 'react';
import Link from 'next/link';
import {usePathname,useRouter} from 'next/navigation';
import {createBrowserSupabase} from '@/lib/supabase/browser';

const items=[['/','Overview'],['/hives','Hives'],['/businesses','Businesses'],['/leads','Lead Hub'],['/opportunities','Opportunities'],['/marketing','Marketing'],['/analytics','Analytics'],['/settings','Settings']];

export default function Shell({children}:{children:React.ReactNode}){
 const pathname=usePathname(),router=useRouter();
 const [email,setEmail]=useState<string|null>(null),[ready,setReady]=useState(false),[menuOpen,setMenuOpen]=useState(false);
 useEffect(()=>{const db=createBrowserSupabase();db.auth.getUser().then(({data})=>{setEmail(data.user?.email||null);setReady(true)});const {data}=db.auth.onAuthStateChange((_event,session)=>{setEmail(session?.user.email||null);setReady(true)});return()=>data.subscription.unsubscribe();},[]);
 useEffect(()=>{setMenuOpen(false)},[pathname]);
 async function signOut(){const db=createBrowserSupabase();await db.auth.signOut();setEmail(null);setMenuOpen(false);router.replace('/onboarding');router.refresh();}
 const nav=items.map(([href,label])=>{const active=href==='/'?pathname===href:pathname===href||pathname.startsWith(href+'/');return <Link aria-current={active?'page':undefined} className={active?'active':''} key={href} href={href}>{label}</Link>});
 return <div className="shell"><header className="mobileBar"><Link className="brand mobileBrand" href="/"><div className="mark">HH</div><div>Home Hive 360</div></Link><button className="mobileMenuButton" aria-label="Toggle navigation" aria-expanded={menuOpen} aria-controls="mobile-navigation" onClick={()=>setMenuOpen(v=>!v)}>☰</button></header>{menuOpen?<div id="mobile-navigation" className="mobileNav">{nav}{ready&&email?<button className="accountAction" onClick={signOut}>Sign Out</button>:<Link className="accountAction" href="/onboarding">Sign In / Create Account</Link>}</div>:null}<aside className="sidebar"><div className="brand"><div className="mark">HH</div><div>Home Hive 360</div></div><nav className="nav" aria-label="Primary navigation">{nav}</nav><div className="accountBox">{ready&&email?<><span className="accountEmail">{email}</span><button className="accountAction" onClick={signOut}>Sign Out</button></>:ready?<Link className="accountAction" href="/onboarding">Sign In / Create Account</Link>:<span className="accountEmail">Checking account…</span>}</div></aside><main className="main">{children}</main></div>
}