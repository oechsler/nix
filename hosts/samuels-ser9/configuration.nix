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
        # This host is headless; reserve only a small margin for the graphics runtime.
        fitTarget = 512;
        batchSize = 2048;
        microBatchSize = 512;
        flashAttention = "on";
        # A quantized KV cache keeps the large model context affordable while
        # retaining the full configured context window.
        cacheTypeK = "q4_0";
        cacheTypeV = "q4_0";
        # The MTP head improves decode throughput on this host; the draft
        # settings should be benchmarked against the no-speculation baseline.
        specType = "draft-mtp";
        specDraftMax = 3;
        specDraftMinP = 0.0;
        models."tiel-coder-35b-a3b" = {
          name = "Tiel Coder 35B-A3B";
          toolCall = true;
          reasoning = true;
          temperature = true;
          context = 131072;
          source = {
            repo = "peculiar-ragdoll/Tiel-Coder-35B-A3B-GGUF-MTP";
            file = "Tiel-Coder-35B-A3B-MTP-UD-Q4_K_XL.gguf";
            revision = "182ae2b61f15ca133f160c6e11badc2791b052fd";
            sha256 = "10960d1d6477b08ed36a0e542e571b473022023c25b8315b0cf8c33c57e98ccd";
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
