/**
 * QA Seed Script — Creates 3 test families in Firebase emulators.
 *
 * Family A: Free tier — 1 caregiver (CA) + 1 care receiver (CN)
 * Family B: Family plan — 3 caregivers (Toronto/Shanghai/Paris) + 1 care receiver (CN)
 * Family C: Enhanced — 1 caregiver (CA) + 1 care receiver (CN), Twilio voice enabled
 *
 * Usage:
 *   FIRESTORE_EMULATOR_HOST=localhost:8080 \
 *   FIREBASE_AUTH_EMULATOR_HOST=localhost:9099 \
 *   npx ts-node qa/seed.ts
 */

import * as admin from "firebase-admin";

// --- Init with emulator ---

process.env.FIRESTORE_EMULATOR_HOST =
  process.env.FIRESTORE_EMULATOR_HOST || "localhost:8080";
process.env.FIREBASE_AUTH_EMULATOR_HOST =
  process.env.FIREBASE_AUTH_EMULATOR_HOST || "localhost:9099";

admin.initializeApp({ projectId: "sweethome-d1edd" });
const db = admin.firestore();
const auth = admin.auth();

// --- Helpers ---

function ts(date?: Date): admin.firestore.Timestamp {
  return admin.firestore.Timestamp.fromDate(date ?? new Date());
}

async function createUser(
  uid: string,
  phone: string,
  displayName: string,
  role: "protected" | "guardian",
  countryCode: string,
  timeZone: string,
  cityName: string,
  plan: string = "free"
): Promise<void> {
  // Create Auth user
  await auth.createUser({ uid, phoneNumber: phone, displayName });

  // Create Firestore user doc
  await db
    .collection("users")
    .doc(uid)
    .set({
      displayName,
      phone,
      role,
      avatarInitial: displayName.charAt(0).toUpperCase(),
      countryCode,
      timeZone,
      cityName,
      notificationPrefs: {
        sosAlerts: true,
        checkinReminder: true,
        checkinOverdue: true,
        familyFeed: true,
      },
      createdAt: ts(),
      updatedAt: ts(),
    });

  // Create subscription doc
  await db.collection("subscriptions").doc(uid).set({
    plan,
    status: "active",
    expiresAt: null,
    features: plan === "free" ? ["basic"] : ["basic", "voice", "evidence"],
  });
}

async function createLink(
  guardianId: string,
  protectedPersonId: string,
  permissions: Record<string, boolean> = {}
): Promise<string> {
  const linkId = `${guardianId}_${protectedPersonId}`;
  await db
    .collection("guardian_links")
    .doc(linkId)
    .set({
      guardianId,
      protectedPersonId,
      status: "active",
      createdAt: ts(),
      acceptedAt: ts(),
      revokedAt: null,
      protectionLayers: 1,
      permissions: {
        canSeeLocation: true,
        canSeeBattery: true,
        canSeeHealth: false,
        canSeePhoneActivity: false,
        canHearEmergencyAudio: false,
        ...permissions,
      },
    });
  return linkId;
}

async function createDeviceToken(
  userId: string,
  token: string
): Promise<void> {
  await db.collection("device_tokens").add({
    userId,
    token,
    platform: "ios",
    environment: "sandbox",
    updatedAt: ts(),
  });
}

async function createSafeZone(
  userId: string,
  name: string,
  lat: number,
  lng: number,
  radius: number
): Promise<string> {
  const ref = await db.collection("safe_zones").add({
    userId,
    name,
    lat,
    lng,
    radius,
    isActive: true,
  });
  return ref.id;
}

// --- Family A: Free tier ---
// Caregiver: Alice Wang (CA, +1-4165551001)
// Care Receiver: Bob Li (CN, +86-13800001001)

