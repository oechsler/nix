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
        # Vulkan is currently more reliable than HIP/ROCm on the SER9's
        # gfx1151 iGPU; let llama.cpp fit offloaded layers at startup.
        backend = "vulkan";
        gpuLayers = "auto";
        # Leave room for the desktop and graphics runtime on the unified-memory APU.
        fitTarget = 2048;
        batchSize = 512;
        microBatchSize = 128;
        # A quantized KV cache keeps the large model context affordable while
        # retaining the full configured context window.
        cacheTypeK = "q4_0";
        cacheTypeV = "q4_0";
        models."ornith-1.5-35b-a3b" = {
          name = "Ornith 1.5 35B-A3B";
          toolCall = true;
          reasoning = true;
          temperature = true;
          context = 131072;
          source = {
            repo = "ornith-ai/Ornith-1.5-35B-A3B-GGUF";
            file = "Ornith-1.5-35B-Q4_K_M.gguf";
            sha256 = "42739874cc2ccfdb8523b23fbe52e29b2a7555c8176737ca9ca0b5d59859d41f";
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
