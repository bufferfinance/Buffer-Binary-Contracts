pragma solidity ^0.8.0;

// SPDX-License-Identifier: BUSL-1.1

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "./OptionConfigBinaryV2.sol";
import "./BufferBinaryIBFRPoolBinary.sol";
import "../Interfaces/Interfaces.sol";

/**
 * @author Heisenberg
 * @title Buffer TokenX Bidirectional (Call and Put) Options
 * @notice Buffer TokenX Options Contract
 */
contract BufferBinaryEuropeanATMOptions is
    IBufferBinaryOptions,
    Ownable,
    ReentrancyGuard,
    ERC721,
    AccessControl,
    ERC721URIStorage
{
    mapping(uint256 => string) private _tokenURIs;
    IPriceProvider public priceProvider;
    uint256 public nextTokenId = 0;
    mapping(uint256 => Option) public options;
    mapping(uint256 => uint256) public optionIdToTournament;
    mapping(address => uint256[]) public userOptionIds;
    mapping(address => uint256) public userOptionCount;
    mapping(uint256 => BinaryOptionType) public binaryOptionType;
    mapping(uint256 => uint256) public expiryToRoundID;
    mapping(uint256 => mapping(address => uint256)) public optionSizeBought;
    BufferBinaryIBFRPoolBinary public pool;
    OptionConfigBinaryV2 public config;
    uint256 internal contractCreationTimestamp;
    string public asset;
    uint256 public constant minimumYield = 5;

    constructor(
        string memory _asset,
        IPriceProvider pp,
        BufferBinaryIBFRPoolBinary _pool,
        OptionConfigBinaryV2 _config
    ) ERC721("Buffer", "BFR") {
        asset = _asset;
        pool = _pool;
        contractCreationTimestamp = block.timestamp;
        config = _config;
        priceProvider = pp;
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
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
        address referrer,
        uint256 tournamentId
    ) external nonReentrant returns (uint256 optionID) {
        // Check tournament specifications
        pool.checkParams(asset, tournamentId, block.timestamp + period);

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

        require(
            totalFee * 365 days * 100 > amount * (period) * minimumYield,
            "O2"
        );
        pool.chargeFee(msg.sender, totalFee, tournamentId);

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
        optionIdToTournament[optionID] = tournamentId;
        binaryOptionType[optionID] = BinaryOptionType(isYes, isAbove);
        userOptionIds[msg.sender].push(optionID);
        userOptionCount[msg.sender] = userOptionIds[msg.sender].length;
        options[optionID] = option;
        _mint(msg.sender, optionID);

        pool.lock(optionID, option.lockedAmount, option.premium, tournamentId);

        emit Create(optionID, msg.sender, 0, totalFee);
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
            _burn(optionID);

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
        require(_exists(optionID), "O10");

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
        pool.send(
            optionID,
            ownerOf(optionID),
            profit,
            optionIdToTournament[optionID]
        );
        // Burn the option
        _burn(optionID);

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
        _burn(tokenId_);
    }

    function decimals() public view virtual returns (uint8) {
        return 18;
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    /**
     * @dev Template code provided by OpenZepplin Code Wizard
     */
    function _setTokenURI(uint256 tokenId, string memory _tokenURI)
        internal
        override
    {
        return super._setTokenURI(tokenId, _tokenURI);
    }

    /**
     * @dev Template code provided by OpenZepplin Code Wizard
     */
    function _baseURI() internal pure override returns (string memory) {
        return "https://gateway.pinata.cloud/ipfs/";
    }

    /**
     * @dev Template code provided by OpenZepplin Code Wizard
     */
    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721, ERC721URIStorage)
        returns (string memory)
    {
        return super.tokenURI(tokenId);
    }

    function _burn(uint256 optionId_)
        internal
        override(ERC721, ERC721URIStorage)
    {
        super._burn(optionId_);
    }
}
