# VEIL Contracts

Companion **EVM rails** for VeilVM. This repo is not the protocol.

v1 layering: [`thesecretlab-dev/veil-docs` `architecture/VEIL_STACK.md`](https://github.com/thesecretlab-dev/veil-docs/blob/main/architecture/VEIL_STACK.md).

Native VEIL, VAI, AMM, COL, fee router live in **veilvm** (actions 0–18). Do not deploy a second copy of those on the companion.

## v1 rails (deploy)

```
contracts/core/WVEIL.sol
contracts/core/VeilFaucet.sol          # testnets only
contracts/bridge/VeilBridgeMinter.sol
contracts/bridge/VeilOrderIntentGateway.sol
contracts/bridge/VeilLiquidityIntentGateway.sol
contracts/identity/ZeroIdVerifier.sol
```

```bash
# PowerShell
$env:FOUNDRY_PROFILE = "rails"
forge build
```

Intent gateways are commit-only: events carry `commitment` and `nullifier`, not trader or amounts. Envelope bytes stay off-chain. Relayer is required.

Companion EVM `chainId` must not be `22207` (that is VeilVM’s HyperSDK app id).

## Parked (git only, not v1)

`core/VeilVAI`, `WsVEIL`, Olympus rebase/bonds, `defi/*` UniV2/treasury/gauges, `maker/*` DSS port, `keeper/*`, `experimental/*` meme/404.

These stay for archaeology. They are not “VEIL on EVM.”

## Build all (including parked)

```bash
forge build
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
