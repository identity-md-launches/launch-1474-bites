// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {BITESToken} from "../src/BITESToken.sol";

/// @title DeployBITESToken
/// @notice Reference deployment for BITES outside an IdentityMD launch. The launch itself deploys the
///         token from its built bytecode through the factory and does not use this script.
/// @dev `deploy()` holds the whole deployment logic so tests can call it directly, with no broadcast
///      and no environment. `run()` only wraps it in a broadcast. The token takes no constructor
///      arguments: whoever deploys it receives the full supply.
contract DeployBITESToken is Script {
    /// @notice Deploys the token and returns it. The caller of this function's inner `new` is the
    ///         deployer and receives the full supply.
    function deploy() public returns (BITESToken token) {
        token = new BITESToken();
    }

    /// @notice Broadcast entry point: `forge script script/DeployBITESToken.s.sol --broadcast`.
    function run() external returns (BITESToken token) {
        vm.startBroadcast();
        token = deploy();
        vm.stopBroadcast();
    }
}
