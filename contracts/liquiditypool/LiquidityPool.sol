pragma solidity ^0.5.0;

/*
constructor(token contract, sfc contract, oracle contract, usd token contract)
getPrice() uint256 priceNative, uint256 priceUSD
getInfo() address tokenNative, uint256 rewardNum, uint256 rewardDenom, uint256 feeNum, uint256 feeDenom, uint256 limitNum, uint256 limitDenom
deposit(uint256 _value token) bool success
depositInfo(uint256 _value token)
withdraw(uint256 _value token) bool success
withdrawInfo(uint256 _value token)
*/

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20Mintable.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "../interface/Oracle.sol";
import "../interface/SFC.sol";

contract LiquidityPool is ReentrancyGuard {
    using SafeMath for uint256;
    using Address for address;
    using SafeERC20 for ERC20;

    // Users
    address internal owner;
    mapping (address => bool) internal admins;
    mapping (address => bool) internal rewardEditors;
    mapping (address => bool) internal feeEditors;
    mapping (address => bool) internal limitEditors;

    // Init values (contracts)
    ERC20 internal token;
    ERC20 internal fUSD;
    ERC20Mintable internal fUSDmint;
    IOracle internal oracle;
    ISFC internal sfc;

    uint256 internal addLkPercentRewardNum;
    uint256 internal addLkPercentRewardDenom;
    uint256 internal getLkPercentFeeNum;
    uint256 internal getLkPercentFeeDenom;
    uint256 internal getLkPercentLimitNum;
    uint256 internal getLkPercentLimitDenom;

    // Epoch reward for fUSD
    uint256 internal epochRewardMin;
    uint256 internal epochRewardMax;            // 0 - mean "no limit"
    uint256 internal epochPercentRewardNum;
    uint256 internal epochPercentRewardDenom;

    // Saved epochs for apply epoch rewards for users
    mapping (address => uint256) internal rewardEpochs;
    address[] internal rewardUsers;

    // Events
    event Deposit(
        address indexed _token,
        address indexed _user,
        uint256 _amount,
        uint256 _amount_fUSD,
        uint256 _timestamp
    );
    event Withdraw(
        address indexed _token,
        address indexed _user,
        uint256 _amount,
        uint256 _amount_fUSD,
        uint256 _timestamp
    );
    event SetRewardParams(
        address indexed _token,
        address indexed _user,

        uint256 beginPercentNum,
        uint256 beginPercentDenom,
        uint256 epochPercentNum,
        uint256 epochPercentDenom,
        uint256 epochMin,
        uint256 epochMax,

        uint256 _timestamp
    );
    event SetFeeParams(
        address indexed _token,
        address indexed _user,

        uint256 feePercentNum,
        uint256 feePercentDenom,

        uint256 _timestamp
    );
    event SetLimitParams(
        address indexed _token,
        address indexed _user,

        uint256 limitPercentNum,
        uint256 limitPercentDenom,

        uint256 _timestamp
    );
    event EpochReward(
        address indexed _token,
        address indexed _user,

        uint256 startEpoch,
        uint256 epochsCount,
        uint256 amount,

        uint256 _timestamp
    );

    // Constructor
    constructor (address _token, address _fusd, address _oracle, address _sfc) public {
        require(_token != address(0), "invalid token address");
        require(_sfc != address(0), "invalid sfc address");
        require(_oracle != address(0), "invalid oracle address");
        require(_fusd != address(0), "invalid fUSD address");
        token = ERC20(_token);
        fUSD = ERC20(_fusd);
        fUSDmint = ERC20Mintable(_fusd);
        oracle = IOracle(_oracle);
        sfc = ISFC(_sfc);
        owner = msg.sender;

        // No limits for output
        getLkPercentLimitNum = 1;
        getLkPercentLimitDenom = 1;

        // No reward
        addLkPercentRewardNum = 0;
        addLkPercentRewardDenom = 1;

        // No fee
        getLkPercentFeeNum = 0;
        getLkPercentFeeDenom = 1;

        // No epoch reward
        epochRewardMin = 0;
        epochRewardMax = 0;
        epochPercentRewardNum = 0;
        epochPercentRewardDenom = 1;

        // Reward users list
        rewardUsers = new address[];
    }

    modifier onlyOwner {
        require(msg.sender == owner, "only owner can call this function");
        _;
    }
    modifier onlyAdmin {
        require(msg.sender == owner || admins[msg.sender], "only owner or admins can call this function");
        _;
    }
    modifier onlyRewardEditor {
        require(msg.sender == owner || rewardEditors[msg.sender], "only owner or reward editors can call this function");
        _;
    }
    modifier onlyFeeEditor {
        require(msg.sender == owner || feeEditors[msg.sender], "only owner or fee editors can call this function");
        _;
    }
    modifier onlyLimitEditor {
        require(msg.sender == owner || limitEditors[msg.sender], "only owner or limit editors can call this function");
        _;
    }

    // Managers functions

    // Access for managers
    function addAdmin(address admin) external onlyOwner {
        admins[admin] = true;
    }
    function removeAdmin(address admin) external onlyOwner {
        delete(admins[admin]);
    }
    function addRewardEditor(address user) external onlyAdmin {
        rewardEditors[user] = true;
    }
    function removeRewardEditor(address user) external onlyAdmin {
        delete(rewardEditors[user]);
    }
    function addFeeEditor(address user) external onlyAdmin {
        feeEditors[user] = true;
    }
    function removeFeeEditor(address user) external onlyAdmin {
        delete(feeEditors[user]);
    }
    function addLimitEditor(address user) external onlyAdmin {
        limitEditors[user] = true;
    }
    function removeLimitEditor(address user) external onlyAdmin {
        delete(limitEditors[user]);
    }

    // Change options
    function setReward(uint256 _beginPercentNum, uint256 _beginPercentDenom,
                        uint256 _epochPercentNum, uint256 _epochPercentDenom,
                        uint256 _epochRewardMin, uint256 _epochRewardMax)
            external onlyRewardEditor {
        require(_beginPercentDenom > 0, "denominator must be great then 0");
        require(_epochPercentDenom > 0, "denominator must be great then 0");

        addLkPercentRewardNum = _beginPercentNum;
        addLkPercentRewardDenom = _beginPercentDenom;
        epochPercentRewardNum = _epochPercentNum;
        epochPercentRewardDenom = _epochPercentDenom;
        epochRewardMin = _epochRewardMin;
        epochRewardMax = _epochRewardMax;

        emit SetRewardParams(address(token), msg.sender,
            _beginPercentNum, _beginPercentDenom,
            _epochPercentNum, _epochPercentDenom,
            _epochRewardMin, _epochRewardMax,
            block.timestamp);
    }
    function getReward() public view
            returns(uint256 _beginPercentNum, uint256 _beginPercentDenom,
                    uint256 _epochPercentNum, uint256 _epochPercentDenom,
                    uint256 _epochRewardMin, uint256 _epochRewardMax) {
        return (addLkPercentRewardNum, addLkPercentRewardDenom,
                epochPercentRewardNum, epochPercentRewardDenom,
                epochRewardMin, epochRewardMax);
    }

    function setFee(uint256 percentNum, uint256 percentDenom) external onlyFeeEditor {
        require(percentDenom > 0, "denominator must be great then 0");

        getLkPercentFeeNum = percentNum;
        getLkPercentFeeDenom = percentDenom;

        emit SetFeeParams(address(token), msg.sender,
            percentNum, percentDenom,
            block.timestamp);
    }
    function getFee() public view returns(uint256 percentNum, uint256 percentDenom) {
        return (getLkPercentFeeNum, getLkPercentFeeDenom);
    }

    function setLimit(uint256 percentNum, uint256 percentDenom) external onlyLimitEditor {
        require(percentDenom > 0, "denominator must be great then 0");

        getLkPercentLimitNum = percentNum;
        getLkPercentLimitDenom = percentDenom;

        emit SetLimitParams(address(token), msg.sender,
            percentNum, percentDenom,
            block.timestamp);
    }
    function getLimit() public view returns(uint256 percentNum, uint256 percentDenom) {
        return (getLkPercentLimitNum, getLkPercentLimitDenom);
    }

    // getPrice - get price fUSD/native token
    function getPrice() public view returns(uint256 nativePrice, uint256 fUSDPrice) {
        nativePrice = oracle.getPrice(address(token));
        require(nativePrice > 0, "native token price must be great then 0");
        fUSDPrice = oracle.getPrice(address(fUSD));
        require(fUSDPrice > 0, "fUSD token price must be great then 0");
    }
    function getInfo() public view returns(address tokenNative,
        uint256 rewardNum, uint256 rewardDenom, uint256 feeNum, uint256 feeDenom, uint256 limitNum, uint256 limitDenom) {

        tokenNative = address(token);

        rewardNum = addLkPercentRewardNum;
        rewardDenom = addLkPercentRewardDenom;

        feeNum = getLkPercentFeeNum;
        feeDenom = getLkPercentFeeDenom;

        limitNum = getLkPercentLimitNum;
        limitDenom = getLkPercentLimitDenom;
    }

    // deposit - add native token from user and generate usd tokens for user
    // params:
    // _value - native token value
    function deposit(uint256 _value_native) external payable nonReentrant {
        require(_value_native > 0, "value must be great then 0");
        require(token.balanceOf(msg.sender) >= _value_native, "sender balance must by great then amount");

        // Apply epoch reward before add fUSD balance
        applyEpochRewards(msg.sender);

        // If current fUSD balance == 0 - add to rewardUsers and save currentEpoch
        if (fUSD.balanceOf(msg.sender) == 0) {
            rewardEpochs[user] = sfc.currentEpoch();
            rewardUsers.push(msg.sender);
        }

        uint256 priceToken = oracle.getPrice(address(token));
        require(priceToken > 0, "native token price must be great then 0");
        uint256 priceUSD = oracle.getPrice(address(fUSD));
        require(priceUSD > 0, "fUSD token price must be great then 0");

        // Transfer contract usd tokens with reward to user balance
        uint256 amount_fUSD = _value_native.mul(priceToken).div(priceUSD);
        uint256 reward_fUSD = amount_fUSD.mul(addLkPercentRewardNum).div(addLkPercentRewardDenom);
        uint256 fUSDAmount = amount_fUSD.add(reward_fUSD);

        if (fUSDAmount < fUSD.balanceOf(owner)) {
            // If contract usd token balance great then amount - transfer
            fUSD.safeTransferFrom(owner, msg.sender, fUSDAmount);
        } else {
            // Else - mint required amount to user address
            bool success = fUSDmint.mint(msg.sender, fUSDAmount);
            require(success, "error mint fUSD to user");
        }

        // Transfer native user tokens to contract native balance
        token.safeTransferFrom(msg.sender, owner, _value_native);

        emit Deposit(address(token), msg.sender, _value_native, fUSDAmount, block.timestamp);
    }
    function depositInfo(uint256 _value_native) public view
            returns(uint256 amount_fUSD, uint256 reward_fUSD) {
        require(_value_native > 0, "value must be great then 0");

        uint256 priceToken = oracle.getPrice(address(token));
        require(priceToken > 0, "native token price must be great then 0");
        uint256 priceUSD = oracle.getPrice(address(fUSD));
        require(priceUSD > 0, "fUSD token price must be great then 0");

        amount_fUSD = _value_native.mul(priceToken).div(priceUSD);
        reward_fUSD = amount_fUSD.mul(addLkPercentRewardNum).div(addLkPercentRewardDenom);
    }

    // withdraw - return native token to user over usd tokens conversation and fee
    // params:
    // _value - native token value
    function withdraw(uint256 _value_native) external nonReentrant {
        require(_value_native > 0, "value must be great then 0");
        require(_value_native <= token.balanceOf(owner), "native token of contract not enaught");

        // Apply epoch reward before withdraw fUSD balance
        applyEpochRewards(msg.sender);

        uint256 priceToken = oracle.getPrice(address(token));
        require(priceToken > 0, "native token price must be great then 0");
        uint256 priceUSD = oracle.getPrice(address(fUSD));
        require(priceUSD > 0, "fUSD token price must be great then 0");

        uint256 amount_fUSD = _value_native.mul(priceToken).div(priceUSD);
        uint256 fee_fUSD = amount_fUSD.mul(getLkPercentFeeNum).div(getLkPercentFeeDenom);
        uint256 fUSDAmount = amount_fUSD.add(fee_fUSD);

        // Check limits
        require(fUSDAmount <= fUSD.balanceOf(msg.sender).mul(getLkPercentLimitNum).div(getLkPercentLimitDenom),
            "out of limits for fUSD tokens getting");

        fUSD.safeTransferFrom(msg.sender, owner, fUSDAmount);
        token.safeTransferFrom(owner, msg.sender, _value_native);

        emit Withdraw(address(token), msg.sender, _value_native, fUSDAmount, block.timestamp);
    }
    function withdrawInfo(uint256 _value_native) public view
            returns(uint256 amount_fUSD, uint256 fee_fUSD, uint256 limit_fUSD) {
        require(_value_native > 0, "value must be great then 0");

        uint256 priceToken = oracle.getPrice(address(token));
        require(priceToken > 0, "native token price must be great then 0");
        uint256 priceUSD = oracle.getPrice(address(fUSD));
        require(priceUSD > 0, "fUSD token price must be great then 0");

        amount_fUSD = _value_native.mul(priceToken).div(priceUSD);
        fee_fUSD = amount_fUSD.mul(getLkPercentFeeNum).div(getLkPercentFeeDenom);
        limit_fUSD = fUSD.balanceOf(msg.sender).mul(getLkPercentLimitNum).div(getLkPercentLimitDenom);
    }

    // Apply calculated epoch rewards from fUSD for user
    function applyEpochRewards(address user) external nonReentrant {
        uint256 lastEpoch = rewardEpochs[user];
        uint256 currentEpoch = sfc.currentEpoch();
        uint256 applyEpochs = currentEpoch - lastEpoch;

        if (applyEpochs == 0) {
            return;
        }

        uint256 currentBalance = fUSD.balanceOf(user);
        uint256 newBalance = currentBalance.mul(
            epochPercentRewardNum.add(epochPercentRewardDenom).div(epochPercentRewardDenom)^applyEpochs
        );

        uint256 diffBalance = newBalance - currentBalance;

        // Check epoch reward limits
        if (diffBalance < epochRewardMin) {
            diffBalance = epochRewardMin;
        }
        if (epochRewardMax > 0 && diffBalance > epochRewardMax) {
            diffBalance = epochRewardMax;
        }

        // Transfer rewards to user fUSD
        if (diffBalance < fUSD.balanceOf(owner)) {
            // If contract usd token balance great then amount - transfer
            fUSD.safeTransferFrom(owner, user, diffBalance);
        } else {
            // Else - mint required amount to user address
            bool success = fUSDmint.mint(user, diffBalance);
            require(success, "error mint epoch reward fUSD to user");
        }

        // Save last epoch for apply user rewards
        rewardEpochs[user] = currentEpoch;

        // Event
        emit EpochReward(address(token), msg.sender, lastEpoch, applyEpochs, diffBalance, block.timestamp);
    }

    // Apply epoch rewards for all users and clean rewardUsers list for users with 0 fUSD balance
    function applyEpochRewardsAll() external onlyAdmin nonReentrant {
        address[] newRewardUsers = new address[];

        for (uint i = 0; i < rewardUsers.length; i++) {
            applyEpochRewards(rewardUsers[i]);

            if (fUSD.balanceOf(rewardUsers[i]) > 0) {
                newRewardUsers.push(rewardUsers[i]);
            }
        }

        if (rewardUsers.length != newRewardUsers.length) {
            rewardUsers = newRewardUsers;
        }
    }
}
