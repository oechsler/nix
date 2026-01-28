{
  description = "Samuel's NixOS configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, sops-nix, ... }@inputs: 
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      nixosConfigurations = {
        samuels-pc = nixpkgs.lib.nixosSystem {
	        inherit system;

          specialArgs = { inherit inputs; };

          modules = [
            ./hosts/samuels-pc/configuration.nix
            home-manager.nixosModules.default
            sops-nix.nixosModules.sops
          ];
        };
        
        default = self.nixosConfigurations.samuels-pc;
      };
    };
}
