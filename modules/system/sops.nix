# SOPS Secrets Management
#
# This module configures sops-nix for encrypted secrets management.
#
# Configuration:
#   sops.secretsFile = ./path/to/sops.encrypted.yaml;  # Override SOPS file path
#
# Setup:
# - Secrets file: sops/sops.encrypted.yaml (encrypted with age)
# - Decryption key: /var/lib/sops/age/keys.txt (machine-specific)
# - Systemd service: sops-install-secrets.service (runs at boot)
#
# How it works:
# 1. age key stored in /var/lib/sops/age/keys.txt
# 2. Secrets encrypted in sops/sops.encrypted.yaml
# 3. At boot, systemd service decrypts and installs secrets
# 4. Secrets available to services via config.sops.secrets.*
#
# See: sops/README.md for secret management workflow

{ config, lib, ... }:

{
  options.sops.secretsFile = lib.mkOption {
    type = lib.types.path;
    default = ../../sops/sops.encrypted.yaml;
    description = "Path to encrypted SOPS secrets file (override for external repos)";
  };

  config.sops = {
    defaultSopsFile = config.sops.secretsFile;
    age.keyFile = "/var/lib/sops/age/keys.txt";

    # Use systemd service instead of activation scripts
    # This creates sops-install-secrets.service that runs at boot
    useSystemdActivation = true;
  };
}
