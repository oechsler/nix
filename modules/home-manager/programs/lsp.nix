# Language Server Protocols (LSP) for OpenCode
#
# Installs LSP servers system-wide so opencode (and other LSP clients)
# can start them directly. Servers are only needed when development tools
# are enabled.
#
# Matching opencode built-ins (https://opencode.ai/docs/lsp/):
#   nixd                   -> .nix (Nix)
#   bash-language-server   -> .sh, .bash, .zsh (bash)
#   yaml-language-server   -> .yaml, .yml (yaml-ls)
#   pyright                -> .py (pyright)
#   gopls                  -> .go (gopls)
#   rust-analyzer          -> .rs (provided by rustup)
#   typescript-language-server -> .ts, .js (typescript)
#   jdt-language-server    -> .java (jdtls)

{
  pkgs,
  features,
  lib,
  ...
}:

{
  config = lib.mkIf features.development.enable {
    home.packages = with pkgs; [
      # Nix
      nixd

      # Shell & Config
      bash-language-server
      yaml-language-server

      # Python
      pyright

      # Go
      gopls

      # TypeScript / JavaScript
      typescript-language-server

      # Java
      jdt-language-server
    ];
  };
}
