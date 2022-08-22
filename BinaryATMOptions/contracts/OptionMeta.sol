pragma solidity ^0.8.0;

// SPDX-License-Identifier: BUSL-1.1

import "./Interfaces/InterfacesV2.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract OptionMeta is Ownable {
    struct UserOptionInput {
        uint256 lastStoredOptionIndex;
        address contractAddress;
        address userAddress;
        bool isNull;
    }
    struct GenricOptionInput {
        uint256 optionId;
        address contractAddress;
    }
    struct NewPrices {
        uint256 price;
        address priceProvider;
    }
    struct OptionMetaData {
        uint256 optionId;
        IBufferOptions.State state;
        uint256 strike;
        uint256 amount;
        uint256 lockedAmount;
        uint256 premium;
        uint256 expiration;
        IBufferOptions.OptionType optionType;
        bool isYes;
        bool isAbove;
        uint256 totalFee;
        uint256 createdAt;
        uint256 iv;
    }

    function transferOwnership(address contract_address, address newOwner)
        public
        onlyOwner
    {
        AggregatorV3Interface priceProviderContract = AggregatorV3Interface(
            contract_address
        );
        priceProviderContract.transferOwnership(newOwner);
    }

    function bulk_price_update(NewPrices[] memory newPrices) public onlyOwner {
        for (uint256 i = 0; i < newPrices.length; i++) {
            AggregatorV3Interface priceProviderContract = AggregatorV3Interface(
                newPrices[i].priceProvider
            );
            priceProviderContract.update(newPrices[i].price);
        }
    }

    function get_price_at_timestamp(address priceProvider, uint256 timestamp)
        public
        view
        returns (uint256)
    {
        AggregatorV3Interface priceProviderContract = AggregatorV3Interface(
            priceProvider
        );
        (
            uint256 roundId,
            uint256 answer,
            ,
            uint256 latestTimestamp,

        ) = priceProviderContract.latestRoundData();
        if (latestTimestamp > timestamp) {
            bool isCorrectRoundId;
            while (!isCorrectRoundId) {
                roundId = roundId - 1;
                require(roundId > 0, "Wrong round id");
                (
                    ,
                    uint256 roundAnswer,
                    ,
                    uint256 roundTimestamp,

                ) = priceProviderContract.getRoundData(roundId);
                if ((roundTimestamp > 0) && (roundTimestamp <= timestamp)) {
                    isCorrectRoundId = true;
                    answer = roundAnswer;
                }
            }
        }
        return answer;
    }

    function get_price_at_timestamp_type2(
        address optionsContract,
        uint256 timestamp
    ) public view returns (uint256) {
        IBufferOptions binaryOptionsContract = IBufferOptions(optionsContract);
        uint256 roundId = binaryOptionsContract.expiryToRoundID(timestamp);
        AggregatorV3Interface priceProviderContract = AggregatorV3Interface(
            binaryOptionsContract.priceProvider()
        );
        (, uint256 answer, , , ) = priceProviderContract.getRoundData(roundId);
        return answer;
    }

    function get_current_prices(address[] calldata assets)
        public
        view
        returns (uint256[] memory prices)
    {
        prices = new uint256[](assets.length);

        for (uint256 i = 0; i < assets.length; i++) {
            AggregatorV3Interface priceProviderContract = AggregatorV3Interface(
                assets[i]
            );
            prices[i] = priceProviderContract.getUsdPrice();
        }
    }

    function get_option_data(GenricOptionInput memory option)
        public
        view
        returns (OptionMetaData memory optionDetails)
    {
        uint256 optionId = option.optionId;
        IBufferOptions binaryOptionsContract = IBufferOptions(
            option.contractAddress
        );
        (
            IBufferOptions.State state,
            uint256 strike,
            uint256 amount,
            uint256 lockedAmount,
            uint256 premium,
            uint256 expiration,
            IBufferOptions.OptionType optionType,
            uint256 totalFee,
            uint256 createdAt
        ) = binaryOptionsContract.options(optionId);
        (bool isYes, bool isAbove) = binaryOptionsContract.binaryOptionType(
            optionId
        );
        optionDetails = OptionMetaData(
            optionId,
            state,
            strike,
            amount,
            lockedAmount,
            premium,
            expiration,
            optionType,
            isYes,
            isAbove,
            totalFee,
            createdAt,
            IOptionsConfig(binaryOptionsContract.config()).impliedVolRate()
        );
    }

    function get_bulk_option_data(GenricOptionInput[] memory options)
        public
        view
        returns (OptionMetaData[] memory allOptions)
    {
        allOptions = new OptionMetaData[](options.length);

        for (uint256 i = 0; i < options.length; i++) {
            allOptions[i] = get_option_data(options[i]);
        }
        return allOptions;
    }

    function get_latest_options_for_user(
        UserOptionInput calldata userOptionInput
    ) external view returns (OptionMetaData[] memory allOptions) {
        uint256 counter;
        uint256 lastStoredOptionIndex = userOptionInput.lastStoredOptionIndex;
        address optionsContractAddress = userOptionInput.contractAddress;
        IBufferOptions binaryOptionsContract = IBufferOptions(
            optionsContractAddress
        );
        uint256 onChainUserOptions = binaryOptionsContract.userOptionCount(
            userOptionInput.userAddress
        );
        uint256 firstOptionIndexToProcess = (
            userOptionInput.isNull ? 0 : lastStoredOptionIndex + 1
        );

        if (firstOptionIndexToProcess < onChainUserOptions) {
            allOptions = new OptionMetaData[](
                onChainUserOptions - firstOptionIndexToProcess
            );

            for (
                uint256 index = firstOptionIndexToProcess;
                index < onChainUserOptions;
                index++
            ) {
                allOptions[counter] = get_option_data(
                    GenricOptionInput(
                        binaryOptionsContract.userOptionIds(
                            userOptionInput.userAddress,
                            index
                        ),
                        optionsContractAddress
                    )
                );
                counter++;
            }
        }
    }
}
