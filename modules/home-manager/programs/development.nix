{ config, pkgs, user, ... }:

{
  # Kubernetes config from sops
  sops = {
    defaultSopsFile = ../../../sops/sops.encrypted.yaml;
    age.keyFile = "${config.home.homeDirectory}/.config/sops/age/keys.txt";

    secrets."kubernetes/kubeconfig" = {
      path = "${config.home.homeDirectory}/.kube/config";
    };
  };

  home.file.".kube/.keep".text = "";

  programs.git = {
    enable = true;

    signing = {
      key = "~/.ssh/id_ed25519.pub";
      signByDefault = true;
      format = "ssh";
    };

    settings = {
      user.name = user.fullName;
      user.email = user.email;

      init.defaultBranch = "main";
      pull.rebase = true;
      pull.autoStash = true;

      diff.tool = "vimdiff";
      difftool.prompt = false;

      merge.tool = "vimdiff";
      merge.conflictstyle = "diff3";
      mergetool.prompt = false;
    };

    ignores = [
      "*~"
      ".DS_Store"
    ];
  };

  programs.delta = {
    enable = true;
    enableGitIntegration = true;
    options = {
      navigate = true;
      side-by-side = true;
    };
  };

  programs.k9s = {
    enable = true;
    settings.k9s.ui = {
      enableMouse = true;
      logoless = true;
      splashless = true;
      reactive = true;
    };
  };

  # Bitwarden SSH Agent with fallback to standard ssh-agent
  programs.ssh.enable = true;
  programs.ssh.enableDefaultConfig = false;
  services.ssh-agent.enable = true;

  home.sessionVariablesExtra = ''
    if [ -S "$HOME/.bitwarden-ssh-agent.sock" ]; then
      export SSH_AUTH_SOCK="$HOME/.bitwarden-ssh-agent.sock"
    fi
  '';

  home.packages = with pkgs; [
    kubectl
    kubernetes-helm
    kubectx
    cloc
    distrobox
    dbeaver-bin
    jetbrains-toolbox

    go
    rustup
    jdk
    nodejs
  ];

  programs.vscode = {
    enable = true;
    package = pkgs.vscode;
  };

  programs.vim = {
    enable = true;
    defaultEditor = true;
    plugins = with pkgs.vimPlugins; [
      vim-airline
      vim-airline-themes
      catppuccin-vim
    ];
    settings = {
      number = true;
      relativenumber = true;
    };
    extraConfig = let
      flavor = config.catppuccin.flavor;
    in ''
      set shortmess+=I
      set termguicolors
      set laststatus=2
      set noshowmode
      let g:airline_powerline_fonts = 1
      let g:airline_theme = 'catppuccin_${flavor}'
      colorscheme catppuccin_${flavor}
    '';
  };
}
