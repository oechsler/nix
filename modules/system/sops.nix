{ config, ... }:

{
  sops = {
    defaultSopsFile = ../../sops/sops.encrypted.yaml;
    age.keyFile = "${config.users.users.${config.user.name}.home}/.config/sops/age/keys.txt";
  };
}
