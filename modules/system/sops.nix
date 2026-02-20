# SOPS Secrets Management
#
# This module configures sops-nix for encrypted secrets management.
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

{ config, ... }:

{
  sops = {
    defaultSopsFile = ../../sops/sops.encrypted.yaml;
    age.keyFile = "/var/lib/sops/age/keys.txt";

    # Use systemd service instead of activation scripts
    # This creates sops-install-secrets.service that runs at boot
    useSystemdActivation = true;
  };
}
