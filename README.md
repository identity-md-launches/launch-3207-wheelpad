# WheelPad (WHEELPAD)

WheelPad is an ERC-20 token with a fixed supply of **1,000,000,000 tokens** and
**18 decimals**. The constructor mints the entire supply once to its immediate
caller (`msg.sender`). The contract exposes no further minting, burning,
ownership, pausing, blacklisting, fees, or upgrade controls.

## Deployment parameters

| Parameter | Value |
| --- | --- |
| Solidity contract | `src/WheelPad.sol:WheelPad` |
| Name | `WheelPad` |
| Symbol | `WHEELPAD` |
| Decimals | `18` |
| Supply in smallest units | `1000000000000000000000000000` (`10^27`) |
| Constructor arguments | None (`[]`) |
| Native currency sent at deployment | None |
| Initial recipient | Immediate deploying address |
| Launch chain | Ethereum, chain ID `1` |
| Compiler | Solidity `0.8.26` |
| EVM target | `cancun` |
| Optimizer | Enabled, 200 runs |
| Metadata bytecode hash | `none` |
| Linked libraries | None |

`INITIAL_SUPPLY` is the named constant for the supply in smallest units.
Deployment needs no external contract, oracle, configuration call, owner
address, or initialization transaction. The creation bytecode is available
in `out/WheelPad.sol/WheelPad.json` after building.

The authorized launch process deploys the bytecode through its factory, so
the factory receives all tokens. A direct deployment instead credits that
direct deployer; deploying through any other helper credits the helper.
This is intentionally independent of `tx.origin`. No supply is preallocated
by the token to application contracts or other recipients.

The launch factory handles the specified subsequent distribution: 10% to
the launch distributor, 80% to pool liquidity, and the remaining 10% to
`0xd6302976e590b9b947da8774b7f1246164e0ce98`. These are external launch
operations, not constructor operations. The token has no hardcoded
factory, pool, distributor, or recipient addresses and transfers every
requested amount exactly. The separate launch step supplies its manifest;
this repository supplies only the token, its tests, and build inputs.

## Behavior and assumptions

- Standard `transfer`, `approve`, and `transferFrom` return `true` on
  success and revert with ERC-6093 custom errors on invalid operations.
- Only the holder can transfer directly. Delegated transfers require that
  holder's allowance for the caller, including when the caller is also
  the holder. The deployer has no privileged access to anyone's balance.
- Transfers of zero tokens and transfers to oneself are supported and
  emit `Transfer`. Zero recipients and zero approval spenders are rejected,
  even for zero amounts. An unsuccessful transfer changes no balances or
  allowances.
- `approve` replaces the existing allowance. Finite allowances decrease
  when spent; `type(uint256).max` represents an allowance that does not
  decrease. Explicit approvals emit `Approval`; allowance spending does
  not emit an additional `Approval` event in this OpenZeppelin version.
  Integrators should query `allowance` instead of reconstructing it solely
  from approval logs.
- Metadata and total supply remain fixed. There are no transfer callbacks,
  transaction limits, external calls, rebases, or transfer taxes.
- The token is not a payable contract and rejects ordinary native-currency
  transfers. It cannot recover assets sent to its own address, and it does
  not validate whether a nonzero recipient can recover received tokens.

## Build and test

All Solidity dependencies and their licenses are included as ordinary files
under `lib/`; no package installation, submodule initialization, RPC, fork,
environment configuration, or network access is needed for the build or
tests once Foundry and Solidity 0.8.26 are installed.

```sh
forge build
FOUNDRY_FUZZ_SEED=0x73b2a8e5c7e393214bbb926d2dd1457991e0aa25989b8c4bb588fb0e2d44892d forge test
forge fmt --check
```

The test suite checks constructor supply and its event, deployment through
a CREATE2 factory, exact launch-style transfers, metadata, transfers,
allowances, events, zero amounts, self-transfers, maximum amounts, invalid
addresses, unauthorized spending, failure atomicity, unsupported privileged
entrypoints, and rejection of native currency. Fuzz tests cover successful
and failing amounts and arbitrary deployers/recipients (512 cases per test).
Stateful invariants compare balances and allowances to a separate model and
check supply conservation across randomized operation sequences (128 runs
of up to 64 calls per invariant).

The launch-style transfer fixture checks token accounting only; it does
not simulate Uniswap swaps. The supplied protected launch tests require
the network's separate factory/PoolManager harness, which is not present
in this standalone project. The network runs those integration checks
against the final launch artifacts.

## After launch

There are no settings, administrator roles, maintenance jobs, or owner-only
actions. The launch operator is responsible for deploying the reviewed
artifact, publishing/verifying its source and address, confirming metadata
and the exact initial supply, and completing the launch distribution and
pool setup. No deployment or broadcast is performed by this project.

Holders manage their own keys and allowances. Integrations should request
only the allowance they need. When changing an active allowance, revoke
it to zero and confirm that transaction before approving a replacement;
this reduces the standard ERC-20 allowance replacement race but cannot
cancel a spend already executed. Lost keys, mistaken transfers, and assets
sent to the token contract cannot be repaired by an administrator.

See [SECURITY.md](SECURITY.md) for the local review and its limits, and
[DEPENDENCIES.md](DEPENDENCIES.md) for vendored source provenance.
