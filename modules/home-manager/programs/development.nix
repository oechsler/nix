{ config, pkgs, features, lib, ... }:

lib.mkIf features.development.enable {
  # Kubernetes config from sops
  sops = {
    defaultSopsFile = ../../../sops/sops.encrypted.yaml;
    age.keyFile = "${config.home.homeDirectory}/.config/sops/age/keys.txt";

    secrets."kubernetes/kubeconfig" = {
      path = "${config.home.homeDirectory}/.kube/config";
      mode = "0600";  # kubectl/kubectx need read+write permissions
    };
  };

  home.file.".kube/.keep".text = "";

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
    cloc
    distrobox
    dbeaver-bin
    jetbrains-toolbox
    claude-code

    go
    rustup
    jdk
    nodejs
  ];

  programs.vscode = {
    enable = true;
    package = pkgs.vscode;

    profiles.default = {
      userSettings = {
        "workbench.startupEditor" = "none";
      };

      extensions = with pkgs.vscode-extensions; [
        jnoortheen.nix-ide
        vscodevim.vim
      ];
    };
  };
}
