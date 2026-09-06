# AGENTS.md

## Repository Purpose

This is an opinionated, multi-host NixOS configuration. It contains reusable
NixOS modules, Home Manager configuration, hardware and storage definitions,
host-specific choices, an installer, local packages, encrypted secrets, and
user documentation. The flake also exports `lib.mkHost` and `lib.mkDisko` for
use by other repositories.

## Start Here

1. Read `NIX_CODE_STYLE.md` before changing Nix.
2. Read `NIX_DOCS_STYLE.md` before changing Markdown.
3. Read the relevant `docs/CONFIG.md` section and inspect the module plus its
   consumers before changing behavior.
4. Inspect representative hosts and the final diff.
5. Run the applicable checks and evaluate affected hosts.

## Architecture

`flake.nix` discovers every `hosts/*/configuration.nix`, creates local
`nixosConfigurations` and `diskoConfigurations`, exports reusable library
functions, builds the installer ISO, and exposes the checks from `lint.nix`.

- `modules/system/features/`: public `features.*` options and defaults.
- `modules/system/`: NixOS implementation, services, boot, hardware, storage,
  networking, and security.
- `modules/home-manager/`: user programs, desktop behavior, theming, and
  session configuration.
- `modules/lib/`: shared helpers and schemas, including OpenCode model metadata.
- `modules/packages/`: locally maintained packages, including Rust `pam-lldap`.
- `hosts/`: hardware facts, disk identities, feature choices, and exceptions.
- `installer/`, `modules/installer/`, `install.sh`, `build-iso.sh`: installer.
- `docs/`: installation, configuration, security, authentication, and
  operational documentation.
- `sops/`: encrypted secrets and secret-management scripts.

Import entry points are `modules/default.nix`, `modules/system/default.nix`,
`modules/system/features.nix`, and `modules/home-manager/default.nix`.
`modules/system/home-manager.nix` connects NixOS to Home Manager and optionally
loads `hosts/<name>/home.nix`.

Keep option declarations, system implementation, Home Manager behavior, and
host decisions in their respective layers. Do not move reusable behavior into a
host merely because one host exposed a problem.

## Configuration Contract

Public options live below `features.*`, commonly as
`features.<feature>.enable` and `features.<feature>.<child>.enable`. Parent and
child defaults follow the declarations and `NIX_CODE_STYLE.md`; do not infer or
normalize them casually.

Option names, types, defaults, effective enablement, inheritance, and
descriptions are a public API. Do not rename options or change these semantics
as cleanup. Such changes require an explicit functional reason, affected-host
review, and a `docs/CONFIG.md` update.

Local LLM backends are configured below `features.llm`, with independent
`ollama` and `llamaCpp` children. OpenCode providers are generated from backend
models and shared metadata in `modules/lib/opencode.nix`; do not create a
second model registry. Read the LLM/OpenCode section of `docs/CONFIG.md` before
changing this area.

## Where Changes Belong

| Change                              | Inspect first                                                                                                  |
| ----------------------------------- | -------------------------------------------------------------------------------------------------------------- |
| Public option or default            | `modules/system/features/`, implementation, `docs/CONFIG.md`, host consumers                                   |
| Service, package, port, or firewall | Owning `modules/system/` module, persistence, security, affected hosts                                         |
| Home Manager or desktop behavior    | `modules/home-manager/`, `modules/system/home-manager.nix`, host `home.nix` files                              |
| Shared helper or schema             | `modules/lib/` and every caller                                                                                |
| Hardware or host choice             | Relevant `hosts/<name>/` files                                                                                 |
| Disk layout or installer            | Host `disko.nix`, `modules/lib/disko.nix`, installer code, `docs/INSTALL.md`                                   |
| LLM or OpenCode integration         | LLM feature options, both backend modules, `modules/lib/opencode.nix`, Home Manager consumer, `docs/CONFIG.md` |
| Secret path or credential consumer  | Consuming module, `sops/README.md`, encrypted data, runtime permissions                                        |

