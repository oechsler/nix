# Feature option module entry point.

{ ... }:

{
  imports = [
    ./features/apps.nix
    ./features/desktop.nix
    ./features/development.nix
    ./features/hardware.nix
    ./features/llm.nix
    ./features/operations.nix
    ./features/security.nix
    ./features/validation.nix
    ./features/virtualisation.nix
  ];
}
