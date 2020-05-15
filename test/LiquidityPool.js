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

  it('test collateral works', async () => {
    await testCollateralWorks(wallets)
    
  });
  it('checking pool parameters', checkPoolParams);
  it('epoch snapshot test', epochSnapshotTest);
  it('test add collateral to list', testAddCollateral);
  it ('test failed deposit', async () => {
    await failDepositWithZeroAmt();
    await failDepositWithMsgValue(wallets);
    await failDepositWithValueAmount(wallets);
  });
  it ('test success deposit', async () => {
    await successDepositWithValueAmount(wallets[0], 1000, testToken)
  })
  it ('test fail withdraw too much', async () => {
    await failWithdrawTooMuch(wallets)
  })
  it ('test fail withdraw with zero amt', async () => {
    await failWithdrawWithZeroAmt()
  })
  it ('test success withdraw', async () => {
    await successWithdraw(wallets)
  });
  it ('test failed borrow', async () => {
    await failBorrowWithZeroAmt(wallets);
    await failBorrowWithTokenValue(wallets);
    await failBorrowWithNativeDenom(wallets);
    await failBorrowWithCollateralValue(wallets);
  });
  it ('test success borrow', async () => {
    await successBorrow(wallets, 1000, Web3.utils.toBN('1'))
  })
  it ('test failed repay', async () => {
    await failRepayWithNativeDenom(wallets);
    await failRepayWithZeroAmt(wallets);
    await failRepayWithEthErc20Transfer(wallets);
  });
  it ('test success repay', async () => {
    await successRepay(wallets)
  });
  it ('test failed buy', async () => {
    await failBuyWithZeroAmt(wallets);
    await failBuyWithNativeDenom(wallets);
    await failBuyWithFusd(wallets);
  });
  it ('test success buy', async () => {
    await successBuy(wallets)
  });
  it ('test failed sell', async () => {
    await failSellWithZeroAmt(wallets);
    await failSellWithNativeDenom(wallets);
    await failSellWithFusd(wallets)
  });
  it ('test success sell', async () => {
    await successSell(wallets)
  });
  it ('test calcCollateralValue', async () => {
    await testCalcCollateralValue(wallets[0])
  });
  it ('test calcDebtValue', async () => {
    await testCalcDebtValue(wallets[0])
  });
  it ('test claimDelegationRewards', async () => {
    await testClaimDelegationRewards()
  });
  it ('test claimValidatorRewards', async () => {
    await testClaimValidatorRewards()
  });

});

async function newLiquidityPool(testSFC, testOracle, fusd) {
  liquiditypool = await LiquidityPool.new(nativeTokenAddr, testSFC.address, testOracle.address, fusd.address);
    if (liquiditypool.constructor._json.deployedBytecode.length >= contractGasLimit)
      throw "gas limit exceeded"
  return liquiditypool
}

async function failSellWithZeroAmt(wallets) {
  let zeroAmt = Web3.utils.toBN('0')
  await tryCatch(liquiditypool.sell(nativeTokenAddr, zeroAmt), 'VM Exception while processing transaction: revert');
}

async function failSellWithNativeDenom(wallets) {
  let amt = Web3.utils.toBN('1')
  await tryCatch(liquiditypool.sell(nativeTokenAddr, amt), 'VM Exception while processing transaction: revert');
}

async function failSellWithFusd(wallets) {
  let amt = Web3.utils.toBN('1')
  await tryCatch(liquiditypool.sell(fUSDAddress, amt), 'VM Exception while processing transaction: revert');
}

async function failBuyWithZeroAmt(wallets) {
  let zeroAmt = Web3.utils.toBN('0')
  await tryCatch(liquiditypool.buy(nativeTokenAddr, zeroAmt), 'VM Exception while processing transaction: revert');
}

async function failBuyWithNativeDenom(wallets) {
  let amt = Web3.utils.toBN('1')
  await tryCatch(liquiditypool.buy(nativeTokenAddr, amt), 'VM Exception while processing transaction: revert');
}

