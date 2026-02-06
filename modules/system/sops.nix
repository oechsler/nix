{ config, ... }:

{
  sops = {
    defaultSopsFile = ../../sops/sops.encrypted.yaml;
    age.keyFile = "/var/lib/sops/age/keys.txt";
  };
}
