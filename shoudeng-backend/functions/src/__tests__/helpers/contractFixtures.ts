import * as fs from "fs";
import * as path from "path";

/** Shared with the iOS test target (ShouDengTests/ContractFixtureTests.swift). */
export const CONTRACT_FIXTURE_DIR = path.resolve(
  __dirname, "../../../../../ShouDengTests/ContractFixtures"
);

export function writeContractFixture(name: string, body: unknown) {
  fs.mkdirSync(CONTRACT_FIXTURE_DIR, { recursive: true });
  fs.writeFileSync(path.join(CONTRACT_FIXTURE_DIR, name), JSON.stringify(body, null, 2) + "\n");
}

/**
 * Compare route output with the committed fixture the iOS suite decodes.
 * UPDATE_CONTRACT_FIXTURES=1 (or a missing fixture) rewrites it.
 */
export function expectMatchesFixture(name: string, body: unknown) {
  const file = path.join(CONTRACT_FIXTURE_DIR, name);
  if (process.env.UPDATE_CONTRACT_FIXTURES === "1" || !fs.existsSync(file)) {
    writeContractFixture(name, body);
    return;
  }
  const committed = JSON.parse(fs.readFileSync(file, "utf8"));
  expect(JSON.parse(JSON.stringify(body))).toEqual(committed);
}
