pragma solidity ^0.8.0;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IBufferBinaryOptions {
    event Create(
        uint256 indexed id,
        address indexed account,
        uint256 settlementFee,
        uint256 totalFee
    );

    event Exercise(uint256 indexed id, uint256 profit);
    event Expire(uint256 indexed id, uint256 premium);
    event PayReferralFee(address indexed referrer, uint256 amount);
    event PayAdminFee(address indexed owner, uint256 amount);

    enum State {
        Inactive,
        Active,
        Exercised,
        Expired
    }
    enum OptionType {
        Invalid,
        Put,
        Call
    }
    enum PaymentMethod {
        Usdc,
        TokenX
    }

    struct OptionDetails {
        uint256 period;
        uint256 amount;
        uint256 strike;
        bool isYes;
        bool isAbove;
    }

    struct Option {
        State state;
        uint256 strike;
        uint256 amount;
        uint256 lockedAmount;
        uint256 premium;
        uint256 expiration;
        OptionType optionType;
        uint256 totalFee;
        uint256 createdAt;
    }

    struct BinaryOptionType {
        bool isYes;
        bool isAbove;
    }

    struct SlotDetail {
        uint256 strike;
        uint256 expiration;
        OptionType optionType;
        bool isValid;
    }
}

interface IBufferOptions {
    event UpdateOptionCreationWindow(
        uint256 startHour,
        uint256 startMinute,
        uint256 endHour,
        uint256 endMinute
    );
    event TransferUnits(
        address indexed from,
        address indexed to,
        uint256 indexed tokenId,
        uint256 targetTokenId,
        uint256 transferUnits
    );

    event Split(
        address indexed owner,
        uint256 indexed tokenId,
        uint256 newTokenId,
        uint256 splitUnits
    );

    event Merge(
        address indexed owner,
        uint256 indexed tokenId,
        uint256 indexed targetTokenId,
        uint256 mergeUnits
    );

    event ApprovalUnits(
        address indexed approval,
        uint256 indexed tokenId,
        uint256 allowance
    );

    struct ApproveUnits {
        address[] approvals;
        mapping(address => uint256) allowances;
    }
}

interface ILiquidityPool {
    struct LockedLiquidity {
        uint256 amount;
        uint256 premium;
        bool locked;
    }

    event Profit(uint256 indexed id, uint256 amount);
    event Loss(uint256 indexed id, uint256 amount);
    event Provide(address indexed account, uint256 amount, uint256 writeAmount);
    event Withdraw(
        address indexed account,
        uint256 amount,
        uint256 writeAmount
    );

    function unlock(uint256 id) external;

    // function unlockPremium(uint256 amount) external;
    event UpdateRevertTransfersInLockUpPeriod(
        address indexed account,
        bool value
    );
    event InitiateWithdraw(uint256 tokenXAmount, address account);
    event ProcessWithdrawRequest(uint256 tokenXAmount, address account);
    event UpdatePoolState(bool hasPoolEnded);
    event PoolRollOver(uint256 round);
    event UpdateMaxLiquidity(uint256 indexed maxLiquidity);
    event UpdateExpiry(uint256 expiry);
    event UpdateProjectOwner(address account);

    function unlockWithoutProfit(uint256 id) external;

    function send(
        uint256 id,
        address to,
        uint256 profit,
        uint256 tournamentId
    ) external;

    function lock(
        uint256 id,
        uint256 amountToLock,
        uint256 premium,
        uint256 tournamentId
    ) external;

    function chargeFee(
        address user,
        uint256 fee,
        uint256 tournamentId
    ) external;

    function checkParams(
        string memory asset,
        uint256 tournamentId,
        uint256 expiration
    ) external view;
}

