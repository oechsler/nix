# NixOS Module Documentation Style Guide

These guidelines were established during the refactoring of networking.nix, development.nix, and features.nix.

## 1. File Header (always at the top)

```nix
# Module Name / Purpose
#
# This module configures:
# 1. Feature A
# 2. Feature B
# 3. Feature C
#
# Configuration options:
#   features.foo.enable = true;       # Description (default: true)
#   features.foo.bar = "value";       # Description (default: "value")
#
# Additional context (z.B. SOPS secrets, dependencies, etc.)
```

**Why:** Anyone who opens the file immediately knows what it does and which options are available.

## 2. Configuration Matrix for complex toggles

```nix
let
  # ============================================================================
  # CONFIGURATION NAME
  # ============================================================================
  # Explanation of what this config does
  #
  # Easy to customize: How to modify this config
  #
  configMatrix = {
    # Category 1
    "option.a" = value;  # Comment what this does
    "option.b" = value;  # Comment what this does

    # Category 2
    "option.c" = value;  # Comment what this does

    # What STAYS active/different:
    # - Thing 1
    # - Thing 2
  };
in
```

**Example:** Server-Mode Config in features.nix

**Why:** Complex configurations become clear, modifiable, and self-documenting.

## 3. Logical sections with separators

```nix
config = lib.mkMerge [
  #---------------------------
  # 1. Section Name
  #---------------------------
  {
    # Config here
  }

  #---------------------------
  # 2. Another Section
  #---------------------------
  (lib.mkIf condition {
    # Config here
  })
];
```

**Why:** Large modules become navigable, you can quickly find what you're looking for.

## 4. Document complex shell scripts

### 4a. Overview before the script

```nix
# Why: Explain the problem this solves
#
# Problem: Specific issue
#
# Solution: High-level approach
#
# How it works:
# - Step 1 explanation
# - Step 2 explanation
# - Step 3 explanation
#
# Result: What is achieved
#
# Note: Important caveats (e.g., "safe to run without X")

systemd.services.foo = {
  ExecStart = pkgs.writeShellScript "script-name" ''
    # ...
  '';
};
```

### 4b. Document functions

```bash
# Function: Short description
#
# Args:
#   $1 = parameter name (description/example)
#   $2 = parameter name (description/example)
#
# Steps:
#   1. What step 1 does
#   2. What step 2 does
#   3. What step 3 does
function_name() {
  local param1=$1
  local param2=$2

  # Extract something
  # Example: "172.22.0.163" (what this variable contains)
  local var=$(command | grep pattern)

  # Do something important
  # Explain WHY this is needed
  some_command "$var"
}
```

### 4c. Inline comments

```bash
# Skip if interface doesn't exist
if ! ip link show "$iface" &>/dev/null; then
  echo "Interface $iface not found, skipping"
  return
fi

# Extract network configuration from interface
# - ip: The interface's IP address (e.g., "172.22.0.163")
# - gateway: The router's IP (e.g., "172.22.0.1")
# - subnet: The network subnet (e.g., "172.22.0.0/24")
local ip=$(ip -4 addr show "$iface" | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
```

**Principles:**
- Explain WHY, not just WHAT
- Use concrete examples (IPs, values)
- Explain what variables contain
- For checks: Why is it being checked?

## 5. Split complex modules

When a module has multiple independent concerns:

```nix
config = lib.mkMerge [
  # Part 1: CLI Tools (useful everywhere)
  (lib.mkIf features.foo.enable {
    # Config
  })

  # Part 2: GUI Tools (only desktop)
  (lib.mkIf (features.foo.enable && features.foo.gui.enable) {
    # Config
  })
];
```

**Example:** development.nix - CLI vs GUI Tools

**Why:** Servers can have CLI tools, desktops can have both.

## 6. Document options

```nix
options.features = {
  foo.enable = (lib.mkEnableOption "description of feature") // {
    default = true;
  };

  foo.bar = lib.mkOption {
    type = lib.types.str;
    default = "value";
    description = "Detailed description with examples and requirements";
  };
};
```

**Principles:**
- Document default values
- For complex options: Explain requirements (e.g., "needs SOPS secret X")
- For lists: Provide examples

## 7. Package categorization

```nix
home.packages = with pkgs; [
  # Category 1
  package1  # Short comment if needed
  package2  # Short comment if needed

  # Category 2
  package3
  package4
];
```

**Example:** development.nix - Kubernetes tools, Languages, Utilities

## Checklist for new modules

- [ ] Header with overview and options
- [ ] Logical sections with `#---` separators
- [ ] Complex configs in `let` block at the beginning
- [ ] Shell scripts: Why/Problem/Solution/How explained
- [ ] Functions: Args and Steps documented
- [ ] Variables: Example values in comments
- [ ] Explain WHY not just WHAT
- [ ] For mkIf: Explain condition in comment
- [ ] Defaults documented

## Anti-Patterns (avoid these)

❌ Code without comments and complex logic
❌ "Magic numbers" without explanation
❌ Long scripts without structure/functions
❌ Variables without explanation of what they contain
❌ Only describing WHAT, not WHY
❌ No overview at the beginning of the file
❌ Unstructured config blocks (everything mixed together)
