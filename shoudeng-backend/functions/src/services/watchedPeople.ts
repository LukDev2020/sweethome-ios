import * as admin from "firebase-admin";

/**
 * Everyone someone is actively looking after, whatever their account role:
 * a guardian can be watched back, and someone who joined through an invite keeps
 * their original role. The scheduled checks (heartbeat, check-in overdue) go
 * through this list instead of `role == "protected"`, which missed those people.
 */
export interface WatchedPerson {
  id: string;
  displayName: string;
  createdAt: admin.firestore.Timestamp | null;
}

export async function watchedPeople(): Promise<WatchedPerson[]> {
  const db = admin.firestore();
  const links = await db.collection("guardian_links")
    .where("status", "==", "active")
    .select("protectedPersonId")
    .get();
  const ids = [...new Set(links.docs
    .map((d) => d.get("protectedPersonId"))
    .filter((v): v is string => typeof v === "string" && v.length > 0))];

  const people: WatchedPerson[] = [];
  for (let i = 0; i < ids.length; i += 100) {
    const snaps = await db.getAll(...ids.slice(i, i + 100).map((id) => db.collection("users").doc(id)));
    for (const snap of snaps) {
      if (!snap.exists) continue;
      const data = snap.data() ?? {};
      people.push({ id: snap.id, displayName: (data.displayName as string) ?? "", createdAt: data.createdAt ?? null });
    }
  }
  return people;
}
