// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {BITESToken} from "../src/BITESToken.sol";
import {DeployBITESToken} from "../script/DeployBITESToken.s.sol";

/// @notice Exercises the deploy script's logic function directly, with no broadcast and no environment.
contract DeployBITESTokenTest is Test {
    function test_deployMintsSupplyToTheScriptCaller() public {
        DeployBITESToken script = new DeployBITESToken();
        BITESToken token = script.deploy();
        // `deploy()` runs `new` from the script contract, so the script contract is the deployer.
        assertEq(token.totalSupply(), 10_000_000 ether);
        assertEq(token.balanceOf(address(script)), 10_000_000 ether);
        assertEq(token.name(), "BITES");
        assertEq(token.symbol(), "BITES");
        assertEq(token.decimals(), 18);
    }
}
