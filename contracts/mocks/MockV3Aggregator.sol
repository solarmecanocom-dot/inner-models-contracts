// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Minimal mock of Chainlink AggregatorV3Interface for testing.
contract MockV3Aggregator {
    int256 public price;
    uint256 public updatedAt;
    uint8 public decimals_ = 8;

    constructor(int256 _price) {
        price = _price;
        updatedAt = block.timestamp;
    }

    function setPrice(int256 _price) external {
        price = _price;
        updatedAt = block.timestamp;
    }

    function latestRoundData()
        external
        view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        return (0, price, 0, updatedAt, 0);
    }

    function decimals() external view returns (uint8) {
        return decimals_;
    }
}
