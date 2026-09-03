# Infrastructure and operations feature options.

{ config, lib, ... }:

{
  options.features.ops = {
    enable = (lib.mkEnableOption "operations tools") // {
      default = true;
    };
    pvetui = {
      enable = (lib.mkEnableOption "pvetui (Proxmox VE Terminal UI)") // {
        default = config.features.ops.enable;
      };
      profiles = lib.mkOption {
        type = lib.types.listOf (
          lib.types.submodule {
            options = {
              name = lib.mkOption {
                type = lib.types.str;
                description = "Profile name (used as identifier and sops secret path)";
              };
              addr = lib.mkOption {
                type = lib.types.str;
                description = "Proxmox API URL (e.g., https://proxmox:8006)";
              };
              user = lib.mkOption {
                type = lib.types.str;
                default = config.user.name;
                description = "Proxmox username";
              };
              realm = lib.mkOption {
                type = lib.types.str;
                default = "sso";
                description = "Authentication realm";
              };
              tokenId = lib.mkOption {
                type = lib.types.str;
                default = "pvetui";
                description = "API token ID";
              };
              insecure = lib.mkOption {
                type = lib.types.bool;
                default = false;
                description = "Skip TLS verification";
              };
              sshUser = lib.mkOption {
                type = lib.types.str;
                default = config.user.name;
                description = "SSH username for node access";
              };
              vmSshUser = lib.mkOption {
                type = lib.types.str;
                default = config.user.name;
                description = "SSH username for VM access";
              };
              sshKeyfile = lib.mkOption {
                type = lib.types.str;
                default = "~/.ssh/id_ed25519";
                description = "SSH private key path";
              };
              sshAddr = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = null;
                description = "SSH hostname (if different from API addr hostname)";
              };
              groups = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [ ];
                description = "List of groups this profile belongs to (for Group Mode)";
              };
            };
          }
        );
        default = [ ];
        description = "List of Proxmox server profiles for pvetui";
      };
      defaultProfile = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Default profile or group name (can be a profile name or a group name)";
      };
      groups = lib.mkOption {
        type = lib.types.attrsOf (
          lib.types.submodule {
            options.mode = lib.mkOption {
              type = lib.types.enum [
                "aggregate"
                "cluster"
              ];
              default = "aggregate";
              description = "Group mode: 'aggregate' combines resources, 'cluster' is active/passive failover";
            };
          }
        );
        default = { };
        description = "Settings for each group (mode: aggregate or cluster)";
      };
    };
    kubernetes = {
      enable = (lib.mkEnableOption "Kubernetes tools and k9s") // {
        default = config.features.ops.enable;
      };
      clusters = lib.mkOption {
        type = lib.types.listOf (
          lib.types.submodule {
            options = {
              name = lib.mkOption {
                type = lib.types.str;
                description = "Cluster name (used as context name)";
              };
              server = lib.mkOption {
                type = lib.types.str;
                description = "Kubernetes API server URL (e.g., https://k3s.example.com:6443)";
              };
              caData = lib.mkOption {
                type = lib.types.str;
                description = "Base64-encoded CA certificate for the cluster";
              };
              namespace = lib.mkOption {
                type = lib.types.str;
                default = "default";
                description = "Default namespace for this context";
              };
              user = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = "oidc";
                description = "User name for this context (null for no user entry)";
              };
              oidc = {
                issuerUrl = lib.mkOption {
                  type = lib.types.str;
                  description = "OIDC issuer URL";
                };
                clientId = lib.mkOption {
                  type = lib.types.str;
                  description = "OIDC client ID";
                };
                extraScopes = lib.mkOption {
                  type = lib.types.listOf lib.types.str;
                  default = [
                    "email"
                    "groups"
                  ];
                  description = "Additional OIDC scopes to request";
                };
              };
            };
          }
        );
        default = [ ];
        description = "List of Kubernetes clusters with OIDC authentication";
      };
      defaultContext = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Default Kubernetes context (empty = first cluster)";
      };
    };
  };
}
