var TestOracle = artifacts.require("TestOracle");
var LiquidityPool = artifacts.require("LiquidityPool");

module.exports = function(deployer) {
  deployer.deploy(TestOracle, '0xC17518AE5dAD82B8fc8b56Fe0295881c30848829');
  deployer.deploy(LiquidityPool,
      '0xFFfFfFffFFfffFFfFFfFFFFFffFFFffffFfFFFfF',
      '0xFC00FACE00000000000000000000000000000000',
      '0xC17518AE5dAD82B8fc8b56Fe0295881c30848829',
      '0xC17518AE5dAD82B8fc8b56Fe0295881c30848829');
};
