# NixOS Configuration Linter
#
# Pure Nix linter that enforces conventions from NIX_CODE_STYLE.md and NIX_DOCS_STYLE.md
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

let
  # Find all Nix files in the repository
  nixFiles = lib.filesystem.listFilesRecursive ./.;

  # Filter to only .nix files, exclude certain paths
  relevantFiles = builtins.filter (path:
    let
      str = toString path;
      isNix = lib.hasSuffix ".nix" str;
      notGenerated = !(lib.hasInfix "hardware-configuration.generated" str);
      notFlakeLock = !(lib.hasInfix "flake.lock" str);
      notResult = !(lib.hasInfix "/result" str);
    in
      isNix && notGenerated && notFlakeLock && notResult
  ) nixFiles;

  # ============================================================================
  # CHECK 1: No Quoted Nested Attributes
  # ============================================================================
  # Convention: NIX_CODE_STYLE.md §2 (Nested Attributes)
  #
  # Detects: "foo.bar" = value;
  # Should be: foo.bar = value;
  #
  # Reason: In Nix, quoted strings create literal attribute names.
  #   "desktop.enable" = false  → { "desktop.enable" = false; }  (single key)
  #   desktop.enable = false    → { desktop = { enable = false; }; }  (nested)
  #
  # Exception: Application settings like Firefox preferences MUST use quoted
  #            strings because they're literal config keys, not Nix attributes:
  #              settings = { "browser.startup.page" = 3; };  ← CORRECT
  #
  checkQuotedAttrs = file: let
    content = builtins.readFile file;
    fileName = baseNameOf (toString file);
    # Skip files with application settings (Firefox, etc.) where quoted keys are required
    # Also skip lint.nix itself (contains example code in comments)
    isAppSettings = builtins.elem fileName [ "browsers.nix" "lint.nix" ];
    # Regex pattern: matches "word.word" = (quoted string with dot followed by equals)
    hasQuotedAttrs = builtins.match ".*\"[a-z][a-z0-9]*\\.[a-z][a-z0-9.]*\"[[:space:]]*=.*" content != null;
  in {
    file = toString file;
    pass = isAppSettings || !hasQuotedAttrs;
    message = if hasQuotedAttrs && !isAppSettings then "Found quoted nested attributes (use foo.bar not \"foo.bar\")" else null;
  };

  # ============================================================================
  # CHECK 2: Documentation Headers
  # ============================================================================
  # Convention: NIX_DOCS_STYLE.md §1 (File Header)
  #
  # Required: All NixOS modules must start with a comment header explaining:
  #   - What the module does
  #   - Configuration options available
  #   - Key features / how it works
  #
  # Example:
  #   # Audio Configuration
  #   #
  #   # This module configures:
  #   # - PipeWire audio server
  #   # - JACK support
  #   # - Low-latency settings
  #   #
  #   # Configuration:
  #   #   features.audio.enable = true;
  #
  # Why: Makes modules self-documenting. Anyone opening the file immediately
  #      understands its purpose and available options.
  #
  # Exceptions:
  #   - default.nix files (they only import other modules)
  #   - packages/*.nix (package definitions use meta.description instead)
  #
  checkDocHeader = file: let
    content = builtins.readFile file;
    fileName = baseNameOf (toString file);
    filePath = toString file;
    # Skip default.nix files (they just import)
    isDefaultNix = fileName == "default.nix";
    # Skip package definitions (they use meta.description)
    isPackage = lib.hasInfix "/packages/" filePath;
    # Check if first 5 lines contain a comment
    lines = lib.splitString "\n" content;
    firstLines = lib.take 5 lines;
    hasComment = builtins.any (line: lib.hasPrefix "#" line) firstLines;
  in {
    file = toString file;
    pass = isDefaultNix || isPackage || hasComment;
    message = if !hasComment && !isDefaultNix && !isPackage then "Missing documentation header" else null;
  };

  # ============================================================================
  # RUN ALL CHECKS
  # ============================================================================
  # For each file, run all check functions and collect results.
  #
  # To add a new check:
  # 1. Create checkFunction above with same signature:
  #      checkNewRule = file: { pass = bool; message = string or null; };
  # 2. Add to checks below: newRule = checkNewRule file;
  # 3. Update failures logic if needed
  #
  results = map (file: {
    inherit file;
    checks = {
      quotedAttrs = checkQuotedAttrs file;
      docHeader = checkDocHeader file;
      # Add new checks here:
      # myNewCheck = checkMyNewRule file;
    };
  }) relevantFiles;

  # Aggregate results
  failures = builtins.filter (r:
    !(r.checks.quotedAttrs.pass && r.checks.docHeader.pass)
  ) results;

  # Generate report
  report = lib.concatStringsSep "\n" (
    [ "=== NixOS Configuration Lint Results ===" "" ]
    ++ (if failures == [] then [
      "✅ All checks passed!"
      ""
      "Files checked: ${toString (builtins.length relevantFiles)}"
      "  - No quoted nested attributes"
      "  - All modules have documentation headers"
    ] else
      [ "❌ Found ${toString (builtins.length failures)} files with issues:" "" ]
      ++ (map (f: let
        quotedFail = !f.checks.quotedAttrs.pass;
        docFail = !f.checks.docHeader.pass;
      in ''
        File: ${f.file}
        ${lib.optionalString quotedFail "  ❌ ${f.checks.quotedAttrs.message}"}
        ${lib.optionalString docFail "  ❌ ${f.checks.docHeader.message}"}
      '') failures)
    )
  );

