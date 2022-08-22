pragma solidity ^0.8.0;

// SPDX-License-Identifier: BUSL-1.1

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./InterfacesBinary.sol";

/**
 * @author Heisenberg
 * @title Buffer TokenX Bidirectional (Call and Put) Options
 * @notice Buffer TokenX Options Contract
 */
contract Router is ReentrancyGuard {
    ERC20 public tokenX;
    IBufferBinaryOptions public optionsContract;

    constructor(ERC20 _tokenX) {
        tokenX = _tokenX;
    }

    /**
     * @notice Creates a new option
     * @return optionID Created option's ID
     */
    function createFor(
        uint256 totalFee,
        uint256 period,
        bool isYes,
        bool isAbove,
        address referrer,
        address contractAddress
    ) external nonReentrant returns (uint256 optionID) {
        optionsContract = IBufferBinaryOptions(contractAddress);
        (uint256 strike, uint256 amount) = optionsContract.checkParams(
            msg.sender,
            totalFee,
            period,
            isYes,
            isAbove,
            referrer
        );

        // User has to approve first inorder to execute this function
        tokenX.transferFrom(msg.sender, contractAddress, totalFee);

        optionsContract.createFromRouter(
            msg.sender,
            totalFee,
            period,
            isYes,
            isAbove,
            referrer,
            strike,
            amount
        );
    }
}
