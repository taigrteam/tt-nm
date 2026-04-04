import { auth } from "@/auth";
import { redirect } from "next/navigation";
import NavBar from "./components/nav-bar";
import MapShell from "./components/map-shell";

export default async function Home() {
  const session = await auth();

  if (!session?.user) {
    redirect("/signin");
  }

  return (
    <div className="flex flex-col h-screen w-screen">
      <NavBar />
      <MapShell />
    </div>
  );
}
