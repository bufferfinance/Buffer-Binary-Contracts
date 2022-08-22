pragma solidity ^0.8.0;

// SPDX-License-Identifier: BUSL-1.1

import "./Interfaces/PriceProviderInterface.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract CustomPriceProvider is Ownable, ICustomPriceProvider {
    mapping(uint256 => RoundData) public roundData;
    uint256 public latestRoundId;
    uint256 public latestTimestamp;

    string public symbol;

    // Should return USD price
    function getUsdPrice() external view returns (uint256 latestPrice) {
        (, latestPrice, , , ) = latestRoundData();
    }

    // Should return timestamp of corresponding round
    function getRoundData(uint256 _roundID)
        external
        view
        returns (
            uint256,
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        RoundData storage _roundData = roundData[_roundID];

        return (
            _roundData.roundId,
            _roundData.price,
            _roundData.startedAt,
            _roundData.updatedAt,
            _roundData.answeredInRound
        );
    }

    function latestRoundData()
        public
        view
        returns (
            uint256,
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        RoundData storage _roundData = roundData[latestRoundId];

        return (
            _roundData.roundId,
            _roundData.price,
            _roundData.startedAt,
            _roundData.updatedAt,
            _roundData.answeredInRound
        );
    }

    function decimals() external view returns (uint8) {
        return 8;
    }

    function setSymbol(string memory _symbol) external onlyOwner {
        symbol = _symbol;
    }

    function update(uint256 price)
        external
        onlyOwner
        returns (uint256 roundId)
    {
        roundId = latestRoundId + 1;
        latestTimestamp = block.timestamp;

        RoundData memory _roundData = RoundData(
            roundId,
            price,
            latestTimestamp,
            latestTimestamp,
            roundId
        );
        roundData[roundId] = _roundData;
        latestRoundId = roundId;
    }
}
