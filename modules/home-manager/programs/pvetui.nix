# pvetui - Proxmox VE Terminal UI
#
# Terminal UI for managing Proxmox VE clusters.
# Pre-configured with Proxmox servers and API token authentication.
#
# Configuration:
#   features.ops.pvetui.profiles = [
#     { name = "server-1"; addr = "https://proxmox-1.lan:8006"; }
#   ];
#   features.ops.pvetui.defaultProfile = "server-1";
#
# SOPS secrets (only token secrets needed):
#   pvetui/<name>/token-secret

{
  config,
  lib,
  features,
  pkgs,
  ...
}:

let
  cfg = features.ops.pvetui;

  # Generate profiles section for pvetui config (with placeholders for secrets)
  profilesSection = lib.concatStringsSep "\n" (
    map (profile: ''
  ${profile.name}:
    addr: "${profile.addr}"
    user: "${profile.user}"
    realm: "${profile.realm}"
    token_id: "${profile.tokenId}"
    token_secret: "__TOKEN_SECRET_${lib.toUpper (lib.replaceStrings [ "-" ] [ "_" ] profile.name)}__"
    insecure: ${lib.boolToString profile.insecure}
    ssh_user: "${profile.sshUser}"
    vm_ssh_user: "${profile.vmSshUser}"
    ssh_keyfile: "${profile.sshKeyfile}"
'') cfg.profiles
  );

  # Generate sops secrets for each profile
  pvetuiSecrets = lib.listToAttrs (
    map (profile: {
      name = "pvetui/${profile.name}/token-secret";
      value = { };
    }) cfg.profiles
  );

  # Base config file (without secrets, stored in nix-store)
  pvetuiBaseConfig = pkgs.writeText "pvetui-config-base.yml" ''
profiles:
${profilesSection}

default_profile: "${cfg.defaultProfile}"
debug: false
show_icons: true
mouse: true

key_bindings:
  view_nodes: "ctrl+1"
  view_guests: "ctrl+2"
  view_tasks: "ctrl+3"
  view_storage: "ctrl+4"
  '';

  # Wrapper script that generates config with secrets at runtime
  pvetuiWithSecrets = pkgs.writeShellScriptBin "pvetui" ''
    CONFIG_DIR="$HOME/.config/pvetui"
    CONFIG_FILE="$CONFIG_DIR/config.yml"
    mkdir -p "$CONFIG_DIR"

    # Generate config with secrets substituted
    ${pkgs.gnused}/bin/sed \
      ${lib.concatMapStringsSep " " (profile:
        let
          secretPath = config.sops.secrets."pvetui/${profile.name}/token-secret".path;
          placeholder = "__TOKEN_SECRET_${lib.toUpper (lib.replaceStrings [ "-" ] [ "_" ] profile.name)}__";
        in
        "-e 's|${placeholder}|$(< ${secretPath})|g'"
      ) cfg.profiles} \
      ${pvetuiBaseConfig} > "$CONFIG_FILE"

    exec ${pkgs.pvetui}/bin/pvetui "$@"
  '';
in
{
  config = lib.mkIf (features.ops.enable && cfg.enable && cfg.profiles != [ ]) {
    home.packages = [ pvetuiWithSecrets ];

    sops.secrets = pvetuiSecrets;
  };
}
