'use client';
import {useEffect} from 'react';
export default function HiveVisitTracker({hiveSlug,pid}:{hiveSlug:string;pid?:string}){useEffect(()=>{if(!pid)return;fetch('/api/v1/events/hive-visit',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({hiveSlug,pid}),keepalive:true}).catch(()=>{});},[hiveSlug,pid]);return null;}