# ERC721SeaDropCycled

An NFT collection that reuses a small set of artworks across an unlimited number of tokens.

Normally, a collection needs one metadata file for every NFT — so a million NFTs means a million files to create and host. This contract lets you provide just a handful of designs (say 33 of them) and have them repeat in order as people mint. The 1st NFT gets design 1, the 2nd gets design 2, and so on; once it reaches the last design it loops back to the first and keeps going. You get a large, open-ended mint while only ever hosting a few files.

The designs are assigned **in fixed order, not at random** — the sequence simply repeats (1, 2, 3, … up to the last design, then back to 1). Every mint is fully predictable, so anyone can know in advance which design a given token number will receive.

It's built on OpenSea's [SeaDrop](https://github.com/ProjectOpenSea/seadrop), so minting, sale settings, and allow lists all work the same way as a standard SeaDrop collection.

---

## How the cycling works

The only logic added over the standard `ERC721SeaDrop` is an overridden `tokenURI`:

```solidity
uint256 fileId = ((tokenId - 1) % TOTAL_FILES) + 1;
return string(abi.encodePacked(baseURI, _toString(fileId)));
```

Behavior of `tokenURI(tokenId)`:

| `baseURI` state                  | Returned value                                  |
| -------------------------------- | ----------------------------------------------- |
| empty (`""`)                     | `""`                                            |
| set, **not** ending in `/`       | the `baseURI` as-is (treated as **pre-reveal**) |
| set, ending in `/`               | `baseURI` + cycled file id (`1..TOTAL_FILES`)   |

Example with `TOTAL_FILES = 33` and `baseURI = "ipfs://CID/"`:

| Token ID | File id | tokenURI            |
| -------- | ------- | ------------------- |
| 1        | 1       | `ipfs://CID/1`      |
| 33       | 33      | `ipfs://CID/33`     |
| 34       | 1       | `ipfs://CID/1`      |
| 66       | 33      | `ipfs://CID/33`     |

`TOTAL_FILES` is set once in the constructor (it is `immutable`) and **must be greater than zero** — deployment reverts with `TotalFilesIsZero()` otherwise.

> The cycled file ids are **not** suffixed with `.json`. Host your metadata so that `baseURI/1`, `baseURI/2`, … resolve correctly (e.g. an IPFS directory with files named `1`, `2`, …), or include the extension as part of how your gateway serves the directory.

---

## Pre-reveal and reveal workflow

The three `baseURI` states above give you a built-in two-phase reveal, controlled entirely by `setBaseURI` (owner-only). The only thing that distinguishes a placeholder from the real designs is **whether the base ends in `/`** — the same function flips the behavior.

### Phase 1 — Pre-reveal (placeholder)

Set a `baseURI` that does **not** end in `/`. Every token, regardless of id, returns that exact string, so all minted NFTs show the same "unrevealed" metadata while minting is in progress.

```solidity
// owner-only, before reveal — note: no trailing slash
setBaseURI("ipfs://PREREVEAL_CID");
```

Result — every token points at the single placeholder file:

| Token ID | tokenURI                              |
| -------- | ------------------------------------- |
| 1        | `ipfs://PREREVEAL_CID` |
| 2        | `ipfs://PREREVEAL_CID` |
| 34       | `ipfs://PREREVEAL_CID` |

(If you leave `baseURI` empty — the initial state — `tokenURI` returns `""` for every token instead. That works too, but a placeholder file generally renders better in marketplaces and wallets than an empty URI.)

### Phase 2 — Reveal

When you're ready to reveal (commonly after mint end), call `setBaseURI` again with a base that **ends in** `/`. From that point on `tokenURI` switches to the cycling logic and each token resolves to its design file.

```solidity
// owner-only, to reveal — note: trailing slash
setBaseURI("ipfs://REVEAL_CID/");
```

Result — tokens now resolve to their cycled designs:

| Token ID | tokenURI              |
| -------- | --------------------- |
| 1        | `ipfs://REVEAL_CID/1` |
| 33       | `ipfs://REVEAL_CID/33`|
| 34       | `ipfs://REVEAL_CID/1` |

After calling this, refresh metadata on your marketplace (e.g. OpenSea's "refresh metadata") so the new URIs are picked up.

### Things to keep in mind

- **The slash is the switch.** Toggling between phases is just whether the base string ends in `/`; there is no separate `reveal()` flag.
- **Reveal is not a shuffle.** Designs are assigned deterministically by token id (`((tokenId - 1) % TOTAL_FILES) + 1`), so anyone can compute which design a token will get even before reveal. The reveal only changes whether the placeholder or the real cycled files are served — it does not randomize or hide assignments. If you need unpredictable assignment, this contract does not provide it.
- **You can re-reveal / re-point.** `setBaseURI` can be called again to migrate gateways or fix a bad CID. Pin your reveal metadata (e.g. on IPFS) so the URIs stay resolvable.
- **Pre-reveal can last indefinitely.** Stay on the placeholder for as long as you like and reveal whenever you choose.

---

## Requirements

- [Foundry](https://book.getfoundry.sh/getting-started/installation) (`forge`) — tested with `forge 1.5.x`, Solidity `0.8.17`.
- The SeaDrop dependency available at `lib/seadrop` (see below).
- An RPC endpoint and a funded deployer key for your target chain.
- A block-explorer API key (Etherscan-compatible) if you want automatic contract verification.

---

## Project layout

```
.
├── src/
│   └── ERC721SeaDropCycled.sol   # the contract (cycling tokenURI override)
├── script/
│   ├── Deploy.s.sol              # Foundry deploy script (reads env vars)
│   └── deploy.sh                 # wrapper that validates env + runs forge script
├── foundry.toml                  # solc 0.8.17, optimizer, remappings
├── .env.example                  # template for required env vars

```

---

## Setup

### 1. Provide the SeaDrop dependency

This project does **not** vendor SeaDrop. It expects OpenSea's standard SeaDrop at `lib/seadrop` (a **symlink** to a local SeaDrop checkout).

If you cloned this project on its own, recreate the dependency one of two ways:

```bash
# Option A: point the symlink at your existing SeaDrop checkout
ln -sfn /path/to/seadrop lib/seadrop

# Option B: vendor SeaDrop directly
rm -f lib/seadrop
forge install ProjectOpenSea/seadrop
```

The remappings in `foundry.toml` resolve `seadrop/`, `ERC721A/`, `forge-std/`, OpenZeppelin, solmate, etc. relative to `lib/seadrop`, so the dependency's own `lib/` must be present (run `forge install` inside the SeaDrop checkout if needed).

### 2. Configure environment variables

Copy the template and fill in real values:

```bash
cp .env.example .env
```

| Variable             | Required        | Description                                                                       |
| -------------------- | --------------- | --------------------------------------------------------------------------------- |
| `RPC_URL`            | yes             | RPC endpoint for the target chain. Default in template: Base mainnet.             |
| `PRIVATE_KEY`        | yes             | Deployer private key (`0x`-prefixed). **Keep secret — never commit `.env`.**      |
| `ETHERSCAN_API_KEY`  | yes (to deploy) | Explorer API key used for verification. `deploy.sh` requires it.                  |
| `NAME`               | yes             | ERC-721 token name (e.g. `"Name of Token"`).                                      |
| `SYMBOL`             | yes             | ERC-721 token symbol.                                                             |
| `TOTAL_FILES`        | yes             | Number of unique metadata files to cycle through (must be > 0). Template: `33`.   |
| `ALLOWED_SEADROP`    | yes             | Comma-separated SeaDrop contract address(es) allowed to mint.                     |
| `VERIFIER_URL`       | no              | Custom verifier URL for non-Etherscan explorers (e.g. Blockscout).               |

`ALLOWED_SEADROP` accepts one or more addresses separated by commas (parsed by `Deploy.s.sol`). The template value `0x00005EA00Ac477B1030CE78506496e8C2dE24bf5` is OpenSea's canonical SeaDrop address.

---

## Build

```bash
forge build
```

---

## Deploy (with verification)

The deploy script validates that all required variables are set, prints the configuration, and runs the Foundry broadcast with verification enabled.

```bash
source .env
script/deploy.sh
```

One-liner:

```bash
source .env && script/deploy.sh
```

For a non-Etherscan explorer, also set `VERIFIER_URL` in `.env` before running:

```bash
# .env
VERIFIER_URL=https://your-explorer/api
```

### Deploy without the wrapper

If you prefer to invoke Foundry directly:

```bash
source .env
forge script script/Deploy.s.sol:Deploy \
  --rpc-url "$RPC_URL" \
  --private-key "$PRIVATE_KEY" \
  --broadcast \
  --verify --etherscan-api-key "$ETHERSCAN_API_KEY"
```

Broadcast logs (including deployed addresses) are written under `broadcast/Deploy.s.sol/<chainId>/`. For example, prior Base mainnet (chain id `8453`) runs are recorded in `broadcast/Deploy.s.sol/8453/run-latest.json`.

---

## Post-deploy configuration

The deployed contract is owned by the deployer. Typical next steps use functions inherited from `ERC721SeaDrop` / `ERC721ContractMetadata` (owner-only):

- **`setMaxSupply(uint256)`** — set the collection's max supply.
- **`setBaseURI(string)`** — set the metadata base.
  - End it with `/` to enable per-token cycled URIs (e.g. `ipfs://CID/`).
  - Omit the trailing `/` for a single pre-reveal URI returned for every token.
  - See [Pre-reveal and reveal workflow](#pre-reveal-and-reveal-workflow) for the full two-phase pattern.
- **`setContractURI(string)`** — set collection-level (storefront) metadata.
- **`updateAllowedSeaDrop(address[])`** — change which SeaDrop contracts may mint.
- Configure the SeaDrop drop itself (public sale, allow lists, creator payout, fees) through the SeaDrop contract listed in `ALLOWED_SEADROP`.

Refer to the [SeaDrop documentation](https://github.com/ProjectOpenSea/seadrop) for the full drop-configuration flow.

---

## Notes & gotchas

- **Keep `.env` out of version control.** It contains your private key. Only `.env.example` should be committed.
- `TOTAL_FILES` is immutable — to change the cycle count you must deploy a new contract.
- `tokenURI` only cycles when `baseURI` ends in `/`; otherwise it returns the base verbatim (the pre-reveal path).
- Token ids are 1-indexed in the cycling math (`((tokenId - 1) % TOTAL_FILES) + 1`), matching SeaDrop's 1-based minting.
- The base is OpenSea's standard, freely transferable `ERC721SeaDrop` — tokens are **not** soulbound.