async function failBuyWithFusd(wallets) {
  let amt = Web3.utils.toBN('1')
  await tryCatch(liquiditypool.buy(fUSDAddress, amt), 'VM Exception while processing transaction: revert');
}

async function successBuy(wallets) {
  await testToken.increaseAllowance(liquiditypool.address, 1000);
  await testToken2.increaseAllowance(liquiditypool.address, 1000);

  let msg = {from: wallets[0]};
  let amt = Web3.utils.toBN('1');
  let beginBalance = await testToken2.balanceOf(wallets[0]);
  await liquiditypool.buy(testToken2.address, amt, msg);

  expect(await testToken2.balanceOf(wallets[0])).to.be.bignumber.equal(beginBalance.add(amt));
}

async function successSell(wallets) {
  let msg = {from: wallets[0]};
  let amt = Web3.utils.toBN('10');
  let beginBalance = await testToken2.balanceOf(wallets[0]);
  beginBalance2 = await testToken2.balanceOf(liquiditypool.address);

  await liquiditypool.sell(testToken2.address, amt, msg);

  expect(await testToken2.balanceOf(wallets[0])).to.be.bignumber.equal(beginBalance.sub(amt));
}

async function failRepayWithNativeDenom(wallets) {
  let amt = Web3.utils.toBN('1')
  await tryCatch(liquiditypool.repay(nativeTokenAddr, amt), 'VM Exception while processing transaction: revert');
}

async function failRepayWithZeroAmt(wallets) {
  let zeroAmt = Web3.utils.toBN('0')
  await tryCatch(liquiditypool.repay(nativeTokenAddr, zeroAmt), 'VM Exception while processing transaction: revert');
}

async function testCollateralWorks(wallets) {
  const testUsr = wallets[1]
  const tokenAddr = fUSDAddress
  const amtToMint = Web3.utils.toBN('100')
  const amtToDeposit = Web3.utils.toBN('1')
  await testToken.increaseAllowance(liquiditypool.address, 1000)

  await liquiditypool.deposit(testToken.address, amtToDeposit)
}

async function failRepayWithEthErc20Transfer(wallets) {
  let amt = Web3.utils.toBN('0')
  let msg = {from: wallets[0], value: amt}
  await tryCatch(liquiditypool.repay(nativeTokenAddr, amt, msg), 'VM Exception while processing transaction: revert');
}

async function successRepay(wallets) {
  let amt = Web3.utils.toBN('1')
  await successBorrow(wallets, 1000, amt)

  msg = {from: wallets[0], sender:wallets[0]}
  const res = await liquiditypool._debtTokens(wallets[0], testToken2.address)
  res.eq(amt).should.be.true

  await liquiditypool.repay(testToken2.address, amt, msg)
}

async function failBorrowWithCollateralValue(wallets) {
  let amt = Web3.utils.toBN('1')
  await tryCatch(liquiditypool.borrow(nonNativeTokenAddr, amt), 'VM Exception while processing transaction: revert');
}

async function failBorrowWithTokenValue(wallets) {
  let amt = Web3.utils.toBN('1')
  let amt2 = Web3.utils.toBN('2221')
  // justDeposit(wallets[0], nonNativeTokenAddr, amt2) fails now
  const fakeToken = '0xf1ff'
  await tryCatch(liquiditypool.borrow(fakeToken, amt), 'VM Exception while processing transaction: revert');
}

async function successBorrow(wallets, depositAmt, borrowVal) {
  await successDepositWithValueAmount(wallets[0], depositAmt, testToken)
  await successDepositWithValueAmount(wallets[0], depositAmt, testToken2)
  msg = {from: wallets[0]}
  await liquiditypool.borrow(testToken2.address, borrowVal, msg)
  const res = await liquiditypool._debtTokens(wallets[0], testToken2.address)
  res.eq(borrowVal).should.be.true
}