async function seedFamilyA(): Promise<void> {
  console.log("Seeding Family A (Free tier)...");

  await createUser(
    "alice-a",
    "+14165551001",
    "Alice Wang",
    "guardian",
    "CA",
    "America/Toronto",
    "Toronto"
  );

  await createUser(
    "bob-a",
    "+8613800001001",
    "Bob Li",
    "protected",
    "CN",
    "Asia/Shanghai",
    "Shanghai",
    "free"
  );

  await createLink("alice-a", "bob-a");

  await createDeviceToken("alice-a", "fake-apns-token-alice-a");
  await createDeviceToken("bob-a", "fake-apns-token-bob-a");

  // Bob's safe zone: home in Shanghai
  await createSafeZone("bob-a", "Home", 31.2304, 121.4737, 200);

  // Seed some historical check-ins (last 3 days)
  const now = new Date();
  for (let d = 0; d < 3; d++) {
    const ciDate = new Date(now);
    ciDate.setDate(ciDate.getDate() - d);
    ciDate.setHours(9, 0, 0, 0);
    await db.collection("checkins").add({
      userId: "bob-a",
      timestamp: ts(ciDate),
      lat: 31.2304,
      lng: 121.4737,
      note: d === 0 ? "早上好" : null,
    });
  }

  // Seed a timeline entry
  await db.collection("timeline_entries").add({
    userId: "bob-a",
    timestamp: ts(),
    type: "checkin",
    description: "报了平安",
    detail: null,
  });

  console.log("  Family A seeded: alice-a (guardian CA) <-> bob-a (protected CN)");
}

// --- Family B: Family plan ---
// Caregivers: Carol (Toronto), Dave (Shanghai), Eve (Paris)
// Care Receiver: Frank (CN, Shanghai)

async function seedFamilyB(): Promise<void> {
  console.log("Seeding Family B (Family plan, 3 caregivers)...");

  await createUser(
    "carol-b",
    "+14165552001",
    "Carol Chen",
    "guardian",
    "CA",
    "America/Toronto",
    "Toronto"
  );

  await createUser(
    "dave-b",
    "+8613800002001",
    "Dave Zhang",
    "guardian",
    "CN",
    "Asia/Shanghai",
    "Shanghai"
  );

  await createUser(
    "eve-b",
    "+33612345678",
    "Eve Dupont",
    "guardian",
    "FR",
    "Europe/Paris",
    "Paris"
  );

  await createUser(
    "frank-b",
    "+8613800002002",
    "Frank Wang",
    "protected",
    "CN",
    "Asia/Shanghai",
    "Shanghai",
    "family"
  );

  await createLink("carol-b", "frank-b");
  await createLink("dave-b", "frank-b");
  await createLink("eve-b", "frank-b");

  await createDeviceToken("carol-b", "fake-apns-token-carol-b");
  await createDeviceToken("dave-b", "fake-apns-token-dave-b");
  await createDeviceToken("eve-b", "fake-apns-token-eve-b");
  await createDeviceToken("frank-b", "fake-apns-token-frank-b");

  // Duty schedule: Carol 0-8, Dave 8-16, Eve 16-24 (UTC)
  const days = [0, 1, 2, 3, 4, 5, 6]; // All days
  for (const day of days) {
    await db.collection("duty_schedules").add({
      guardianId: "carol-b",
      protectedPersonId: "frank-b",
      dayOfWeek: day,
      startHour: 0,
      endHour: 8,
      isActive: true,
    });
    await db.collection("duty_schedules").add({
      guardianId: "dave-b",
      protectedPersonId: "frank-b",
      dayOfWeek: day,
      startHour: 8,
      endHour: 16,
      isActive: true,
    });
    await db.collection("duty_schedules").add({
      guardianId: "eve-b",
      protectedPersonId: "frank-b",
      dayOfWeek: day,
      startHour: 16,
      endHour: 24,
      isActive: true,
    });
  }

  // Frank's safe zones
  await createSafeZone("frank-b", "Home", 31.2345, 121.4689, 200);
  await createSafeZone("frank-b", "Park", 31.238, 121.472, 300);

  // Seed 14 days of check-ins (for baseline scorer testing)
  const now = new Date();
  for (let d = 0; d < 14; d++) {
    const ciDate = new Date(now);
    ciDate.setDate(ciDate.getDate() - d);
    // Vary check-in time: 8-10 AM Shanghai time
    ciDate.setHours(Math.floor(Math.random() * 2) + 8, Math.floor(Math.random() * 60), 0, 0);
    await db.collection("checkins").add({
      userId: "frank-b",
      timestamp: ts(ciDate),
      lat: 31.2345 + (Math.random() - 0.5) * 0.001,
      lng: 121.4689 + (Math.random() - 0.5) * 0.001,
      note: null,
    });
  }

  console.log(
    "  Family B seeded: carol-b/dave-b/eve-b (guardians) <-> frank-b (protected)"
  );
}

