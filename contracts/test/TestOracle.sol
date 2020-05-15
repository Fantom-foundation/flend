pragma solidity >=0.4.21 <0.7.0;

contract TestOracle {
    mapping(address => uint256) _priceStore;
    mapping(address => uint256) _liquidityStore;

    function setPrice(address _token, uint256 _price) public {
        _priceStore[_token] = _price;
    }

    function getPrice(address _token) external view returns (uint256) {
        return _priceStore[_token];
    }

    function setLiquidity(address _token, uint256 _liquidity) public {
        _liquidityStore[_token] = _liquidity;
    }

    function getLiquidity(address _token) external view returns (uint256) {
        return _liquidityStore[_token];
    }
}
