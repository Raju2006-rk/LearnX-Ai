/** @type {import('jest').Config} */
module.exports = {
  testEnvironment: "node",
  testMatch: ["**/*.test.js"],
  // Emulator round-trips can be slower than the Jest default on cold start.
  testTimeout: 20000,
};
