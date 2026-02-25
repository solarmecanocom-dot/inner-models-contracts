// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import "./InnerModelsNFT.sol";

/**
 * @title PoolManager
 * @notice Core contract for the Inner Models NFT project.
 *
 * Architecture: Two-Pool System
 * ─────────────────────────────
 * 1. Guarantee Pool: Holds the sum of all cost bases. Every holder
 *    is guaranteed to get their cost basis back at trigger.
 *    Invariant: guaranteePool == sum(costBasis[i]) for all minted tokens.
 *
 * 2. Surplus Pool: Funded by a 5% surcharge on every secondary sale.
 *    Distributed at trigger: 10% to creator, 90% equally to holders.
 *
 * Trigger: When Chainlink ETH/USD oracle reports >= $10,000
 *   OR when the deadline expires (3 years after deployment):
 *   - All art is destroyed (metadata updated)
 *   - Each holder can claim: costBasis + share of surplus
 *   - Creator receives 10% of surplus pool
 *
 * Resale Mechanism:
 *   - Seller lists NFT at price P (must be >= their cost basis)
 *   - Buyer pays P + 5% surcharge
 *   - Seller receives their cost basis from guarantee pool
 *   - P enters guarantee pool (buyer's new cost basis)
 *   - 5% surcharge enters surplus pool
 *   - Pool always grows on every trade
 *
 * Tiered Pricing:
 *   - Common: 0.05 ETH, Standard: 0.1 ETH, Rare: 0.15 ETH, Legendary: 0.2 ETH
 */
