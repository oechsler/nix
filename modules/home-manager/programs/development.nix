{ config, pkgs, user, features, lib, ... }:

lib.mkMerge [
  # Always active: Git, Delta, SSH, Vim
  {
    programs.git = {
      enable = true;

      signing = {
        key = "${config.home.homeDirectory}/.ssh/id_ed25519.pub";
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

        # Git Credential Manager
        credential.helper = "${pkgs.git-credential-manager}/bin/git-credential-manager";
        credential.credentialStore = "secretservice";

        # GitHub OAuth support
        "credential.https://github.com".provider = "github";
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

    # Bitwarden SSH Agent
    programs.ssh = {
      enable = true;
      enableDefaultConfig = false;
      matchBlocks."*" = {
        identityFile = "${config.home.homeDirectory}/.ssh/id_ed25519";
        extraOptions = {
          IdentityAgent = "${config.home.homeDirectory}/.bitwarden-ssh-agent.sock";
        };
      };
    };

    # Set SSH_AUTH_SOCK to Bitwarden SSH Agent
    home.sessionVariables = {
      SSH_AUTH_SOCK = "${config.home.homeDirectory}/.bitwarden-ssh-agent.sock";
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

  # Toggleable: IDEs, languages, K8s tools
  (lib.mkIf features.development.enable {
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
  })
]