## Hosts And State

The current hosts are `samuels-terra`, `samuels-ser9`, and `samuels-razer`.
The flake discovers new hosts automatically when a directory contains
`configuration.nix`. Host files should primarily describe hardware, device
IDs, intentional feature selections, display/layout values, and genuine
exceptions. `disko.nix` contains destructive disk assumptions.

When shared behavior changes, evaluate every discovered host, not only the host
that motivated the change.

For stateful services, inspect `StateDirectory`, mutable paths, ownership,
`modules/system/impermanence.nix`, and `docs/INSTALL.md`. Decide whether each
path is required state or disposable cache and whether it must survive reboot.

## Style And Documentation

`NIX_CODE_STYLE.md` and `NIX_DOCS_STYLE.md` are authoritative. In summary:

- Keep ownership and lifecycle boundaries clear; prefer straightforward Nix.
- Define public switches under `features.*` with explicit schemas.
- Use `lib.mkDefault` for overridable emitted values; reserve `lib.mkForce`
  for documented conflicts or invariants.
- Evaluated modules need a short purpose comment near the top.
- Comments should explain intent, constraints, failure modes, or invariants.
- Update existing user documentation when options, defaults, endpoints, ports,
  services, persistence, hardware requirements, or procedures change.
- Keep `docs/CONFIG.md` as the coherent user-facing home for LLM, Ollama,
  llama.cpp, and OpenCode configuration. Do not create backend-specific guides
  without a real discoverability need.

## Validation

The canonical checks are exported for `x86_64-linux`:

```bash
nix build .#checks.x86_64-linux.format --no-link
nix build .#checks.x86_64-linux.lint --no-link
nix build .#checks.x86_64-linux.statix --no-link
nix build .#checks.x86_64-linux.deadnix --no-link
nix build .#checks.x86_64-linux.shellcheck --no-link
nix build .#checks.x86_64-linux.shfmt --no-link
nix build .#checks.x86_64-linux.markdownlint --no-link
nix build .#checks.x86_64-linux.markdown-format --no-link
nix build .#checks.x86_64-linux.rust --no-link
nix flake check
```

Evaluate all discovered hosts:

```bash
for host_dir in hosts/*; do
  if [ -f "$host_dir/configuration.nix" ]; then
    host=${host_dir##*/}
    nix eval ".#nixosConfigurations.$host.config.system.build.toplevel.drvPath"
  fi
done
```

Use `nix build .#nixosConfigurations.<host>.config.system.build.toplevel
--no-link` for affected hosts when changing boot, services, packages, generated
scripts, or module composition. Evaluation and builds do not prove runtime,
hardware, boot, networking, acceleration, or restart behavior.

## Safety And Compatibility

- Inspect `git status --short`, `git diff`, and `git diff --cached` first.
- Treat unfamiliar worktree changes as intentional. Do not use
  `git reset --hard`, `git clean -fd`, `git checkout -- .`, or `git restore .`
  to remove them.
- Never print, decrypt into tracked paths, or commit plaintext secrets. Follow
  `sops/README.md` and use secret references rather than inline credentials.
- Services bind to loopback by default. Remote access must be deliberate and
  preserve firewall, authentication, and documented network-risk assumptions.
- Disko formatting, snapshot deletion, installer operations, and key enrollment
  may be destructive or irreversible.
- Unless a behavior change or bug fix is requested, preserve option semantics,
  generated services and packages, ports, firewall rules, persistence, provider
  IDs, model registries, and host behavior.
- Review generated shell, systemd, and configuration output as production code;
  consider missing resources, failed downloads, unavailable networks, repeated
  execution, reboot, and service restart.
- Prefer the smallest design that clearly owns the behavior. Do not add generic
  frameworks, one-consumer helpers, unused options, or cosmetic host
  normalization.

## Completion

Before finishing, understand the owning layers, make the smallest justified
change, update affected user documentation, run applicable checks, evaluate
affected hosts, review the complete diff, and state what was not runtime-tested.
