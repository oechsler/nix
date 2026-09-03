# NixOS Configuration Checks
#
# Central definitions for every repository lint, formatter, and quality check.
#
# Checks exported by this module:
#   - lint: Repository-specific Nix and Markdown conventions
#   - statix: Nix anti-patterns and best practices
#   - deadnix: Dead Nix bindings
#   - shellcheck: Shell correctness and safety
#   - shfmt: Installer shell formatting
#   - format: Nix formatting
#   - markdownlint / markdown-format: Markdown quality and formatting
#   - rust: Rust formatting and Clippy
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
# 1. NO UNINTENTIONAL QUOTED NESTED ATTRIBUTES (NIX_CODE_STYLE.md §Configuration)
#    ❌ WRONG:  "desktop.enable" = false;
#    ✅ CORRECT: desktop.enable = false;
#
#    Why: Quoted strings create a literal key "desktop.enable" instead of
#         a nested attribute structure { desktop = { enable = false; }; }
#
#    Exception: Application settings (Firefox, etc.) where quoted keys are
#               required: settings = { "browser.startup.page" = 3; };
#
# 2. DOCUMENTATION HEADERS (NIX_CODE_STYLE.md §Comments)
#    ✅ Evaluated modules must have a short purpose comment in the first five lines.
#       The check verifies header presence; review verifies its quality.
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
# 3. MARKDOWN SHAPE (NIX_DOCS_STYLE.md §Markdown)
#    ✅ Markdown documents must have an H1 title, no empty headings, and balanced
#       fenced code blocks. Content quality remains a review concern.
#
# 4. FUTURE CHECKS (can be added):
#    - Module structure (config = lib.mkIf ...)
#    - Section separators (#=== vs #---)
#    - Shell script documentation (Why/Problem/Solution/How)
#
# Full conventions: NIX_CODE_STYLE.md, NIX_DOCS_STYLE.md
# ============================================================================

{ pkgs, ... }:

let
  source = ./.;

  lint = pkgs.runCommand "nixos-config-lint" { } ''
    export LC_ALL=C.UTF-8

    src="${source}"

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

    # ==========================================================================
    # CHECK 3: Markdown Shape
    # ==========================================================================
    echo "--- Check 3: Markdown Shape ---"

    while IFS= read -r -d $'\0' f; do
      total=$((total + 1))
      if ! head -20 "$f" | grep -q '^# [^#]'; then
        echo "  ❌ $f: Missing H1 title" >&2
        fails=1
      fi

      if grep -n '^#$' "$f" 2>/dev/null; then
        echo "  ❌ $f: Found empty Markdown heading" >&2
        fails=1
      fi

      fences=$(grep -c '^```' "$f" 2>/dev/null || true)
      if [ $((fences % 2)) -ne 0 ]; then
        echo "  ❌ $f: Unbalanced fenced code blocks" >&2
        fails=1
      fi
    done < <(find "$src" -name '*.md' -print0)

    echo ""

    if [ "$fails" -eq 0 ]; then
      echo "✅ All checks passed!"
      echo "Files checked: $total"
      echo "  - No unintentional quoted nested attributes"
      echo "  - All modules have documentation headers"
      echo "  - Markdown has valid document shape"
    else
      echo "❌ Found files with issues"
      echo ""
      echo "Linting failed! See NIX_CODE_STYLE.md and NIX_DOCS_STYLE.md"
      exit 1
    fi

    touch $out
  '';

  statix = pkgs.runCommand "statix-check" { } ''
    cp -r ${source} ./source
    chmod -R +w ./source
    rm -f ./source/hosts/*/hardware-configuration.generated.nix
    ${pkgs.statix}/bin/statix check ./source --format=stderr
    touch $out
  '';

  deadnix = pkgs.runCommand "deadnix-check" { } ''
    ${pkgs.deadnix}/bin/deadnix ${source}
    touch $out
  '';

  shellcheck = pkgs.runCommand "shellcheck-check" { } ''
    find ${source} -type f -name '*.sh' -print0 \
      | xargs --null --no-run-if-empty ${pkgs.shellcheck}/bin/shellcheck -x
    touch $out
  '';

  shfmt = pkgs.runCommand "shfmt-check" { } ''
    find ${source} \( -path '*/installer/*.sh' -o -name 'install.sh' \) -print0 \
      | xargs --null --no-run-if-empty ${pkgs.shfmt}/bin/shfmt -i 2 -ci -d
    touch $out
  '';

  format = pkgs.runCommand "nixfmt-check" { } ''
    find ${source} -name '*.nix' ! -name 'hardware-configuration.generated.nix' -print0 \
      | xargs --null --no-run-if-empty ${pkgs.nixfmt}/bin/nixfmt --check
    touch $out
  '';

  markdownlint = pkgs.runCommand "markdownlint-check" { } ''
    cp -r ${source} ./source
    cd ./source
    ${pkgs.markdownlint-cli2}/bin/markdownlint-cli2 '**/*.md'
    touch $out
  '';

  markdown-format = pkgs.runCommand "markdown-format-check" { } ''
    ${pkgs.prettier}/bin/prettier --check '${source}/**/*.md'
    touch $out
  '';

  rust = pkgs.rustPlatform.buildRustPackage {
    pname = "pam-lldap-check";
    version = "0.1.0";
    src = ./modules/packages/pam-lldap;
    cargoHash = "sha256-+Du65HEaZSKbafS21q/TVPJGS28jd0FENP3+PsSF7F4=";
    nativeBuildInputs = [
      pkgs.clippy
      pkgs.rustfmt
    ];
    dontBuild = true;
    checkPhase = ''
      cargo fmt --check
      cargo clippy --offline --all-targets -- -D warnings
    '';
    installPhase = "touch $out";
  };
in
{
  inherit
    lint
    statix
    deadnix
    shellcheck
    shfmt
    format
    markdownlint
    markdown-format
    rust
    ;
}
