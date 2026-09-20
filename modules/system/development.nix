# System-wide development runtime defaults.

{
  config,
  pkgs,
  lib,
  ...
}:

{
  config =
    let
      selectedLanguages =
        if config.features.dev.languages == [ ] then
          (import ../lib/development.nix).languageNames
        else
          config.features.dev.languages;
      languageEnabled = name: builtins.elem name selectedLanguages;
    in
    lib.mkIf config.features.dev.enable {
      # Runtimes, SDKs, compilers, and language tooling are system-wide on
      # development hosts. Each language can be disabled independently.
      environment.systemPackages =
        with pkgs;
        [
          cloc
          ansible
          opentofu
        ]
        ++ lib.optionals (languageEnabled "c") [
          clang
          lld
          clang-tools
        ]
        ++ lib.optionals (languageEnabled "cmake") [
          cmake-language-server
          cmake-format
        ]
        ++ lib.optionals (languageEnabled "css" || languageEnabled "html" || languageEnabled "scss") [
          vscode-langservers-extracted
          prettierd
        ]
        ++ lib.optionals (languageEnabled "docker") [
          dockerfile-language-server
          hadolint
        ]
        ++ lib.optionals (languageEnabled "go") [
          go
          gopls
          gofumpt
          golangci-lint
        ]
        ++ lib.optionals (languageEnabled "java") [
          jdk25
          gradle
          jdt-language-server
          google-java-format
        ]
        ++ lib.optionals (languageEnabled "kotlin") [
          kotlin
          kotlin-language-server
          detekt
          ktlint
        ]
        ++ lib.optionals (languageEnabled "javascript" || languageEnabled "typescript") [
          bun
          prettierd
        ]
        ++ lib.optionals (languageEnabled "javascript" || languageEnabled "typescript") [ eslint_d ]
        ++ lib.optionals (languageEnabled "typescript") [ typescript-language-server ]
        ++ lib.optionals (languageEnabled "json") [
          vscode-json-languageserver
          prettierd
        ]
        ++ lib.optionals (languageEnabled "markdown") [
          marksman
          prettierd
          markdownlint-cli2
        ]
        ++ lib.optionals (languageEnabled "nix") [
          nil
          nixd
          nixfmt
        ]
        ++ lib.optionals (languageEnabled "python") [
          pyright
          ruff
        ]
        ++ lib.optionals (languageEnabled "rust") [
          rustc
          cargo
          clippy
          rustfmt
          rust-analyzer
          rustPlatform.rustcSrc
        ]
        ++ lib.optionals (languageEnabled "shell") [
          bash-language-server
          fish-lsp
          shfmt
          shellcheck
        ]
        ++ lib.optionals (languageEnabled "lua") [
          lua-language-server
          stylua
        ]
        ++ lib.optionals (languageEnabled "toml") [ taplo ]
        ++ lib.optionals (languageEnabled "sql") [
          sqls
          sql-formatter
        ]
        ++ lib.optionals (languageEnabled "terraform") [
          terraform-ls
          tflint
        ]
        ++ lib.optionals (languageEnabled "yaml") [
          yaml-language-server
          prettierd
          yamllint
        ]
        ++ lib.optionals config.features.virtualisation.container.enable [ distrobox ];
    };
}
