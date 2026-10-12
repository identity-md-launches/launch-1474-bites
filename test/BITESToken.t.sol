// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {BITESToken} from "../src/BITESToken.sol";

/// @notice Minimal ERC-20 surface, declared here so the tests do not depend on any vendored interface.
interface IERC20Like {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
}

/// @notice Stands in for the launch factory: deploys the token from its own context so `msg.sender`
///         in the constructor is this contract, exactly as at launch.
contract DeployerProbe {
    function deployToken() external returns (BITESToken) {
        return new BITESToken();
    }

    function send(BITESToken token, address to, uint256 amount) external returns (bool) {
        return token.transfer(to, amount);
    }
}

contract BITESTokenTest is Test {
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    uint256 internal constant SUPPLY = 10_000_000 ether; // 10,000,000 * 10**18

    DeployerProbe internal deployer;
    BITESToken internal token;

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");

    function setUp() public {
        deployer = new DeployerProbe();
        token = deployer.deployToken();
    }

    // ---------------------------------------------------------------------------------------------
    // Metadata and supply
    // ---------------------------------------------------------------------------------------------

    function test_metadata() public view {
        assertEq(token.name(), "BITES");
        assertEq(token.symbol(), "BITES");
        assertEq(token.decimals(), 18);
    }

    function test_supplyIsTenMillionWithEighteenDecimals() public view {
        assertEq(token.totalSupply(), 10_000_000 * 10 ** 18);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.TOTAL_SUPPLY(), SUPPLY);
    }

    function test_constructorMintsWholeSupplyToDeployer() public view {
        assertEq(token.balanceOf(address(deployer)), SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(0)), 0);
    }

    function test_constructorEmitsMintTransfer() public {
        vm.expectEmit(true, true, true, true);
        emit Transfer(address(0), address(this), SUPPLY);
        new BITESToken();
    }

    function test_deployerIsWhoeverCreatesTheContract() public {
        vm.prank(alice);
        BITESToken fresh = new BITESToken();
        assertEq(fresh.balanceOf(alice), SUPPLY);
        assertEq(fresh.balanceOf(address(this)), 0);
    }

    function test_eachDeploymentIsIndependent() public {
        BITESToken second = deployer.deployToken();
        assertEq(second.totalSupply(), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(second.balanceOf(address(deployer)), SUPPLY);
        assertEq(token.balanceOf(address(deployer)), SUPPLY);
    }

    // ---------------------------------------------------------------------------------------------
    // transfer
    // ---------------------------------------------------------------------------------------------

    function test_transferMovesExactAmountAndEmits() public {
        vm.expectEmit(true, true, true, true, address(token));
        emit Transfer(address(deployer), alice, 1_000 ether);
        assertTrue(deployer.send(token, alice, 1_000 ether));
        assertEq(token.balanceOf(alice), 1_000 ether);
        assertEq(token.balanceOf(address(deployer)), SUPPLY - 1_000 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferBetweenOrdinaryHoldersIsExact() public {
        deployer.send(token, alice, 500 ether);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 200 ether));
        assertEq(token.balanceOf(alice), 300 ether);
        assertEq(token.balanceOf(bob), 200 ether);
    }

    function test_transferWholeBalance() public {
        deployer.send(token, alice, 7 ether);
        vm.prank(alice);
        token.transfer(bob, 7 ether);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 7 ether);
    }

    function test_transferZeroAmountSucceeds() public {
        vm.prank(alice);
        assertTrue(token.transfer(bob, 0));
        assertEq(token.balanceOf(bob), 0);
    }

    function test_transferToSelfKeepsBalance() public {
        deployer.send(token, alice, 10 ether);
        vm.prank(alice);
        token.transfer(alice, 10 ether);
        assertEq(token.balanceOf(alice), 10 ether);
    }

    function test_transferWholeSupplyAtOnce() public {
        assertTrue(deployer.send(token, alice, SUPPLY));
        assertEq(token.balanceOf(alice), SUPPLY);
        assertEq(token.balanceOf(address(deployer)), 0);
    }

    function test_RevertWhen_transferExceedsBalance() public {
        deployer.send(token, alice, 1 ether);
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(BITESToken.ERC20InsufficientBalance.selector, alice, 1 ether, 1 ether + 1)
        );
        token.transfer(bob, 1 ether + 1);
    }

    function test_RevertWhen_transferFromEmptyAccount() public {
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(BITESToken.ERC20InsufficientBalance.selector, bob, 0, 1));
        token.transfer(alice, 1);
    }

    function test_RevertWhen_transferToZeroAddress() public {
        deployer.send(token, alice, 1 ether);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(BITESToken.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 1);
    }

    // ---------------------------------------------------------------------------------------------
    // approve / allowance / transferFrom
    // ---------------------------------------------------------------------------------------------

    function test_approveSetsAllowanceAndEmits() public {
        vm.expectEmit(true, true, true, true, address(token));
        emit Approval(alice, bob, 42);
        vm.prank(alice);
        assertTrue(token.approve(bob, 42));
        assertEq(token.allowance(alice, bob), 42);
    }

    function test_approveOverwritesPreviousAllowance() public {
        vm.startPrank(alice);
        token.approve(bob, 100);
        token.approve(bob, 5);
        vm.stopPrank();
        assertEq(token.allowance(alice, bob), 5);
    }

    function test_approveZeroClearsAllowance() public {
        vm.startPrank(alice);
        token.approve(bob, 100);
        token.approve(bob, 0);
        vm.stopPrank();
        assertEq(token.allowance(alice, bob), 0);
    }

    function test_RevertWhen_approveZeroAddressSpender() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(BITESToken.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 1);
    }

    function test_transferFromSpendsAllowance() public {
        deployer.send(token, alice, 100 ether);
        vm.prank(alice);
        token.approve(bob, 60 ether);

        vm.expectEmit(true, true, true, true, address(token));
        emit Transfer(alice, carol, 40 ether);
        vm.prank(bob);
        assertTrue(token.transferFrom(alice, carol, 40 ether));

        assertEq(token.balanceOf(alice), 60 ether);
        assertEq(token.balanceOf(carol), 40 ether);
        assertEq(token.balanceOf(bob), 0, "the spender does not receive anything");
        assertEq(token.allowance(alice, bob), 20 ether);
    }

    function test_transferFromWithMaxAllowanceDoesNotDecrement() public {
        deployer.send(token, alice, 100 ether);
        vm.prank(alice);
        token.approve(bob, type(uint256).max);
        vm.prank(bob);
        token.transferFrom(alice, carol, 30 ether);
        assertEq(token.allowance(alice, bob), type(uint256).max);
        assertEq(token.balanceOf(carol), 30 ether);
    }

    function test_transferFromExactAllowanceLeavesZero() public {
        deployer.send(token, alice, 10 ether);
        vm.prank(alice);
        token.approve(bob, 10 ether);
        vm.prank(bob);
        token.transferFrom(alice, bob, 10 ether);
        assertEq(token.allowance(alice, bob), 0);
        assertEq(token.balanceOf(bob), 10 ether);
    }

    function test_RevertWhen_transferFromWithoutAllowance() public {
        deployer.send(token, alice, 10 ether);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(BITESToken.ERC20InsufficientAllowance.selector, bob, 0, 1));
        token.transferFrom(alice, bob, 1);
    }

    function test_RevertWhen_transferFromExceedsAllowance() public {
        deployer.send(token, alice, 10 ether);
        vm.prank(alice);
        token.approve(bob, 5 ether);
        vm.prank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(BITESToken.ERC20InsufficientAllowance.selector, bob, 5 ether, 5 ether + 1)
        );
        token.transferFrom(alice, carol, 5 ether + 1);
    }

    function test_RevertWhen_transferFromExceedsBalanceDespiteAllowance() public {
        deployer.send(token, alice, 1 ether);
        vm.prank(alice);
        token.approve(bob, 2 ether);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(BITESToken.ERC20InsufficientBalance.selector, alice, 1 ether, 2 ether));
        token.transferFrom(alice, carol, 2 ether);
        // A failed transferFrom spends nothing.
        assertEq(token.allowance(alice, bob), 2 ether);
    }

    function test_RevertWhen_transferFromToZeroAddress() public {
        deployer.send(token, alice, 1 ether);
        vm.prank(alice);
        token.approve(bob, 1 ether);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(BITESToken.ERC20InvalidReceiver.selector, address(0)));
        token.transferFrom(alice, address(0), 1);
    }

    function test_RevertWhen_strangerPullsFromDeployer() public {
        // The deployer holds the supply; without an approval nobody, including the test, can move it.
        vm.expectRevert(abi.encodeWithSelector(BITESToken.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(address(deployer), address(this), 1);
        assertEq(token.balanceOf(address(deployer)), SUPPLY);
    }

    // ---------------------------------------------------------------------------------------------
    // No privileged surface: nothing mints, pauses, blocks, freezes or seizes
    // ---------------------------------------------------------------------------------------------

    function test_noMintOrAdminSelectorIncreasesSupply() public {
        address attacker = makeAddr("attacker");
        string[10] memory signatures = [
            "mint(address,uint256)",
            "mint(uint256)",
            "mint()",
            "issue(uint256)",
            "setOwner(address)",
            "transferOwnership(address)",
            "upgradeTo(address)",
            "initialize(address)",
            "unpause()",
            "setMinter(address)"
        ];
        for (uint256 i; i < signatures.length; ++i) {
            bytes memory data = abi.encodeWithSignature(signatures[i], attacker, type(uint128).max);
            vm.prank(attacker);
            (bool ok,) = address(token).call(data);
            assertFalse(ok, signatures[i]);
            vm.prank(address(deployer));
            (ok,) = address(token).call(data);
            assertFalse(ok, signatures[i]);
            assertEq(token.totalSupply(), SUPPLY, signatures[i]);
            assertEq(token.balanceOf(attacker), 0, signatures[i]);
        }
    }

    function test_noPrivilegedSelectorMovesOrFreezesAHolder() public {
        deployer.send(token, alice, SUPPLY / 1_000);
        uint256 held = token.balanceOf(alice);
        string[12] memory signatures = [
            "pause()",
            "blacklist(address)",
            "blocklist(address)",
            "freeze(address)",
            "freezeAccount(address)",
            "setBlacklist(address,bool)",
            "setBlocked(address,bool)",
            "lock(address)",
            "disableTransfers()",
            "setTransfersEnabled(bool)",
            "burnFrom(address,uint256)",
            "seize(address)"
        ];
        for (uint256 i; i < signatures.length; ++i) {
            vm.prank(address(deployer));
            (bool ok,) = address(token).call(abi.encodeWithSignature(signatures[i], alice, true));
            assertFalse(ok, signatures[i]);
        }
        assertEq(token.balanceOf(alice), held);
        vm.prank(alice);
        assertTrue(token.transfer(bob, held / 2));
        assertEq(token.balanceOf(bob), held / 2);
    }

    function test_unknownSelectorReverts() public {
        (bool ok,) = address(token).call(abi.encodeWithSignature("doesNotExist()"));
        assertFalse(ok);
    }

    function test_RevertWhen_sendingEther() public {
        vm.deal(address(this), 1 ether);
        (bool ok,) = address(token).call{value: 1}("");
        assertFalse(ok, "the token must not accept ether");
    }

    function test_runtimeHasNoDelegatecallCallcodeOrSelfdestruct() public view {
        bytes memory runtime = address(token).code;
        assertGt(runtime.length, 0);
        assertLe(runtime.length, 24_576, "runtime exceeds EIP-170");
        for (uint256 i; i < runtime.length; ++i) {
            uint8 op = uint8(runtime[i]);
            if (op >= 0x60 && op <= 0x7F) {
                i += (op - 0x5F);
                continue;
            }
            assertTrue(op != 0xF4, "DELEGATECALL");
            assertTrue(op != 0xF2, "CALLCODE");
            assertTrue(op != 0xFF, "SELFDESTRUCT");
        }
    }

    // ---------------------------------------------------------------------------------------------
    // Launch-shaped flows: factory -> distributor -> claimant, and a pool-like contract round trip
    // ---------------------------------------------------------------------------------------------

    function test_launchFlowsMoveExactlyWhatTheySay() public {
        address distributor = makeAddr("distributor");
        address claimant = makeAddr("claimant");
        address remainder = makeAddr("remainder");
        address pool = makeAddr("pool");

        uint256 swarm = (SUPPLY * 1_000) / 10_000;
        uint256 poolShare = (SUPPLY * 8_100) / 10_000;
        uint256 rest = SUPPLY - swarm - poolShare;

        assertTrue(deployer.send(token, distributor, swarm));
        assertTrue(deployer.send(token, pool, poolShare));
        assertTrue(deployer.send(token, remainder, rest));
        assertEq(token.balanceOf(distributor), swarm);
        assertEq(token.balanceOf(pool), poolShare);
        assertEq(token.balanceOf(remainder), rest);
        assertEq(token.balanceOf(address(deployer)), 0);

        vm.prank(distributor);
        token.transfer(claimant, swarm);
        assertEq(token.balanceOf(claimant), swarm);
        assertEq(token.balanceOf(distributor), 0);

        // A trader buys from and sells back into the pool: both legs exact.
        address trader = makeAddr("trader");
        vm.prank(pool);
        token.transfer(trader, 123_456);
        assertEq(token.balanceOf(trader), 123_456);
        vm.prank(trader);
        token.transfer(pool, 123_456);
        assertEq(token.balanceOf(trader), 0);
        assertEq(token.balanceOf(pool), poolShare);

        assertEq(token.totalSupply(), SUPPLY, "the flows changed the supply");
    }

    // ---------------------------------------------------------------------------------------------
    // Fuzz
    // ---------------------------------------------------------------------------------------------

    function testFuzz_transferConservesSupply(address to, uint256 amount) public {
        vm.assume(to != address(0));
        amount = bound(amount, 0, SUPPLY);
        deployer.send(token, to, amount);
        if (to == address(deployer)) {
            assertEq(token.balanceOf(to), SUPPLY);
        } else {
            assertEq(token.balanceOf(to), amount);
            assertEq(token.balanceOf(address(deployer)), SUPPLY - amount);
        }
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_transferAboveBalanceReverts(uint256 held, uint256 extra) public {
        held = bound(held, 0, SUPPLY - 1);
        extra = bound(extra, 1, SUPPLY - held);
        deployer.send(token, alice, held);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(BITESToken.ERC20InsufficientBalance.selector, alice, held, held + extra));
        token.transfer(bob, held + extra);
    }

    function testFuzz_allowanceAccounting(uint256 allowed, uint256 spent) public {
        allowed = bound(allowed, 0, type(uint256).max - 1); // exclude the unlimited sentinel
        spent = bound(spent, 0, SUPPLY);
        deployer.send(token, alice, SUPPLY);
        vm.prank(alice);
        token.approve(bob, allowed);
        vm.prank(bob);
        if (spent > allowed) {
            vm.expectRevert(abi.encodeWithSelector(BITESToken.ERC20InsufficientAllowance.selector, bob, allowed, spent));
            token.transferFrom(alice, carol, spent);
        } else {
            token.transferFrom(alice, carol, spent);
            assertEq(token.allowance(alice, bob), allowed - spent);
            assertEq(token.balanceOf(carol), spent);
            assertEq(token.balanceOf(alice), SUPPLY - spent);
        }
    }
}
