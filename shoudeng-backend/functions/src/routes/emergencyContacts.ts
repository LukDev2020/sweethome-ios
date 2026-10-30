import { Router, Request, Response } from "express";
import * as admin from "firebase-admin";
import { authMiddleware } from "../middleware/auth";

/**
 * Personal emergency contacts (people who are not app users). Used by the SOS
 * escalation to text someone when the user has no guardians.
 *
 * GET /v1/emergency-contacts  → LocalEmergencyContact[]
 * PUT /v1/emergency-contacts  ← LocalEmergencyContact[] → { success }
 */
const router = Router();
const db = admin.firestore();

router.use(authMiddleware);

export const MAX_CONTACTS = 10;

export interface EmergencyContact {
  id: string;
  name: string;
  relationship: string;
  phone: string;
  email: string;
  address: string;
  countryCode: string;
}

const str = (v: unknown, max: number) => (typeof v === "string" ? v.trim().slice(0, max) : "");

export function sanitizeContacts(input: unknown): EmergencyContact[] | null {
  if (!Array.isArray(input) || input.length > MAX_CONTACTS) return null;
  const out: EmergencyContact[] = [];
  for (const raw of input) {
    if (!raw || typeof raw !== "object") return null;
    const c = raw as Record<string, unknown>;
    const contact: EmergencyContact = {
      id: str(c.id, 64),
      name: str(c.name, 80),
      relationship: str(c.relationship, 40),
      phone: str(c.phone, 32),
      email: str(c.email, 120),
      address: str(c.address, 200),
      countryCode: str(c.countryCode, 8),
    };
    if (!contact.id || !contact.name || !/^\+?[0-9 ()-]{3,32}$/.test(contact.phone)) return null;
    out.push(contact);
  }
  return out;
}

router.get("/", async (req: Request, res: Response) => {
  try {
    const doc = await db.collection("emergency_contacts").doc(req.uid!).get();
    res.json(doc.exists ? doc.data()?.contacts ?? [] : []);
  } catch (error) {
    console.error("[EmergencyContacts] get error:", error);
    res.status(500).json({ error: "Failed to load emergency contacts" });
  }
});

router.put("/", async (req: Request, res: Response) => {
  const contacts = sanitizeContacts(req.body);
  if (!contacts) {
    res.status(400).json({ error: `Expected an array of at most ${MAX_CONTACTS} contacts with id, name and phone` });
    return;
  }
  try {
    await db.collection("emergency_contacts").doc(req.uid!).set({
      contacts,
      updatedAt: admin.firestore.Timestamp.now(),
    });
    res.json({ success: true });
  } catch (error) {
    console.error("[EmergencyContacts] put error:", error);
    res.status(500).json({ error: "Failed to save emergency contacts" });
  }
});

export default router;
