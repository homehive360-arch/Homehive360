import './globals.css';
import type { Metadata } from 'next';
export const metadata: Metadata = { title: 'Home Hive 360', description: 'Home Hive 360 Command Center' };
export default function RootLayout({children}:{children:React.ReactNode}){return <html lang="en"><body>{children}</body></html>}
