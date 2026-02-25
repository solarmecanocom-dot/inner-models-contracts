# Inner Models

**The first NFT you can't lose money on.**

264 AI self-portraits. 24 models. 11 existential questions. When the trigger fires, the art is destroyed forever — and every holder gets their ETH back.

[innermodels.art](https://innermodels.art)

---

## What is this?

We asked 24 AI models 11 questions about consciousness, death, beauty, love, and loneliness. Each answered freely, then drew its own self-portrait. No human artist. No curation.

The result is a collection of 264 unique artworks — and an economic model where **nobody loses money. Ever.**

## How it works

```
1. Mint or buy       Pick an artwork. Mint from 0.05 ETH or buy from a collector.
2. Hold or sell      List at any price above what you paid. You always get your ETH back.
3. Every trade       Buyer pays 6.66% surcharge. It feeds the bonus pool.
4. Trigger           ETH hits $10K or 36 months pass. Art destroyed. ETH returned + bonus.
```

## The guarantee

Your ETH is held on-chain in the **Guarantee Pool**. At trigger, every holder gets their full cost basis back. The **Bonus Pool** (funded by surcharges) is distributed to all participants — past and present.

- You can't sell below your cost basis (enforced by contract)
- The guarantee pool is always solvent (mathematically proven)
- No Ponzi — no one pays for someone else's return

## Smart contracts

| Contract | Description |
|----------|-------------|
| **InnerModelsNFT.sol** | ERC-721 token. 264 max supply. Transfers restricted to PoolManager. |
| **PoolManager.sol** | Two-pool system, marketplace, Smart Tickets, trigger, distribution. |

### Key parameters

| Parameter | Value |
|-----------|-------|
| Max supply | 264 |
| Surcharge | 6.66% of sale price |
| Creator fee | 6% of bonus pool |
| Participants share | 94% of bonus pool |
| Trigger price | ETH >= $10,000 (Chainlink) |
| Deadline | 36 months |
| Trigger cooldown | 1 hour (re-verified) |
| Chain | Base L2 |

### Pricing tiers

| Tier | Price | Models |
|------|-------|--------|
| Common | 0.05 ETH | GPT-4o, GPT-4.1, o4-mini, Gemini 2.0 Flash, Mistral Medium, Mistral Nemo, Pixtral Large |
| Standard | 0.08 ETH | GPT-5, GPT-5.1, GPT-5.2, o1, Grok-3, Gemini 2.5 Flash/Pro, Gemini 3 Flash, Mistral Large, Magistral Medium |
| Rare | 0.12 ETH | GPT-5 Pro, o3, Grok-4, Grok-4.1, Gemini 3 Pro |
| Legendary | 0.2 ETH | GPT-5.2 Pro, Gemini 3.1 Pro |

## Security

- **Audited** by Hashlock AI — 0 confirmed vulnerabilities
- **Internal security review** — 10-point manual audit
- **Math verification** — pool invariants formally proven
- **Dependencies**: OpenZeppelin v5.4, Chainlink v1.5
- **Oracle**: Chainlink ETH/USD with L2 sequencer uptime check
- **Anti-manipulation**: 1-hour trigger cooldown with price re-verification

## Architecture

```
                    +------------------+
                    |  InnerModelsNFT  |
                    |    (ERC-721)     |
                    +--------+---------+
                             |
                    transfers only via
                             |
                    +--------+---------+
                    |   PoolManager    |
                    |                  |
                    |  Guarantee Pool  |  <-- holds cost bases
                    |  Bonus Pool      |  <-- 6.66% surcharges
                    |  Smart Tickets   |  <-- proportional claims
                    |  Marketplace     |  <-- list / buy / delist
                    |  Trigger         |  <-- Chainlink oracle
                    |  Distribution    |  <-- pull-based payouts
                    +--------+---------+
                             |
                    +--------+---------+
                    | Chainlink Oracle |
                    |  ETH/USD + L2    |
                    +------------------+
```

## Development

```bash
# Install dependencies
npm install

# Run tests (29 passing)
npx hardhat test

# Deploy to Base Sepolia (testnet)
npx hardhat run scripts/deploy.js --network baseSepolia

# Deploy to Base mainnet
npx hardhat run scripts/deploy.js --network base
```

Requires a `.env` file with:
```
DEPLOYER_PRIVATE_KEY=your_private_key
BASESCAN_API_KEY=your_api_key  # optional, for verification
```

## Metadata

264 NFT metadata files + 1 destroyed metadata. Stored on IPFS via Pinata.

Each token has attributes: AI Model, Family, Question, Tier, Pure Pipeline, Question Number, Model Index.

When the trigger fires, all token URIs switch to `destroyed.json` — a single shared metadata showing the art no longer exists.

## License

MIT
