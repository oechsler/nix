# Shared Language Tooling
#
# Installs language servers and formatters system-wide so OpenCode, Neovim, and
# other clients can start them directly. These tools are only needed when
# development tools are enabled.
#
# The same tools are consumed by Neovim and OpenCode. Keep this list aligned
# with the language-specific configuration in those clients.

{
  pkgs,
  features,
  lib,
  ...
}:

{
  config = lib.mkIf features.dev.enable {
    home.packages = with pkgs; [
      # C/C++
      clang-tools

      # Go
      gofumpt
      gopls

      # Java
      google-java-format
      jdt-language-server

      # JavaScript/TypeScript
      prettierd
      typescript-language-server

      # JSON
      vscode-json-languageserver

      # Kotlin
      detekt
      kotlin-language-server
      ktlint

      # Markdown
      marksman

      # Nix
      nil
      nixd
      nixfmt

      # Python
      pyright
      ruff

      # Rust
      rust-analyzer

      # Shell
      bash-language-server
      fish-lsp
      shfmt

      # TOML
      taplo

      # YAML
      yaml-language-server
    ];
  };
}