async function failBorrowWithNativeDenom(wallets) {
  let amt = Web3.utils.toBN('1')
  await tryCatch(liquiditypool.borrow(nativeTokenAddr, amt), 'VM Exception while processing transaction: revert');
}

async function failBorrowWithZeroAmt(wallets) {
  let zeroAmt = Web3.utils.toBN('0')
  await tryCatch(liquiditypool.borrow(nativeTokenAddr, zeroAmt), 'VM Exception while processing transaction: revert');
}

async function checkPoolParams() {
  expect(await liquiditypool.calcCollateralValue.call(nativeTokenAddr)).to.be.bignumber.equal(ether('0'));
}

async function epochSnapshotTest() {
  // TODO: Unstable test!!!
  let currentEpoch = Web3.utils.toBN('1')
  let expectedVal = Web3.utils.toBN('0') // TODO change to blocktime

  let currentSnapshot = await liquiditypool.epochSnapshots(currentEpoch)
  let block = await web3.eth.getBlock("latest")
  expect(currentSnapshot.endTime).to.be.bignumber.equal(expectedVal)

  await liquiditypool._makeEpochSnapshot()
  
  currentSnapshot = await liquiditypool.epochSnapshots(currentEpoch)
  let expectedTime = Web3.utils.toBN(block.timestamp)
  expect(currentSnapshot.endTime).to.be.bignumber.equal(expectedTime)
}

async function testAddCollateral() {
    let zeroAmt = Web3.utils.toBN('0')
    let amt = Web3.utils.toBN('1')
    let newAcc = web3.eth.accounts.create();
    await tryCatch(liquiditypool.deposit(nativeTokenAddr, zeroAmt), 'VM Exception while processing transaction: revert');
}

async function failDepositWithZeroAmt() {
  let zeroAmt = Web3.utils.toBN('0')
  await tryCatch(liquiditypool.deposit(nativeTokenAddr, zeroAmt), 'VM Exception while processing transaction: revert');
}

async function failWithdrawWithZeroAmt() {
  let zeroAmt = Web3.utils.toBN('0')
  await tryCatch(liquiditypool.withdraw(nativeTokenAddr, zeroAmt), 'VM Exception while processing transaction: revert');
}

async function failDepositWithMsgValue(wallets) {
  let zeroAmt = Web3.utils.toBN('0')
  let nonZeroAmt = Web3.utils.toBN('1')
  let msg = {from: wallets[0], value: zeroAmt}
  await tryCatch(liquiditypool.deposit(nativeTokenAddr, nonZeroAmt, msg), 'VM Exception while processing transaction: revert');
}

async function failWithdrawTooMuch(wallets) {
  await successDepositWithValueAmount(wallets[0], 1000, testToken)
  
  let nonZeroAmt = Web3.utils.toBN('1')
  let res = await liquiditypool._collateralTokens(wallets[0], testToken.address)
  let valToWithdraw = res.add(nonZeroAmt)

  await tryCatch(liquiditypool.withdraw(testToken.address, valToWithdraw), 'VM Exception while processing transaction: revert');
}

async function successWithdraw(wallets) {
  const valToDeposit = 1000
  const valBigint = Web3.utils.toBN('1000')
  const zeroAmt = Web3.utils.toBN('0')
  await successDepositWithValueAmount(wallets[0], valToDeposit, testToken)
  const tokens = await liquiditypool._collateralTokens(wallets[0], testToken.address)
  tokens.eq(zeroAmt).should.be.false

  const collateralValue = await liquiditypool.calcCollateralValue(wallets[0])
  const debtValue = await liquiditypool.calcDebtValue(wallets[0])
  console.log("collateralValue", collateralValue)
  console.log("debtValue", debtValue)

  await liquiditypool.withdraw(testToken.address, valBigint), 'VM Exception while processing transaction: revert';
}