interface IOptionsConfig {
    enum PermittedTradingType {
        All,
        OnlyPut,
        OnlyCall,
        None
    }
    event UpdateImpliedVolatility(uint256 value);
    event UpdateSettlementFeePercentage(uint256 value);
    event UpdateSettlementFeeRecipient(address account);
    event UpdateStakingFeePercentage(uint256 value);
    event UpdateReferralRewardPercentage(uint256 value);
    event UpdateOptionCollaterizationRatio(uint256 value);
    event UpdateNFTSaleRoyaltyPercentage(uint256 value);
    event UpdateTradingPermission(PermittedTradingType permissionType);
    event UpdateStrike(uint256 value);
    event UpdateUnits(uint256 value);
    event UpdateMaxPeriod(uint256 value);
    event UpdateOptionSizePerBlockLimitPercent(uint256 value);

    enum OptionType {
        Invalid,
        Put,
        Call
    }
}

interface IPriceProvider {
    function getUsdPrice() external view returns (uint256 _price);

    function getRoundData(uint256 _roundId)
        external
        view
        returns (
            uint80 roundId,
            uint256 price,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );

    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );

    function decimals() external view returns (uint8);
}

interface ITournamentManager {
    struct ERC20Asset {
        string name;
        string symbol;
        uint8 decimals;
        IERC20 token;
    }
    struct Asset {
        string name;
        string symbol;
        uint8 decimals;
    }
    struct Rank {
        bytes32 next;
        bytes32 previous;
        address user;
        uint256 score;
        bool hasClaimed;
        bool exists;
    }
    struct Tournament {
        string name;
        uint256 start;
        uint256 close;
        uint256 ticketCost;
        ERC20Asset ticketToken;
        uint256 playTokenMintAmount;
        ERC20Asset rewardToken;
        bool isClosed;
        bytes32 rankFirst;
        bytes32 rankLast;
        uint256 userCount;
    }

    function bulkFetchTournaments(uint256[] memory tournamentIds)
        external
        view
        returns (Tournament[] memory bulkTournaments);

    function getMid(
        bytes32 start,
        bytes32 end,
        uint256 tournamentId
    ) external view returns (bytes32);

    function getSortedPreviousRankIndex(
        address user,
        uint256 tournamentId,
        uint256 newUserScore
    ) external view returns (bytes32 previousIndex);

    function getScore(address user, uint256 tournamentId)
        external
        view
        returns (uint256 score);

    function getUserReward(address user, uint256 tournamentId)
        external
        view
        returns (uint256 reward);

    function getWinners(uint256 tournamentId, uint256 totalWinners)
        external
        view
        returns (address[] memory winners);

    function isTradable(uint256 tournamentId, string memory symbol)
        external
        view
        returns (bool);

    function createTournament(
        string memory name,
        uint256 start,
        uint256 close,
        uint256[] memory underlyingAssetIndex,
        uint256 ticketCost,
        uint256 ticketTokenIndex,
        uint256 playTokenMintAmount,
        uint256[] memory rewardAmount,
        uint256 rewardTokenIndex
    ) external returns (uint256);

    function addNewUnderlyingAsset(Asset memory newAsset) external;

    function addNewTradableAsset(ERC20Asset memory newAsset) external;

    function mint(
        address user,
        uint256 tournamentId,
        uint256 tokensToMint
    ) external;

    function burn(
        address user,
        uint256 tournamentId,
        uint256 tokensToBurn
    ) external;

    function updateUserRank(address user, uint256 tournamentId) external;

    function decimals() external view returns (uint8);

    function balanceOf(address user, uint256 tournamentId)
        external
        view
        returns (uint256);

    function tournaments(uint256 tournamentsId)
        external
        view
        returns (
            string memory name,
            uint256 start,
            uint256 close,
            uint256 ticketCost,
            ERC20Asset memory ticketToken,
            uint256 playTokenMintAmount,
            ERC20Asset memory rewardToken,
            bool isClosed,
            bytes32 rankFirst,
            bytes32 rankLast,
            uint256 userCount
        );

    function buyTicket(uint256 tournamentId) external;

    function claimReward(uint256 tournamentId)
        external
        returns (uint256 reward);

    function safeTransferFrom(
        address from,
        address to,
        uint256 id,
        uint256 amount,
        bytes memory data
    ) external;
}
