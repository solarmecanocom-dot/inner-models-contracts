// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title InnerModelsNFT
 * @notice ERC-721 token for the Inner Models project.
 *         Transfers are restricted to the PoolManager contract only.
 *         The collection is viewable on OpenSea but not tradeable there.
 */
contract InnerModelsNFT is ERC721, Ownable {
    address public poolManager;
    string private _baseTokenURI;
    bool public artDestroyed;
    string private _destroyedURI;

    uint256 public constant MAX_SUPPLY = 264;
    uint256 public totalMinted;

    event PoolManagerSet(address indexed poolManager);

    modifier onlyPoolManager() {
        require(msg.sender == poolManager, "Only PoolManager");
        _;
    }

    constructor(
        string memory baseURI,
        string memory destroyedURI
    ) ERC721("Inner Models", "INNER") Ownable(msg.sender) {
        _baseTokenURI = baseURI;
        _destroyedURI = destroyedURI;
    }

    /// @notice Update base URI for metadata (e.g., after IPFS re-upload).
    function setBaseURI(string memory newBaseURI) external onlyOwner {
        require(!artDestroyed, "Art destroyed");
        _baseTokenURI = newBaseURI;
    }

    /// @notice Set the PoolManager address. Can only be called once.
    function setPoolManager(address _poolManager) external onlyOwner {
        require(poolManager == address(0), "Already set");
        require(_poolManager != address(0), "Zero address");
        poolManager = _poolManager;
        emit PoolManagerSet(_poolManager);
    }

    /// @notice Mint a new token. Only callable by PoolManager.
    function mint(address to, uint256 tokenId) external onlyPoolManager {
        require(tokenId < MAX_SUPPLY, "Invalid tokenId");
        require(totalMinted < MAX_SUPPLY, "Max supply reached");
        totalMinted++;
        _mint(to, tokenId);
    }

    /// @notice Mark all art as destroyed after trigger event.
    function destroyArt() external onlyPoolManager {
        artDestroyed = true;
    }

    /// @notice Token URI — returns destroyed metadata if art has been burned.
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireOwned(tokenId);
        if (artDestroyed) {
            return _destroyedURI;
        }
        return string(abi.encodePacked(_baseTokenURI, _toString(tokenId), ".json"));
    }

    /// @notice Override _update to block transfers outside PoolManager.
    ///         When PoolManager calls transferFrom, we skip approval checks
    ///         by passing auth=address(0) to the parent _update.
    function _update(
        address to,
        uint256 tokenId,
        address auth
    ) internal override returns (address) {
        address from = _ownerOf(tokenId);
        // Allow minting (from == address(0))
        if (from != address(0)) {
            require(msg.sender == poolManager, "Transfers only via PoolManager");
            // Skip approval check for PoolManager
            return super._update(to, tokenId, address(0));
        }
        return super._update(to, tokenId, auth);
    }

    /// @notice Convert uint to string for tokenURI construction.
    function _toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) return "0";
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits--;
            buffer[digits] = bytes1(uint8(48 + (value % 10)));
            value /= 10;
        }
        return string(buffer);
    }
}
