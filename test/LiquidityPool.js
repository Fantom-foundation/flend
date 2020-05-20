const {
    BN,
    ether,
    expectRevert,
    time,
    balance,
} = require('openzeppelin-test-helpers');

const { expect } = require('chai');
const { promiseExpect } = require('chai-as-promised');
var should = require('chai').should();


const Web3 = require('web3');
var web3 = new Web3();
web3.setProvider(Web3.givenProvider || 'ws://localhost:9545')//..Web3.givenProvider);

const LiquidityPool = artifacts.require('LiquidityPool');
const TestOracle = artifacts.require('TestOracle');
const TestSFC = artifacts.require('TestSFC');
const TestToken = artifacts.require('TestToken');
const contractGasLimit = 4712388;

const nativeTokenAddr = '0xFFfFfFffFFfffFFfFFfFFFFFffFFFffffFfFFFfF';
const nonNativeTokenAddr = '0xC17518AE5dAD82B8fc8b56Fe0295881c30848829';

const sfcAddress = '0xFC00FACE00000000000000000000000000000000';
const fUSDAddress = '0xC17518AE5dAD82B8fc8b56Fe0295881c30848829';

contract('liquidity pool test', async (wallets) => {
  const owner = wallets[0];

  const alice = wallets[1];
  const bob = wallets[2];
  const carol = wallets[3];
  const dave = wallets[4];
  const frank = wallets[5];
  const grace = wallets[6];

  beforeEach(async function () {
    testSFC = await TestSFC.new();
    
    testToken = await TestToken.new('Test', 'tst', 3);
    testToken2 = await TestToken.new('Test2', 'tst2', 3);

    testOracle = await TestOracle.new();
    testOracle.setPrice(testToken.address, Web3.utils.toBN('1'));
    testOracle.setPrice(testToken2.address, Web3.utils.toBN('1'));
    testOracle.setPrice(nativeTokenAddr, Web3.utils.toBN('1'));
    testOracle.setPrice(nonNativeTokenAddr, Web3.utils.toBN('2'));
    
    liquiditypool = await newLiquidityPool(testSFC, testOracle, testToken)
    amt = 100000000000
    await testToken.increaseAllowance(liquiditypool.address, amt)
    await testToken2.increaseAllowance(liquiditypool.address, amt)
  });

  it('checking pool parameters', checkPoolParams);
});

async function newLiquidityPool(testSFC, testOracle, fusd) {
  liquiditypool = await LiquidityPool.new(nativeTokenAddr, fusd.address, testOracle.address, testSFC.address);
    if (liquiditypool.constructor._json.deployedBytecode.length >= contractGasLimit)
      throw "gas limit exceeded"
  return liquiditypool
}

async function checkPoolParams() {
  const resReward = liquiditypool.getReward()
  const {0: rewardNum, 1: rewardDenom} = resReward;
  expect(rewardNum === 0 && rewardDenom === 1);

  const resFee = liquiditypool.getFee()
  const {0: feeNum, 1: feeDenom} = resFee;
  expect(feeNum === 0 && feeDenom === 1);

  const resLimit = liquiditypool.getLimit()
  const {0: limitNum, 1: limitDenom} = resLimit;
  expect(limitNum === 1 && limitDenom === 1);
}
