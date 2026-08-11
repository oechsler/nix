# Kubernetes Configuration
#
# Manages kubeconfig and k9s configuration for multiple Kubernetes clusters.
# Supports OIDC authentication via kubectl oidc-login plugin.
#
# Configuration:
#   features.ops.kubernetes.clusters = [
#     {
#       name = "k3s.oechsler.it";
#       server = "https://k3s.oechsler.it:6443";
#       caData = "LS0tLS1CRUdJTi...";
#       oidc = {
#         issuerUrl = "https://id.at.oechsler.it";
#         clientId = "f18b9f65-0a3c-4fea-ace3-73954937bcd1";
#       };
#     }
#   ];
#   features.ops.kubernetes.defaultContext = "k3s.oechsler.it";

{
  config,
  lib,
  features,
  pkgs,
  ...
}:

let
  cfg = features.ops.kubernetes;

  # Generate cluster entries for kubeconfig
  clusterEntries = lib.concatMapStringsSep "\n" (cluster: ''
- cluster:
    certificate-authority-data: ${cluster.caData}
    server: ${cluster.server}
  name: ${cluster.name}
  '') cfg.clusters;

  # Generate context entries for kubeconfig
  contextEntries = lib.concatMapStringsSep "\n" (cluster: ''
- context:
    cluster: ${cluster.name}
    namespace: ${cluster.namespace}
    user: ${cluster.user}
  name: ${cluster.name}
  '') cfg.clusters;

  # Generate user entries for kubeconfig (OIDC)
  userEntries = lib.concatMapStringsSep "\n" (cluster: ''
- name: ${cluster.user}
  user:
    exec:
      apiVersion: client.authentication.k8s.io/v1beta1
      args:
      - oidc-login
      - get-token
      - --oidc-issuer-url=${cluster.oidc.issuerUrl}
      - --oidc-client-id=${cluster.oidc.clientId}
      ${lib.concatMapStringsSep "\n" (scope: "- --oidc-extra-scope=${scope}") cluster.oidc.extraScopes}
      command: kubectl
      env: null
      interactiveMode: IfAvailable
      provideClusterInfo: false
  '') (lib.filter (c: c.user != null) cfg.clusters);

  # Generate complete kubeconfig
  kubeconfig = pkgs.writeText "kubeconfig" ''
    apiVersion: v1
    clusters:
    ${clusterEntries}
    contexts:
    ${contextEntries}
    current-context: ${cfg.defaultContext}
    kind: Config
    users:
    ${userEntries}
  '';
in
{
  config = lib.mkIf (features.ops.enable && cfg.enable && cfg.clusters != [ ]) {
    catppuccin.k9s.transparent = true;

    programs.k9s = {
      enable = true;
      settings.k9s.ui = {
        enableMouse = true;
        logoless = true;
        splashless = true;
        reactive = true;
      };
    };

    home.packages = with pkgs; [
      kubectl
      kubernetes-helm
      kubectx
      kubeseal
      kubelogin-oidc
    ];

    # Link kubeconfig to ~/.kube/config
    home.file.".kube/config".source = kubeconfig;
  };
}
