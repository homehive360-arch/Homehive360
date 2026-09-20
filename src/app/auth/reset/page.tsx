'use client';
import {FormEvent,useEffect,useState} from 'react';
import {useRouter} from 'next/navigation';
import {createBrowserSupabase} from '@/lib/supabase/browser';

export default function ResetPassword(){
 const router=useRouter(),[ready,setReady]=useState(false),[password,setPassword]=useState(''),[msg,setMsg]=useState('');
 useEffect(()=>{const db=createBrowserSupabase();db.auth.getSession().then(({data})=>setReady(Boolean(data.session)));const {data}=db.auth.onAuthStateChange((event,session)=>{if(event==='PASSWORD_RECOVERY'||session)setReady(true)});return()=>data.subscription.unsubscribe();},[]);
 async function submit(e:FormEvent){e.preventDefault();if(password.length<8){setMsg('Use at least 8 characters.');return;}const db=createBrowserSupabase();const {error}=await db.auth.updateUser({password});if(error){setMsg(error.message);return;}setMsg('Password updated. Redirecting…');setTimeout(()=>router.push('/'),700);}
 return <main style={{maxWidth:520,margin:'70px auto',padding:22}}><div className="eyebrow">HOME HIVE 360</div><h1 className="title">Choose a new password</h1><p className="sub">{ready?'Enter a new password for your account.':'Open this page from the secure reset link in your email.'}</p>{ready?<form className="card" onSubmit={submit}><div className="field"><label>New password</label><input type="password" value={password} onChange={e=>setPassword(e.target.value)} minLength={8} required/></div><br/><button className="btn">Update Password</button>{msg&&<p className="sub" style={{marginTop:15}}>{msg}</p>}</form>:null}</main>;
}
