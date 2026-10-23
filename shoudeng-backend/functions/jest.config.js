/** @type {import('ts-jest').JestConfigWithTsJest} */
module.exports = {
  preset: "ts-jest",
  testEnvironment: "node",
  roots: ["<rootDir>/src"],
  testMatch: ["**/__tests__/**/*.test.ts"],
  testPathIgnorePatterns: ["/node_modules/", "e2e-bots"],
  moduleFileExtensions: ["ts", "js", "json"],
  clearMocks: true,
  forceExit: true,
};