contract PoolManager is ReentrancyGuard, Ownable {

    // ═══════════════════════════════════════════
    //  Constants
    // ═══════════════════════════════════════════

    uint256 public constant MAX_SUPPLY = 264;
    uint256 public constant SURCHARGE_BPS = 500;        // 5%
    uint256 public constant CREATOR_FEE_BPS = 1000;     // 10% of surplus
    uint256 public constant BPS = 10000;
    uint256 public constant TRIGGER_PRICE = 10_000e8;   // $10,000 in Chainlink 8-decimal format
    uint256 public constant TRIGGER_COOLDOWN = 1 hours;
    uint256 public constant STALE_PRICE_THRESHOLD = 3600; // 1 hour
    uint256 public constant DEADLINE_DURATION = 1095 days; // 3 years

    // ═══════════════════════════════════════════
    //  State
    // ═══════════════════════════════════════════

    InnerModelsNFT public immutable nft;
    AggregatorV3Interface public immutable priceFeed;
    AggregatorV3Interface public immutable sequencerUptimeFeed;
    address public immutable creator;
    uint256 public immutable deployedAt;

    uint256 public totalMinted;

    // Tiered mint prices
    mapping(uint256 => uint256) public mintPriceOf;

    // Two pools
    uint256 public guaranteePool;
    uint256 public surplusPool;

    // Per-token tracking
    mapping(uint256 => uint256) public costBasis;

    // Marketplace listings
    struct Listing {
        uint256 price;
        bool active;
    }
    mapping(uint256 => Listing) public listings;

    // Trigger state
    enum TriggerState { Inactive, Initiated, Finalized }
    TriggerState public triggerState;
    uint256 public triggerTimestamp;

    // Claims after trigger
    mapping(uint256 => bool) public claimed;
    bool public creatorClaimed;

    // ═══════════════════════════════════════════
    //  Events
    // ═══════════════════════════════════════════

    event Minted(address indexed buyer, uint256 indexed tokenId, uint256 price);
    event Listed(uint256 indexed tokenId, uint256 price);
    event Delisted(uint256 indexed tokenId);
    event Sold(
        uint256 indexed tokenId,
        address indexed seller,
        address indexed buyer,
        uint256 salePrice,
        uint256 surcharge,
        uint256 sellerPayout
    );
    event TriggerInitiated(uint256 ethPrice, uint256 timestamp);
    event TriggerFinalized(uint256 ethPrice, uint256 guaranteePool, uint256 surplusPool);
    event Claimed(uint256 indexed tokenId, address indexed holder, uint256 basePayout, uint256 bonusPayout);
    event CreatorClaimed(address indexed creator, uint256 amount);

    // ═══════════════════════════════════════════
    //  Constructor
    // ═══════════════════════════════════════════

    // Tier assignments: tokenId => tier
    // 0 = Common (0.05 ETH), 1 = Standard (0.1 ETH), 2 = Rare (0.15 ETH), 3 = Legendary (0.2 ETH)
    uint256 public constant PRICE_COMMON    = 0.05 ether;
    uint256 public constant PRICE_STANDARD  = 0.1 ether;
    uint256 public constant PRICE_RARE      = 0.15 ether;
    uint256 public constant PRICE_LEGENDARY = 0.2 ether;

    constructor(
        address _nft,
        address _priceFeed,
        address _sequencerUptimeFeed,
        address _creator,
        uint256[] memory _tierAssignments  // 264 values: 0=Common, 1=Standard, 2=Rare, 3=Legendary
    ) Ownable(_creator) {
        require(_tierAssignments.length == MAX_SUPPLY, "Must provide 264 tier assignments");
        require(_creator != address(0), "Creator cannot be zero address");

        nft = InnerModelsNFT(_nft);
        priceFeed = AggregatorV3Interface(_priceFeed);
        sequencerUptimeFeed = AggregatorV3Interface(_sequencerUptimeFeed);
        creator = _creator;
        deployedAt = block.timestamp;

        // Set mint prices per tier
        uint256[4] memory tierPrices = [PRICE_COMMON, PRICE_STANDARD, PRICE_RARE, PRICE_LEGENDARY];
        for (uint256 i = 0; i < _tierAssignments.length; i++) {
            mintPriceOf[i] = tierPrices[_tierAssignments[i]];
        }
    }

    // ═══════════════════════════════════════════
    //  Minting
    // ═══════════════════════════════════════════

    /// @notice Mint an NFT. Full payment goes to the guarantee pool.
    ///         Price depends on the token's tier (Common/Standard/Rare/Legendary).
    function mint(uint256 tokenId) external payable nonReentrant {
        require(triggerState == TriggerState.Inactive, "Trigger active");
        require(totalMinted < MAX_SUPPLY, "Sold out");
        require(tokenId < MAX_SUPPLY, "Invalid tokenId");
        require(mintPriceOf[tokenId] > 0, "Invalid tokenId");
        require(msg.value == mintPriceOf[tokenId], "Wrong mint price");

        totalMinted++;
        costBasis[tokenId] = msg.value;
        guaranteePool += msg.value;

        nft.mint(msg.sender, tokenId);

        emit Minted(msg.sender, tokenId, msg.value);
    }

    // ═══════════════════════════════════════════
    //  Marketplace: List / Delist
    // ═══════════════════════════════════════════

    /// @notice List your NFT for sale. Price must be >= your cost basis.
    function list(uint256 tokenId, uint256 price) external {
        require(triggerState == TriggerState.Inactive, "Trigger active");
        require(nft.ownerOf(tokenId) == msg.sender, "Not owner");
        require(price >= costBasis[tokenId], "Price below cost basis");
        require(price > 0, "Price must be > 0");

        listings[tokenId] = Listing(price, true);

        emit Listed(tokenId, price);
    }

    /// @notice Remove your NFT from sale.
    function delist(uint256 tokenId) external {
        require(nft.ownerOf(tokenId) == msg.sender, "Not owner");
        require(listings[tokenId].active, "Not listed");

        listings[tokenId].active = false;

        emit Delisted(tokenId);
    }

    // ═══════════════════════════════════════════
    //  Marketplace: Buy
    // ═══════════════════════════════════════════

    /// @notice Buy a listed NFT. You pay: listing price + 5% surcharge.
    ///         Seller receives their cost basis. Price goes to guarantee pool.
    ///         Surcharge goes to surplus pool.
    function buy(uint256 tokenId) external payable nonReentrant {
        require(triggerState == TriggerState.Inactive, "Trigger active");

        Listing memory listing = listings[tokenId];
        require(listing.active, "Not listed");

        uint256 salePrice = listing.price;
        uint256 surcharge = (salePrice * SURCHARGE_BPS) / BPS;
        uint256 totalCost = salePrice + surcharge;
        require(msg.value == totalCost, "Wrong payment amount");

        address seller = nft.ownerOf(tokenId);
        require(seller != msg.sender, "Cannot buy own NFT");

        uint256 sellerCostBasis = costBasis[tokenId];

        // --- Effects ---
        listings[tokenId].active = false;
        costBasis[tokenId] = salePrice;
        guaranteePool = guaranteePool - sellerCostBasis + salePrice;
        surplusPool += surcharge;

        // --- Interactions ---
        // Transfer NFT from seller to buyer
        nft.transferFrom(seller, msg.sender, tokenId);

        // Pay seller their cost basis
        (bool success,) = payable(seller).call{value: sellerCostBasis}("");
        require(success, "Seller payment failed");

        emit Sold(tokenId, seller, msg.sender, salePrice, surcharge, sellerCostBasis);
    }

    // ═══════════════════════════════════════════
    //  Trigger: ETH reaches $10,000
    // ═══════════════════════════════════════════

    /// @notice Initiate the trigger when ETH >= $10,000 OR when deadline has passed.
    ///         Freezes all marketplace activity for TRIGGER_COOLDOWN.
    function initiateTrigger() external {
        require(triggerState == TriggerState.Inactive, "Already initiated");

        bool deadlineReached = block.timestamp >= deployedAt + DEADLINE_DURATION;

        if (!deadlineReached) {
            // Price-based trigger: need oracle check
            _checkSequencer();
            (, int256 price,,uint256 updatedAt,) = priceFeed.latestRoundData();
            require(price > 0, "Invalid price");
            require(block.timestamp - updatedAt <= STALE_PRICE_THRESHOLD, "Stale price data");
            require(uint256(price) >= TRIGGER_PRICE, "ETH below $10,000 and deadline not reached");

            triggerState = TriggerState.Initiated;
            triggerTimestamp = block.timestamp;

            emit TriggerInitiated(uint256(price), block.timestamp);
        } else {
            // Deadline trigger: no oracle needed
            triggerState = TriggerState.Initiated;
            triggerTimestamp = block.timestamp;

            emit TriggerInitiated(0, block.timestamp);
        }
    }

    /// @notice Finalize the trigger after cooldown. Re-verifies price (or deadline).
    ///         Destroys all art and enables claims.
    function finalizeTrigger() external nonReentrant {
        require(triggerState == TriggerState.Initiated, "Not initiated");
        require(block.timestamp >= triggerTimestamp + TRIGGER_COOLDOWN, "Cooldown not over");

        bool deadlineReached = block.timestamp >= deployedAt + DEADLINE_DURATION;

        if (!deadlineReached) {
            // Price-based: re-verify oracle
            _checkSequencer();
            (, int256 price,,uint256 updatedAt,) = priceFeed.latestRoundData();
            require(price > 0, "Invalid price");
            require(block.timestamp - updatedAt <= STALE_PRICE_THRESHOLD, "Stale price data");
            require(uint256(price) >= TRIGGER_PRICE, "Price dropped below $10,000");

            triggerState = TriggerState.Finalized;
            nft.destroyArt();

            emit TriggerFinalized(uint256(price), guaranteePool, surplusPool);
        } else {
            // Deadline-based: no oracle needed
            triggerState = TriggerState.Finalized;
            nft.destroyArt();

            emit TriggerFinalized(0, guaranteePool, surplusPool);
        }
    }

    /// @notice Cancel a trigger if ETH drops back below $10,000 during cooldown.
    ///         Cannot cancel a deadline-based trigger.
    function cancelTrigger() external {
        require(triggerState == TriggerState.Initiated, "Not initiated");
        require(block.timestamp < triggerTimestamp + TRIGGER_COOLDOWN, "Cooldown passed");

        // Cannot cancel a deadline-based trigger
        bool deadlineReached = block.timestamp >= deployedAt + DEADLINE_DURATION;
        require(!deadlineReached, "Deadline trigger cannot be cancelled");

        _checkSequencer();

        (, int256 price,,uint256 updatedAt,) = priceFeed.latestRoundData();
        require(block.timestamp - updatedAt <= STALE_PRICE_THRESHOLD, "Stale price data");
        if (uint256(price) < TRIGGER_PRICE) {
            triggerState = TriggerState.Inactive;
            triggerTimestamp = 0;
        }
    }

    // ═══════════════════════════════════════════
    //  Claims after trigger
    // ═══════════════════════════════════════════

    /// @notice Claim your payout after trigger finalization.
    ///         You receive: your cost basis + your share of surplus.
    function claim(uint256 tokenId) external nonReentrant {
        require(triggerState == TriggerState.Finalized, "Not finalized");
        require(nft.ownerOf(tokenId) == msg.sender, "Not owner");
        require(!claimed[tokenId], "Already claimed");

        claimed[tokenId] = true;

        // Base payout: cost basis (from guarantee pool)
        uint256 basePayout = costBasis[tokenId];

        // Bonus payout: equal share of 90% of surplus pool
        uint256 surplusForHolders = (surplusPool * (BPS - CREATOR_FEE_BPS)) / BPS;
        uint256 bonusPayout = totalMinted > 0 ? surplusForHolders / totalMinted : 0;

        uint256 totalPayout = basePayout + bonusPayout;

        (bool success,) = payable(msg.sender).call{value: totalPayout}("");
        require(success, "Claim failed");

        emit Claimed(tokenId, msg.sender, basePayout, bonusPayout);
    }

    /// @notice Creator claims their 10% of the surplus pool.
    function claimCreator() external nonReentrant {
        require(triggerState == TriggerState.Finalized, "Not finalized");
        require(msg.sender == creator, "Not creator");
        require(!creatorClaimed, "Already claimed");

        creatorClaimed = true;

        uint256 creatorPayout = (surplusPool * CREATOR_FEE_BPS) / BPS;

        (bool success,) = payable(creator).call{value: creatorPayout}("");
        require(success, "Creator claim failed");

        emit CreatorClaimed(creator, creatorPayout);
    }

    // ═══════════════════════════════════════════
    //  Views
    // ═══════════════════════════════════════════

    /// @notice Get the total cost to buy a listed NFT (price + surcharge).
    function getBuyPrice(uint256 tokenId) external view returns (uint256) {
        Listing memory listing = listings[tokenId];
        require(listing.active, "Not listed");
        uint256 surcharge = (listing.price * SURCHARGE_BPS) / BPS;
        return listing.price + surcharge;
    }

    /// @notice Get the current ETH/USD price from Chainlink.
    function getEthPrice() external view returns (uint256) {
        (, int256 price,,,) = priceFeed.latestRoundData();
        return uint256(price);
    }

    /// @notice Get the deadline timestamp.
    function deadline() external view returns (uint256) {
        return deployedAt + DEADLINE_DURATION;
    }

    /// @notice Check if the deadline has passed.
    function isDeadlineReached() external view returns (bool) {
        return block.timestamp >= deployedAt + DEADLINE_DURATION;
    }

    /// @notice Get pool statistics.
    function getPoolStats() external view returns (
        uint256 _guaranteePool,
        uint256 _surplusPool,
        uint256 _totalMinted,
        uint256 _triggerState
    ) {
        return (guaranteePool, surplusPool, totalMinted, uint256(triggerState));
    }

    /// @notice Estimate payout for a specific token at current state.
    function estimatePayout(uint256 tokenId) external view returns (uint256 base, uint256 bonus) {
        base = costBasis[tokenId];
        uint256 surplusForHolders = (surplusPool * (BPS - CREATOR_FEE_BPS)) / BPS;
        bonus = totalMinted > 0 ? surplusForHolders / totalMinted : 0;
    }

    // ═══════════════════════════════════════════
    //  Internal: Oracle checks
    // ═══════════════════════════════════════════

    function _checkSequencer() internal view {
        // If no sequencer feed is set (e.g., testnet), skip check
        if (address(sequencerUptimeFeed) == address(0)) return;

        (, int256 answer, uint256 startedAt,,) = sequencerUptimeFeed.latestRoundData();
        // answer == 0 means sequencer is up
        require(answer == 0, "Sequencer is down");
        require(block.timestamp - startedAt > TRIGGER_COOLDOWN, "Sequencer grace period");
    }

    // ═══════════════════════════════════════════
    //  Emergency
    // ═══════════════════════════════════════════

    /// @notice Recover any dust ETH left after all claims are processed.
    ///         Only callable after ALL tokens have been claimed.
    function sweepDust() external onlyOwner {
        require(triggerState == TriggerState.Finalized, "Not finalized");
        require(creatorClaimed, "Creator not claimed");

        // Check all tokens claimed
        for (uint256 i = 0; i < MAX_SUPPLY; i++) {
            // Only check minted tokens
            try nft.ownerOf(i) returns (address) {
                require(claimed[i], "Not all claimed");
            } catch {
                // Token not minted, skip
            }
        }

        uint256 dust = address(this).balance;
        if (dust > 0) {
            (bool success,) = payable(creator).call{value: dust}("");
            require(success, "Sweep failed");
        }
    }

    /// @notice Allow contract to receive ETH directly (for edge cases).
    receive() external payable {}
}
