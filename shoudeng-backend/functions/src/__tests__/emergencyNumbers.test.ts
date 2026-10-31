// twilio.ts touches Firestore at import time; this test only needs the pure table.
jest.mock("firebase-admin", () => ({
  firestore: Object.assign(() => ({ collection: jest.fn() }), { FieldValue: {}, Timestamp: {} }),
  initializeApp: jest.fn(),
}));
jest.mock("firebase-functions", () => ({ config: () => ({}) }));

import { getEmergencyNumber } from "../services/twilio";

// Mirrors ShouDengTests/EmergencyNumbersTests.swift (App Store markets).
const PRIMARY: Record<string, string> = {
  US: "911", CA: "911", HK: "999", MO: "999", TW: "119", SG: "995",
  AU: "000", NZ: "111", MY: "999", TH: "1669", PH: "911", JP: "119",
};

describe("emergency number per App Store market", () => {
  for (const [country, number] of Object.entries(PRIMARY)) {
    it(`${country} → ${number}`, () => {
      expect(getEmergencyNumber(country)).toBe(number);
      expect(getEmergencyNumber(country.toLowerCase())).toBe(number);
    });
  }
  it("unknown region → 112", () => {
    expect(getEmergencyNumber("ZZ")).toBe("112");
  });
});
