pragma solidity ^0.5.0;

/*
constructor(token contract, sfc contract, oracle contract, usd token contract)
addLiquidity(uint256 _value token) bool success
getLiquidity(uint256 _value token) bool success
getBalance(address _from) uint256 balance in usd token
transfer(address _to, uint256 _amount usd token) bool success
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
    address internal token;
    address internal fUSD;
    IOracle internal oracle;
    ISFC internal sfc;

    int32 internal addLkPercentReward1000;
    int32 internal getLkPercentFee1000;
    int32 internal getLkPercentLimit1000;

    // Events
    event Add(
        address indexed _token,
        address indexed _user,
        uint256 _amount,
        uint256 _timestamp
    );

    // Constructor
    constructor (address _token, address _fusd, address _sfc, address _oracle) public {
        require(_token != address(0), "invalid token address");
        require(_sfc != address(0), "invalid sfc address");
        require(_oracle != address(0), "invalid oracle address");
        require(_fusd != address(0), "invalid fUSD address");
        nativeDenom = denom;
        fUSD = fusd;
        sfc = ISFC(sfc);
        oracle = IOracle(oracle);
        owner = msg.sender;

        // Init values
        getLkPercentLimit1000 = 1000; // No limits for output
    }

    modifier onlyOwner {
        require(msg.sender == owner, "Only owner can call this function.");
        _;
    }
    modifier onlyAdmin {
        require(msg.sender == owner || admins[msg.sender], "Only owner or admins can call this function.");
        _;
    }
    modifier onlyRewardEditor {
        require(msg.sender == owner || rewardEditors[msg.sender], "Only owner or reward editors can call this function.");
        _;
    }
    modifier onlyFeeEditor {
        require(msg.sender == owner || feeEditors[msg.sender], "Only owner or fee editors can call this function.");
        _;
    }
    modifier onlyLimitEditor {
        require(msg.sender == owner || LimitEditors[msg.sender], "Only owner or limit editors can call this function.");
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
    function setReward(int32 percent1000) external onlyRewardEditor {
        addLkPercentReward1000 = percent1000;
    }
    function getReward() external returns(int32 percent1000) {
        return addLkPercentReward1000;
    }
    function setFee(int32 percent1000) external onlyFeeEditor {
        getLkPercentFee1000 = percent1000;
    }
    function getFee() external returns(int32 percent1000) {
        return getLkPercentFee1000;
    }
    function setLimit(int32 percent1000) external onlyLimitEditor {
        getLkPercentLimit1000 = percent1000;
    }
    function getLimit() external returns(int32 percent1000) {
        return getLkPercentLimit1000;
    }

    // addLiquidity - add native token from user and generate usd tokens for user
    // params:
    // _value - native token value
    function addLiquidity(uint256 _value) external nonReentrant returns(bool) {
        require(_value > 0, "value must be great then 0.");

        priceToken = oracle.getPrice(token);
        priceUSD = oracle.getPrice(fUSD);

        // Transfer contract usd tokens with reward to user balance
        fUSDAmount = _value * priceToken * (1 + addLkPercentReward1000 / 1000) / priceUSD;
        if (fUSDAmount < ERC20(fUSD).balanceOf(address(this))) {
            // If contract usd token balance great then amount - transfer
            success = ERC20(fUSD).safeTransferFrom(address(this), msg.sender, fUSDAmount);
            require(success, "error transfer fUSD from contract to user.");
        } else {
            // Else - mint required amount to user address
            success = ERC20Mintable(fUSD).mint(msg.sender, fUSDAmount);
            require(success, "error mint fUSD to user.");
        }

        // Transfer native user tokens to contract native balance
        success = ERC20(token).safeTransferFrom(msg.sender, address(this), _value);
        require(success, "error transfer native token from user to contract.");

        emit Deposit(token, msg.sender, _value, block.timestamp);
        return true;
    }
    function addLiquidityInfo(uint256 _value) external nonReentrant returns(uint256 amount, int256 reward) {
        require(_value > 0, "value must be great then 0.");

        priceToken = oracle.getPrice(token);
        priceUSD = oracle.getPrice(fUSD);

        reward = _value * priceToken * addLkPercentReward1000 / (priceUSD * 1000);
        amount = _value * priceToken / priceUSD;
    }

    // getLiquidity - return native token to user over usd tokens conversation and fee
    // params:
    // _value - native token value
    function getLiquidity(uint256 _value) external nonReentrant returns(bool) {
        require(_value > 0, "value must be great then 0.");
        require(_value > ERC20(token).balanceOf(address(this)), "native token of contract not enaught.");

        priceToken = oracle.getPrice(token);
        priceUSD = oracle.getPrice(fUSD);

        fUSDAmount = _value * priceToken * (1 - getLkPercentFee1000 / 1000) / priceUSD;

        // Check limits
        require(fUSDAmount <= ERC20(token).balanceOf(msg.sender) * getLkPercentLimit1000 / 1000,
            "out of limits for fUSD tokens getting.");

        success = ERC20(fUSD).safeTransferFrom(msg.sender, address(this), fUSDAmount);
        require(success, "error transfer fUSD from user to contract.");

        return true;
    }
    function getLiquidityInfo(uint256 _value) external nonReentrant returns(uint256 amount, int256 fee, uint256 limit) {
        require(_value > 0, "value must be great then 0.");

        priceToken = oracle.getPrice(token);
        priceUSD = oracle.getPrice(fUSD);

        fee = _value * priceToken * getLkPercentFee1000/(priceUSD * 1000);
        amount = _value * priceToken / priceUSD;
        limit = ERC20(token).balanceOf(msg.sender) * getLkPercentLimit1000 / 1000;
    }

    // transfer - move fUSD between users
    function transfer(address _to, uint256 _amount) external nonReentrant returns(bool) {
        require(_value > 0, "value must be great then 0.");
        require(_amount <= ERC20(fUSD).balanceOf(msg.sender), "sender have not required fUSD tokens for operation.");

        ERC20(fUSD).safeTransferFrom(msg.sender, _to, _amount);

        return true;
    }
}
