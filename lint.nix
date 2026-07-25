# NixOS Configuration Linter
#
# Shell-based linter that enforces conventions from NIX_CODE_STYLE.md and NIX_DOCS_STYLE.md
#
# This is the custom convention checker. Additional linters also run:
#   - statix: Anti-patterns and best practices (15 built-in rules)
#   - deadnix: Dead code detection (unused variable bindings)
#
# Usage:
#   nix build .#checks.x86_64-linux.lint     # Custom conventions
#   nix build .#checks.x86_64-linux.statix   # Anti-patterns
#   nix build .#checks.x86_64-linux.deadnix  # Dead code
#   nix flake check                          # All checks
#
# CI Integration:
#   nix flake check || exit 1
#
# Design: Uses shell scripts during the build phase instead of pure Nix
# evaluation (lib.filesystem.listFilesRecursive + builtins.readFile) to
# avoid evaluation-timeouts in CI on large directory trees.
#
# ============================================================================
# CONVENTIONS ENFORCED
# ============================================================================
#
# 1. NO QUOTED NESTED ATTRIBUTES (NIX_CODE_STYLE.md §2)
#    ❌ WRONG:  "desktop.enable" = false;
#    ✅ CORRECT: desktop.enable = false;
#
#    Why: Quoted strings create a literal key "desktop.enable" instead of
#         a nested attribute structure { desktop = { enable = false; }; }
#
#    Exception: Application settings (Firefox, etc.) where quoted keys are
#               required: settings = { "browser.startup.page" = 3; };
#
# 2. DOCUMENTATION HEADERS (NIX_DOCS_STYLE.md §1)
#    ✅ All modules must have a header comment explaining:
#       - Purpose of the module
#       - Configuration options available
#       - Key features
#
#    Example:
#      # Module Name / Purpose
#      #
#      # This module configures:
#      # - Feature A
#      # - Feature B
#      #
#      # Configuration:
#      #   option.foo = value;  # Description
#
#    Exception: default.nix (import-only files)
#               packages/*.nix (use meta.description)
#
# 3. FUTURE CHECKS (can be added):
#    - Module structure (config = lib.mkIf ...)
#    - Section separators (#=== vs #---)
#    - Shell script documentation (Why/Problem/Solution/How)
#
# Full conventions: NIX_CODE_STYLE.md, NIX_DOCS_STYLE.md
# ============================================================================

{ pkgs, lib, ... }:

pkgs.runCommand "nixos-config-lint" { } ''
  export LC_ALL=C.UTF-8

  src="${./.}"

  fails=0
  total=0

  echo "=== NixOS Configuration Lint Results ==="
  echo ""

  # ==========================================================================
  # CHECK 1: No Quoted Nested Attributes
  # ==========================================================================
  echo "--- Check 1: No Quoted Nested Attributes ---"

  while IFS= read -r -d $'\0' f; do
    total=$((total + 1))
    if grep -nP '"[a-z][a-z0-9]*\.[a-z][a-z0-9.]*"\s*=' "$f" 2>/dev/null; then
      echo "  ❌ $f: Found quoted nested attributes (use foo.bar not \"foo.bar\")" >&2
      fails=1
    fi
  done < <(
    find "$src" -name '*.nix' \
      ! -name 'browsers.nix' \
      ! -name 'lint.nix' \
      ! -name 'gaming.nix' \
      ! -path '*/hardware-configuration.generated.nix' \
      -print0
  )

  echo ""

  # ==========================================================================
  # CHECK 2: Documentation Headers
  # ==========================================================================
  echo "--- Check 2: Documentation Headers ---"

  while IFS= read -r -d $'\0' f; do
    if ! head -5 "$f" | grep -q '^#'; then
      echo "  ❌ $f: Missing documentation header" >&2
      fails=1
    fi
  done < <(
    find "$src" -name '*.nix' \
      ! -name 'default.nix' \
      ! -path '*/packages/*' \
      ! -path '*/hardware-configuration.generated.nix' \
      -print0
  )

  echo ""

  if [ "$fails" -eq 0 ]; then
    echo "✅ All checks passed!"
    echo "Files checked: $total"
    echo "  - No quoted nested attributes"
    echo "  - All modules have documentation headers"
  else
    echo "❌ Found files with issues"
    echo ""
    echo "Linting failed! See NIX_CODE_STYLE.md and NIX_DOCS_STYLE.md"
    exit 1
  fi

  touch $out
''
