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
import "../interface/Oracle.sol";
import "../interface/SFC.sol";

contract LiquidityPool is ReentrancyGuard {
    using SafeMath for uint256;
    using Address for address;

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
        require(msg.sender == owner || limitEditors[msg.sender], "Only owner or limit editors can call this function.");
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
    function setReward(uint256 percentNum, uint256 percentDenom) external onlyRewardEditor {
        require(percentDenom > 0, "denominator must be great then 0.");

        addLkPercentRewardNum = percentNum;
        addLkPercentRewardDenom = percentDenom;
    }
    function getReward() external returns(uint256 percentNum, uint256 percentDenom) {
        return (addLkPercentRewardNum, addLkPercentRewardDenom);
    }
    function setFee(uint256 percentNum, uint256 percentDenom) external onlyFeeEditor {
        require(percentDenom > 0, "denominator must be great then 0.");

        getLkPercentFeeNum = percentNum;
        getLkPercentFeeDenom = percentDenom;
    }
    function getFee() external returns(uint256 percentNum, uint256 percentDenom) {
        return (getLkPercentFeeNum, getLkPercentFeeDenom);
    }
    function setLimit(uint256 percentNum, uint256 percentDenom) external onlyLimitEditor {
        require(percentDenom > 0, "denominator must be great then 0.");

        getLkPercentLimitNum = percentNum;
        getLkPercentLimitDenom = percentDenom;
    }
    function getLimit() external returns(uint256 percentNum, uint256 percentDenom) {
        return (getLkPercentLimitNum, getLkPercentLimitDenom);
    }

    // getPrice - get price fUSD/native token
    function getPrice() external nonReentrant returns(uint256 nativePrice, uint256 fUSDPrice) {
        nativePrice = oracle.getPrice(address(token));
        require(nativePrice > 0, "native token price must be great then 0.");
        fUSDPrice = oracle.getPrice(address(fUSD));
        require(fUSDPrice > 0, "fUSD token price must be great then 0.");
    }
    function getInfo() external nonReentrant returns(address tokenNative,
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
        require(_value_native > 0, "value must be great then 0.");

        uint256 priceToken = oracle.getPrice(address(token));
        require(priceToken > 0, "native token price must be great then 0.");
        uint256 priceUSD = oracle.getPrice(address(fUSD));
        require(priceUSD > 0, "fUSD token price must be great then 0.");

        // Transfer contract usd tokens with reward to user balance
        uint256 fUSDAmount = _value_native.mul(priceToken).mul(
                addLkPercentRewardNum.add(addLkPercentRewardDenom).div(addLkPercentRewardDenom)
            ).div(priceUSD);

        if (fUSDAmount < fUSD.balanceOf(address(this))) {
            // If contract usd token balance great then amount - transfer
            fUSD.transferFrom(address(this), msg.sender, fUSDAmount);
        } else {
            // Else - mint required amount to user address
            bool success = fUSDmint.mint(msg.sender, fUSDAmount);
            require(success, "error mint fUSD to user.");
        }

        // Transfer native user tokens to contract native balance
        require(token.balanceOf(msg.sender) >= _value_native, "sender balance must by great then amount.");
        token.transferFrom(msg.sender, address(this), _value_native);

        emit Deposit(address(token), msg.sender, _value_native, fUSDAmount, block.timestamp);
    }
    function depositInfo(uint256 _value_native) external nonReentrant returns(uint256 amount_fUSD, uint256 reward_fUSD) {
        require(_value_native > 0, "value must be great then 0.");

        uint256 priceToken = oracle.getPrice(address(token));
        require(priceToken > 0, "native token price must be great then 0.");
        uint256 priceUSD = oracle.getPrice(address(fUSD));
        require(priceUSD > 0, "fUSD token price must be great then 0.");

        reward_fUSD = _value_native.mul(priceToken).mul(addLkPercentRewardNum).div(priceUSD.mul(addLkPercentRewardDenom));
        amount_fUSD = _value_native.mul(priceToken).div(priceUSD);
    }

    // withdraw - return native token to user over usd tokens conversation and fee
    // params:
    // _value - native token value
    function withdraw(uint256 _value_native) external nonReentrant {
        require(_value_native > 0, "value must be great then 0.");
        require(_value_native > token.balanceOf(address(this)), "native token of contract not enaught.");

        uint256 priceToken = oracle.getPrice(address(token));
        require(priceToken > 0, "native token price must be great then 0.");
        uint256 priceUSD = oracle.getPrice(address(fUSD));
        require(priceUSD > 0, "fUSD token price must be great then 0.");

        uint256 fUSDAmount = _value_native.mul(priceToken).mul(
                getLkPercentFeeNum.add(getLkPercentFeeDenom).div(getLkPercentFeeDenom)
            ).div(priceUSD);
        // Check limits
        require(fUSDAmount <= fUSD.balanceOf(msg.sender).mul(getLkPercentLimitNum).div(getLkPercentLimitDenom),
            "out of limits for fUSD tokens getting.");

        fUSD.transferFrom(msg.sender, address(this), fUSDAmount);

        emit Withdraw(address(token), msg.sender, _value_native, fUSDAmount, block.timestamp);
    }
    function withdrawInfo(uint256 _value_native) external nonReentrant
                returns(uint256 amount_fUSD, uint256 fee_fUSD, uint256 limit_fUSD) {
        require(_value_native > 0, "value must be great then 0.");

        uint256 priceToken = oracle.getPrice(address(token));
        require(priceToken > 0, "native token price must be great then 0.");
        uint256 priceUSD = oracle.getPrice(address(fUSD));
        require(priceUSD > 0, "fUSD token price must be great then 0.");

        fee_fUSD = _value_native.mul(priceToken).mul(getLkPercentFeeNum).div(priceUSD.mul(getLkPercentFeeDenom));
        amount_fUSD = _value_native.mul(priceToken).div(priceUSD);
        limit_fUSD = token.balanceOf(msg.sender).mul(getLkPercentLimitNum).div(getLkPercentFeeDenom);
    }
}
