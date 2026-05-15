import { readFileSync } from "fs";
import path from "path";
import { Dashboard } from "../components/Dashboard";
import type { AddressBook } from "../lib/types";

function loadAddresses(): AddressBook {
  const filePath = path.join(process.cwd(), "../addresses.sepolia.json");
  return JSON.parse(readFileSync(filePath, "utf8")) as AddressBook;
}

export default function HomePage() {
  return <Dashboard addresses={loadAddresses()} />;
}