in
  # ============================================================================
  # DERIVATION: Fail build if any checks fail
  # ============================================================================
  # Creates a derivation that:
  # 1. Prints the linting report (successes and failures)
  # 2. Writes report to $out (for nix build)
  # 3. Exits with code 1 if any checks failed (breaks CI/CD)
  #
  pkgs.runCommand "nixos-config-lint" {
    inherit report;
    failOnIssues = failures != [];
  } ''
    echo "$report"
    echo "$report" > $out

    if [ "$failOnIssues" = "1" ]; then
      echo ""
      echo "Linting failed! See NIX_CODE_STYLE.md and NIX_DOCS_STYLE.md"
      exit 1
    fi
  ''

# ============================================================================
# EXTENDING THE LINTER
# ============================================================================
#
# Example: Add check for consistent section separators
#
# 1. Define the check function (add after checkDocHeader):
#
#   checkSectionSeparators = file: let
#     content = builtins.readFile file;
#     # Look for inconsistent separator lengths
#     hasBadSeps = builtins.match ".*#[-=]{10,25}.*" content != null;
#   in {
#     pass = !hasBadSeps;
#     message = if hasBadSeps then
#       "Inconsistent section separators (use #=== or #--- with 27 chars)"
#     else null;
#   };
#
# 2. Add to checks (in results = map):
#
#   checks = {
#     quotedAttrs = checkQuotedAttrs file;
#     docHeader = checkDocHeader file;
#     sectionSeps = checkSectionSeparators file;  # ← Add here
#   };
#
# 3. Done! The new check will automatically run and report failures.
#
# ============================================================================
# USEFUL NIX PATTERNS FOR CHECKS
# ============================================================================
#
# Pattern matching:
#   builtins.match "regex" content != null  # Returns true if match
#
# String operations:
#   lib.hasPrefix "prefix" string           # Starts with
#   lib.hasSuffix "suffix" string           # Ends with
#   lib.hasInfix "substring" string         # Contains
#   lib.splitString "\n" content            # Split into lines
#
# File filtering:
#   lib.hasInfix "/path/" (toString file)   # Filter by path
#   baseNameOf (toString file) == "name"    # Filter by filename
#
# List operations:
#   builtins.filter (x: condition x) list   # Filter list
#   map (x: transform x) list               # Transform list
#   builtins.any (x: test x) list           # Any true?
#   builtins.all (x: test x) list           # All true?
#
# ============================================================================

