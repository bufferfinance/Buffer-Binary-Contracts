pragma solidity ^0.8.0;

// SPDX-License-Identifier: BUSL-1.1

import "./InterfacesBinary.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @author Heisenberg
 * @title Buffer TokenX Liquidity Pool
 * @notice Accumulates liquidity in TokenX from LPs and distributes P&L in TokenX
 */
contract BufferBinaryIBFRPoolBinary is
    ERC20("Buffer LP Token", "rBFR"),
    AccessControl,
    ILiquidityPool
{
    string private _name;
    string private _symbol;
    uint256 public constant ACCURACY = 1e3;
    uint256 public constant INITIAL_RATE = 1e3;
    uint256 public lockedAmount;
    uint256 public lockedPremium;
    uint256 public maxLiquidity;
    address public projectOwner;
    address public owner;
    mapping(address => LockedLiquidity[]) public lockedLiquidity;

    bytes32 public constant OPTION_ISSUER_ROLE =
        keccak256("OPTION_ISSUER_ROLE");

    bytes32 public constant PROJECT_OWNER_ROLE =
        keccak256("PROJECT_OWNER_ROLE");

    ERC20 public tokenX;

    constructor(ERC20 _tokenX) {
        _name = string(
            bytes.concat(
                "Buffer Generic ",
                bytes(_tokenX.symbol()),
                " LP Token"
            )
        );
        _symbol = string(bytes.concat("r", bytes(_tokenX.symbol())));
        tokenX = _tokenX;
        owner = msg.sender;
        maxLiquidity = 5000000 * 10**_tokenX.decimals();
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /**
     * @dev Returns the name of the token.
     */
    function name() public view virtual override returns (string memory) {
        return _name;
    }

    /**
     * @dev Returns the symbol of the token, usually a shorter version of the
     * name.
     */
    function symbol() public view virtual override returns (string memory) {
        return _symbol;
    }

    /**
     * @dev Returns the decimals of the token.
     */
    function decimals() public view virtual override returns (uint8) {
        return tokenX.decimals();
    }

    /**
     * @notice Used for setting owner
     * @param account owner account
     */
    function setProjectOwner(address account)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        grantRole(PROJECT_OWNER_ROLE, account);
        projectOwner = account;
        emit UpdateProjectOwner(account);
    }

    /**
     * @notice Used for adjusting the max limit of the pool
     * @param _maxLiquidity New limit
     */
    function setMaxLiquidity(uint256 _maxLiquidity)
        external
        onlyRole(PROJECT_OWNER_ROLE)
    {
        maxLiquidity = _maxLiquidity;
        emit UpdateMaxLiquidity(_maxLiquidity);
    }

    /**
     * @notice A provider supplies tokenX to the pool and receives rBFR-X tokens
     * @param minMint Minimum amount of tokens that should be received by a provider.
                      Calling the provide function will require the minimum amount of tokens to be minted.
                      The actual amount that will be minted could vary but can only be higher (not lower) than the minimum value.
     * @return mint Amount of tokens to be received
     */
    function provide(uint256 tokenXAmount, uint256 minMint)
        external
        returns (uint256 mint)
    {
        uint256 supply = totalSupply();
        uint256 balance = totalTokenXBalance();

        require(
            balance + tokenXAmount <= maxLiquidity,
            "Pool has already reached it's max limit"
        );

        if (supply > 0 && balance > 0)
            mint = (tokenXAmount * supply) / (balance);
        else mint = tokenXAmount * INITIAL_RATE;

        require(mint >= minMint, "Pool: Mint limit is too large");
        require(mint > 0, "Pool: Amount is too small");

        bool success = tokenX.transferFrom(
            msg.sender,
            address(this),
            tokenXAmount
        );
        require(success, "The Provide transfer didn't go through");

        _mint(msg.sender, mint);

        emit Provide(msg.sender, tokenXAmount, mint);
    }

    /**
     * @notice Provider burns rBFR-X and receives X from the pool
     * @param tokenXAmount Amount of X to receive
     * @param account User address for which the withdrawal has to be initiated
     * @return burn Amount of tokens to be burnt
     */
    function _withdraw(uint256 tokenXAmount, address account)
        internal
        returns (uint256 burn)
    {
        require(
            tokenXAmount <= availableBalance(),
            "Pool: Not enough funds on the pool contract. Please lower the amount."
        );
        uint256 totalSupply = totalSupply();
        uint256 balance = totalTokenXBalance();

        uint256 maxUserTokenXWithdrawal = (balanceOf(account) * balance) /
            totalSupply;

        uint256 tokenXAmountToWithdraw = maxUserTokenXWithdrawal < tokenXAmount
            ? maxUserTokenXWithdrawal
            : tokenXAmount;

        burn = divCeil((tokenXAmountToWithdraw * totalSupply), balance);

        require(burn <= balanceOf(account), "Pool: Amount is too large");
        require(burn > 0, "Pool: Amount is too small");

        _burn(account, burn);

        bool success = tokenX.transfer(account, tokenXAmountToWithdraw);
        require(success, "Pool: The Withdrawal didn't go through");
        emit Withdraw(account, tokenXAmountToWithdraw, burn);
    }

    /**
     * @notice withdraw burns rBFR-X and receives X from the pool
     * @param tokenXAmount Amount Amount of X to receive
     */
    function withdraw(uint256 tokenXAmount) external {
        _withdraw(tokenXAmount, msg.sender);
    }

    /**
     * @notice allows admin to send back the funds of the depositer
     * @param user  User address for which the withdrawal has to be made
     * @param tokenXAmount  Amount of X to receive
     */
    function adminWithdraw(address user, uint256 tokenXAmount)
        external
        onlyRole(PROJECT_OWNER_ROLE)
    {
        _withdraw(tokenXAmount, user);
    }

    /**
     * @notice Called by BufferCallOptions to lock the funds
     * @param tokenXAmount Amount of funds that should be locked in an option
     */
    function lock(
        uint256 id,
        uint256 tokenXAmount,
        uint256 premium
    ) external override onlyRole(OPTION_ISSUER_ROLE) {
        require(id == lockedLiquidity[msg.sender].length, "Wrong id");

        require(
            (lockedAmount + tokenXAmount) <= totalTokenXBalance(),
            "Pool: Amount is too large."
        );

        bool success = tokenX.transferFrom(msg.sender, address(this), premium);
        require(success, "The Premium transfer didn't go through");

        lockedLiquidity[msg.sender].push(
            LockedLiquidity(tokenXAmount, premium, true)
        );
        lockedPremium = lockedPremium + premium;
        lockedAmount = lockedAmount + tokenXAmount;
    }

    /**
     * @notice Called by BufferCallOptions to change the locked funds
     * @param tokenXAmount Amount of funds that should be locked in an option
     */
    function changeLock(
        uint256 id,
        uint256 tokenXAmount,
        uint256 premium
    ) public override onlyRole(OPTION_ISSUER_ROLE) {
        LockedLiquidity storage ll = lockedLiquidity[msg.sender][id];
        require(ll.locked, "lockedAmount is already unlocked");
        if (ll.premium > premium) {
            tokenX.transfer(msg.sender, ll.premium - premium);
        }
        lockedPremium = lockedPremium - ll.premium + premium;
        lockedAmount = lockedAmount - ll.amount + tokenXAmount;
        ll.premium = premium;
        ll.amount = tokenXAmount;
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

        lockedPremium = lockedPremium - ll.premium;
        lockedAmount = lockedAmount - ll.amount;
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
     * @param tokenXAmount Funds that should be sent
     */
    function send(
        uint256 id,
        address to,
        uint256 tokenXAmount
    ) external override onlyRole(OPTION_ISSUER_ROLE) {
        LockedLiquidity storage ll = lockedLiquidity[msg.sender][id];
        require(ll.locked, "Pool: lockedAmount is already unlocked");
        require(to != address(0));

        ll.locked = false;
        lockedPremium = lockedPremium - ll.premium;
        lockedAmount = lockedAmount - ll.amount;

        uint256 transferTokenXAmount = tokenXAmount > ll.amount
            ? ll.amount
            : tokenXAmount;

        bool success = tokenX.transfer(to, transferTokenXAmount);
        require(success, "Pool: The Payout transfer didn't go through");

        if (transferTokenXAmount <= ll.premium)
            emit Profit(id, ll.premium - transferTokenXAmount);
        else emit Loss(id, transferTokenXAmount - ll.premium);
    }

    /**
     * @notice Returns provider's share in X
     * @param account Provider's address
     * @return share Provider's share in X
     */
    function shareOf(address account) external view returns (uint256 share) {
        if (totalSupply() > 0)
            share = (totalTokenXBalance() * balanceOf(account)) / totalSupply();
        else share = 0;
    }

    /**
     * @notice Returns the amount of X available for withdrawals
     * @return balance Unlocked amount
     */
    function availableBalance() public view returns (uint256 balance) {
        return totalTokenXBalance() - lockedAmount;
    }

    /**
     * @notice Returns the total balance of X provided to the pool
     * @return balance Pool balance
     */
    function totalTokenXBalance()
        public
        view
        override
        returns (uint256 balance)
    {
        return tokenX.balanceOf(address(this)) - lockedPremium;
    }

    function divCeil(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b > 0);
        uint256 c = a / b;
        if (a % b != 0) c = c + 1;
        return c;
    }
}