// --- Family C: Enhanced with Twilio voice ---
// Caregiver: Grace (CA)
// Care Receiver: Henry (CN), enhanced plan

async function seedFamilyC(): Promise<void> {
  console.log("Seeding Family C (Enhanced, Twilio voice)...");

  await createUser(
    "grace-c",
    "+14165553001",
    "Grace Liu",
    "guardian",
    "CA",
    "America/Toronto",
    "Toronto"
  );

  await createUser(
    "henry-c",
    "+8613800003001",
    "Henry Chen",
    "protected",
    "CN",
    "Asia/Shanghai",
    "Shanghai",
    "enhanced"
  );

  await createLink("grace-c", "henry-c", {
    canSeeLocation: true,
    canSeeBattery: true,
    canSeeHealth: true,
    canSeePhoneActivity: true,
    canHearEmergencyAudio: true,
  });

  await createDeviceToken("grace-c", "fake-apns-token-grace-c");
  await createDeviceToken("henry-c", "fake-apns-token-henry-c");

  // Henry's safe zone and medical card
  await createSafeZone("henry-c", "Home", 31.22, 121.46, 200);

  await db
    .collection("medical_cards")
    .doc("henry-c")
    .set({
      bloodType: "A+",
      allergies: ["Penicillin"],
      medications: ["Metformin 500mg"],
      conditions: ["Type 2 Diabetes"],
      insuranceProvider: "China Life",
      insurancePolicyNumber: "CL-2026-12345",
      emergencyNote: "Has insulin in bag",
      organDonor: false,
      weight: 72,
      height: 170,
    });

  // Henry's selected hotline
  await db
    .collection("selected_hotlines")
    .doc("henry-c")
    .set({
      countryCode: "CN",
      countryName: "China",
      flag: "🇨🇳",
      emergency: "120",
      embassy: "",
      selectedPhone: "120",
      selectedLabel: "急救中心",
    });

  console.log("  Family C seeded: grace-c (guardian CA) <-> henry-c (protected CN, enhanced)");
}

// --- Main ---

async function main(): Promise<void> {
  console.log("=== Vela QA Seed Script ===");
  console.log(
    `Firestore: ${process.env.FIRESTORE_EMULATOR_HOST}`
  );
  console.log(
    `Auth: ${process.env.FIREBASE_AUTH_EMULATOR_HOST}`
  );
  console.log("");

  try {
    await seedFamilyA();
    await seedFamilyB();
    await seedFamilyC();

    console.log("\n=== Seed complete ===");
    console.log("Users: alice-a, bob-a, carol-b, dave-b, eve-b, frank-b, grace-c, henry-c");
    console.log("Links: 5 guardian_links (3 for family B)");
    console.log("Safe zones: 4");
    console.log("Check-ins: ~17 (3 for A, 14 for B)");
    console.log("Device tokens: 8");
    console.log("Duty schedules: 21 (7 days x 3 shifts for family B)");
  } catch (error) {
    console.error("Seed failed:", error);
    process.exit(1);
  }

  process.exit(0);
}

main();
