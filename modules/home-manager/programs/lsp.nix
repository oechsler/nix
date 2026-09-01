# Shared Language Tooling
#
# Installs language servers and formatters system-wide so OpenCode, Neovim, and
# other clients can start them directly. These tools are only needed when
# development tools are enabled.
#
# Matching opencode built-ins (https://opencode.ai/docs/lsp/):
#   nixd                   -> .nix (Nix)
#   bash-language-server   -> .sh, .bash, .zsh (bash)
#   yaml-language-server   -> .yaml, .yml (yaml-ls)
#   pyright                -> .py (pyright)
#   gopls                  -> .go (gopls)
#   rust-analyzer          -> .rs (provided by the Nix Rust toolchain)
#   typescript-language-server -> .ts, .js (typescript)
#   jdt-language-server    -> .java (jdtls)
#   marksman               -> .md (markdown)
#   vscode-json-language-server -> .json, .jsonc (jsonls)
#   taplo                  -> .toml (taplo)

{
  pkgs,
  features,
  lib,
  ...
}:

{
  config = lib.mkIf features.dev.enable {
    home.packages = with pkgs; [
      # Nix
      nixd
      nil

      # Shell & Config
      bash-language-server
      yaml-language-server
      marksman
      vscode-json-languageserver
      taplo

      # Python
      pyright

      # Go
      gopls

      # Rust
      rust-analyzer

      # TypeScript / JavaScript
      typescript-language-server

      # Java
      jdt-language-server

      # Formatters
      nixfmt
      prettierd
      gofumpt
      google-java-format
    ];
  };
}
