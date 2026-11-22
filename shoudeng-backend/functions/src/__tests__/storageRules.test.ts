/**
 * Cloud Storage holds evidence PDFs, GPX tracks and family photos. Clients never
 * touch it directly (Admin SDK + signed URLs only), so the deployed rules must
 * refuse all direct access — and firebase.json must deploy them.
 */
import * as fs from "fs";
import * as path from "path";

const root = path.join(__dirname, "../../..");

describe("storage.rules", () => {
  const rules = fs.readFileSync(path.join(root, "storage.rules"), "utf8");
  const code = rules.replace(/\/\/.*$/gm, "");

  test("is deployed by firebase.json", () => {
    const config = JSON.parse(fs.readFileSync(path.join(root, "firebase.json"), "utf8"));
    expect(config.storage?.rules).toBe("storage.rules");
  });

  test("refuses every direct read and write", () => {
    expect(code).toMatch(/match \/\{allPaths=\*\*\}/);
    expect(code).toMatch(/allow read, write: if false;/);
    // No rule anywhere grants access
    expect(code).not.toMatch(/if\s+(true|request\.auth)/);
  });
});
