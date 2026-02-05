{ lib, ... }:

{
  options.input = {
    mouse.naturalScroll = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Natural (reverse) scroll direction for mice";
    };
    touchpad.naturalScroll = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Natural (reverse) scroll direction for touchpads";
    };
  };
}
