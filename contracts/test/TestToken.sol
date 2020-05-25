pragma solidity ^0.5.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20Detailed.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20Mintable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20Pausable.sol";
import "@openzeppelin/contracts/GSN/Context.sol";

contract TestToken is Context, ERC20, ERC20Detailed, ERC20Mintable, ERC20Burnable, ERC20Pausable {
    /**
     * @dev Constructor that gives _msgSender() all of existing tokens.
     */
    constructor (string memory name, string memory symbol, uint8 decimals) public ERC20Detailed(name, symbol, decimals) {
        uint256 valToMint = 100000000000;
        _mint(msg.sender, valToMint);
    }

    // For test
    function isMinter(address /*account*/) public view returns (bool) {
        return true;
    }

    function() external {}
}
