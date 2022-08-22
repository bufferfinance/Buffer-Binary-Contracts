// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "../Interfaces/Interfaces.sol";

/**
 * @author Heisenberg
 * @title Tournament Manager
 * @notice The contract which manages the Tournaments
 */
contract TournamentManager is ERC1155("sample_uri"), Ownable, AccessControl {
    address public ticketFeeReceipient;
    uint256[] public liveTournaments;
    ITournamentManager.Asset[] public underlyingAssets;
    ITournamentManager.ERC20Asset[] public tradableAssets;
    uint256 public nextTournamentId = 0;
    bytes32 public constant LIQUIDITY_POOL_ROLE =
        keccak256("LIQUIDITY_POOL_ROLE");

    mapping(bytes32 => ITournamentManager.Rank) public tournamentUserRank;
    mapping(uint256 => mapping(uint256 => uint256))
        public tournamentUserPlayTokenBalance;
    mapping(uint256 => mapping(address => bool)) public tournamentUsers;
    mapping(uint256 => mapping(address => uint256))
        public tournamentUserTicketCount;
    mapping(uint256 => ITournamentManager.Tournament) public tournaments;
    mapping(uint256 => uint256[]) public tournamentRewardAmounts;
    mapping(uint256 => mapping(string => bool))
        public tournamentUnderlyingAssets;

    event UpdateUserRank(address user, uint256 tournamentId, bytes32 id);
    event BuyTicket(address user, uint256 tournamentId);
    event ClaimReward(address user, uint256 tournamentId, uint256 reward);
    event CreateTournament(uint256 tournamentId, string name);
    event AddUnderlyingAsset(string name);
    event AddTradableAsset(string name);

    constructor(address _ticketFeeReceipient) public {
        ticketFeeReceipient = _ticketFeeReceipient;
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /************************************************
     *  READ FUNCTIONS
     ***********************************************/

    function bulkFetchTournaments(uint256[] memory tournamentIds)
        public
        view
        returns (ITournamentManager.Tournament[] memory bulkTournaments)
    {
        bulkTournaments = new ITournamentManager.Tournament[](
            tournamentIds.length
        );
        for (uint256 i = 0; i < tournamentIds.length; i++) {
            bulkTournaments[i] = tournaments[tournamentIds[i]];
        }
    }

    function getMid(
        bytes32 start,
        bytes32 end,
        uint256 tournamentId
    ) public view returns (bytes32) {
        bytes32 slow = start;
        bytes32 fast = start;

        while (fast != end) {
            fast = tournamentUserRank[fast].next;
            if (fast != end) {
                slow = tournamentUserRank[slow].next;
                fast = tournamentUserRank[fast].next;
            }
        }
        return slow;
    }

    function getSortedPreviousRankIndex(
        address user,
        uint256 tournamentId,
        uint256 newUserScore
    ) public view returns (bytes32 previousIndex) {
        ITournamentManager.Tournament storage tournament = tournaments[
            tournamentId
        ];

        if (
            (tournament.rankFirst == 0) ||
            tournamentUserRank[tournament.rankFirst].score <= newUserScore
        ) {
            return 0;
        } else if (
            tournamentUserRank[tournament.rankLast].score > newUserScore
        ) {
            return tournament.rankLast;
        } else {
            // Get index from binary search
            bytes32 low = tournament.rankFirst;
            bytes32 high = tournament.rankLast;

            while (tournamentUserRank[low].next != high) {
                bytes32 mid = getMid(low, high, tournamentId);

                // Note that mid will always be strictly less than high (i.e. it will be a valid array index)
                // because Math.average rounds down (it does integer division with truncation).
                if (tournamentUserRank[mid].score < newUserScore) {
                    high = mid;
                } else {
                    low = mid;
                }
            }

            return low;
        }
    }

    function getScore(address user, uint256 tournamentId)
        public
        view
        returns (uint256 score)
    {
        ITournamentManager.Tournament storage tournament = tournaments[
            tournamentId
        ];
        uint256 playTokensBought = tournamentUserTicketCount[tournamentId][
            user
        ] * tournament.playTokenMintAmount;
        score =
            ((
                balanceOf(user, tournamentId) > playTokensBought
                    ? (balanceOf(user, tournamentId) - playTokensBought)
                    : 0
            ) * 1e5) /
            playTokensBought;
    }

    function getUserReward(address user, uint256 tournamentId)
        public
        view
        returns (uint256 reward)
    {
        ITournamentManager.Tournament storage tournament = tournaments[
            tournamentId
        ];
        bytes32 rankIndex = tournament.rankFirst;
        for (uint256 i = 0; i < 3; i++) {
            if (tournamentUserRank[rankIndex].user == user) {
                reward = tournamentRewardAmounts[tournamentId][i];
                break;
            } else {
                rankIndex = tournamentUserRank[rankIndex].next;
            }
        }
    }

    function getWinners(uint256 tournamentId, uint256 totalWinners)
        public
        view
        returns (address[] memory winners)
    {
        ITournamentManager.Tournament storage tournament = tournaments[
            tournamentId
        ];
        bytes32 rankIndex = tournament.rankFirst;
        winners = new address[](totalWinners);
        for (uint256 i = 0; i < totalWinners; i++) {
            winners[i] = tournamentUserRank[rankIndex].user;
            rankIndex = tournamentUserRank[rankIndex].next;
        }
    }

    function isTradable(uint256 tournamentId, string memory symbol)
        public
        view
        returns (bool)
    {
        return tournamentUnderlyingAssets[tournamentId][symbol];
    }

    /************************************************
     *  ADMIN FUNCTIONS
     ***********************************************/

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
    ) external onlyOwner returns (uint256) {
        ITournamentManager.Tournament storage newTournament = tournaments[
            nextTournamentId
        ];

        newTournament.name = name;
        newTournament.start = start;
        newTournament.close = close;
        newTournament.ticketCost = ticketCost;
        newTournament.ticketToken = tradableAssets[ticketTokenIndex];
        newTournament.rewardToken = tradableAssets[rewardTokenIndex];
        newTournament.playTokenMintAmount = playTokenMintAmount;

        for (uint256 i = 0; i < rewardAmount.length; i++) {
            tournamentRewardAmounts[nextTournamentId].push(rewardAmount[i]);
        }
        for (uint256 i = 0; i < underlyingAssetIndex.length; i++) {
            tournamentUnderlyingAssets[nextTournamentId][
                underlyingAssets[i].symbol
            ] = true;
        }

        liveTournaments.push(nextTournamentId);
        emit CreateTournament(nextTournamentId, name);
        nextTournamentId++;
        return nextTournamentId - 1;
    }

    function addNewUnderlyingAsset(ITournamentManager.Asset memory newAsset)
        external
        onlyOwner
    {
        underlyingAssets.push(newAsset);
        emit AddUnderlyingAsset(newAsset.name);
    }

    function addNewTradableAsset(ITournamentManager.ERC20Asset memory newAsset)
        external
        onlyOwner
    {
        tradableAssets.push(newAsset);
        emit AddTradableAsset(newAsset.name);
    }

    /************************************************
     *  POOL FUNCTIONS
     ***********************************************/

    function mint(
        address user,
        uint256 tournamentId,
        uint256 tokensToMint
    ) external onlyRole(LIQUIDITY_POOL_ROLE) {
        _mint(user, tournamentId, tokensToMint, "");
    }

    function burn(
        address user,
        uint256 tournamentId,
        uint256 tokensToBurn
    ) external onlyRole(LIQUIDITY_POOL_ROLE) {
        _burn(user, tournamentId, tokensToBurn);
    }

    function updateUserRank(address user, uint256 tournamentId)
        external
        onlyRole(LIQUIDITY_POOL_ROLE)
    {
        ITournamentManager.Tournament storage tournament = tournaments[
            tournamentId
        ];
        uint256 score = getScore(user, tournamentId);
        bytes32 id = keccak256(abi.encode(user, tournamentId));

        // Reset the Node
        if (tournamentUserRank[id].exists) {
            if (tournament.rankFirst == id) {
                tournament.rankFirst = tournamentUserRank[id].next;
            } else if (tournament.rankLast == id) {
                tournament.rankLast = tournamentUserRank[id].previous;
                tournamentUserRank[tournamentUserRank[id].previous].next = 0;
            } else {
                tournamentUserRank[tournamentUserRank[id].previous]
                    .next = tournamentUserRank[id].next;
                tournamentUserRank[tournamentUserRank[id].next]
                    .previous = tournamentUserRank[id].previous;
            }
        }

        // Get previous index through binary search
        bytes32 previousIndex = getSortedPreviousRankIndex(
            user,
            tournamentId,
            score
        );
        ITournamentManager.Rank memory newRank;
        if (previousIndex == 0) {
            if (tournamentUserRank[tournament.rankFirst].exists) {
                tournamentUserRank[tournament.rankFirst].previous = id;
            }
            newRank = ITournamentManager.Rank(
                tournament.rankFirst,
                0,
                user,
                score,
                false,
                true
            );
            tournament.rankFirst = id;
        } else {
            ITournamentManager.Rank storage previousRank = tournamentUserRank[
                previousIndex
            ];
            newRank = ITournamentManager.Rank(
                previousRank.next,
                previousIndex,
                user,
                score,
                false,
                true
            );

            tournamentUserRank[previousRank.next].previous = id;
            previousRank.next = id;
        }
        if (previousIndex == tournament.rankLast) {
            tournament.rankLast = id;
        }
        tournamentUserRank[id] = newRank;
        emit UpdateUserRank(user, tournamentId, id);
    }

    /************************************************
     *  USER FUNCTIONS
     ***********************************************/

    function decimals() public view returns (uint8) {
        return 18;
    }

    function buyTicket(uint256 tournamentId) external {
        address user = msg.sender;
        ITournamentManager.Tournament storage tournament = tournaments[
            tournamentId
        ];
        IERC20 ticketToken = tournament.ticketToken.token;
        require(
            ((block.timestamp < tournament.close) &&
                (block.timestamp > tournament.start)),
            "Buying tickets is not allowed at the moment"
        );
        require(
            ticketToken.balanceOf(user) >= tournament.ticketCost,
            "Insufficient balance to buy"
        );

        // Approve before this
        ticketToken.transferFrom(
            user,
            ticketFeeReceipient,
            tournament.ticketCost
        );

        if (!tournamentUsers[tournamentId][user]) {
            tournamentUsers[tournamentId][user] = true;
            tournament.userCount++;
        }
        tournamentUserTicketCount[tournamentId][user]++;

        _mint(user, tournamentId, tournament.playTokenMintAmount, "");

        emit BuyTicket(user, tournamentId);
    }

    function claimReward(uint256 tournamentId)
        external
        returns (uint256 reward)
    {
        ITournamentManager.Tournament storage tournament = tournaments[
            tournamentId
        ];

        require(
            block.timestamp >= tournament.close,
            "Can't claim rewards before tournament ends"
        );
        address user = msg.sender;
        reward = getUserReward(user, tournamentId);
        if (reward > 0) {
            IERC20 rewardToken = tournament.rewardToken.token;

            require(
                rewardToken.balanceOf(address(this)) >= reward,
                "Insufficient balance to distribute rewards"
            );

            rewardToken.transfer(user, reward);
            emit ClaimReward(user, tournamentId, reward);
        }
    }

    /************************************************
     *  OVERRIDE FUNCTIONS
     ***********************************************/

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC1155, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    function _beforeTokenTransfer(
        address operator,
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) internal virtual override {
        if (
            from != address(0) &&
            to != address(0) &&
            !hasRole(LIQUIDITY_POOL_ROLE, from) &&
            !hasRole(LIQUIDITY_POOL_ROLE, to)
        ) {
            revert("Token transfer not allowed");
        }
    }
}
