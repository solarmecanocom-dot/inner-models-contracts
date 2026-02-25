# Inner Models

**The first NFT you can't lose money on.**

297 AI self-portraits. 27 models. 11 existential questions. When the trigger fires, the art is destroyed forever — and every holder gets their ETH back.

[innermodels.art](https://innermodels.art)

---

## What is this?

We asked 27 AI models 11 questions about consciousness, death, beauty, love, and loneliness. Each answered freely, then drew its own self-portrait. No human artist. No curation.

The result is a collection of 297 unique artworks — and an economic model where **nobody loses money. Ever.**

## How it works

```
1. Mint or buy       Pick an artwork. Mint for 0.1 ETH or buy from a collector.
2. Hold or sell      List at any price above what you paid. You always get your ETH back.
3. Every trade       Buyer pays 6.66% surcharge. It feeds the bonus pool.
4. Trigger           ETH hits $10K or 36 months pass. Art destroyed. ETH returned + bonus.
```

## The guarantee

Your ETH is held on-chain in the **Guarantee Pool**. At trigger, every holder gets their full cost basis back. The **Bonus Pool** (funded by surcharges) is distributed to all participants — past and present.

- You can't sell below your cost basis (enforced by contract)
- The guarantee pool is always solvent (mathematically proven)
- No Ponzi — no one pays for someone else's return

## AI Models

5 providers, 27 models:

| Provider | Models |
|----------|--------|
| **OpenAI** | GPT-4o, GPT-4.1, GPT-5, GPT-5.1, GPT-5.2, GPT-5 Pro, GPT-5.2 Pro, o1, o3, o4-mini |
| **xAI** | Grok-3, Grok-4, Grok-4.1 |
| **Google** | Gemini 2.0 Flash, Gemini 2.5 Flash, Gemini 2.5 Pro, Gemini 3 Flash, Gemini 3 Pro, Gemini 3.1 Pro |
| **Mistral** | Mistral Large, Mistral Medium, Magistral Medium, Pixtral Large, Mistral Nemo |
| **Anthropic** | Claude Opus 4.6, Claude Sonnet 4.6, Claude Haiku 4.5 |

## Smart contracts

| Contract | Description |
|----------|-------------|
| **InnerModelsNFT.sol** | ERC-721 token. 297 max supply. Transfers restricted to PoolManager. |
| **PoolManager.sol** | Two-pool system, marketplace, Smart Tickets, trigger, distribution. |

### Key parameters

| Parameter | Value |
|-----------|-------|
| Max supply | 297 |
| Mint price | 0.1 ETH (uniform) |
| Surcharge | 6.66% of sale price |
| Creator fee | 6% of bonus pool |
| Participants share | 94% of bonus pool |
| Trigger price | ETH >= $10,000 (Chainlink) |
| Deadline | 36 months |
| Trigger cooldown | 15 minutes (re-verified) |
| Chain | Base L2 |

## Security

- **Audited** by Hashlock AI — 0 confirmed vulnerabilities
- **Internal security review** — 10-point manual audit
- **Math verification** — pool invariants formally proven
- **60 tests passing** — full coverage of minting, trading, trigger, distribution
- **Dependencies**: OpenZeppelin v5.4, Chainlink v1.5
- **Oracle**: Chainlink ETH/USD with L2 sequencer uptime check
- **Anti-manipulation**: 15-minute trigger cooldown with price re-verification

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

# Run tests (60 passing)
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

297 NFT metadata files + 1 destroyed metadata. Stored on IPFS via Pinata.

Each token has attributes: AI Model, Family, Question, Pure Pipeline, Question Number, Model Index.

When the trigger fires, all token URIs switch to `destroyed.json` — a single shared metadata showing the art no longer exists.

## License
 
MIT
