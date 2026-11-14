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
        # 35B Q4 model + large KV cache on 32GB shared RAM: these caps bound peak
        # memory so the service is not OOM-killed and restarted by systemd.
        batchSize = 1024;
        microBatchSize = 256;
        flashAttention = "on";
        # A quantized KV cache keeps the large model context affordable while
        # retaining the full configured context window.
        cacheTypeK = "q4_0";
        cacheTypeV = "q4_0";
        specType = "none";
        models = {
          "tiel-coder-35b-a3b" = {
            name = "Tiel Coder 35B-A3B";
            toolCall = true;
            reasoning = true;
            inputModalities = [
              "text"
              "image"
            ];
            # TielCoder's pinned Sharp template has no documented native effort
            # hierarchy, so profiles differ by deterministic budget ceilings.
            temperature = true;
            # 100k as KiB-aligned context (not a strict power of 2) to fit the
            # KV cache in 32GB shared RAM without OOM restarts.
            context = 102400;
            source = {
              repo = "peculiar-ragdoll/Tiel-Coder-35B-A3B-GGUF";
              file = "Tiel-Coder-35B-A3B-UD-Q4_K_XL.gguf";
              revision = "0b5b446a04ef6c89efc10408105b1b78d227f0a3";
              sha256 = "9286a94c453c6a40ad51982c3dc88df4bba32fee9efad06e4588c83c059cf17c";
              mmproj = {
                repo = "peculiar-ragdoll/Tiel-Coder-35B-A3B-GGUF";
                file = "mmproj-BF16.gguf";
                revision = "0b5b446a04ef6c89efc10408105b1b78d227f0a3";
                sha256 = "d9ce31026d1cb1f3f8d5152e2e2a014d9d2b302b6c93a7dc07bb0a0487f52837";
              };
            };
          };
          "dirk-qwen3.8-27b" = {
            name = "Dirk 27B";
            toolCall = true;
            reasoning = true;
            inputModalities = [
              "text"
              "image"
            ];
            reasoningProfile = {
              budgets = {
                low = 256;
                medium = 512;
                high = 1024;
                xhigh = 2048;
              };
              nativeEffort = {
                low = "low";
                medium = "medium";
                high = "medium";
                xhigh = "xhigh";
              };
              effortTransport = "chat_template_kwargs";
            };
            temperature = true;
            context = 102400;
            source = {
              repo = "peculiar-ragdoll/Dirk-Qwen3.8-27B-GGUF";
              file = "Dirk-Qwen3.8-27B-UD-Q4_K_XL.gguf";
              revision = "c4d587fbcd64d0e2c768465706cfa0705d91f2fa";
              sha256 = "711530303357f26d02539354f44bf60685045607d065ca78e83b84e112dd25be";
              mmproj = {
                repo = "peculiar-ragdoll/Dirk-Qwen3.8-27B-GGUF";
                file = "mmproj-F16.gguf";
                revision = "c4d587fbcd64d0e2c768465706cfa0705d91f2fa";
                sha256 = "cbb841a9ee0636b2ec172f5bb8df2ea8dfeb01e90fe7c6126581d662a0b4e43e";
              };
            };
          };
          "nail-qwen3.6-35b-a3b" = {
            name = "Nail Qwen3.6 35B-A3B";
            toolCall = true;
            reasoning = true;
            inputModalities = [
              "text"
              "image"
            ];
            temperature = true;
            # The Q4_K_S tier is the roomy 4-bit choice; 100k is below the
            # upstream 262k window and leaves memory for the rest of the system.
            context = 102400;
            source = {
              repo = "peculiar-ragdoll/Nail-Qwen3.6-35B-A3B-GGUF";
              file = "Nail-Qwen3.6-35B-A3B-UD-Q4_K_S.gguf";
              revision = "ac66b0fad4bc2b68d29eff967c06d55de09429c1";
              sha256 = "cafba2e3320dcd0a5e3a101372c04e1b023afa85e82bc0ea5852542452d4d98d";
              mmproj = {
                repo = "peculiar-ragdoll/Nail-Qwen3.6-35B-A3B-GGUF";
                file = "mmproj-F16.gguf";
                revision = "ac66b0fad4bc2b68d29eff967c06d55de09429c1";
                sha256 = "8971ee4f331ff0a4c609374f32984b3d4e6dc086c0aa35f1d637fad1829e887f";
              };
            };
          };
          "sharp-spark-x2.6-4b" = {
            name = "Sharp Spark X2.6 4B";
            toolCall = true;
            reasoning = true;
            temperature = true;
            # Spark's sliding-window attention keeps KV-cache growth low, making
            # it a practical fallback when the larger models are too expensive.
            context = 102400;
            source = {
              repo = "peculiar-ragdoll/Sharp-Spark-X2.6-4B-GGUF";
              file = "Sharp-Spark-X2.6-4B-Q6_K_XL.gguf";
              revision = "d6b3e40d5f6372d16f83320230f9b26796ee956e";
              sha256 = "66cba01df2e2228aedce3f4592efeff69a495ef7ce2e176fc3d902793fbf8eb3";
            };
          };
          "gemma-4-26b-a4b-it" = {
            name = "Gemma 4 26B A4B";
            toolCall = true;
            reasoning = true;
            inputModalities = [
              "text"
              "image"
              "video"
            ];
            # Gemma exposes a thinking toggle rather than a native effort ladder.
            reasoningProfile = {
              budgets = {
                low = 0;
                medium = 512;
                high = 1024;
                xhigh = 2048;
              };
              chatTemplateKwargsByProfile = {
                low.enable_thinking = false;
                medium.enable_thinking = true;
                high.enable_thinking = true;
                xhigh.enable_thinking = true;
              };
            };
            temperature = true;
            # Five global-attention layers keep q4_0 KV-cache growth modest at 100k.
            context = 102400;
            source = {
              repo = "ggml-org/gemma-4-26B-A4B-it-GGUF";
              file = "gemma-4-26B-A4B-it-Q4_0.gguf";
              revision = "1ca99aae748b4b01f609fa51eb23682ee5f00b85";
              sha256 = "d208665ab1cd3a69f7a9a4bc59430e8448c8093d9b06334f566ac59d6d504a03";
              mmproj = {
                repo = "ggml-org/gemma-4-26B-A4B-it-GGUF";
                file = "mmproj-gemma-4-26B-A4B-it-Q8_0.gguf";
                revision = "1ca99aae748b4b01f609fa51eb23682ee5f00b85";
                sha256 = "cc4e855736da450bf1e162d8cccfe0ad685727d0c9e04ef7dd8d884f3121039b";
              };
            };
          };
          "gemma-4-12b-it" = {
            name = "Gemma 4 12B";
            toolCall = true;
            reasoning = true;
            inputModalities = [
              "text"
              "image"
              "audio"
              "video"
            ];
            temperature = true;
            context = 102400;
            source = {
              repo = "google/gemma-4-12B-it-qat-q4_0-gguf";
              file = "gemma-4-12b-it-qat-q4_0.gguf";
              revision = "29d097773436b69ff9feafd636ab4cf873786537";
              sha256 = "93567e57a8fe10b23569b9d9ec38cd005deedf71e29477c421a4b83f418a538b";
              mmproj = {
                repo = "google/gemma-4-12B-it-qat-q4_0-gguf";
                file = "mmproj-gemma-4-12b-it-qat-q4_0.gguf";
                revision = "29d097773436b69ff9feafd636ab4cf873786537";
                sha256 = "cb018338a7538a9814d994bfe54644c71eb7ed54e31eae2f721e45fd3c260da7";
              };
            };
          };
          "gemma-4-31b-it" = {
            name = "Gemma 4 31B";
            toolCall = true;
            reasoning = true;
            inputModalities = [
              "text"
              "image"
              "video"
            ];
            # The dense 31B model is stronger on coding benchmarks, but its
            # context is capped to leave memory for the model and runtime.
            reasoningProfile = {
              budgets = {
                low = 0;
                medium = 512;
                high = 1024;
                xhigh = 2048;
              };
              chatTemplateKwargsByProfile = {
                low.enable_thinking = false;
                medium.enable_thinking = true;
                high.enable_thinking = true;
                xhigh.enable_thinking = true;
              };
            };
            temperature = true;
            context = 32768;
            source = {
              repo = "ggml-org/gemma-4-31B-it-GGUF";
              file = "gemma-4-31B-it-Q4_0.gguf";
              revision = "f39d380138390ea246513ff0f087352f3cfc3a1b";
              sha256 = "031dc1c5fa9c5a0abbf3c39c5173fb2af65f5ac2dc2a090268561d3c72dcd834";
              mmproj = {
                repo = "ggml-org/gemma-4-31B-it-GGUF";
                file = "mmproj-gemma-4-31B-it-Q8_0.gguf";
                revision = "f39d380138390ea246513ff0f087352f3cfc3a1b";
                sha256 = "8872f1dd7ba6a750a039c04b45812511f4ecf004e229420cea58c8049a970fb6";
              };
            };
          };
        };
      };
      opencode = {
        enable = true;
        defaultModel = "llama-cpp/tiel-coder-35b-a3b";
        # Keep this headless host on its configured llama.cpp models only.
        provider.openai.enable = false;
        server = {
          enable = true;
          remote = true;
        };
      };
    };

    # --- Development ---
    dev = {
      enable = false;
    };
    # --- Operations ---
    ops.enable = false;
  };

  system.stateVersion = "26.11";
}
