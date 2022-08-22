pragma solidity ^0.8.0;

// SPDX-License-Identifier: BUSL-1.1

import "./Interfaces/Interfaces.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract Faucet is Ownable {
    ERC20 public token;
    uint256 public amount;
    uint256 public fee = 1e17; // 0.1 ETH
    address public fee_collector;
    mapping(address => uint256) public lastSavedTimestamp;

    constructor(ERC20 _token, address _fee_collector) {
        fee_collector = _fee_collector;
        token = _token;
        amount = 500 * (10**token.decimals());
    }

    function claim() external payable {
        require(
            block.timestamp - lastSavedTimestamp[msg.sender] > 1 days,
            "Already claimed!"
        );
        require(msg.value >= fee, "Wrong fee");

        payable(fee_collector).transfer(fee);
        token.transfer(msg.sender, amount);
        lastSavedTimestamp[msg.sender] = block.timestamp;

        if (msg.value > fee) {
            payable(msg.sender).transfer(msg.value - fee);
        }
    }

    function withdraw() external onlyOwner {
        uint256 balance = token.balanceOf(address(this));
        token.transfer(owner(), balance);
    }

    /**
     * @notice Used for adjusting the amount of claimable tokens
     * @param value New amount of claimable tokens
     */
    function setAmount(uint256 value) external onlyOwner {
        amount = value;
    }

    /**
     * @notice Used for adjusting the fee to claim tokens
     * @param value New fee to claim tokens
     */
    function setFee(uint256 value) external onlyOwner {
        fee = value;
    }
}
