# Vendored dependencies

Dependencies are source files in this repository, not submodules. No build
step downloads them. `remappings.txt` maps imports into the repository.

| Dependency | Pinned release | Included files | License |
| --- | --- | --- | --- |
| [OpenZeppelin Contracts](https://github.com/OpenZeppelin/openzeppelin-contracts/tree/v5.0.2) | `v5.0.2` | ERC20 and its four transitive source dependencies, plus license | MIT |
| [forge-std](https://github.com/foundry-rs/forge-std/tree/v1.9.6) | `v1.9.6` | Complete `src/` tree and licenses; used only by tests | MIT / Apache-2.0 |

Sources are unmodified upstream files. Only the selected paths were
extracted from each tagged source archive; repository metadata, workflows,
and package managers are not required. `dependencies.lock.json` records
the exact download URLs, archive SHA-256 digests, and per-file SHA-256
digests for verification. The included files are the build inputs; future
upstream changes do not affect compilation.

OpenZeppelin licenses are in `lib/openzeppelin-contracts/LICENSE`.
forge-std licenses are in `lib/forge-std/LICENSE-MIT` and
`lib/forge-std/LICENSE-APACHE`.
