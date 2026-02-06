{ config, inputs, ... }:

{
  home-manager = {
    extraSpecialArgs = {
      inherit inputs;
      fonts = config.fonts.defaults;
      theme = config.theme;
      locale = config.locale;
      user = config.user;
      features = config.features;
      displays = config.displays;
      input = config.input;
    };
    users.${config.user.name} = {
      imports = [
        ../../hosts/${config.networking.hostName}/home.nix
        inputs.catppuccin.homeModules.catppuccin
        inputs.sops-nix.homeManagerModules.sops
        inputs.plasma-manager.homeModules.plasma-manager
      ];
    };
    backupFileExtension = "bak";
  };
}
