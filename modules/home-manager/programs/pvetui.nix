# pvetui - Proxmox VE Terminal UI
#
# Terminal UI for managing Proxmox VE clusters.
# Pre-configured with Proxmox servers and API token authentication.
# Supports Group Mode for multi-cluster views.
#
# Configuration:
#   features.ops.pvetui.profiles = [
#     { name = "server-1"; addr = "https://proxmox-1.lan:8006"; groups = ["all-servers"]; }
#     { name = "server-2"; addr = "https://proxmox-2.lan:8006"; groups = ["all-servers"]; }
#   ];
#   features.ops.pvetui.defaultProfile = "all-servers";
#   features.ops.pvetui.groups = {
#     "all-servers" = { mode = "aggregate"; };
#   };
#
# SOPS secrets (only token secrets needed):
#   pvetui/<name>/token-secret

{
  config,
  lib,
  features,
  pkgs,
  theme,
  ...
}:

let
  cfg = features.ops.pvetui;

  # pvetui currently does not expose mouse activation in its YAML config.
  # Enable it in tview while keeping the rest of the package from nixpkgs.
  pvetui = pkgs.pvetui.overrideAttrs (old: {
    postPatch = (old.postPatch or "") + ''
      substituteInPlace internal/ui/components/app.go \
        --replace-fail 'Application:        tview.NewApplication(),' \
        'Application:        tview.NewApplication().EnableMouse(true),'

      # Reuse pvetui's parser for compound Proxmox agent settings such as
      # "enabled=1,fstrim_cloned_disks=0,type=virtio".
      substituteInPlace pkg/api/vm.go \
        --replace-fail \
          'vm.AgentEnabled = v == "1" || v == StringTrue' \
          'vm.AgentEnabled = parseQEMUAgentEnabled(v)'
    '';
  });

  # Catppuccin palette loaded from source (same as desktop/common/theme.nix)
  palette =
    (lib.importJSON "${config.catppuccin.sources.palette}/palette.json")
    .${theme.catppuccin.flavor}.colors;

  # Extract hostname from URL (removes protocol and port)
  extractHost =
    url:
    let
      withoutProtocol = lib.removePrefix "https://" (lib.removePrefix "http://" url);
      withoutPath = lib.head (lib.splitString "/" withoutProtocol);
      withoutPort = lib.head (lib.splitString ":" withoutPath);
    in
    withoutPort;

  # Generate sops secrets for each profile
  pvetuiSecrets = lib.listToAttrs (
    map (profile: {
      name = "pvetui/${profile.name}/token-secret";
      value = { };
    }) cfg.profiles
  );

  # Generate groups section for a profile
  profileGroups =
    profile:
    if profile.groups != [ ] then
      ''
            groups:
        ${lib.concatMapStringsSep "\n" (g: "      - ${g}") profile.groups}''
    else
      "";

  # Generate group_settings section
  groupsSection =
    if cfg.groups != { } then
      ''
        group_settings:
        ${lib.concatStringsSep "\n" (
          lib.mapAttrsToList (name: settings: ''
            ${name}:
              mode: ${settings.mode}'') cfg.groups
        )}''
    else
      "";

  # Wrapper script that generates config with secrets at runtime
  pvetuiWithSecrets = pkgs.writeShellScriptBin "pvetui" ''
        CONFIG_DIR="$HOME/.config/pvetui"
        CONFIG_FILE="$CONFIG_DIR/config.yml"
        mkdir -p "$CONFIG_DIR"

        # Generate config with secrets
        cat > "$CONFIG_FILE" << EOF
    profiles:
    ${lib.concatMapStringsSep "\n" (
      profile:
      let
        secretPath = config.sops.secrets."pvetui/${profile.name}/token-secret".path;
      in
      ''
          ${profile.name}:
            addr: "${profile.addr}"
            user: "${profile.user}"
            realm: "${profile.realm}"
            token_id: "${profile.tokenId}"
            token_secret: "$(cat ${secretPath})"
            insecure: ${lib.boolToString profile.insecure}
            ssh_user: "${profile.sshUser}"
            vm_ssh_user: "${profile.vmSshUser}"
            ssh_keyfile: "${profile.sshKeyfile}"
            ssh_addr: "${if profile.sshAddr != null then profile.sshAddr else extractHost profile.addr}"
        ${profileGroups profile}''
    ) cfg.profiles}

    default_profile: "${cfg.defaultProfile}"
    ${groupsSection}
    debug: false
    show_icons: true

    theme:
      colors:
        primary: "${palette.text.hex}"
        secondary: "${palette.subtext1.hex}"
        tertiary: "${palette.subtext0.hex}"
        success: "${palette.green.hex}"
        warning: "${palette.yellow.hex}"
        error: "${palette.red.hex}"
        info: "${palette.blue.hex}"
        background: "${palette.base.hex}"
        border: "${palette.surface1.hex}"
        selection: "${palette.surface2.hex}"
        header: "${palette.surface0.hex}"
        headertext: "${palette.text.hex}"
        footer: "${palette.surface0.hex}"
        footertext: "${palette.text.hex}"
        title: "${palette.mauve.hex}"
        contrast: "${palette.surface0.hex}"
        morecontrast: "${palette.mantle.hex}"
        inverse: "${palette.base.hex}"
        statusrunning: "${palette.green.hex}"
        statusstopped: "${palette.red.hex}"
        statuspending: "${palette.yellow.hex}"
        statuserror: "${palette.red.hex}"
        usagelow: "${palette.green.hex}"
        usagemedium: "${palette.yellow.hex}"
        usagehigh: "${palette.peach.hex}"
        usagecritical: "${palette.red.hex}"

    key_bindings:
      nodes_page: "F1"
      guests_page: "F2"
      tasks_page: "F3"
      storage_page: "F4"
    EOF

        exec ${pvetui}/bin/pvetui "$@"
  '';
in
{
  config = lib.mkIf (features.ops.enable && cfg.enable && cfg.profiles != [ ]) {
    home.packages = [ pvetuiWithSecrets ];

    sops.secrets = pvetuiSecrets;
  };
}
