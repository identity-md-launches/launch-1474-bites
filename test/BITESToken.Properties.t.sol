// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {BITESToken} from "src/BITESToken.sol";

/// @notice Boundary and algebraic properties supplementing the original token tests.
/// forge-config: default.fuzz.runs = 1000
contract BITESTokenPropertiesTest is Test {
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    uint256 internal constant SUPPLY = 10_000_000 * 10 ** 18;
    BITESToken internal token;
    address internal owner = makeAddr("property-owner");
    address internal alice = makeAddr("property-alice");
    address internal bob = makeAddr("property-bob");
    address internal carol = makeAddr("property-carol");
    address[4] internal actors;

    function setUp() public {
        actors = [owner, alice, bob, carol];
        vm.prank(owner);
        token = new BITESToken();
    }

    function test_oneWeiCanMoveThroughEveryHolderAndReturnToDeployer() public {
        for (uint256 i; i < actors.length; ++i) {
            address from = actors[i];
            address to = actors[(i + 1) % actors.length];
            vm.expectEmit(true, true, false, true, address(token));
            emit Transfer(from, to, 1);
            vm.prank(from);
            assertTrue(token.transfer(to, 1));
        }
        assertEq(token.balanceOf(owner), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(carol), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_zeroTransfersEmitEvenWithNoBalanceOrApproval() public {
        bytes32 beforeState = _stateDigest();
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, carol, 0);
        vm.prank(alice);
        assertTrue(token.transfer(carol, 0));

        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, carol, 0);
        vm.prank(bob);
        assertTrue(token.transferFrom(alice, carol, 0));
        assertEq(_stateDigest(), beforeState, "zero transfers changed accounting");
    }

    function test_zeroAmountsStillRejectZeroReceiverAndSpender() public {
        _assertRejected(
            alice,
            abi.encodeCall(token.transfer, (address(0), 0)),
            abi.encodeWithSelector(BITESToken.ERC20InvalidReceiver.selector, address(0))
        );
        _assertRejected(
            bob,
            abi.encodeCall(token.transferFrom, (alice, address(0), 0)),
            abi.encodeWithSelector(BITESToken.ERC20InvalidReceiver.selector, address(0))
        );
        _assertRejected(
            alice,
            abi.encodeCall(token.approve, (address(0), 0)),
            abi.encodeWithSelector(BITESToken.ERC20InvalidSpender.selector, address(0))
        );
    }

    function test_maximumTransferCannotWrapBalances() public {
        _assertRejected(
            owner,
            abi.encodeCall(token.transfer, (alice, type(uint256).max)),
            abi.encodeWithSelector(BITESToken.ERC20InsufficientBalance.selector, owner, SUPPLY, type(uint256).max)
        );
        _approve(owner, bob, type(uint256).max);
        _assertRejected(
            bob,
            abi.encodeCall(token.transferFrom, (owner, alice, type(uint256).max)),
            abi.encodeWithSelector(BITESToken.ERC20InsufficientBalance.selector, owner, SUPPLY, type(uint256).max)
        );
        assertEq(token.allowance(owner, bob), type(uint256).max);
    }

    function test_fullSupplyDelegatedTransferExhaustsFiniteAllowance() public {
        _approve(owner, bob, SUPPLY);
        vm.prank(bob);
        assertTrue(token.transferFrom(owner, alice, SUPPLY));
        assertEq(token.balanceOf(owner), 0);
        assertEq(token.balanceOf(alice), SUPPLY);
        assertEq(token.allowance(owner, bob), 0);

        // Returning the funds does not restore an already consumed authorization.
        vm.prank(alice);
        assertTrue(token.transfer(owner, SUPPLY));
        _assertRejected(
            bob,
            abi.encodeCall(token.transferFrom, (owner, alice, 1)),
            abi.encodeWithSelector(BITESToken.ERC20InsufficientAllowance.selector, bob, 0, 1)
        );
    }

    function test_maximumMinusOneAllowanceIsFinite() public {
        _approve(owner, bob, type(uint256).max - 1);
        vm.prank(bob);
        assertTrue(token.transferFrom(owner, alice, 1));
        assertEq(token.allowance(owner, bob), type(uint256).max - 2);
        vm.prank(bob);
        assertTrue(token.transferFrom(owner, carol, SUPPLY - 1));
        assertEq(token.allowance(owner, bob), type(uint256).max - 1 - SUPPLY);
        assertEq(token.balanceOf(owner), 0);
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(carol), SUPPLY - 1);
    }

    function test_unlimitedAllowanceSurvivesRepeatedSpendsThenCanBeRevoked() public {
        _approve(owner, bob, type(uint256).max);
        vm.prank(bob);
        assertTrue(token.transferFrom(owner, alice, 1));
        vm.prank(bob);
        assertTrue(token.transferFrom(owner, carol, SUPPLY - 1));
        assertEq(token.allowance(owner, bob), type(uint256).max);
        assertEq(token.balanceOf(owner), 0);

        vm.prank(carol);
        assertTrue(token.transfer(owner, SUPPLY - 1));
        _approve(owner, bob, 0);
        _assertRejected(
            bob,
            abi.encodeCall(token.transferFrom, (owner, alice, 1)),
            abi.encodeWithSelector(BITESToken.ERC20InsufficientAllowance.selector, bob, 0, 1)
        );

        _approve(owner, bob, 2);
        vm.prank(bob);
        assertTrue(token.transferFrom(owner, alice, 1));
        assertEq(token.allowance(owner, bob), 1, "a former unlimited approval must become finite");
    }

    function test_allowancesBelongToAnOrderedOwnerSpenderPair() public {
        vm.prank(owner);
        assertTrue(token.transfer(alice, 10));
        _approve(alice, bob, 8);
        _approve(alice, carol, 3);
        _approve(bob, alice, 9);
        _approve(owner, bob, 11);

        vm.prank(bob);
        assertTrue(token.transferFrom(alice, carol, 5));
        assertEq(token.allowance(alice, bob), 3);
        assertEq(token.allowance(alice, carol), 3);
        assertEq(token.allowance(bob, alice), 9);
        assertEq(token.allowance(owner, bob), 11);

        // Receiving tokens or being the original deployer does not authorize a pull.
        _assertRejected(
            carol,
            abi.encodeCall(token.transferFrom, (owner, carol, 1)),
            abi.encodeWithSelector(BITESToken.ERC20InsufficientAllowance.selector, carol, 0, 1)
        );
        _assertRejected(
            owner,
            abi.encodeCall(token.transferFrom, (alice, owner, 1)),
            abi.encodeWithSelector(BITESToken.ERC20InsufficientAllowance.selector, owner, 0, 1)
        );
    }

    function test_failedZeroRecipientPullPreservesAllowanceForValidRetry() public {
        _approve(owner, bob, 7);
        _assertRejected(
            bob,
            abi.encodeCall(token.transferFrom, (owner, address(0), 7)),
            abi.encodeWithSelector(BITESToken.ERC20InvalidReceiver.selector, address(0))
        );
        vm.prank(bob);
        assertTrue(token.transferFrom(owner, carol, 7));
        assertEq(token.allowance(owner, bob), 0);
        assertEq(token.balanceOf(carol), 7);
    }

    function test_selfTransferStillRequiresSufficientBalance() public {
        _assertRejected(
            alice,
            abi.encodeCall(token.transfer, (alice, 1)),
            abi.encodeWithSelector(BITESToken.ERC20InsufficientBalance.selector, alice, 0, 1)
        );
        _approve(alice, bob, 1);
        _assertRejected(
            bob,
            abi.encodeCall(token.transferFrom, (alice, alice, 1)),
            abi.encodeWithSelector(BITESToken.ERC20InsufficientBalance.selector, alice, 0, 1)
        );
    }

    function test_allThreeTransferFromRolesMayBeTheSameAddress() public {
        _approve(owner, owner, SUPPLY);
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(owner, owner, SUPPLY);
        vm.prank(owner);
        assertTrue(token.transferFrom(owner, owner, SUPPLY));
        assertEq(token.balanceOf(owner), SUPPLY);
        assertEq(token.allowance(owner, owner), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_transferRoundTripRestoresBalances(uint256 held, uint256 amount) public {
        held = bound(held, 0, SUPPLY);
        amount = bound(amount, 0, held);
        vm.prank(owner);
        assertTrue(token.transfer(alice, held));
        bytes32 beforeState = _stateDigest();

        vm.prank(alice);
        assertTrue(token.transfer(bob, amount));
        assertEq(token.balanceOf(bob), amount, "recipient must receive the entire amount");
        vm.prank(bob);
        assertTrue(token.transfer(alice, amount));
        assertEq(_stateDigest(), beforeState, "round trip created or destroyed value");
    }

    function testFuzz_selfTransferPreservesBalancesButDelegatedSpendConsumesAllowance(
        uint256 held,
        uint256 amount,
        uint256 allowanceSeed
    ) public {
        held = bound(held, 0, SUPPLY);
        amount = bound(amount, 0, held);
        uint256 allowed = bound(allowanceSeed, amount, type(uint256).max - 1);
        vm.prank(owner);
        assertTrue(token.transfer(alice, held));
        _approve(alice, bob, allowed);
        bytes32 beforeState = _stateDigest();

        vm.prank(alice);
        assertTrue(token.transfer(alice, amount));
        assertEq(_stateDigest(), beforeState);
        vm.prank(bob);
        assertTrue(token.transferFrom(alice, alice, amount));
        assertEq(token.balanceOf(alice), held);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.allowance(alice, bob), allowed - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_approvalOverwriteIsIdempotentAndDoesNotMoveFunds(uint256 first, uint256 second) public {
        _approve(alice, bob, first);
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(alice, bob, second);
        _approve(alice, bob, second);
        assertEq(token.allowance(alice, bob), second);
        bytes32 once = _stateDigest();
        _approve(alice, bob, second);
        assertEq(_stateDigest(), once);
        assertEq(token.balanceOf(owner), SUPPLY);
        assertEq(token.balanceOf(alice), 0, "approval must work without tokens and must not mint");
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_splitDelegatedSpendingCannotExceedGrant(uint256 allowed, uint256 first) public {
        allowed = bound(allowed, 1, SUPPLY - 1);
        first = bound(first, 0, allowed);
        _approve(owner, bob, allowed);
        vm.prank(bob);
        assertTrue(token.transferFrom(owner, alice, first));
        vm.prank(bob);
        assertTrue(token.transferFrom(owner, carol, allowed - first));
        assertEq(token.allowance(owner, bob), 0);
        assertEq(token.balanceOf(alice) + token.balanceOf(carol), allowed);
        assertEq(token.balanceOf(owner), SUPPLY - allowed);
        _assertRejected(
            bob,
            abi.encodeCall(token.transferFrom, (owner, carol, 1)),
            abi.encodeWithSelector(BITESToken.ERC20InsufficientAllowance.selector, bob, 0, 1)
        );
    }

    function testFuzz_insufficientBalanceRollsBackFiniteAllowance(uint256 held, uint256 neededSeed) public {
        held = bound(held, 0, SUPPLY);
        uint256 needed = bound(neededSeed, held + 1, type(uint256).max - 1);
        vm.prank(owner);
        assertTrue(token.transfer(alice, held));
        _approve(alice, bob, needed);
        _approve(alice, carol, 13);
        _assertRejected(
            bob,
            abi.encodeCall(token.transferFrom, (alice, carol, needed)),
            abi.encodeWithSelector(BITESToken.ERC20InsufficientBalance.selector, alice, held, needed)
        );
    }

    function testFuzz_insufficientAllowanceDoesNotMoveFunds(uint256 allowed, uint256 neededSeed) public {
        allowed = bound(allowed, 0, SUPPLY - 1);
        uint256 needed = bound(neededSeed, allowed + 1, SUPPLY);
        _approve(owner, bob, allowed);
        _approve(owner, carol, SUPPLY);
        _assertRejected(
            bob,
            abi.encodeCall(token.transferFrom, (owner, alice, needed)),
            abi.encodeWithSelector(BITESToken.ERC20InsufficientAllowance.selector, bob, allowed, needed)
        );
    }

    function testFuzz_zeroRecipientPullRollsBackAnyAllowance(uint256 amount, bool unlimited) public {
        amount = bound(amount, 0, SUPPLY);
        _approve(owner, bob, unlimited ? type(uint256).max : amount);
        _assertRejected(
            bob,
            abi.encodeCall(token.transferFrom, (owner, address(0), amount)),
            abi.encodeWithSelector(BITESToken.ERC20InvalidReceiver.selector, address(0))
        );
    }

    function _approve(address from, address spender, uint256 amount) internal {
        vm.prank(from);
        assertTrue(token.approve(spender, amount));
    }

    function _assertRejected(address caller, bytes memory data, bytes memory expectedError) internal {
        bytes32 beforeState = _stateDigest();
        vm.prank(caller);
        (bool ok, bytes memory result) = address(token).call(data);
        assertFalse(ok, "invalid operation succeeded");
        assertEq(result, expectedError, "unexpected rejection reason");
        assertEq(_stateDigest(), beforeState, "rejected operation changed balances or allowances");
    }

    /// @dev Snapshot every actor and allowance pair, including unrelated pairs, through the public API.
    function _stateDigest() internal view returns (bytes32) {
        uint256[4] memory balances;
        uint256[16] memory allowances;
        for (uint256 i; i < actors.length; ++i) {
            balances[i] = token.balanceOf(actors[i]);
            assertEq(token.allowance(actors[i], address(0)), 0);
            for (uint256 j; j < actors.length; ++j) {
                allowances[i * actors.length + j] = token.allowance(actors[i], actors[j]);
            }
        }
        return keccak256(
            abi.encode(
                balances, allowances, token.totalSupply(), token.balanceOf(address(0)), token.balanceOf(address(token))
            )
        );
    }
}
