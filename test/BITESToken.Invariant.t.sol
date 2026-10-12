// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {BITESToken} from "src/BITESToken.sol";
import {BITESTokenHandler} from "./handlers/BITESTokenHandler.sol";

/// @notice Fixed supply, ownership and spending authorization after random transaction sequences.
/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 128
/// forge-config: default.invariant.fail-on-revert = true
contract BITESTokenInvariantTest is Test {
    uint256 internal constant SUPPLY = 10_000_000 * 10 ** 18;
    BITESToken internal token;
    BITESTokenHandler internal handler;

    function setUp() public {
        handler = new BITESTokenHandler();
        token = handler.token();

        bytes4[] memory selectors = new bytes4[](10);
        selectors[0] = handler.transfer.selector;
        selectors[1] = handler.transferAll.selector;
        selectors[2] = handler.approve.selector;
        selectors[3] = handler.transferFrom.selector;
        selectors[4] = handler.approveAndTransferFrom.selector;
        selectors[5] = handler.rejectTransferAboveBalance.selector;
        selectors[6] = handler.revokeAndRejectPull.selector;
        selectors[7] = handler.rejectPullAboveBalance.selector;
        selectors[8] = handler.rejectZeroReceiver.selector;
        selectors[9] = handler.rejectZeroSpender.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    /// @dev Independent of the token's constant totalSupply getter: actual holdings must also sum correctly.
    function invariant_fixedSupplyEqualsAllHolderBalances() public view {
        uint256 sum;
        for (uint256 i; i < handler.ACTOR_COUNT(); ++i) {
            sum += token.balanceOf(handler.actors(i));
        }
        assertEq(token.totalSupply(), SUPPLY, "supply changed after construction");
        assertEq(sum, SUPPLY, "tokens were created, destroyed or diverted");
        assertEq(token.balanceOf(address(0)), 0, "zero address acquired tokens");
        assertEq(token.balanceOf(address(token)), 0, "token collected an unrequested fee");
    }

    /// @dev Accounting identity from the authorized call inputs, including self-transfers.
    function invariant_eachHolderOwnsExactlyItsAuthorizedNetReceipts() public view {
        for (uint256 i; i < handler.ACTOR_COUNT(); ++i) {
            address actor = handler.actors(i);
            assertEq(
                token.balanceOf(actor) + handler.sent(actor),
                handler.initialBalance(actor) + handler.received(actor),
                "holder balance differs from authorized flows"
            );
        }
    }

    function invariant_allowancesEqualLatestGrantLessSuccessfulSpending() public view {
        for (uint256 i; i < handler.ACTOR_COUNT(); ++i) {
            address owner = handler.actors(i);
            assertEq(token.allowance(owner, address(0)), 0);
            for (uint256 j; j < handler.ACTOR_COUNT(); ++j) {
                address spender = handler.actors(j);
                assertEq(
                    token.allowance(owner, spender),
                    handler.expectedAllowance(owner, spender),
                    "allowance leaked, revived, or was spent on a failed call"
                );
            }
        }
    }

    /// @dev Every sequence must leave every holder able to move its entire remaining balance.
    ///      Uses transfer, so previous approvals, revocations and failed calls cannot impede exit.
    function afterInvariant() public {
        for (uint256 i = 1; i < handler.ACTOR_COUNT(); ++i) {
            handler.transferAll(i, 0);
            assertEq(token.balanceOf(handler.actors(i)), 0, "holder could not send its full balance");
        }
        assertEq(token.balanceOf(address(handler)), SUPPLY);
        invariant_fixedSupplyEqualsAllHolderBalances();
        invariant_eachHolderOwnsExactlyItsAuthorizedNetReceipts();
        invariant_allowancesEqualLatestGrantLessSuccessfulSpending();
    }
}
