# Nix Code Style

Keep the configuration cohesive, explicit, and easy to evaluate. Prefer small
changes that make ownership and behavior obvious.

## Modules

- Split modules at ownership, lifecycle, or reuse boundaries, not at an arbitrary line count.
- Keep shared desktop behavior separate from Hyprland- and KDE-specific behavior.
- Use a directory import only when the directory has a clear `default.nix` entry point.
- Destructure only arguments used by the module; prefix intentionally unused arguments with `_` when needed.
- Keep long or reused generated scripts in named `let` bindings.
- Treat modules above roughly 300-500 lines as candidates for review, not automatic violations.

## Options

- Define public feature switches under `features.*`.
- Keep implementation settings in the namespace that owns them.
- Make child defaults inherit from their parent when a child has no useful meaning without it.
- Independent extensions may use their own defaults, but their resulting configuration must still be gated by the parent where appropriate.
- Give every public option a description stating purpose, units, valid values, constraints, and required external resources.
- Use `lib.types.enum`, `lib.types.submodule`, and `lib.types.nullOr` to make schemas explicit.
- Use `example =` for non-trivial public list or submodule options when it improves discoverability.

## Configuration

- Use `mkOption { default = ...; }` for normal option defaults.
- Use `lib.mkDefault` when emitting a lower-priority configuration value that hosts or other modules may override.
- Use `lib.mkForce` only for deliberate conflict resolution, and comment the external constraint or invariant that requires it.
- Use `lib.mkIf` for one coherent conditional fragment.
- Use `lib.mkMerge` when several fragments have independent conditions or when combining unconditional and conditional fragments.
- Do not introduce `mkMerge` only for visual grouping.
- Prefer dot notation for Nix option paths: `foo.bar = value;`.
- Quote keys when the key itself is a literal required by an external schema, filename, sysctl namespace, application preference, or string-keyed map.

These are intentionally different:

```nix
features.desktop.wm = "kde";
boot.kernel.sysctl."vm.swappiness" = 10;
programs.firefox.preferences."browser.startup.page" = 1;
xdg.configFile."systemd/user.conf".text = "...";
```

## Comments

- Every evaluated module must begin with a short purpose comment within its first five lines. Import-only `default.nix` files, packages, and generated files are exempt.
- Comment intent, constraints, failure modes, invariants, destructive behavior, and non-obvious external behavior.
- Comments explaining an opaque external setting are useful; comments restating a simple assignment are not.
- Section separators are optional. If used, keep one separator style within a file.
- Embedded scripts should document privileged or destructive operations, retry and timeout policy, generated formats, cleanup, and why a script is needed.

## File Moves

- Use `git mv` for tracked file moves.
- Move companion files together and update imports in the same change.
- For new modules, add the file to the flake input before relying on flake evaluation; untracked files are ignored by flakes.

## Verification

Before committing, run:

```bash
nix build .#checks.x86_64-linux.format --no-link
nix build .#checks.x86_64-linux.lint --no-link
nix build .#checks.x86_64-linux.statix --no-link
nix build .#checks.x86_64-linux.deadnix --no-link
nix build .#checks.x86_64-linux.shellcheck --no-link
nix build .#checks.x86_64-linux.markdownlint --no-link
nix build .#checks.x86_64-linux.markdown-format --no-link
nix build .#checks.x86_64-linux.rust --no-link
```

For functional changes, evaluate the affected host with `nix eval`. Build the
affected toplevel when changing boot, services, packages, generated scripts,
or module composition. CI also runs shellcheck where configured. `nix eval`
checks evaluation; `nix build` additionally checks derivation builds.
