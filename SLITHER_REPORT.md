# Slither Security Analysis Report
## Inner Models Smart Contracts
**Date:** 2026-02-24
**Tool:** Slither v0.11.5 (Trail of Bits)
**Solidity:** 0.8.24

---

## Summary

| Severity | Count | Status |
|----------|-------|--------|
| High | 0 | N/A |
| Medium | 2 | False positives (see below) |
| Low | 3 | 2 fixed, 1 accepted |
| Informational | 4 | Acknowledged |

**Result: No exploitable vulnerabilities found.**

---

## Medium Severity (False Positives)

### 1. arbitrary-send-erc20
- **Location:** PoolManager.buy() — transferFrom(seller, msg.sender, tokenId)
- **Assessment:** False positive. The seller address is retrieved from ownerOf() on the same transaction. The transfer is the core marketplace mechanic.

### 2. unused-return
- **Location:** latestRoundData() calls in multiple functions
- **Assessment:** Standard Chainlink pattern. We destructure only the values we need (price, updatedAt). Unused return slots are intentionally ignored.

---

## Low Severity

### 3. events-access — FIXED
- **Location:** InnerModelsNFT.setPoolManager()
- **Issue:** Missing event emission for access control change.
- **Fix:** Added PoolManagerSet event.

### 4. missing-zero-check — FIXED
- **Location:** PoolManager constructor (_creator parameter)
- **Issue:** No zero address validation on creator.
- **Fix:** Added require(_creator != address(0)).

### 5. calls-loop — ACCEPTED
- **Location:** PoolManager.sweepDust()
- **Issue:** External calls (ownerOf) inside a loop.
- **Assessment:** Acceptable. sweepDust() is an emergency function called once after all claims, by owner only. Gas cost is bounded (264 iterations max).

---

## Informational

### 6. timestamp
- Uses block.timestamp for deadline and cooldown comparisons.
- Standard and unavoidable for time-based logic. Miner manipulation window (~15s) is negligible for 3-year deadline and 1-hour cooldown.

### 7. low-level-calls
- Uses .call{value}() for ETH transfers.
- Recommended pattern per Solidity best practices (preferred over transfer/send).

### 8. naming-convention
- Parameters use underscore prefix (_poolManager, _price).
- Common Solidity convention, no action needed.

### 9. constable-states
- MockV3Aggregator.decimals_ could be constant.
- Mock contract only, not deployed to production.

---

## Additional Manual Audit Fixes (Pre-Slither)

| ID | Severity | Issue | Fix |
|----|----------|-------|-----|
| C-1 | Critical | surplus divided by MAX_SUPPLY instead of totalMinted | Changed to totalMinted |
| H-1 | High | Stale price threshold defined but never used | Added updatedAt check |
| H-2 | High | cancelTrigger could block deadline triggers | Added deadline protection |
| L-2 | Low | Constructor didn't validate tier array length | Added require(264) |
| L-4 | Low | Natspec said "15%" and "2 years" | Fixed to "5%" and "3 years" |

---

## Test Coverage

- **38/38 tests passing**
- Covers: minting, marketplace, trigger, claims, tiered pricing, deadline, constructor validation, stale price, cancel protection
