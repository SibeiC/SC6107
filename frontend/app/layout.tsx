import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "SC6107 Arbitrage Dashboard",
  description: "Frontend dashboard for the SC6107 flash-loan arbitrage platform"
};

export default function RootLayout({
  children
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
