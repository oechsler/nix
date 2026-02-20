# NixOS Code Style & Conventions

These coding conventions have proven effective in the project and should be applied consistently.

## 1. Module Organization

### Directory Structure

**Pattern**: Organize modules into thematic subdirectories with `default.nix`

```
modules/
├── home-manager/
│   ├── desktop/
│   │   ├── default.nix       # Imports: common, hyprland, kde
│   │   ├── common/
│   │   │   ├── default.nix   # Imports all common/*.nix
│   │   │   └── ...
│   │   ├── hyprland/
│   │   │   ├── default.nix   # Imports all hyprland/*.nix
│   │   │   └── ...
│   │   └── kde/
│   │       ├── default.nix   # Imports all kde/*.nix
│   │       └── ...
│   └── programs/
│       ├── default.nix
│       └── ...
```

**Advantages**:
- ✅ Clear separation of concerns
- ✅ Simple imports (only directories instead of individual files)
- ✅ Scalable (easy to add new modules)

### When to split modules?

**Split when**:
- ✅ WM-specific code mixed with common code
- ✅ Module exceeds 300 lines
- ✅ Multiple logically independent sections

**Example**: `theme.nix` → `common/theme.nix` + `hyprland/theme.nix` + `kde/theme.nix`

**Keep together when**:
- ✅ Module is <200 lines and focused
- ✅ Everything relates to one feature
- ✅ No WM-specific logic

## 2. Nix Syntax Patterns

### Nested Attributes

**❌ WRONG** (quoted nested attributes):
```nix
{
  "desktop.enable" = false;
  "desktop.dock.enable" = false;
}
```

**✅ CORRECT** (dot notation without quotes):
```nix
{
  desktop.enable = false;
  desktop.dock.enable = false;
}
```

**Why**: Quoted strings create a literal key instead of a nested structure.

### Conditional Configuration

**lib.mkIf** for single condition:
```nix
config = lib.mkIf config.features.desktop.enable {
  # ... configuration
};
```

**lib.mkMerge** for multiple sections:
```nix
config = lib.mkMerge [
  # Section 1: Always active
  {
    foo = "bar";
  }

  # Section 2: Conditional
  (lib.mkIf isKde {
    kde.enable = true;
  })

  # Section 3: Another condition
  (lib.mkIf (!isKde) {
    hyprland.enable = true;
  })
];
```

**When to use what**:
- `lib.mkIf` → Single conditional block
- `lib.mkMerge` → Multiple sections (unconditional + conditional)

### Options vs Config

**Options** definieren verfügbare Konfiguration:
```nix
options.features.desktop = {
  enable = lib.mkEnableOption "desktop environment" // { default = true; };
  wm = lib.mkOption {
    type = lib.types.enum [ "hyprland" "kde" ];
    default = "hyprland";
    description = "Window manager to use";
  };
};
```

**Config** nutzt die Options:
```nix
config = lib.mkIf config.features.desktop.enable {
  services.xserver.enable = true;
  # ...
};
```

**Rule**: Options = "What is configurable?", Config = "How is it implemented?"

### Defaults with override capability

```nix
# Overridable default
desktop.pinnedApps = lib.mkDefault [ "firefox" "kitty" ];

# Forced default (only when absolutely necessary!)
iconTheme.name = lib.mkForce "Papirus";
```

## 3. File Structure

### Standard Template

```nix
# Module Name / Purpose
#
# This module configures:
# - Feature A
# - Feature B
#
# Configuration:
#   option.foo = value;  # Description
#
# Dependencies / Notes

{ config, pkgs, lib, ... }:

let
  # ============================================================================
  # HELPER FUNCTIONS / CONSTANTS
  # ============================================================================

  helper = x: x + 1;
  constant = "value";

in
{
  #===========================
  # Options
  #===========================

  options.myModule = {
    enable = lib.mkEnableOption "my module";
  };

  #===========================
  # Configuration
  #===========================

  config = lib.mkIf config.myModule.enable {
    # Implementation
  };
}
```

### Section Separators

```nix
#===========================
# Major Section (Options, Config, etc.)
#===========================

#---------------------------
# Subsection
#---------------------------

# ============================================================================
# COMPLEX SUBSYSTEM (let bindings, scripts, etc.)
# ============================================================================
```

**Consistency**: Always use the same separators for the same purposes.

## 4. Import Patterns

### Module Parameters

**Standard destructuring**:
```nix
{ config, pkgs, lib, ... }:
```

**Zusätzliche custom parameters**:
```nix
{ config, pkgs, lib, features, theme, fonts, ... }:
```

**Rule**: Only destructure what is actually used.

### Import Types

**File import** (same directory):
```nix
imports = [
  ./foo.nix
  ./bar.nix
];
```

**Directory import** (when default.nix exists):
```nix
imports = [
  ./subdir     # → loads ./subdir/default.nix
];
```

