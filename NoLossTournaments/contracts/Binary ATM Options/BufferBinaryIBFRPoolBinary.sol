pragma solidity ^0.8.0;

// SPDX-License-Identifier: BUSL-1.1

import "../Interfaces/Interfaces.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

/**
 * @author Heisenberg
 * @title Buffer TokenX Liquidity Pool
 * @notice Accumulates liquidity in TokenX from LPs and distributes P&L in TokenX
 */
contract BufferBinaryIBFRPoolBinary is
    AccessControl,
    ILiquidityPool,
    ERC1155Holder
{
    address public owner;
    ITournamentManager public tournamentManager;
    mapping(address => LockedLiquidity[]) public lockedLiquidity;

    bytes32 public constant OPTION_ISSUER_ROLE =
        keccak256("OPTION_ISSUER_ROLE");

    constructor(address _tournamentManager) {
        owner = msg.sender;
        tournamentManager = ITournamentManager(_tournamentManager);
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function chargeFee(
        address user,
        uint256 fee,
        uint256 tournamentId
    ) external override onlyRole(OPTION_ISSUER_ROLE) {
        tournamentManager.burn(user, tournamentId, fee);
    }

    function checkParams(
        string memory asset,
        uint256 tournamentId,
        uint256 expiration
    ) external view override {
        require(
            tournamentManager.isTradable(tournamentId, asset),
            "Trading isn't allowed on this asset"
        );
        (, uint256 start, uint256 close, , , , , , , , ) = tournamentManager
            .tournaments(tournamentId);
        require(block.timestamp > start, "This tournament has not started yet");
        require(expiration < close, "Option expiry is out of bounds");
    }

    /**
     * @notice Called by BufferCallOptions to lock the funds
     * @param amountToLock Amount of funds that should be locked in an option
     * @param premium Fee that the user paid
     * @param tournamentId Id of the tournament the option is bought for
     */
    function lock(
        uint256 id,
        uint256 amountToLock,
        uint256 premium,
        uint256 tournamentId
    ) external override onlyRole(OPTION_ISSUER_ROLE) {
        require(id == lockedLiquidity[msg.sender].length, "Wrong id");

        lockedLiquidity[msg.sender].push(
            LockedLiquidity(amountToLock, premium, true)
        );
        tournamentManager.mint(address(this), tournamentId, amountToLock);
    }

    /**
     * @notice Called by BufferOptions to unlock the funds
     * @param id Id of LockedLiquidity that should be unlocked
     */
    function _unlock(uint256 id)
        internal
        onlyRole(OPTION_ISSUER_ROLE)
        returns (uint256 premium)
    {
        LockedLiquidity storage ll = lockedLiquidity[msg.sender][id];
        require(ll.locked, "Pool: lockedAmount is already unlocked");
        ll.locked = false;

        premium = ll.premium;
    }

    /**
     * @notice Called by BufferOptions to unlock the funds
     * @param id Id of LockedLiquidity that should be unlocked
     */
    function unlock(uint256 id) external override {
        uint256 premium = _unlock(id);
        emit Profit(id, premium);
    }

    /**
     * @notice Called by BufferOptions to unlock the funds
     * @param id Id of LockedLiquidity that should be unlocked
     */
    function unlockWithoutProfit(uint256 id) external override {
        _unlock(id);
    }

    /**
     * @notice Called by BufferCallOptions to send funds to liquidity providers after an option's expiration
     * @param to Provider
     * @param profit Funds that should be sent
     * @param tournamentId Id of the tournament the option is bought for
     */
    function send(
        uint256 id,
        address to,
        uint256 profit,
        uint256 tournamentId
    ) external override onlyRole(OPTION_ISSUER_ROLE) {
        LockedLiquidity storage ll = lockedLiquidity[msg.sender][id];
        require(ll.locked, "Pool: lockedAmount is already unlocked");
        require(to != address(0));

        ll.locked = false;

        uint256 transferrableProfit = profit > ll.amount ? ll.amount : profit;

        tournamentManager.safeTransferFrom(
            address(this),
            to,
            tournamentId,
            transferrableProfit,
            ""
        );
        tournamentManager.updateUserRank(to, tournamentId);

        if (transferrableProfit <= ll.premium)
            emit Profit(id, ll.premium - transferrableProfit);
        else emit Loss(id, transferrableProfit - ll.premium);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(AccessControl, ERC1155Receiver)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
