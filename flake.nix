{
  description = "Samuel's NixOS configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    catppuccin.url = "github:catppuccin/nix";

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    awww.url = "git+https://codeberg.org/LGFae/awww";

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    firefox-addons = {
      url = "gitlab:rycee/nur-expressions?dir=pkgs/firefox-addons";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    cachyos-kernel = {
      url = "github:xddxdd/nix-cachyos-kernel";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    lanzaboote = {
      url = "github:nix-community/lanzaboote/v0.4.2";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    plasma-manager = {
      url = "github:nix-community/plasma-manager";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };

    nix-flatpak.url = "github:gmodena/nix-flatpak";
  };

  outputs = { self, nixpkgs, home-manager, catppuccin, disko, sops-nix, cachyos-kernel, lanzaboote, ... }@inputs:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};

      mkHost = hostName: extraModules: nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit inputs; };
        modules = [
          ./hosts/${hostName}/configuration.nix
          home-manager.nixosModules.default
          sops-nix.nixosModules.sops
          inputs.nix-flatpak.nixosModules.nix-flatpak
          {
            nixpkgs.overlays = [ cachyos-kernel.overlays.pinned ];
          }
        ] ++ extraModules;
      };
    in
    {
      diskoConfigurations = {
        samuels-pc = import ./hosts/samuels-pc/disko.nix;
        samuels-razer = import ./hosts/samuels-razer/disko.nix;
      };

      nixosConfigurations = {
        samuels-razer = mkHost "samuels-razer" [
          disko.nixosModules.disko
        ];

        samuels-pc = mkHost "samuels-pc" [
          disko.nixosModules.disko
        ];

        default = self.nixosConfigurations.samuels-razer;
      };
    };
}
