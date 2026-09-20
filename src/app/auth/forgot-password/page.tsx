'use client';
import {FormEvent,useState} from 'react';
import Link from 'next/link';
import {createBrowserSupabase} from '@/lib/supabase/browser';

export default function ForgotPassword(){
 const [email,setEmail]=useState(''),[msg,setMsg]=useState('');
 async function submit(e:FormEvent){e.preventDefault();setMsg('Sending reset link...');const db=createBrowserSupabase();const redirectTo=window.location.origin+'/auth/reset';const {error}=await db.auth.resetPasswordForEmail(email,{redirectTo});setMsg(error?error.message:'Check your email for a password reset link.');}
 return <main style={{maxWidth:520,margin:'70px auto',padding:22}}><div className="eyebrow">HOME HIVE 360</div><h1 className="title">Reset password</h1><p className="sub">Enter your account email and HH360 will send a secure reset link.</p><form className="card" onSubmit={submit}><div className="field"><label>Email</label><input type="email" value={email} onChange={e=>setEmail(e.target.value)} required/></div><br/><button className="btn">Send Reset Link</button>{msg&&<p className="sub" style={{marginTop:15}}>{msg}</p>}<p className="label" style={{marginTop:18}}><Link href="/onboarding">Return to sign in</Link></p></form></main>;
}
