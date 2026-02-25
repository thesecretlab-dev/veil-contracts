# VEIL Contracts

Smart contract suite for the VEIL protocol — privacy-native prediction markets on Avalanche.

## Architecture

```
contracts/
├── core/           Core token infrastructure
│   ├── WVEIL.sol                  Wrapped VEIL (ERC-20)
│   ├── WsVEIL.sol                 Wrapped staked VEIL (rebase wrapper)
│   ├── VeilVAI.sol                VAI stablecoin (VEIL-native)
│   ├── VeilOlympusRebaseToken.sol Rebase mechanics (Olympus-style)
│   └── VeilFaucet.sol             Testnet faucet
│
├── defi/           DeFi primitives
│   ├── VeilOlympusBondVault.sol   Bond vaults (discount VEIL via LP/DAI)
│   ├── VeilUniV2Dex.sol           Native Uniswap V2 DEX
│   ├── NativeVeilPool.sol         Liquidity pools
│   ├── NativeVeilGauge.sol        Gauge voting & emission routing
│   ├── SvDAI.sol                  Staked vault DAI
│   ├── VeilTreasury.sol           Protocol treasury
│   └── VeilLinearVesting.sol      Linear token vesting
│
├── bridge/         Cross-chain & intent infrastructure
│   ├── VeilBridgeMinter.sol       Production bridge minter (HyperSDK ↔ EVM)
│   ├── VeilLiquidityIntentGateway.sol  LP intent routing
│   └── VeilOrderIntentGateway.sol      Order intent routing
│
├── keeper/         Automation
│   └── VeilKeep3r.sol             Keeper network for automated operations
│
├── maker/          MakerDAO-style stability modules
│   ├── Vat.sol                    Core accounting engine
│   ├── DaiJoin.sol                DAI adapter
│   ├── GemJoin.sol                Collateral adapter
│   ├── Dog.sol                    Liquidation engine
│   ├── Jug.sol                    Stability fee accumulator
│   ├── Pot.sol                    DAI savings rate
│   ├── Spot.sol                   Oracle price feed
│   ├── Vow.sol                    System surplus/debt
│   └── Clip.sol                   Dutch auction liquidator
│
├── identity/       Zero-knowledge identity
│   └── ZeroIdVerifier.sol         ZER0ID Groth16 on-chain verifier
│
└── experimental/   R&D and community features
    ├── VeilMemeLauncher.sol       Meme token launchpad
    ├── VeilMemeToken.sol          Meme token standard
    ├── VeilMemeTokenV2.sol        Meme token V2 (improved)
    ├── VeilMemeV2Dex.sol          Meme-specific DEX
    ├── VeilMinerals404.sol        ERC-404 mineral tokens
    ├── MineralRarityTokens.sol    Rarity system
    ├── Multicall3.sol             Batch call utility
    └── TestCounter.sol            Test helper
```

## Key Concepts

### Chain-Owned Liquidity (COL)
Not "protocol-owned" — **chain-owned**. The L1 itself holds deep liquidity positions. Bond vaults sell discounted VEIL in exchange for LP tokens that the chain retains permanently.

### Dual Stability System
VAI stablecoin backed by MakerDAO-style modules (Vat/Jug/Spot/Dog) adapted for the VEIL ecosystem. Full liquidation engine with Dutch auctions.

### Intent Architecture
Bridge and order routing via intent gateways — users express *what* they want, the system figures out *how* across HyperSDK and companion EVM.

### Rebase + Wrapping
Olympus-style rebase token with wsVEIL wrapping for DeFi composability. Stakers earn rebase rewards; wsVEIL holders get a continuously appreciating wrapper.

## Deployment

Target chain: **VEIL L1** (Avalanche HyperSDK, ChainId `22207`) + **Companion EVM**

```bash
# Install Foundry
curl -L https://foundry.paradigm.xyz | bash
foundryup

# Build
forge build

# Test
forge test

# Deploy (requires .env with PRIVATE_KEY and RPC_URL)
forge script script/Deploy.s.sol --rpc-url $RPC_URL --broadcast
```

## Related Repos

| Repo | Description |
|------|------------|
| [`veilvm`](https://github.com/thesecretlab-dev/veilvm) | Custom Go VM (HyperSDK) — the chain these contracts run on |
| [`veil-frontend`](https://github.com/thesecretlab-dev/veil-frontend) | Market frontend at veil.markets |
| [`zeroid`](https://github.com/thesecretlab-dev/zeroid) | ZER0ID identity system (circom circuits + this verifier) |
| [`veildb`](https://github.com/thesecretlab-dev/veildb) | IPFS data layer for market and agent state |

## License

MIT
