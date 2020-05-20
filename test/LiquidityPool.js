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

const sfcAddress = '0xFC00FACE00000000000000000000000000000000';
const fUSDAddress = '0xC17518AE5dAD82B8fc8b56Fe0295881c30848829';

const wallet1BeginBalance = 1000000000;

contract('liquidity pool test', async (wallets) => {
  const owner = wallets[0];

  beforeEach(async function () {
    testSFC = await TestSFC.new();
    
    nativeToken = await TestToken.new('Test', 'tst', 3);
    testToken2 = await TestToken.new('Test2', 'tst2', 3);

    testOracle = await TestOracle.new();
    testOracle.setPrice(nativeToken.address, Web3.utils.toBN('1'));
    testOracle.setPrice(testToken2.address, Web3.utils.toBN('1'));

    liquiditypool = await newLiquidityPool(nativeToken, testToken2, testOracle, testSFC);
    amt = Web3.utils.toBN('100000000000');

    let msg = {from: wallets[0]};
    await nativeToken.increaseAllowance(liquiditypool.address, amt, msg);
    await nativeToken.increaseAllowance(wallets[1], amt, msg);
    await nativeToken.increaseAllowance(wallets[0], amt, msg);
    await testToken2.increaseAllowance(liquiditypool.address, amt, msg);
    await testToken2.increaseAllowance(wallets[0], amt, msg);
    await testToken2.increaseAllowance(wallets[1], amt, msg);
    msg = {from: wallets[1]};
    await nativeToken.increaseAllowance(liquiditypool.address, amt, msg);
    await nativeToken.increaseAllowance(wallets[0], amt, msg);
    await nativeToken.increaseAllowance(wallets[1], amt, msg);
    await testToken2.increaseAllowance(liquiditypool.address, amt, msg);
    await testToken2.increaseAllowance(wallets[0], amt, msg);
    await testToken2.increaseAllowance(wallets[1], amt, msg);
  });

  it('checking pool parameters', checkPoolParams);
  it('test success deposit no reward', async () => {
    await checkSuccessDepositNoReward(wallets)
  });
  it('test success deposit with reward', async () => {
    await checkSuccessDepositWithReward(wallets)
  });
});

async function newLiquidityPool(nativeToken, fusd, testOracle, testSFC) {
  liquiditypool = await LiquidityPool.new(nativeToken.address, fusd.address, testOracle.address, testSFC.address);
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

async function checkSuccessDepositNoReward(wallets) {
  await nativeToken.transferFrom(wallets[0], wallets[1], wallet1BeginBalance);

  let nonZeroAmt = Web3.utils.toBN('100');

  let msg = {from: wallets[1]};
  res = await liquiditypool.deposit(nonZeroAmt, msg);
  expect(res.receipt != null);

  expect(nativeToken.balanceOf(wallets[1]) === (wallet1BeginBalance - nonZeroAmt));
  expect(testToken2.balanceOf(wallets[1]) === nonZeroAmt);
}

async function checkSuccessDepositWithReward(wallets) {
  await nativeToken.transferFrom(wallets[0], wallets[1], wallet1BeginBalance);

  let nonZeroAmt = Web3.utils.toBN('100');

  // With reward
  await liquiditypool.setReward(1, 100);

  let msg = {from: wallets[1]};
  res = await liquiditypool.deposit(nonZeroAmt, msg);
  expect(res.receipt != null);

  expect(nativeToken.balanceOf(wallets[1]) === (wallet1BeginBalance - nonZeroAmt));
  expect(testToken2.balanceOf(wallets[1]) === (nonZeroAmt + 1));
}