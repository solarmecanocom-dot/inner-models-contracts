// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

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

    uint256 public constant MAX_SUPPLY = 297;
    uint256 public totalMinted;

    event PoolManagerSet(address indexed poolManager);
    event ArtDestroyed(uint256 timestamp);
    event BaseURIUpdated(string newURI);

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
        emit BaseURIUpdated(newBaseURI);
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
        emit ArtDestroyed(block.timestamp);
    }

    /// @notice Token URI — returns destroyed metadata if art has been burned.
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireOwned(tokenId);
        if (artDestroyed) {
            return _destroyedURI;
        }
        return string(abi.encodePacked(_baseTokenURI, Strings.toString(tokenId), ".json"));
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
            require(poolManager != address(0), "PoolManager not set");
            require(msg.sender == poolManager, "Transfers only via PoolManager");
            // Skip approval check for PoolManager
            return super._update(to, tokenId, address(0));
        }
        return super._update(to, tokenId, auth);
    }

}
