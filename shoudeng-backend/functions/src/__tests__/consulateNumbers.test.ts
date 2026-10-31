jest.mock("firebase-admin", () => ({
  firestore: Object.assign(() => ({ collection: jest.fn() }), { FieldValue: {}, Timestamp: {} }),
  initializeApp: jest.fn(),
}));
jest.mock("firebase-functions", () => ({ config: () => ({}) }));
// eslint-disable-next-line @typescript-eslint/no-var-requires
const { CONSULATE_DATA } = require("../routes/consulate");
// eslint-disable-next-line @typescript-eslint/no-var-requires
const { getEmergencyNumber } = require("../services/twilio");

describe("consulate data", () => {
  it("each country's emergency number is the ambulance-first number", () => {
    for (const code of Object.keys(CONSULATE_DATA)) {
      expect([code, CONSULATE_DATA[code].emergency]).toEqual([code, getEmergencyNumber(code)]);
    }
  });

  // Consular protection lines checked on official embassy / consulate sites, 2026-10-31
  it.each([
    ["US", "+1-202-495-2216"], ["JP", "+81-3-6450-2195"], ["SG", "+65-6475-0165"],
    ["PH", "+63-2-8231-1033"], ["AU", "+61-2-6228-3948"],
  ])("%s embassy line is %s", (code, phone) => {
    expect(CONSULATE_DATA[code].embassy).toBe(phone);
  });

  it("Australian consulates and Chiang Mai duty line are current", () => {
    const au = CONSULATE_DATA.AU.consulates.map((c: { phone: string }) => c.phone);
    expect(au).toEqual(["+61-2-9550-5519", "+61-3-9824-8810"]);
    expect(CONSULATE_DATA.TH.consulates[0].phone).toBe("+66-81-882-3283");
  });
});
