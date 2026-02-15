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
