{ ... }:

{
  programs.coolercontrol.enable = true;
  services.printing.enable = false;
  zramSwap = {
    enable = true;
    memoryPercent = 100;
  };
}
