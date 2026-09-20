'use client';
import {FormEvent,useEffect,useState} from 'react';
import Link from 'next/link';
import {useRouter} from 'next/navigation';
import {createBrowserSupabase} from '@/lib/supabase/browser';

export default function ResetPassword(){
 const router=useRouter(),[ready,setReady]=useState(false),[checked,setChecked]=useState(false),[password,setPassword]=useState(''),[confirmPassword,setConfirmPassword]=useState(''),[msg,setMsg]=useState('');
 useEffect(()=>{const db=createBrowserSupabase();db.auth.getSession().then(({data})=>{setReady(Boolean(data.session));setChecked(true)});const {data}=db.auth.onAuthStateChange((event,session)=>{if(event==='PASSWORD_RECOVERY'||session)setReady(true);setChecked(true)});return()=>data.subscription.unsubscribe();},[]);
 async function submit(e:FormEvent){e.preventDefault();if(password.length<8){setMsg('Use at least 8 characters.');return}if(password!==confirmPassword){setMsg('Passwords do not match.');return}const db=createBrowserSupabase();const {error}=await db.auth.updateUser({password});if(error){setMsg(error.message);return}await db.auth.signOut();setMsg('Password updated. Redirecting to sign in…');setTimeout(()=>router.replace('/onboarding'),700)}
 return <main style={{maxWidth:520,margin:'70px auto',padding:22}}><div className="eyebrow">HOME HIVE 360</div><h1 className="title">Choose a new password</h1><p className="sub">{ready?'Enter a new password for your account.':checked?'This recovery link is invalid or has expired. Request a new reset link.':'Verifying your secure recovery link…'}</p>{ready?<form className="card" onSubmit={submit}><div className="field"><label>New password</label><input type="password" value={password} onChange={e=>setPassword(e.target.value)} minLength={8} required autoComplete="new-password"/></div><br/><div className="field"><label>Confirm new password</label><input type="password" value={confirmPassword} onChange={e=>setConfirmPassword(e.target.value)} minLength={8} required autoComplete="new-password"/></div><br/><button className="btn">Update Password</button>{msg&&<p className="sub" style={{marginTop:15}}>{msg}</p>}</form>:checked?<p className="label"><Link href="/auth/forgot-password">Request another reset link</Link></p>:null}</main>;
}
