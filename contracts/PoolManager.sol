// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import "./InnerModelsNFT.sol";

/**
 * @title PoolManager
 * @notice Core contract for the Inner Models NFT project — v2.
 *
 * Architecture: Two-Pool System + Smart Tickets
 * ──────────────────────────────────────────────
 * 1. Guarantee Pool: Holds the sum of all cost bases. Every holder
 *    is guaranteed to get their cost basis back at trigger.
 *    Invariant: guaranteePool == sum(costBasis[i]) for all minted tokens.
 *
 * 2. Surplus Pool: Funded by a 6.66% surcharge on every secondary sale.
 *    Distributed at trigger: 6% to creator, 94% to all participants
 *    proportionally to their accumulated tickets.
 *
 * Smart Tickets: Every purchase (mint or secondary) earns tickets
 *   proportional to the surcharge paid. 1 ticket = 0.001 ETH of surcharge.
 *   Tickets are cumulative and permanent — you keep them even after selling.
 *
 * Trigger: When Chainlink ETH/USD oracle reports >= $10,000
 *   OR when the deadline expires (36 months after deployment):
 *   - All art is destroyed (metadata updated)
 *   - Each participant can receive: their ticket bonus
 *   - Each holder can also receive: their cost basis (Zero Loss Guarantee)
 *   - Creator receives 6% of surplus pool
 *
 * Resale Mechanism:
 *   - Seller lists NFT at price P (must be >= their cost basis)
 *   - Buyer pays P + 6.66% surcharge
 *   - Seller receives their cost basis from guarantee pool
 *   - P enters guarantee pool (buyer's new cost basis)
 *   - 6.66% surcharge enters surplus pool
 *   - Buyer earns tickets: floor(surcharge / 0.001 ETH)
 *
 * Distribution: Anyone can call distributeFor(address) to send
 *   payouts to any participant. Failed transfers are stored for
 *   manual withdrawal via withdraw().
 */
