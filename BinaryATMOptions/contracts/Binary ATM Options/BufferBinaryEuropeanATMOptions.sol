pragma solidity ^0.8.0;

// SPDX-License-Identifier: BUSL-1.1

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./OptionConfigBinaryV2.sol";
import "./BufferNFTCoreBinary.sol";
import "./BufferBinaryIBFRPoolBinary.sol";
import "./InterfacesBinary.sol";

/**
 * @author Heisenberg
 * @title Buffer TokenX Bidirectional (Call and Put) Options
 * @notice Buffer TokenX Options Contract
 */
contract BufferBinaryEuropeanATMOptions is
    IBufferBinaryOptions,
    Ownable,
    ReentrancyGuard,
    BufferNFTCoreBinary
{
    ERC20 public tokenX;
    mapping(uint256 => string) private _tokenURIs;
    IPriceProvider public priceProvider;
    uint256 public nextTokenId = 0;
    mapping(uint256 => Option) public options;
    mapping(address => uint256[]) public userOptionIds;
    mapping(address => uint256) public userOptionCount;
    mapping(uint256 => BinaryOptionType) public binaryOptionType;
    mapping(uint256 => uint256) public expiryToRoundID;
    mapping(uint256 => mapping(address => uint256)) public optionSizeBought;
    BufferBinaryIBFRPoolBinary public pool;
    OptionConfigBinaryV2 public config;
    mapping(uint256 => SlotDetail) public slotDetails;
    uint256 internal contractCreationTimestamp;

    bytes32 public constant ROUTER_ROLE = keccak256("ROUTER_ROLE");

    uint256 public constant minimumYield = 5;

    constructor(
        ERC20 _tokenX,
        IPriceProvider pp,
        BufferBinaryIBFRPoolBinary _pool,
        OptionConfigBinaryV2 _config
    ) {
        tokenX = _tokenX;
        pool = _pool;
        contractCreationTimestamp = block.timestamp;
        config = _config;
        priceProvider = pp;
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /**
     * @notice Call this to set the max approval for tokenX transfers from the options to pool
     */
    function approvePoolToTransferTokenX() public {
        tokenX.approve(address(pool), ~uint256(0));
    }

    /************************************************
     *  OPTIONS CORE
     ***********************************************/

    /**
     * @notice Creates a new option
     * @return optionID Created option's ID
     */
    function create(
        uint256 totalFee,
        uint256 period,
        bool isYes,
        bool isAbove,
        address referrer
    ) external nonReentrant returns (uint256 optionID) {
        // Check if the option period is higher the 5 mins
        require((period) >= 5 minutes, "O21");
        require((period) < config.maxPeriod(), "O24");

        uint256 strike = priceProvider.getUsdPrice();
        (uint256 unitFee, , ) = fees(
            period,
            10**decimals(),
            strike,
            isYes,
            isAbove
        );

        uint256 amount = (totalFee * 10**decimals()) / unitFee;

        // A user is only allowed to buy a n amount size per block
        // so we'll have to keep track of the amount bought per block
        optionSizeBought[block.number][msg.sender] += amount;
        require(
            optionSizeBought[block.number][msg.sender] + amount <
                (config.optionSizePerBlockLimitPercent() *
                    pool.availableBalance()) /
                    100,
            "O23"
        );

        require(
            totalFee * 365 days * 100 > amount * (period) * minimumYield,
            "O2"
        );

        // User has to approve first inorder to execute this function
        tokenX.transferFrom(msg.sender, address(this), totalFee);
        OptionType optionType = OptionType.Put;

        if (
            (isYes == true && isAbove == true) ||
            (isYes == false && isAbove == false)
        ) {
            optionType = OptionType.Call;
        }
        Option memory option = Option(
            State.Active,
            strike,
            amount,
            amount,
            amount / 2,
            block.timestamp + period,
            optionType,
            totalFee,
            block.timestamp
        );
        optionID = _generateTokenId();
        binaryOptionType[optionID] = BinaryOptionType(isYes, isAbove);
        userOptionIds[msg.sender].push(optionID);
        userOptionCount[msg.sender] = userOptionIds[msg.sender].length;
        options[optionID] = option;
        _mint(
            optionID,
            msg.sender,
            createSlot(optionID, option.strike, option.expiration, optionType)
        );
        uint256 stakingAmount = distributeSettlementFee(
            totalFee - option.premium,
            referrer,
            msg.sender
        );

        _lock(optionID, option.lockedAmount, option.premium);
        emit Create(optionID, msg.sender, stakingAmount, totalFee);
    }

    /**
     * @notice Checks option requirements
     */
    function checkParams(
        address user,
        uint256 totalFee,
        uint256 period,
        bool isYes,
        bool isAbove,
        address referrer
    )
        external
        override
        onlyRole(ROUTER_ROLE)
        returns (uint256 strike, uint256 amount)
    {
        // Check if the option period is higher the 5 mins
        require((period) >= 5 minutes, "O21");
        require((period) < config.maxPeriod(), "O24");

        strike = priceProvider.getUsdPrice();
        (uint256 unitFee, , ) = fees(
            period,
            10**decimals(),
            strike,
            isYes,
            isAbove
        );

        amount = (totalFee * 10**decimals()) / unitFee;

        // A user is only allowed to buy a n amount size per block
        // so we'll have to keep track of the amount bought per block
        require(
            optionSizeBought[block.number][user] + amount <
                (config.optionSizePerBlockLimitPercent() *
                    pool.availableBalance()) /
                    100,
            "O23"
        );

        require(
            totalFee * 365 days * 100 > amount * (period) * minimumYield,
            "O2"
        );
    }

    /**
     * @notice Creates a new option
     * @return optionID Created option's ID
     */
    function createFromRouter(
        address user,
        uint256 totalFee,
        uint256 period,
        bool isYes,
        bool isAbove,
        address referrer,
        uint256 strike,
        uint256 amount
    ) external override onlyRole(ROUTER_ROLE) returns (uint256 optionID) {
        optionSizeBought[block.number][user] += amount;

        OptionType optionType = OptionType.Put;
        if (
            (isYes == true && isAbove == true) ||
            (isYes == false && isAbove == false)
        ) {
            optionType = OptionType.Call;
        }
        Option memory option = Option(
            State.Active,
            strike,
            amount,
            amount,
            amount / 2,
            block.timestamp + period,
            optionType,
            totalFee,
            block.timestamp
        );
        optionID = _generateTokenId();
        binaryOptionType[optionID] = BinaryOptionType(isYes, isAbove);
        userOptionIds[user].push(optionID);
        userOptionCount[user] = userOptionIds[user].length;
        options[optionID] = option;
        _mint(
            optionID,
            user,
            createSlot(optionID, option.strike, option.expiration, optionType)
        );
        uint256 stakingAmount = distributeSettlementFee(
            totalFee - option.premium,
            referrer,
            user
        );

        _lock(optionID, option.lockedAmount, option.premium);
        emit Create(optionID, user, stakingAmount, totalFee);
    }

    function distributeSettlementFee(
        uint256 settlementFee,
        address referrer,
        address user
    ) internal returns (uint256 stakingAmount) {
        stakingAmount = ((settlementFee * config.stakingFeePercentage()) / 100);

        // Incase the stakingAmount is 0
        if (stakingAmount > 0) {
            tokenX.transfer(config.settlementFeeRecipient(), stakingAmount);
        }

        uint256 adminFee = settlementFee - stakingAmount;
        if (adminFee > 0) {
            if (
                config.referralRewardPercentage() > 0 &&
                referrer != owner() &&
                referrer != user
            ) {
                uint256 referralReward = (adminFee *
                    config.referralRewardPercentage()) / 100;
                adminFee = adminFee - referralReward;
                tokenX.transfer(referrer, referralReward);
                emit PayReferralFee(referrer, referralReward);
            }
            tokenX.transfer(owner(), adminFee);
            emit PayAdminFee(owner(), adminFee);
        }
    }

    function _modifyOption(
        uint256 optionID,
        Option memory option,
        uint256 lockedAmount,
        uint256 amount,
        uint256 premium
    ) internal returns (Option memory modifiedOption) {
        option.lockedAmount = lockedAmount;
        option.amount = amount;
        option.premium = premium;
        modifiedOption = option;
        _setOption(optionID, option);
    }

    function _lock(
        uint256 id,
        uint256 lockedAmount,
        uint256 premium
    ) internal {
        pool.lock(id, lockedAmount, premium);
    }

    /**
     * @notice Sets the expiry price in the oracle
     * @dev a roundId must be provided to confirm price validity,
     * which is the first Chainlink price provided after the expiryTimestamp
     * @param roundId the first roundId after expiryTimestamp
     */
    function setRoundIDForExpiry(uint256 roundId, uint256 optionID)
        external
        returns (bool isCorrectRoundId)
    {
        (, uint256 price, , uint256 roundTimestamp, ) = priceProvider
            .getRoundData(roundId);
        Option storage option = options[optionID];
        uint256 expiryTimestamp = option.expiration;
        require(expiryTimestamp < roundTimestamp, "C1");
        require(price >= 0, "C2");
        uint256 previousRoundId = expiryToRoundID[expiryTimestamp];
        if (previousRoundId <= 0) {
            previousRoundId = roundId - 1;
            while (!isCorrectRoundId) {
                (, , , uint256 previousRoundTimestamp, ) = priceProvider
                    .getRoundData(previousRoundId);
                if (previousRoundTimestamp == 0) {
                    require(previousRoundId > 0, "C3");
                    previousRoundId = previousRoundId - 1;
                } else if (previousRoundTimestamp > expiryTimestamp) {
                    revert("C4");
                } else {
                    isCorrectRoundId = true;
                    expiryToRoundID[expiryTimestamp] = previousRoundId;
                }
            }
        }
    }

    /**
     * @notice Unlocks the locked funds if the option was
     * OTM at the time of expiry otherwise exercises it
     * @param optionID ID of the option
     */
    function unlock(uint256 optionID) public {
        Option storage option = options[optionID];
        require(option.expiration <= block.timestamp, "O4");
        require(option.state == State.Active, "O5");
        uint256 roundID = expiryToRoundID[option.expiration];
        require(roundID > 0, "O20");
        (, uint256 priceAtExpiration, , , ) = priceProvider.getRoundData(
            roundID
        );
        if (
            (option.optionType == OptionType.Call &&
                priceAtExpiration > option.strike) ||
            (option.optionType == OptionType.Put &&
                priceAtExpiration < option.strike)
        ) {
            exercise(optionID);
        } else {
            option.state = State.Expired;
            pool.unlock(optionID);
            burnToken(optionID);
            emit Expire(optionID, option.premium);
        }
    }

    /**
     * @notice Unlocks an array of options
     * @param optionIDs array of options
     */
    function unlockAll(uint256[] calldata optionIDs) external {
        uint256 arrayLength = optionIDs.length;
        for (uint256 i = 0; i < arrayLength; i++) {
            unlock(optionIDs[i]);
        }
    }

    /**
     * @notice Exercises an option if it was
     * ITM at the time of expiry
     * @param optionID ID of your option
     * @return profit Profit sent to the user
     */
    function exercise(uint256 optionID) public returns (uint256 profit) {
        require(exists(optionID), "O10");

        Option storage option = options[optionID];

        require(option.expiration <= block.timestamp, "O4");
        require(option.state == State.Active, "O14");
        uint256 roundID = expiryToRoundID[option.expiration];
        require(roundID > 0, "O20");
        (, uint256 priceAtExpiration, , , ) = priceProvider.getRoundData(
            roundID
        );

        if (option.optionType == OptionType.Call) {
            require(option.strike <= priceAtExpiration, "O17");
        } else {
            require(option.strike >= priceAtExpiration, "O18");
        }
        profit = option.lockedAmount;
        pool.send(optionID, ownerOf(optionID), profit);
        // Burn the option
        burnToken(optionID);
        option.state = State.Exercised;
        emit Exercise(optionID, profit);
    }

    /**
     * @notice Used for getting the option's price using blackscholes
     * @param period Option period in seconds
     * @param amount Option amount
     * @param strike Strike price of the option
     * @param isYes whether the option isAbove or not
     * @param isAbove whether the price will stay above this strike or not
     * @return total Total price to be paid
     * @return settlementFee Amount to be distributed to the Buffer token holders
     * @return premium Amount that covers the price difference in the ITM options
     */
    function fees(
        uint256 period,
        uint256 amount,
        uint256 strike,
        bool isYes,
        bool isAbove
    )
        public
        view
        returns (
            uint256 total,
            uint256 settlementFee,
            uint256 premium
        )
    {
        uint256 currentPrice = priceProvider.getUsdPrice();

        // Probability for ATM options will always be 0.5 due to which we can skip using black scholes to calculate the same
        premium = amount / 2;
        total = (premium * 1e4) / (1e4 - config.settlementFeePercentage());
        settlementFee = total - premium;
    }

    function _generateTokenId() internal returns (uint256) {
        return nextTokenId++;
    }

    function _getOption(uint256 optionID)
        internal
        view
        returns (Option memory)
    {
        return options[optionID];
    }

    function _setOption(uint256 optionID, Option memory option) internal {
        options[optionID] = option;
    }

    function burn(uint256 tokenId_) external {
        require(msg.sender == ownerOf(tokenId_), "O9");
        burnToken(tokenId_);
    }

    function decimals() public view virtual returns (uint8) {
        return 18;
    }

    /************************************************
     *  ERC3525 Functions
     ***********************************************/

    /**
     * @notice Splits the option
     * @param optionID OptionId to be splitted
     * @param splitUnits_ Units to be splitted into
     * @return newOptionIDs An array of the splitted options
     */
    function split(uint256 optionID, uint256[] calldata splitUnits_)
        external
        returns (uint256[] memory newOptionIDs)
    {
        require(splitUnits_.length > 0, "N1");
        newOptionIDs = new uint256[](splitUnits_.length);
        Option memory option = _getOption(optionID);
        uint256 totalUnits = unitsInToken(optionID);
        uint256 totalChildAmount;
        uint256 totalChildLockedAmount;
        uint256 totalChildPremium;
        // Create child options
        for (uint256 i = 0; i < splitUnits_.length; i++) {
            uint256 newOptionID = _generateTokenId();
            newOptionIDs[i] = newOptionID;

            _split(optionID, newOptionID, splitUnits_[i]);

            uint256 childAmount = (option.amount * splitUnits_[i]) / totalUnits;
            totalChildAmount += childAmount;

            uint256 childLockedAmount = (option.lockedAmount * splitUnits_[i]) /
                totalUnits;
            totalChildLockedAmount += childLockedAmount;

            uint256 childPremium = (option.premium * splitUnits_[i]) /
                totalUnits;
            totalChildPremium += childPremium;

            Option memory newOption = Option(
                option.state,
                option.strike,
                childAmount,
                childLockedAmount,
                childPremium,
                option.expiration,
                option.optionType,
                option.totalFee,
                block.timestamp
            );
            _setOption(newOptionID, newOption);
        }
        // Modify the parent option once all child options are created
        option = _modifyOption(
            optionID,
            option,
            option.lockedAmount - totalChildLockedAmount,
            option.amount - totalChildAmount,
            option.premium - totalChildPremium
        );
        pool.changeLock(optionID, option.lockedAmount, option.premium);

        // Lock the amount in the pool for the child options
        for (uint256 i = 0; i < splitUnits_.length; i++) {
            Option memory newOption = _getOption(newOptionIDs[i]);
            _lock(newOptionIDs[i], newOption.lockedAmount, newOption.premium);
        }
    }

    /**
     * @notice Merges the options
     * @param optionIDs An array of the optionsIds to be merged
     * @param targetOptionID OptionId to be merged into
     */
    function merge(uint256[] calldata optionIDs, uint256 targetOptionID)
        external
    {
        require(optionIDs.length > 0, "N4");
        Option memory targetOption = _getOption(targetOptionID);

        uint256 totalLockedAmount = targetOption.lockedAmount;
        uint256 totalAmount = targetOption.amount;
        uint256 totalPremium = targetOption.premium;

        for (uint256 i = 0; i < optionIDs.length; i++) {
            Option memory option = _getOption(optionIDs[i]);
            totalLockedAmount = totalLockedAmount + option.lockedAmount;
            totalAmount = totalAmount + option.amount;
            totalPremium = totalPremium + option.premium;
            pool.unlockWithoutProfit(optionIDs[i]);
            _merge(optionIDs[i], targetOptionID);
        }
        _modifyOption(
            targetOptionID,
            targetOption,
            totalLockedAmount,
            totalAmount,
            totalPremium
        );
        pool.changeLock(targetOptionID, totalLockedAmount, totalPremium);
    }

    /**
     * @notice Transfer part of units of a option to another option.
     * @param optionID Id of the option to transfer
     * @param transferUnits_ Amount of units to transfer
     */
    function _beforeTransferFrom(uint256 optionID, uint256 transferUnits_)
        internal
        returns (
            uint256 newAmount,
            uint256 newPremium,
            uint256 newLockedAmount,
            Option memory option
        )
    {
        option = _getOption(optionID);
        uint256 totalUnits = unitsInToken(optionID);
        newAmount = (option.amount * transferUnits_) / totalUnits;
        newPremium = (option.premium * transferUnits_) / totalUnits;
        newLockedAmount = (option.lockedAmount * transferUnits_) / totalUnits;

        option = _modifyOption(
            optionID,
            option,
            option.lockedAmount - newLockedAmount,
            option.amount - newAmount,
            option.premium - newPremium
        );
        pool.changeLock(optionID, option.lockedAmount, option.premium);
    }

    /**
     * @notice Transfer part of units of a option to target address.
     * @param from_ Address of the option sender
     * @param to_ Address of the option recipient
     * @param optionID Id of the option to transfer
     * @param transferUnits_ Amount of units to transfer
     */
    function transferFrom(
        address from_,
        address to_,
        uint256 optionID,
        uint256 transferUnits_
    ) external returns (uint256 newOptionID) {
        newOptionID = _generateTokenId();
        (
            uint256 newAmount,
            uint256 newPremium,
            uint256 newLockedAmount,
            Option memory option
        ) = _beforeTransferFrom(optionID, transferUnits_);
        Option memory newOption = Option(
            option.state,
            option.strike,
            newAmount,
            newLockedAmount,
            newPremium,
            option.expiration,
            option.optionType,
            option.totalFee,
            block.timestamp
        );
        _setOption(newOptionID, newOption);

        _lock(newOptionID, newLockedAmount, newPremium);
        _transferUnitsFrom(from_, to_, optionID, newOptionID, transferUnits_);
    }

    /**
     * @notice Transfer part of units of a option to another option.
     * @param from_ Address of the option sender
     * @param to_ Address of the option recipient
     * @param optionID Id of the option to transfer
     * @param targetOptionID Id of the option to receive
     * @param transferUnits_ Amount of units to transfer
     */
    function transferFrom(
        address from_,
        address to_,
        uint256 optionID,
        uint256 targetOptionID,
        uint256 transferUnits_
    ) external virtual {
        require(exists(targetOptionID), "N12");
        (
            uint256 newAmount,
            uint256 newPremium,
            uint256 newLockedAmount,

        ) = _beforeTransferFrom(optionID, transferUnits_);
        Option memory targetOption = _getOption(targetOptionID);
        targetOption = _modifyOption(
            targetOptionID,
            targetOption,
            targetOption.lockedAmount + newLockedAmount,
            targetOption.amount + newAmount,
            targetOption.premium + newPremium
        );

        pool.changeLock(
            targetOptionID,
            targetOption.lockedAmount,
            targetOption.premium
        );
        _transferUnitsFrom(
            from_,
            to_,
            optionID,
            targetOptionID,
            transferUnits_
        );
    }

    function createSlot(
        uint256 optionID,
        uint256 strike,
        uint256 expiration,
        OptionType optionType
    ) internal returns (uint256 slot) {
        slot = uint256(
            keccak256(abi.encode(strike, expiration, optionType, optionID))
        );
        require(!slotDetails[slot].isValid, "N14");
        slotDetails[slot] = SlotDetail(strike, expiration, optionType, true);
    }
}