**Conditional imports**:
```nix
imports = lib.optionals features.desktop.enable [
  ./desktop
] ++ lib.optionals (features.desktop.wm == "kde") [
  ./kde
];
```

## 5. Common Patterns

### Feature Toggles

```nix
# Simple toggle
lib.mkIf config.features.foo.enable { ... }

# Enum-based toggle
isKde = features.desktop.wm == "kde";
lib.mkIf isKde { ... }

# Multiple conditions
lib.mkIf (features.desktop.enable && !features.server) { ... }
```

### List Building

**Conditional items**:
```nix
myList =
  [ "always-present" ]
  ++ lib.optionals condition1 [ "item1" ]
  ++ lib.optionals condition2 [ "item2" "item3" ];
```

**Map over list**:
```nix
configs = map (monitor: {
  name = monitor.name;
  resolution = "${toString monitor.width}x${toString monitor.height}";
}) displays.monitors;
```

### String Interpolation

```nix
# Simple
"Hello ${name}"

# With toString
"Width: ${toString width}"

# Multiline (HEREDOC)
text = ''
  Line 1
  Line 2 with ${variable}
'';
```

## 6. Common Pitfalls & Solutions

### Pitfall 1: Quoted Nested Attributes

```nix
# ❌ FALSCH
"foo.bar" = value;

# ✅ RICHTIG
foo.bar = value;
```

### Pitfall 2: Forgetting companion files

When moving a `.nix` file:
- ✅ Check for `.scss`, `.sh`, `.json`, `.yaml` files
- ✅ Use `git mv` for both files
- ✅ Update imports in other modules

**Example**:
```bash
git mv waybar.nix hyprland/
git mv waybar-style.scss hyprland/  # Don't forget!
```

### Pitfall 3: Imports after restructuring

After file moves:
```nix
# Before
imports = [ ./waybar.nix ];

# After (if in subdir)
imports = [ ./hyprland/waybar.nix ];

# Or if default.nix exists
imports = [ ./hyprland ];
```

### Pitfall 4: Let vs Config

```nix
# ❌ WRONG - Config in let
let
  services.foo.enable = true;  # Error!
in
{ ... }

# ✅ CORRECT - Config in config block
let
  shouldEnable = true;
in
{
  config.services.foo.enable = shouldEnable;
}
```

### Pitfall 5: Missing lib functions

```nix
# mkIf, mkMerge, mkDefault, mkForce, etc. require lib
{ config, pkgs, lib, ... }:  # ← lib needed!

config = lib.mkIf condition {  # ← lib prefix
  ...
};
```

## 7. Git Workflow

### Commits

**Format**:
```
type: short description

Longer explanation of what and why.

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>
```

**Types**:
- `feat:` - New feature
- `fix:` - Bug fix
- `refactor:` - Code restructuring (no behavior change)
- `docs:` - Documentation only
- `style:` - Formatting, whitespace
- `chore:` - Maintenance (deps, build, etc.)

### File Operations

**Always use git mv**:
```bash
git mv old/path.nix new/path.nix  # Preserves history
```

**Never**:
```bash
mv old/path.nix new/path.nix
git add new/path.nix
git rm old/path.nix
# ❌ History lost!
```

## 8. Testing

### Before Commit

```bash
# Check syntax
nix flake check --no-build

# Test build
nix build .#nixosConfigurations.hostname.config.system.build.toplevel --dry-run

# Full build (takes time)
nix build .#nixosConfigurations.hostname.config.system.build.toplevel
```

### After Restructuring

Test **all** hosts:
```bash
for host in samuels-pc samuels-razer; do
  echo "Testing $host..."
  nix build .#nixosConfigurations.$host.config.system.build.toplevel --dry-run || exit 1
done
```

## 9. Documentation

See `NIX_DOCS_STYLE.md` for full documentation guidelines.

**TL;DR**:
- ✅ File header with Purpose + Options + Examples
- ✅ Comments explain **WHY**, not **WHAT**
- ✅ Complex logic with WHY/Problem/Solution/How
- ✅ Cross-references to related modules

## 10. Best Practices Summary

**DO**:
- ✅ Use `lib.mkMerge` for multiple conditional sections
- ✅ Use `lib.mkIf` for single conditions
- ✅ Organize into subdirectories with `default.nix`
- ✅ Document all modules (see NIX_DOCS_STYLE.md)
- ✅ Use `git mv` to preserve history
- ✅ Test builds before committing
- ✅ Keep modules focused and under 300 lines
- ✅ Use descriptive variable names
- ✅ Add comments for complex logic

**DON'T**:
- ❌ Quote nested attribute paths (`"foo.bar"`)
- ❌ Mix WM-specific code in common modules
- ❌ Forget companion files when moving modules
- ❌ Skip testing after restructuring
- ❌ Use `lib.mkForce` unless absolutely necessary
- ❌ Create circular dependencies between modules
- ❌ Put configuration in `let` bindings
- ❌ Forget to update imports after moves

---

**Remember**: Code is read more often than it is written. Write for the next person (including future you)!