async function failDepositWithValueAmount(wallets) {
  let nonZeroAmt = Web3.utils.toBN('1')
  let nonZeroAmt2 = Web3.utils.toBN('2')
  let msg = {from: wallets[0], value: nonZeroAmt}
  await tryCatch(liquiditypool.deposit(nonNativeTokenAddr, nonZeroAmt2, msg), 'VM Exception while processing transaction: revert');
}

async function successDepositWithValueAmount(addr, val, token) {
  const strVal = parseInt(val)
  const expectedBn = Web3.utils.toBN(strVal)
  await depositAndAllow(val, token)
  const res = await liquiditypool._collateralTokens(addr, token.address)
  res.eq(expectedBn).should.be.true
}

async function depositAndAllow(amt, token) {
  const valStr = parseInt(amt)
  const amtToDeposit = Web3.utils.toBN(valStr)
  await liquiditypool.deposit(token.address, amtToDeposit)
}

async function justDeposit(fromAddr, token, amount) {
  let zeroAmt = Web3.utils.toBN('0')
  let msg = {from: fromAddr, value: zeroAmt}
  await liquiditypool.deposit(token, amount, msg);
}

async function  testCalcCollateralValue(addr) {
  expect(await liquiditypool.calcCollateralValue(addr)).to.be.bignumber.equal(Web3.utils.toBN('0'))

  let nonZeroAmt2 = Web3.utils.toBN('2')
  msg = {from: addr, value: nonZeroAmt2}
  await liquiditypool.deposit(nativeTokenAddr, nonZeroAmt2, msg);

  expect(await liquiditypool.calcCollateralValue(addr)).to.be.bignumber.equal(Web3.utils.toBN(nonZeroAmt2))
}

async function  testCalcDebtValue(addr) {
  expect(await liquiditypool.calcDebtValue(addr)).to.be.bignumber.equal(Web3.utils.toBN('0'))

  let nonZeroAmt2 = Web3.utils.toBN('2')
  msg = {from: addr, value: nonZeroAmt2}
  await liquiditypool.deposit(nativeTokenAddr, nonZeroAmt2, msg);

  expect(await liquiditypool.calcDebtValue(addr)).to.be.bignumber.equal(Web3.utils.toBN(nonZeroAmt2))
}

async function  testClaimDelegationRewards() {
  testSFC.setDelegationRewards(1, 1, 1);
  await testSFC.calcDelegationRewards(sfcAddress, 2, 3); // TODO: Why test fail without this call?

  expect(await liquiditypool.claimDelegationRewards(Web3.utils.toBN('1')))
}

async function  testClaimValidatorRewards() {
  testSFC.setValidatorRewards(1, 1, 1);
  await testSFC.calcValidatorRewards(sfcAddress, 2, 3); // TODO: Why test fail without this call?

  expect(await liquiditypool.claimValidatorRewards(Web3.utils.toBN('1')))
}

tryCatch = async function(promise, errType) {
  try {
    await promise;
    throw null;
  }
  catch (error) {
    assert(error, "Expected an error but did not get one");
    // assert(error.message.startsWith(PREFIX + errType), "Expected an error starting with '" + PREFIX + errType + "' but got '" + error.message + "' instead");
  }
};

// a list for saving subscribed event instances
const subscribedEvents = {}
// Subscriber method
const subscribeLogEvent = (contract, eventName) => {
  console.log("enter event")
  const eventJsonInterface = web3.utils._.find(
    contract._jsonInterface,
    o => o.name === eventName && o.type === 'event',
  )
  console.log("eventJsonInterface", eventJsonInterface)
  const subscription = web3.eth.subscribe('logs', {
    // address: contract.options.address,
    // topics: [eventJsonInterface.signature]
  }, (error, result) => {
    
    if (!error) {
      const eventObj = web3.eth.abi.decodeLog(
        eventJsonInterface.inputs,
        result.data,
        result.topics.slice(1)
      )
      console.log(`New ${eventName}!`, eventObj)
    } else {
      console.log("transaction error:", error)
    }
  })
  subscribedEvents[eventName] = subscription
}