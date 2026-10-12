// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @title BITES
/// @notice A fixed-supply ERC-20 token. The whole supply, 10,000,000 BITES with 18 decimals, is
///         minted once to the deployer in the constructor. There is no owner, no minter, no pause,
///         no blocklist and no fee: after construction the contract holds no privileged role at all,
///         so nothing can grow the supply or move a holder's balance without that holder's approval.
/// @dev Self-contained ERC-20 (EIP-20) implementation. It follows the OpenZeppelin v5 semantics that
///      wallets and routers expect: `transfer`/`transferFrom` return true or revert, allowances are
///      spent on `transferFrom` unless set to `type(uint256).max`, and the zero address can neither
///      send nor receive. The contract name is `BITESToken`; the token's own name and symbol are
///      `BITES`, returned by `name()` and `symbol()`.
contract BITESToken {
    // ---------------------------------------------------------------------------------------------
    // Errors
    // ---------------------------------------------------------------------------------------------

    /// @notice A transfer was attempted to the zero address, or would take more than the sender holds.
    error ERC20InvalidReceiver(address receiver);
    /// @notice The sender's balance is lower than the amount being moved.
    error ERC20InsufficientBalance(address sender, uint256 balance, uint256 needed);
    /// @notice An approval names the zero address as spender.
    error ERC20InvalidSpender(address spender);
    /// @notice `transferFrom` was called for more than the spender was allowed.
    error ERC20InsufficientAllowance(address spender, uint256 allowance, uint256 needed);

    // ---------------------------------------------------------------------------------------------
    // Events (EIP-20)
    // ---------------------------------------------------------------------------------------------

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    // ---------------------------------------------------------------------------------------------
    // Constants
    // ---------------------------------------------------------------------------------------------

    /// @notice Token name as returned by `name()`.
    string public constant NAME = "BITES";
    /// @notice Token symbol as returned by `symbol()`.
    string public constant SYMBOL = "BITES";
    /// @notice Number of decimals; fixed at 18.
    uint8 public constant DECIMALS = 18;
    /// @notice The total supply in minor units: 10,000,000 whole tokens at 18 decimals. Minted once
    ///         in the constructor; there is no function that mints again.
    uint256 public constant TOTAL_SUPPLY = 10_000_000 * 10 ** uint256(DECIMALS);

    // ---------------------------------------------------------------------------------------------
    // Storage
    // ---------------------------------------------------------------------------------------------

    mapping(address account => uint256) private _balances;
    mapping(address owner => mapping(address spender => uint256)) private _allowances;

    // ---------------------------------------------------------------------------------------------
    // Constructor
    // ---------------------------------------------------------------------------------------------

    /// @notice Mints the entire fixed supply to the deployer (`msg.sender`).
    /// @dev Takes no arguments and calls no other contract, so it can run on an empty chain. The
    ///      deployer is whatever address creates the contract; at an IdentityMD launch that is the
    ///      factory, which then distributes the supply according to the launch manifest.
    constructor() {
        _balances[msg.sender] = TOTAL_SUPPLY;
        emit Transfer(address(0), msg.sender, TOTAL_SUPPLY);
    }

    // ---------------------------------------------------------------------------------------------
    // Metadata
    // ---------------------------------------------------------------------------------------------

    /// @notice Returns the token name.
    function name() external pure returns (string memory) {
        return NAME;
    }

    /// @notice Returns the token symbol.
    function symbol() external pure returns (string memory) {
        return SYMBOL;
    }

    /// @notice Returns the number of decimals.
    function decimals() external pure returns (uint8) {
        return DECIMALS;
    }

    // ---------------------------------------------------------------------------------------------
    // Views
    // ---------------------------------------------------------------------------------------------

    /// @notice Total supply in minor units. Constant for the life of the contract.
    function totalSupply() external pure returns (uint256) {
        return TOTAL_SUPPLY;
    }

    /// @notice Balance of `account` in minor units.
    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    /// @notice Remaining amount `spender` may move out of `owner`'s balance through `transferFrom`.
    function allowance(address owner, address spender) external view returns (uint256) {
        return _allowances[owner][spender];
    }

    // ---------------------------------------------------------------------------------------------
    // Mutations
    // ---------------------------------------------------------------------------------------------

    /// @notice Moves `amount` from the caller to `to`.
    /// @dev Reverts on a zero-address receiver or an insufficient balance. Always returns true.
    function transfer(address to, uint256 amount) external returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    /// @notice Sets the caller's allowance for `spender` to `amount`.
    /// @dev Overwrites the previous value, as EIP-20 specifies. Reverts on a zero-address spender.
    function approve(address spender, uint256 amount) external returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }

    /// @notice Moves `amount` from `from` to `to` using the caller's allowance.
    /// @dev An allowance of `type(uint256).max` is treated as unlimited and is not decremented.
    ///      Reverts on insufficient allowance, insufficient balance or a zero-address receiver.
    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        _spendAllowance(from, msg.sender, amount);
        _transfer(from, to, amount);
        return true;
    }

    // ---------------------------------------------------------------------------------------------
    // Internals
    // ---------------------------------------------------------------------------------------------

    function _transfer(address from, address to, uint256 amount) private {
        if (to == address(0)) revert ERC20InvalidReceiver(address(0));
        uint256 fromBalance = _balances[from];
        if (fromBalance < amount) revert ERC20InsufficientBalance(from, fromBalance, amount);
        unchecked {
            // fromBalance >= amount was just checked.
            _balances[from] = fromBalance - amount;
            // The sum of all balances is TOTAL_SUPPLY, which fits in uint256, so no overflow.
            _balances[to] += amount;
        }
        emit Transfer(from, to, amount);
    }

    function _approve(address owner, address spender, uint256 amount) private {
        if (spender == address(0)) revert ERC20InvalidSpender(address(0));
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _spendAllowance(address owner, address spender, uint256 amount) private {
        uint256 current = _allowances[owner][spender];
        if (current == type(uint256).max) return;
        if (current < amount) revert ERC20InsufficientAllowance(spender, current, amount);
        unchecked {
            _allowances[owner][spender] = current - amount;
        }
        // No Approval event on spend, matching OpenZeppelin v5 behaviour.
    }
}
