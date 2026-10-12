// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {BITESToken} from "src/BITESToken.sol";

/// @notice A closed set of holders with an independent ledger of authorized token flows.
/// @dev Only the selected action functions are fuzz targets. No storage writes, token deals,
///      mint mocks or environment mutations are used to manufacture reachable token states.
contract BITESTokenHandler is Test {
    uint256 public constant SUPPLY = 10_000_000 * 10 ** 18;
    uint256 public constant ACTOR_COUNT = 4;
    BITESToken public immutable token;
    address[4] public actors;

    // Cumulative receipts and payments constrain each balance independently of totalSupply().
    mapping(address => uint256) public initialBalance;
    mapping(address => uint256) public received;
    mapping(address => uint256) public sent;
    // Grants come from requested approvals, never from reading the token's allowance back.
    mapping(address => mapping(address => uint256)) public grant;
    mapping(address => mapping(address => uint256)) public spentSinceGrant;

    constructor() {
        actors = [address(this), makeAddr("invariant-alice"), makeAddr("invariant-bob"), makeAddr("invariant-carol")];
        token = new BITESToken();
        assertEq(token.balanceOf(address(this)), SUPPLY, "constructor allocation");
        assertTrue(token.transfer(actors[1], SUPPLY / 4));
        assertTrue(token.transfer(actors[2], SUPPLY / 4));
        initialBalance[actors[0]] = SUPPLY / 2;
        initialBalance[actors[1]] = SUPPLY / 4;
        initialBalance[actors[2]] = SUPPLY / 4;
        // Actor 3 begins empty; random transfers can fund it later.
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        address from = _actor(fromSeed);
        _transfer(from, _actor(toSeed), bound(amountSeed, 0, expectedBalance(from)));
    }

    function transferAll(uint256 fromSeed, uint256 toSeed) external {
        address from = _actor(fromSeed);
        _transfer(from, _actor(toSeed), expectedBalance(from));
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amountSeed) external {
        // Bias towards revocation, dust, full supply and the finite/unlimited boundary,
        // while still exercising arbitrary 256-bit approval amounts.
        uint256 mode = amountSeed % 8;
        uint256 amount = amountSeed;
        if (mode == 0) amount = 0;
        else if (mode == 1) amount = 1;
        else if (mode == 2) amount = SUPPLY;
        else if (mode == 3) amount = type(uint256).max - 1;
        else if (mode == 4) amount = type(uint256).max;
        _approve(_actor(ownerSeed), _actor(spenderSeed), amount);
    }

    function transferFrom(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amountSeed) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        uint256 available = expectedBalance(owner);
        uint256 allowed = expectedAllowance(owner, spender);
        if (allowed < available) available = allowed;
        _transferFrom(owner, spender, _actor(toSeed), bound(amountSeed, 0, available));
    }

    /// @dev Makes nonzero delegated spends reachable without waiting for matching random approvals.
    ///      Existing allowances are also spent by the separate transferFrom action above.
    function approveAndTransferFrom(
        uint256 ownerSeed,
        uint256 spenderSeed,
        uint256 toSeed,
        uint256 amountSeed,
        bool unlimited
    ) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        uint256 amount = bound(amountSeed, 0, expectedBalance(owner));
        _approve(owner, spender, unlimited ? type(uint256).max : amount);
        _transferFrom(owner, spender, _actor(toSeed), amount);
    }

    function rejectTransferAboveBalance(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        address from = _actor(fromSeed);
        uint256 balance = expectedBalance(from);
        uint256 amount = bound(amountSeed, balance + 1, type(uint256).max);
        _reject(
            from,
            abi.encodeCall(token.transfer, (_actor(toSeed), amount)),
            abi.encodeWithSelector(BITESToken.ERC20InsufficientBalance.selector, from, balance, amount)
        );
    }

    function revokeAndRejectPull(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amountSeed) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        uint256 amount = bound(amountSeed, 1, type(uint256).max);
        _approve(owner, spender, 0);
        _reject(
            spender,
            abi.encodeCall(token.transferFrom, (owner, _actor(toSeed), amount)),
            abi.encodeWithSelector(BITESToken.ERC20InsufficientAllowance.selector, spender, 0, amount)
        );
    }

    function rejectPullAboveBalance(
        uint256 ownerSeed,
        uint256 spenderSeed,
        uint256 toSeed,
        uint256 amountSeed,
        bool unlimited
    ) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        uint256 balance = expectedBalance(owner);
        uint256 amount = bound(amountSeed, balance + 1, type(uint256).max - 1);
        _approve(owner, spender, unlimited ? type(uint256).max : amount);
        _reject(
            spender,
            abi.encodeCall(token.transferFrom, (owner, _actor(toSeed), amount)),
            abi.encodeWithSelector(BITESToken.ERC20InsufficientBalance.selector, owner, balance, amount)
        );
        // The grant stays intact. The allowance invariant detects an incorrectly spent approval.
    }

    function rejectZeroReceiver(uint256 ownerSeed, uint256 spenderSeed, uint256 amountSeed, bool delegated) external {
        address owner = _actor(ownerSeed);
        uint256 amount = bound(amountSeed, 0, expectedBalance(owner));
        bytes memory expected = abi.encodeWithSelector(BITESToken.ERC20InvalidReceiver.selector, address(0));
        if (delegated) {
            address spender = _actor(spenderSeed);
            _approve(owner, spender, amount);
            _reject(spender, abi.encodeCall(token.transferFrom, (owner, address(0), amount)), expected);
        } else {
            _reject(owner, abi.encodeCall(token.transfer, (address(0), amount)), expected);
        }
    }

    function rejectZeroSpender(uint256 ownerSeed, uint256 amount) external {
        _reject(
            _actor(ownerSeed),
            abi.encodeCall(token.approve, (address(0), amount)),
            abi.encodeWithSelector(BITESToken.ERC20InvalidSpender.selector, address(0))
        );
    }

    function expectedBalance(address actor) public view returns (uint256) {
        return initialBalance[actor] + received[actor] - sent[actor];
    }

    function expectedAllowance(address owner, address spender) public view returns (uint256) {
        uint256 approved = grant[owner][spender];
        return approved == type(uint256).max ? approved : approved - spentSinceGrant[owner][spender];
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[bound(seed, 0, ACTOR_COUNT - 1)];
    }

    function _approve(address owner, address spender, uint256 amount) internal {
        vm.prank(owner);
        assertTrue(token.approve(spender, amount), "valid approval returned false");
        grant[owner][spender] = amount;
        spentSinceGrant[owner][spender] = 0;
    }

    function _transfer(address from, address to, uint256 amount) internal {
        vm.prank(from);
        assertTrue(token.transfer(to, amount), "valid transfer returned false");
        sent[from] += amount;
        received[to] += amount;
    }

    function _transferFrom(address owner, address spender, address to, uint256 amount) internal {
        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount), "valid delegated transfer returned false");
        sent[owner] += amount;
        received[to] += amount;
        spentSinceGrant[owner][spender] += amount;
    }

    function _reject(address caller, bytes memory data, bytes memory expectedError) internal {
        vm.prank(caller);
        (bool ok, bytes memory result) = address(token).call(data);
        assertFalse(ok, "invalid operation succeeded");
        assertEq(result, expectedError, "unexpected rejection reason");
        // Ghosts remain unchanged; all balances and allowance pairs are checked by invariants.
    }
}
