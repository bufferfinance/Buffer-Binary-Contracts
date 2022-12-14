// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @author Heisenberg
 * @title Buffer USDC Token
 * @notice The central token to the Buffer ecosystem
 */
contract USDC is ERC20("USDC", "USDC") {
    constructor() {
        uint256 INITIAL_SUPPLY = 1000 * 10**6 * 10**decimals();
        _mint(msg.sender, INITIAL_SUPPLY);
    }

    function decimals() public view virtual override returns (uint8) {
        return 18;
    }
}
