# Nix Code Style

Keep modules small, explicit, and easy to evaluate.

## Modules

- Split modules by ownership, not by aesthetic preference.
- Keep common desktop code separate from Hyprland/KDE-specific code.
- Use directory imports only when `default.nix` is the clear entry point.
- Destructure only arguments that are used.

## Options

- Define feature flags under `features.*`.
- Child toggles should default from their parent when possible.
- Use `mkDefault` for host-overridable defaults.
- Use `mkForce` only when another module must not override the value.
- Document option requirements in the option description, not in nearby prose.

## Config

- Use `lib.mkIf` for one conditional block.
- Use `lib.mkMerge` for multiple independent blocks.
- Prefer dot notation for nested attributes: `foo.bar = value;`.
- Do not quote nested attribute paths: `"foo.bar" = value;` creates a literal key.
- Keep generated scripts in `let` bindings when reused or long.

## Comments

- Explain why a value exists, not what the syntax does.
- Comment external constraints, workarounds, and non-obvious invariants.
- Remove comments when the code becomes self-explanatory.

## File Moves

- Use `git mv` for tracked file moves.
- Move companion files together (`.scss`, `.sh`, `.json`, `.yaml`).
- Update imports in the same change.

## Verification

- Run `nix flake check` before committing functional changes.
- For risky host changes, build the affected host toplevel.
