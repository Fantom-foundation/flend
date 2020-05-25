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

    uint256 internal addLkRewardNum;
    uint256 internal addLkRewardDenom;
    uint256 internal getLkFeeNum;
    uint256 internal getLkFeeDenom;
    uint256 internal getLkLimitNum;
    uint256 internal getLkLimitDenom;

    // Epoch reward for fUSD
    uint256 internal epochRewardMin;
    uint256 internal epochRewardMax;            // 0 - mean "no limit"
    uint256 internal epochRewardNum;
    uint256 internal epochRewardDenom;

    // Saved epochs for apply epoch rewards for users
    mapping (address => uint256) internal rewardEpochs;
    address[][2] internal rewardUsers;
    uint256 internal currentRewardUsers;

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

        uint256 beginNum,
        uint256 beginDenom,
        uint256 epochNum,
        uint256 epochDenom,
        uint256 epochMin,
        uint256 epochMax,

        uint256 _timestamp
    );
    event SetFeeParams(
        address indexed _token,
        address indexed _user,

        uint256 feeNum,
        uint256 feeDenom,

        uint256 _timestamp
    );
    event SetLimitParams(
        address indexed _token,
        address indexed _user,

        uint256 limitNum,
        uint256 limitDenom,

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
        getLkLimitNum = 1;
        getLkLimitDenom = 1;

        // No reward
        addLkRewardNum = 0;
        addLkRewardDenom = 1;

        // No fee
        getLkFeeNum = 0;
        getLkFeeDenom = 1;

        // No epoch reward
        epochRewardMin = 0;
        epochRewardMax = 0;
        epochRewardNum = 0;
        epochRewardDenom = 1;

        currentRewardUsers = 0;
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
        require(msg.sender == owner || admins[msg.sender] || rewardEditors[msg.sender], "only owner or reward editors can call this function");
        _;
    }
    modifier onlyFeeEditor {
        require(msg.sender == owner || admins[msg.sender] || feeEditors[msg.sender], "only owner or fee editors can call this function");
        _;
    }
    modifier onlyLimitEditor {
        require(msg.sender == owner || admins[msg.sender] || limitEditors[msg.sender], "only owner or limit editors can call this function");
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
    function setReward(uint256 _beginNum, uint256 _beginDenom,
                        uint256 _epochNum, uint256 _epochDenom,
                        uint256 _epochRewardMin, uint256 _epochRewardMax)
            external onlyRewardEditor {
        require(_beginDenom > 0, "denominator must be great then 0");
        require(_epochDenom > 0, "denominator must be great then 0");

        addLkRewardNum = _beginNum;
        addLkRewardDenom = _beginDenom;
        epochRewardNum = _epochNum;
        epochRewardDenom = _epochDenom;
        epochRewardMin = _epochRewardMin;
        epochRewardMax = _epochRewardMax;

        emit SetRewardParams(address(token), msg.sender,
            _beginNum, _beginDenom,
            _epochNum, _epochDenom,
            _epochRewardMin, _epochRewardMax,
            block.timestamp);
    }
    function getReward() public view
            returns(uint256 _beginNum, uint256 _beginDenom,
                    uint256 _epochNum, uint256 _epochDenom,
                    uint256 _epochRewardMin, uint256 _epochRewardMax) {
        return (addLkRewardNum, addLkRewardDenom,
        epochRewardNum, epochRewardDenom,
                epochRewardMin, epochRewardMax);
    }

    function setFee(uint256 valNum, uint256 valDenom) external onlyFeeEditor {
        require(valDenom > 0, "denominator must be great then 0");

        getLkFeeNum = valNum;
        getLkFeeDenom = valDenom;

        emit SetFeeParams(address(token), msg.sender,
            valNum, valDenom,
            block.timestamp);
    }
    function getFee() public view returns(uint256 valNum, uint256 valDenom) {
        return (getLkFeeNum, getLkFeeDenom);
    }

    function setLimit(uint256 valNum, uint256 valDenom) external onlyLimitEditor {
        require(valDenom > 0, "denominator must be great then 0");

        getLkLimitNum = valNum;
        getLkLimitDenom = valDenom;

        emit SetLimitParams(address(token), msg.sender,
            valNum, valDenom,
            block.timestamp);
    }
    function getLimit() public view returns(uint256 valNum, uint256 valDenom) {
        return (getLkLimitNum, getLkLimitDenom);
    }

    // getPrice - get price fUSD/native token
    function getPrice() public view returns(uint256 nativePrice, uint256 fUSDPrice) {
        nativePrice = oracle.getPrice(address(token));
        require(nativePrice > 0, "native token price must be great then 0");
        fUSDPrice = oracle.getPrice(address(fUSD));
        require(fUSDPrice > 0, "fUSD token price must be great then 0");
    }
    function getInfo() public view returns(address _tokenNative,
        uint256 _rewardNum, uint256 _rewardDenom,
        uint256 _feeNum, uint256 _feeDenom,
        uint256 _limitNum, uint256 _limitDenom,
        uint256 _epochNum, uint256 _epochDenom, uint256 _epochRewardMin, uint256 _epochRewardMax
    ) {
        _tokenNative = address(token);

        _rewardNum = addLkRewardNum;
        _rewardDenom = addLkRewardDenom;

        _feeNum = getLkFeeNum;
        _feeDenom = getLkFeeDenom;

        _limitNum = getLkLimitNum;
        _limitDenom = getLkLimitDenom;

        _epochNum = epochRewardNum;
        _epochDenom = epochRewardDenom;
        _epochRewardMin = epochRewardMin;
        _epochRewardMax = epochRewardMax;
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
            rewardEpochs[msg.sender] = sfc.currentEpoch();
            rewardUsers[currentRewardUsers].push(msg.sender);
        }

        uint256 priceToken = oracle.getPrice(address(token));
        require(priceToken > 0, "native token price must be great then 0");
        uint256 priceUSD = oracle.getPrice(address(fUSD));
        require(priceUSD > 0, "fUSD token price must be great then 0");

        // Transfer contract usd tokens with reward to user balance
        uint256 amount_fUSD = _value_native.mul(priceToken).div(priceUSD);
        uint256 reward_fUSD = amount_fUSD.mul(addLkRewardNum).div(addLkRewardDenom);
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
        reward_fUSD = amount_fUSD.mul(addLkRewardNum).div(addLkRewardDenom);
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
        uint256 fee_fUSD = amount_fUSD.mul(getLkFeeNum).div(getLkFeeDenom);
        uint256 fUSDAmount = amount_fUSD.add(fee_fUSD);

        // Check limits
        require(fUSDAmount <= fUSD.balanceOf(msg.sender).mul(getLkLimitNum).div(getLkLimitDenom),
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
        fee_fUSD = amount_fUSD.mul(getLkFeeNum).div(getLkFeeDenom);
        limit_fUSD = fUSD.balanceOf(msg.sender).mul(getLkLimitNum).div(getLkLimitDenom);
    }

    // Apply calculated epoch rewards from fUSD for user
    function applyEpochRewards(address user) internal {
        uint256 lastEpoch = rewardEpochs[user];
        uint256 currentEpoch = sfc.currentEpoch();
        require(currentEpoch >= lastEpoch, "current epoch should be great then user saved last epoch");
        if (currentEpoch == lastEpoch) {
            return;
        }

        uint256 applyEpochs = currentEpoch - lastEpoch;

        uint256 currentBalance = fUSD.balanceOf(user);
        uint256 newBalance = currentBalance;
        uint256 prevBalance = currentBalance;
        uint256 diffBalance = 0;
        for (uint256 i = 0; i < applyEpochs; i++) {
            newBalance = newBalance.mul(
                epochRewardNum.add(epochRewardDenom)
            ).div(epochRewardDenom);

            diffBalance = newBalance - prevBalance;

            // Check epoch reward limits
            if (diffBalance < epochRewardMin) {
                diffBalance = epochRewardMin;
            }
            if (epochRewardMax > 0 && diffBalance > epochRewardMax) {
                diffBalance = epochRewardMax;
            }

            newBalance = prevBalance + diffBalance;
            prevBalance = newBalance;
        }

        diffBalance = newBalance - currentBalance;

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
    function applyRewardsAll() external onlyAdmin nonReentrant {
        // Clean not current reward users array
        uint256 newRewardUsers = (currentRewardUsers + 1) % 2;
        if (rewardUsers[newRewardUsers].length > 0) {
            delete rewardUsers[newRewardUsers];
        }

        for (uint i = 0; i < rewardUsers[currentRewardUsers].length; i++) {
            address user = rewardUsers[currentRewardUsers][i];
            applyEpochRewards(user);

            // If user have balance > 0 - add to not corrent reward users array
            if (fUSD.balanceOf(user) > 0) {
                rewardUsers[newRewardUsers].push(user);
            }
        }

        // Switch current reward users array to new array and clean old array
        uint256 prev = currentRewardUsers;
        currentRewardUsers = newRewardUsers;
        delete rewardUsers[prev];
    }
    function applyRewards(address user) external nonReentrant {
        applyEpochRewards(user);
    }
}
