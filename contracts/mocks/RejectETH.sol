// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Mock contract that rejects all ETH transfers. Used for testing pull-pattern fallback.
contract RejectETH {
    // No receive() or fallback() — all ETH transfers will fail
}
