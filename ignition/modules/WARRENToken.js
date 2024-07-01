const { buildModule } = require("@nomicfoundation/hardhat-ignition/modules");

module.exports = buildModule("WARRENToken", (m) => {
  const warrenToken = m.contract("WARRENToken");
  return { warrenToken };
});