contract PoolManager is ReentrancyGuard, Ownable {

    // ═══════════════════════════════════════════
    //  Constants
    // ═══════════════════════════════════════════

    uint256 public constant MAX_SUPPLY = 264;
    uint256 public constant SURCHARGE_BPS = 666;         // 6.66%
    uint256 public constant CREATOR_FEE_BPS = 600;       // 6% of surplus
    uint256 public constant BPS = 10000;
    uint256 public constant TICKET_PRICE = 0.001 ether;  // 1 ticket per 0.001 ETH of surcharge
    uint256 public constant TRIGGER_PRICE = 10_000e8;    // $10,000 in Chainlink 8-decimal format
    uint256 public constant TRIGGER_COOLDOWN = 1 hours;
    uint256 public constant STALE_PRICE_THRESHOLD = 3600; // 1 hour
    uint256 public constant DEADLINE_DURATION = 1095 days; // 36 months

    // Tiered mint prices
    uint256 public constant PRICE_COMMON    = 0.05 ether;
    uint256 public constant PRICE_STANDARD  = 0.08 ether;
    uint256 public constant PRICE_RARE      = 0.12 ether;
    uint256 public constant PRICE_LEGENDARY = 0.2 ether;

    // ═══════════════════════════════════════════
    //  State
    // ═══════════════════════════════════════════

    InnerModelsNFT public immutable nft;
    AggregatorV3Interface public immutable priceFeed;
    AggregatorV3Interface public immutable sequencerUptimeFeed;
    address public immutable creator;
    uint256 public immutable deployedAt;

    uint256 public totalMinted;

    // Tiered mint prices per token
    mapping(uint256 => uint256) public mintPriceOf;

    // Two pools
    uint256 public guaranteePool;
    uint256 public surplusPool;

    // Per-token tracking
    mapping(uint256 => uint256) public costBasis;

    // Smart Tickets
    mapping(address => uint256) public tickets;
    uint256 public totalTickets;
    uint256 public totalParticipants;

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

    // Distribution after trigger
    mapping(address => bool) public bonusClaimed;
    mapping(uint256 => bool) public costBasisClaimed;
    bool public creatorClaimed;
    uint256 public bonusesDistributed;

    // Fallback for failed transfers
    mapping(address => uint256) public pendingWithdrawals;
    uint256 public totalPendingWithdrawals;

    // ═══════════════════════════════════════════
    //  Events
    // ═══════════════════════════════════════════

    event Minted(address indexed buyer, uint256 indexed tokenId, uint256 price, uint256 ticketsEarned);
    event Listed(uint256 indexed tokenId, uint256 price);
    event Delisted(uint256 indexed tokenId);
    event Sold(
        uint256 indexed tokenId,
        address indexed seller,
        address indexed buyer,
        uint256 salePrice,
        uint256 surcharge,
        uint256 sellerPayout,
        uint256 ticketsEarned
    );
    event TriggerInitiated(uint256 ethPrice, uint256 timestamp);
    event TriggerFinalized(uint256 ethPrice, uint256 guaranteePool, uint256 surplusPool);
    event TriggerCancelled(uint256 ethPrice, uint256 timestamp);
    event Distributed(address indexed participant, uint256 bonus, uint256 costBasisTotal);
    event CreatorDistributed(address indexed creator, uint256 amount);
    event PendingWithdrawal(address indexed participant, uint256 amount);
    event Withdrawn(address indexed participant, uint256 amount);

    // ═══════════════════════════════════════════
    //  Constructor
    // ═══════════════════════════════════════════

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
            require(_tierAssignments[i] < 4, "Invalid tier assignment");
            mintPriceOf[i] = tierPrices[_tierAssignments[i]];
        }
    }

    // ═══════════════════════════════════════════
    //  Minting
    // ═══════════════════════════════════════════

    /// @notice Mint an NFT. Full payment goes to the guarantee pool.
    ///         Minter earns tickets based on a notional 6.66% surcharge.
    function mint(uint256 tokenId) external payable nonReentrant {
        require(triggerState == TriggerState.Inactive, "Trigger active");
        require(totalMinted < MAX_SUPPLY, "Sold out");
        require(tokenId < MAX_SUPPLY, "Invalid tokenId");
        require(mintPriceOf[tokenId] > 0, "Invalid tokenId");
        require(costBasis[tokenId] == 0, "Token already minted");
        require(msg.value == mintPriceOf[tokenId], "Wrong mint price");

        totalMinted++;
        costBasis[tokenId] = msg.value;
        guaranteePool += msg.value;

        // Award tickets to minter (notional surcharge)
        uint256 notionalSurcharge = (msg.value * SURCHARGE_BPS) / BPS;
        uint256 newTickets = notionalSurcharge / TICKET_PRICE;
        if (newTickets > 0) {
            _addTickets(msg.sender, newTickets);
        }

        nft.mint(msg.sender, tokenId);

        emit Minted(msg.sender, tokenId, msg.value, newTickets);
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

    /// @notice Buy a listed NFT. You pay: listing price + 6.66% surcharge.
    ///         Seller receives their cost basis. Price goes to guarantee pool.
    ///         Surcharge goes to surplus pool. Buyer earns tickets.
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

        // Award tickets to buyer
        uint256 newTickets = surcharge / TICKET_PRICE;
        if (newTickets > 0) {
            _addTickets(msg.sender, newTickets);
        }

        // --- Interactions ---
        // Transfer NFT from seller to buyer
        nft.transferFrom(seller, msg.sender, tokenId);

        // Pay seller their cost basis (pull pattern on failure)
        (bool success,) = payable(seller).call{value: sellerCostBasis}("");
        if (!success) {
            pendingWithdrawals[seller] += sellerCostBasis;
            totalPendingWithdrawals += sellerCostBasis;
            emit PendingWithdrawal(seller, sellerCostBasis);
        }

        emit Sold(tokenId, seller, msg.sender, salePrice, surcharge, sellerCostBasis, newTickets);
    }

    // ═══════════════════════════════════════════
    //  Trigger: ETH reaches $10,000 or deadline
    // ═══════════════════════════════════════════

    /// @notice Initiate the trigger when ETH >= $10,000 OR when deadline has passed.
    ///         Freezes all marketplace activity for TRIGGER_COOLDOWN.
    function initiateTrigger() external {
        require(triggerState == TriggerState.Inactive, "Already initiated");

        bool deadlineReached = block.timestamp >= deployedAt + DEADLINE_DURATION;

        if (!deadlineReached) {
            _checkSequencer();
            (, int256 price,,uint256 updatedAt,) = priceFeed.latestRoundData();
            require(price > 0, "Invalid price");
            require(block.timestamp - updatedAt <= STALE_PRICE_THRESHOLD, "Stale price data");
            require(uint256(price) >= TRIGGER_PRICE, "ETH below $10,000 and deadline not reached");

            triggerState = TriggerState.Initiated;
            triggerTimestamp = block.timestamp;
            emit TriggerInitiated(uint256(price), block.timestamp);
        } else {
            triggerState = TriggerState.Initiated;
            triggerTimestamp = block.timestamp;
            emit TriggerInitiated(0, block.timestamp);
        }
    }

    /// @notice Finalize the trigger after cooldown. Re-verifies price (or deadline).
    ///         Destroys all art and enables distribution.
    function finalizeTrigger() external nonReentrant {
        require(triggerState == TriggerState.Initiated, "Not initiated");
        require(block.timestamp >= triggerTimestamp + TRIGGER_COOLDOWN, "Cooldown not over");

        bool deadlineReached = block.timestamp >= deployedAt + DEADLINE_DURATION;

        if (!deadlineReached) {
            _checkSequencer();
            (, int256 price,,uint256 updatedAt,) = priceFeed.latestRoundData();
            require(price > 0, "Invalid price");
            require(block.timestamp - updatedAt <= STALE_PRICE_THRESHOLD, "Stale price data");
            require(uint256(price) >= TRIGGER_PRICE, "Price dropped below $10,000");

            triggerState = TriggerState.Finalized;
            nft.destroyArt();
            emit TriggerFinalized(uint256(price), guaranteePool, surplusPool);
        } else {
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

        bool deadlineReached = block.timestamp >= deployedAt + DEADLINE_DURATION;
        require(!deadlineReached, "Deadline trigger cannot be cancelled");

        _checkSequencer();
        (, int256 price,,uint256 updatedAt,) = priceFeed.latestRoundData();
        require(block.timestamp - updatedAt <= STALE_PRICE_THRESHOLD, "Stale price data");
        require(uint256(price) < TRIGGER_PRICE, "Price still above trigger");

        triggerState = TriggerState.Inactive;
        triggerTimestamp = 0;
        emit TriggerCancelled(uint256(price), block.timestamp);
    }

    // ═══════════════════════════════════════════
    //  Distribution after trigger
    // ═══════════════════════════════════════════

    /// @notice Distribute payout to any participant. Anyone can call this.
    ///         Sends: ticket bonus + cost basis for any held tokens.
    ///         If transfer fails, amount is stored for manual withdrawal.
    function distributeFor(address participant) external nonReentrant {
        require(triggerState == TriggerState.Finalized, "Not finalized");
        require(tickets[participant] > 0, "No tickets");
        require(!bonusClaimed[participant], "Already distributed");

        bonusClaimed[participant] = true;
        bonusesDistributed++;

        // Calculate ticket bonus: participant's share of 94% of surplus
        uint256 surplusForParticipants = (surplusPool * (BPS - CREATOR_FEE_BPS)) / BPS;
        uint256 bonus = (surplusForParticipants * tickets[participant]) / totalTickets;

        // Also distribute cost basis for any tokens this address holds
        uint256 costBasisTotal = 0;
        for (uint256 i = 0; i < MAX_SUPPLY; i++) {
            if (costBasis[i] > 0 && !costBasisClaimed[i]) {
                try nft.ownerOf(i) returns (address owner) {
                    if (owner == participant) {
                        costBasisClaimed[i] = true;
                        costBasisTotal += costBasis[i];
                    }
                } catch {}
            }
        }

        uint256 totalPayout = bonus + costBasisTotal;

        if (totalPayout > 0) {
            (bool success,) = payable(participant).call{value: totalPayout}("");
            if (!success) {
                pendingWithdrawals[participant] += totalPayout;
                totalPendingWithdrawals += totalPayout;
                emit PendingWithdrawal(participant, totalPayout);
            }
        }

        emit Distributed(participant, bonus, costBasisTotal);
    }

    /// @notice Creator claims their 6% of the surplus pool.
    ///         Anyone can call this — funds go to the creator address.
    function distributeCreator() external nonReentrant {
        require(triggerState == TriggerState.Finalized, "Not finalized");
        require(!creatorClaimed, "Already claimed");

        creatorClaimed = true;

        uint256 creatorPayout = (surplusPool * CREATOR_FEE_BPS) / BPS;

        if (creatorPayout > 0) {
            (bool success,) = payable(creator).call{value: creatorPayout}("");
            if (!success) {
                pendingWithdrawals[creator] += creatorPayout;
                totalPendingWithdrawals += creatorPayout;
                emit PendingWithdrawal(creator, creatorPayout);
            }
        }

        emit CreatorDistributed(creator, creatorPayout);
    }

    /// @notice Withdraw pending funds if a previous distribution failed.
    function withdraw() external nonReentrant {
        uint256 amount = pendingWithdrawals[msg.sender];
        require(amount > 0, "Nothing to withdraw");

        pendingWithdrawals[msg.sender] = 0;
        totalPendingWithdrawals -= amount;

        (bool success,) = payable(msg.sender).call{value: amount}("");
        require(success, "Withdraw failed");

        emit Withdrawn(msg.sender, amount);
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
        uint256 _triggerState,
        uint256 _totalTickets,
        uint256 _totalParticipants
    ) {
        return (guaranteePool, surplusPool, totalMinted, uint256(triggerState), totalTickets, totalParticipants);
    }

    /// @notice Estimate payout for a participant.
    function estimatePayout(address participant) external view returns (
        uint256 bonus,
        uint256 costBasisTotal,
        uint256 participantTickets
    ) {
        participantTickets = tickets[participant];
        if (totalTickets > 0 && participantTickets > 0) {
            uint256 surplusForParticipants = (surplusPool * (BPS - CREATOR_FEE_BPS)) / BPS;
            bonus = (surplusForParticipants * participantTickets) / totalTickets;
        }

        // Sum cost basis for held tokens
        for (uint256 i = 0; i < MAX_SUPPLY; i++) {
            if (costBasis[i] > 0) {
                try nft.ownerOf(i) returns (address owner) {
                    if (owner == participant) {
                        costBasisTotal += costBasis[i];
                    }
                } catch {}
            }
        }
    }

    /// @notice Get ticket info for an address.
    function getTickets(address participant) external view returns (uint256) {
        return tickets[participant];
    }

    // ═══════════════════════════════════════════
    //  Internal
    // ═══════════════════════════════════════════

    event TicketsAwarded(address indexed participant, uint256 amount, uint256 newTotal);

    function _addTickets(address participant, uint256 amount) internal {
        if (tickets[participant] == 0) {
            totalParticipants++;
        }
        tickets[participant] += amount;
        totalTickets += amount;
        emit TicketsAwarded(participant, amount, tickets[participant]);
    }

    function _checkSequencer() internal view {
        if (address(sequencerUptimeFeed) == address(0)) return;

        (, int256 answer, uint256 startedAt,,) = sequencerUptimeFeed.latestRoundData();
        require(answer == 0, "Sequencer is down");
        require(block.timestamp - startedAt > TRIGGER_COOLDOWN, "Sequencer grace period");
    }

    // ═══════════════════════════════════════════
    //  Emergency
    // ═══════════════════════════════════════════

    /// @notice Recover any dust ETH left after all distributions are done.
    function sweepDust() external onlyOwner {
        require(triggerState == TriggerState.Finalized, "Not finalized");
        require(creatorClaimed, "Creator not distributed");
        require(bonusesDistributed == totalParticipants, "Not all bonuses distributed");
        require(totalPendingWithdrawals == 0, "Pending withdrawals exist");

        // Check all cost bases claimed for minted tokens
        for (uint256 i = 0; i < MAX_SUPPLY; i++) {
            if (costBasis[i] > 0) {
                try nft.ownerOf(i) returns (address) {
                    require(costBasisClaimed[i], "Not all cost bases distributed");
                } catch {}
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
