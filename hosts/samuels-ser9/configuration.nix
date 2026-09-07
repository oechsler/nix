# samuels-ser9 Host Configuration
#
# Beelink SER9 Mini PC headless server configuration.
#
# Hardware:
# - AMD Ryzen AI 9 HX 370 (Zen 5/Zen 5c, 12C/24T, up to 5.1GHz)
# - Integrated Radeon 890M graphics
# - 32GB LPDDR5X
# - 1TB PCIe 4.0 NVMe SSD
# - 2.5G LAN, WiFi 6, Bluetooth 5.2
#
# Purpose:
# - Headless llama.cpp Vulkan server with AMD GPU acceleration
# - Remote SSH administration with synchronized public keys
# - Secure Boot with TPM2-backed LUKS unlock

{ ... }:

{
  imports = [
    ./disko.nix
    ./hardware-configuration.nix

    ../../modules
  ];

  networking.hostName = "samuels-ser9";

  features = {
    # --- Hardware & Kernel ---
    kernel = "cachyos-v4";
    hardware = {
      formFactor = "headless";
      cpu = "amd";
      gpu = "amd";
      unifiedMemory = {
        enable = true;
        size = 32768;
      };
    };

    # --- Boot & Security ---
    secureBoot.enable = true;
    encryption.unlockMethod = "tpm2";
    auth.ldap = {
      enable = true;
      uri = "ldaps://lldap.k3s.oechsler.it:6360";
      baseDn = "dc=oechsler,dc=it";
    };

    # --- Networking ---
    wifi.enable = false;

    # --- System Services ---
    ssh.enable = true;
    bluetooth.enable = false;
    audio.enable = false;

    # --- LLM ---
    llm = {
      enable = true;
      ollama.enable = false;
      llamaCpp = {
        enable = true;
        server = true;
        models."qwen3.8-27b" = {
          name = "Qwen 3.8 27B";
          toolCall = true;
          reasoning = true;
          temperature = true;
          source = {
            repo = "unsloth/Qwen3.8-27B-GGUF";
            file = "Qwen3.8-27B-UD-Q4_K_M.gguf";
            sha256 = "322e194ff79741c7baa497c240f677f54b201b0efab44ca8e50f122b39123482";
          };
        };
      };
    };

    # --- Development ---
    dev.enable = false;

    # --- Operations ---
    ops.enable = false;
  };

  system.stateVersion = "26.11";
}
