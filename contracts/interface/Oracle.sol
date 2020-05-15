pragma solidity ^0.5.0;

interface IOracle {

    function getPrice(address _token) external view returns (uint256);
    function getLiquidity(address _token) external view returns (uint256);

}
