pragma solidity ^0.8.0;

// SPDX-License-Identifier: BUSL-1.1

import "@openzeppelin/contracts/access/Ownable.sol";
import "./BufferBinaryIBFRPoolBinary.sol";

/**
 * @author Heisenberg
 * @title Buffer BNB Bidirectional (Call and Put) Options
 * @notice Buffer BNB Options Contract
 */
contract OptionConfigBinaryV2 is Ownable, IOptionsConfig {
    uint256 public impliedVolRate;
    uint256 public optionCollateralizationRatio = 100;
    uint256 public settlementFeePercentage = 5e2;
    uint256 public stakingFeePercentage = 50;
    uint256 public referralRewardPercentage = 0;
    uint256 public nftSaleRoyaltyPercentage = 5;
    uint256 internal constant PRICE_DECIMALS = 1e8;
    address public settlementFeeRecipient;
    uint256 public utilizationRate = 60e8;
    uint256 public optionSizePerBlockLimitPercent = 5;
    uint256 public maxPeriod = 24 hours;
    BufferBinaryIBFRPoolBinary public pool;
    PermittedTradingType public permittedTradingType;

    constructor(
        address staking,
        uint256 initialImpliedVolRate,
        BufferBinaryIBFRPoolBinary _pool
    ) {
        settlementFeeRecipient = staking;
        impliedVolRate = initialImpliedVolRate;
        pool = _pool;
    }

    /**
     * @notice Used for adjusting the maxPeriod
     * @param value New maxPeriod
     */
    function setMaxPeriod(uint256 value) external onlyOwner {
        require(
            value >= 5 minutes,
            "MaxPeriod needs to be greater than 5 minutes"
        );
        maxPeriod = value;
        emit UpdateMaxPeriod(value);
    }

    /**
     * @notice Used for adjusting the options prices while balancing asset's implied volatility rate
     * @param value New IVRate value
     */
    function setImpliedVolRate(uint256 value) external onlyOwner {
        require(value >= 100, "ImpliedVolRate limit is too small");
        impliedVolRate = value;
        emit UpdateImpliedVolatility(value);
    }

    function setTradingPermission(PermittedTradingType permissionType)
        external
        onlyOwner
    {
        permittedTradingType = permissionType;
        emit UpdateTradingPermission(permissionType);
    }

    /**
     * @notice Used for adjusting the settlement fee percentage with a factor of 100
     * @param value New Settlement Fee Percentage
     */
    function setSettlementFeePercentage(uint256 value) external onlyOwner {
        require(value < 20e2, "SettlementFeePercentage is too high");
        settlementFeePercentage = value;
        emit UpdateSettlementFeePercentage(value);
    }

    /**
     * @notice Used for changing settlementFeeRecipient
     * @param recipient New settlementFee recipient address
     */
    function setSettlementFeeRecipient(address recipient) external onlyOwner {
        require(address(recipient) != address(0));
        settlementFeeRecipient = recipient;
        emit UpdateSettlementFeeRecipient(address(recipient));
    }

    /**
     * @notice Used for adjusting the staking fee percentage
     * @param value New Staking Fee Percentage
     */
    function setStakingFeePercentage(uint256 value) external onlyOwner {
        require(value <= 100, "StakingFeePercentage is too high");
        stakingFeePercentage = value;
        emit UpdateStakingFeePercentage(value);
    }

    /**
     * @notice Used for adjusting the referral reward percentage
     * @param value New Referral Reward Percentage
     */
    function setReferralRewardPercentage(uint256 value) external onlyOwner {
        require(value <= 100, "ReferralRewardPercentage is too high");
        referralRewardPercentage = value;
        emit UpdateReferralRewardPercentage(value);
    }

    /**
     * @notice Used for changing option collateralization ratio
     * @param value New optionCollateralizationRatio value
     */
    function setOptionCollaterizationRatio(uint256 value) external onlyOwner {
        require(50 <= value && value <= 100, "wrong value");
        optionCollateralizationRatio = value;
        emit UpdateOptionCollaterizationRatio(value);
    }

    /**
     * @notice Used for changing nftSaleRoyaltyPercentage
     * @param value New nftSaleRoyaltyPercentage value
     */
    function setNFTSaleRoyaltyPercentage(uint256 value) external onlyOwner {
        require(value <= 10, "wrong value");
        nftSaleRoyaltyPercentage = value;
        emit UpdateNFTSaleRoyaltyPercentage(value);
    }

    /**
     * @notice Used for updating utilizationRate value
     * @param value New utilizationRate value
     **/
    function setUtilizationRate(uint256 value) external onlyOwner {
        utilizationRate = value;
    }
}
