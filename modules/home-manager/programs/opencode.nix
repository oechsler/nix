# OpenCode AI coding agent configuration.
# Provider credentials and MCP secrets are injected at runtime from SOPS.

{
  config,
  lib,
  features,
  pkgs,
  theme,
  ...
}:

let
  modelSpec = import ../../lib/opencode.nix { inherit lib; };
  cfg = features.dev.opencode;
  selectedLanguages =
    if features.dev.languages == [ ] then
      (import ../../lib/development.nix).languageNames
    else
      features.dev.languages;
  languageEnabled = name: builtins.elem name selectedLanguages;
  localOllamaCfg = features.llm.ollama;
  localOllamaEnabled = features.llm.enable && localOllamaCfg.enable;
  localLlamaCppCfg = features.llm.llamaCpp;
  localLlamaCppEnabled = features.llm.enable && localLlamaCppCfg.enable;
  opencodeTheme =
    {
      latte = "catppuccin";
      frappe = "catppuccin-frappe";
      macchiato = "catppuccin-macchiato";
      mocha = "catppuccin";
    }
    .${theme.catppuccin.flavor};
  configuredProviders = lib.filterAttrs (_: provider: provider.enable) (
    lib.optionalAttrs localOllamaEnabled { ollama = localOllamaProvider; }
    // lib.optionalAttrs localLlamaCppEnabled { "llama-cpp" = localLlamaCppProvider; }
    // cfg.provider
  );
  localOllamaProvider = {
    enable = true;
    apiKeySecret = null;
    apiKey = null;
    baseURL = "http://127.0.0.1:11434/v1";
    name = "Ollama";
    package = "@opencode/ai/providers/openai-compatible";
    models = lib.mapAttrs (
      _: model:
      model
      // lib.optionalAttrs ((model.context or null) == null) {
        inherit (localOllamaCfg) context;
      }
      // lib.optionalAttrs ((model.output or null) == null) {
        output = 16384;
      }
    ) localOllamaCfg.models;
  };
  localLlamaCppProvider = {
    enable = true;
    apiKeySecret = null;
    apiKey = null;
    baseURL = "http://127.0.0.1:${toString localLlamaCppCfg.port}/v1";
    name = "llama.cpp";
    package = "@opencode/ai/providers/openai-compatible";
    models = lib.mapAttrs (
      _: model:
      model
      // lib.optionalAttrs ((model.context or null) == null) {
        inherit (localLlamaCppCfg) context;
      }
      // lib.optionalAttrs ((model.output or null) == null) {
        inherit (localLlamaCppCfg) output;
      }
    ) localLlamaCppCfg.models;
  };
  providersWithSecrets = lib.filterAttrs (
    _: provider: provider.apiKeySecret != null
  ) configuredProviders;
  # MCP enablement is runtime-configurable in OpenCode, so prepare credentials
  # and process-wide TLS behavior even for entries disabled by default.
  mcpWithSecrets = lib.filterAttrs (_: server: server.tokenSecret != null) cfg.mcp;
  mcpWithInsecureTls = lib.any (server: server.insecureTls) (lib.attrValues cfg.mcp);
  mcpWithOAuthSecrets = lib.filterAttrs (
    _: server:
    server.type == "remote" && server.oauth != null && server.oauth.clientSecretSecret != null
  ) cfg.mcp;
  envName =
    prefix: name:
    "OPENCODE_${prefix}_${
      lib.toUpper (lib.replaceStrings [ "-" "." " " ] [ "_" "_" "_" ] name)
    }_API_KEY";
  providerEnvName = name: envName "PROVIDER" name;
  mcpEnvName =
    name: "OPENCODE_MCP_${lib.toUpper (lib.replaceStrings [ "-" "." " " ] [ "_" "_" "_" ] name)}";
  mcpOAuthEnvName = name: "${mcpEnvName name}_OAUTH_CLIENT_SECRET";
  providerSecretPath = provider: config.sops.secrets.${provider.apiKeySecret}.path;
  mcpSecretPath = server: config.sops.secrets.${server.tokenSecret}.path;
  mcpOAuthSecretPath = server: config.sops.secrets.${server.oauth.clientSecretSecret}.path;
  defaultLsp = {
    nixd = {
      command = [
        "${pkgs.nixd}/bin/nixd"
        "--stdio"
      ];
      extensions = [ ".nix" ];
    };
    bash-language-server = {
      command = [
        "${pkgs.bash-language-server}/bin/bash-language-server"
        "start"
      ];
      extensions = [
        ".sh"
        ".bash"
        ".zsh"
      ];
    };
    fish-lsp = {
      command = [
        "${pkgs.fish-lsp}/bin/fish-lsp"
        "start"
      ];
      extensions = [ ".fish" ];
    };
    yaml-language-server = {
      command = [
        "${pkgs.yaml-language-server}/bin/yaml-language-server"
        "--stdio"
      ];
      extensions = [
        ".yaml"
        ".yml"
      ];
    };
    pyright = {
      command = [
        "${pkgs.pyright}/bin/pyright-langserver"
        "--stdio"
      ];
      extensions = [ ".py" ];
    };
    gopls = {
      command = [ "${pkgs.gopls}/bin/gopls" ];
      extensions = [ ".go" ];
    };
    rust-analyzer = {
      command = [ "${pkgs.rust-analyzer}/bin/rust-analyzer" ];
      extensions = [ ".rs" ];
    };
    typescript-language-server = {
      command = [
        "${pkgs.typescript-language-server}/bin/typescript-language-server"
        "--stdio"
      ];
      extensions = [
        ".js"
        ".jsx"
        ".ts"
        ".tsx"
      ];
    };
    lua-language-server = {
      command = [ "${pkgs.lua-language-server}/bin/lua-language-server" ];
      extensions = [ ".lua" ];
    };
    jdtls = {
      command = [ "${pkgs.jdt-language-server}/bin/jdtls" ];
      extensions = [ ".java" ];
    };
    kotlin-language-server = {
      command = [ "${pkgs.kotlin-language-server}/bin/kotlin-language-server" ];
      extensions = [
        ".kt"
        ".kts"
      ];
    };
    clangd = {
      command = [ "${pkgs.clang-tools}/bin/clangd" ];
      extensions = [
        ".c"
        ".h"
        ".cc"
        ".cpp"
        ".cxx"
        ".hpp"
      ];
    };
    cmake-language-server = {
      command = [ "${pkgs.cmake-language-server}/bin/cmake-language-server" ];
      extensions = [
        "CMakeLists.txt"
        ".cmake"
      ];
    };
    vscode-css-language-server = {
      command = [
        "${pkgs.vscode-langservers-extracted}/bin/vscode-css-language-server"
        "--stdio"
      ];
      extensions = [
        ".css"
        ".scss"
        ".less"
      ];
    };
    vscode-html-language-server = {
      command = [
        "${pkgs.vscode-langservers-extracted}/bin/vscode-html-language-server"
        "--stdio"
      ];
      extensions = [ ".html" ];
    };
    dockerfile-language-server = {
      command = [
        "${pkgs.dockerfile-language-server}/bin/docker-langserver"
        "--stdio"
      ];
      extensions = [ "Dockerfile" ];
    };
    sqls = {
      command = [ "${pkgs.sqls}/bin/sqls" ];
      extensions = [ ".sql" ];
    };
    terraform-ls = {
      command = [
        "${pkgs.terraform-ls}/bin/terraform-ls"
        "serve"
      ];
      extensions = [
        ".tf"
        ".tfvars"
        ".hcl"
      ];
    };
    marksman = {
      command = [
        "${pkgs.marksman}/bin/marksman"
        "server"
      ];
      extensions = [ ".md" ];
    };
    vscode-json-language-server = {
      command = [
        "${pkgs.vscode-json-languageserver}/bin/vscode-json-language-server"
        "--stdio"
      ];
      extensions = [
        ".json"
        ".jsonc"
      ];
    };
    taplo = {
      command = [
        "${pkgs.taplo}/bin/taplo"
        "lsp"
        "stdio"
      ];
      extensions = [ ".toml" ];
    };
  };
  lspLanguages = {
    nixd = "nix";
    bash-language-server = "shell";
    fish-lsp = "shell";
    yaml-language-server = "yaml";
    pyright = "python";
    gopls = "go";
    rust-analyzer = "rust";
    typescript-language-server = "typescript";
    jdtls = "java";
    kotlin-language-server = "kotlin";
    lua-language-server = "lua";
    clangd = "c";
    marksman = "markdown";
    vscode-json-language-server = "json";
    taplo = "toml";
    cmake-language-server = "cmake";
    vscode-css-language-server = "css";
    vscode-html-language-server = "html";
    dockerfile-language-server = "docker";
    sqls = "sql";
    terraform-ls = "terraform";
  };
  enabledDefaultLsp = lib.filterAttrs (
    name: _server: languageEnabled lspLanguages.${name}
  ) defaultLsp;
  providerSecretChecks = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (name: provider: ''
      if ! test -r ${providerSecretPath provider}; then
        echo "OpenCode provider API key is missing for ${name}: run sops-install-secrets.service and check the SOPS age key" >&2
        exit 1
      fi
    '') providersWithSecrets
  );
  mcpSecretChecks = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (name: server: ''
      if ! test -r ${mcpSecretPath server}; then
        echo "OpenCode MCP token is missing for ${name}: run sops-install-secrets.service and check the SOPS age key" >&2
        exit 1
      fi
    '') mcpWithSecrets
  );
  mcpOAuthSecretChecks = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (name: server: ''
      if ! test -r ${mcpOAuthSecretPath server}; then
        echo "OpenCode MCP OAuth client secret is missing for ${name}: run sops-install-secrets.service and check the SOPS age key" >&2
        exit 1
      fi
    '') mcpWithOAuthSecrets
  );
  providerEnvAssignments = lib.concatStringsSep "" (
    lib.mapAttrsToList (name: provider: ''
      export ${providerEnvName name}="$(< ${providerSecretPath provider})"
    '') providersWithSecrets
  );
  mcpEnvAssignments = lib.concatStringsSep "" (
    lib.mapAttrsToList (name: server: ''
      export ${mcpEnvName name}="$(< ${mcpSecretPath server})"
    '') mcpWithSecrets
  );
  mcpOAuthEnvAssignments = lib.concatStringsSep "" (
    lib.mapAttrsToList (name: server: ''
      export ${mcpOAuthEnvName name}="$(< ${mcpOAuthSecretPath server})"
    '') mcpWithOAuthSecrets
  );
  defaultFormatters = {
    nixfmt = {
      command = [
        "${pkgs.nixfmt}/bin/nixfmt"
        "$FILE"
      ];
      extensions = [ ".nix" ];
    };
    prettier = {
      command = [
        "${pkgs.prettierd}/bin/prettierd"
        "$FILE"
      ];
      extensions = [
        ".js"
        ".jsx"
        ".ts"
        ".tsx"
        ".json"
        ".jsonc"
        ".yaml"
        ".yml"
        ".md"
      ];
    };
    stylua = {
      command = [
        "${pkgs.stylua}/bin/stylua"
        "$FILE"
      ];
      extensions = [ ".lua" ];
    };
    cmake-format = {
      command = [
        "${pkgs.cmake-format}/bin/cmake-format"
        "-i"
        "$FILE"
      ];
      extensions = [
        ".cmake"
        "CMakeLists.txt"
      ];
    };
    sql-formatter = {
      command = [
        "${pkgs.sql-formatter}/bin/sql-formatter"
        "--fix"
        "$FILE"
      ];
      extensions = [ ".sql" ];
    };
    tofu-format = {
      command = [
        "${pkgs.opentofu}/bin/tofu"
        "fmt"
        "$FILE"
      ];
      extensions = [
        ".tf"
        ".tfvars"
        ".hcl"
      ];
    };
    shfmt = {
      command = [
        "${pkgs.shfmt}/bin/shfmt"
        "-w"
        "$FILE"
      ];
      extensions = [
        ".sh"
        ".bash"
        ".zsh"
      ];
    };
    fish_indent = {
      command = [
        "${pkgs.fish}/bin/fish_indent"
        "-w"
        "$FILE"
      ];
      extensions = [ ".fish" ];
    };
    ruff = {
      command = [
        "${pkgs.ruff}/bin/ruff"
        "format"
        "$FILE"
      ];
      extensions = [
        ".py"
        ".pyi"
      ];
    };
    gofumpt = {
      command = [
        "${pkgs.gofumpt}/bin/gofumpt"
        "-w"
        "$FILE"
      ];
      extensions = [ ".go" ];
    };
    rustfmt = {
      command = [
        "${pkgs.rustfmt}/bin/rustfmt"
        "$FILE"
      ];
      extensions = [ ".rs" ];
    };
    google-java-format = {
      command = [
        "${pkgs.google-java-format}/bin/google-java-format"
        "--replace"
        "$FILE"
      ];
      extensions = [ ".java" ];
    };
    ktlint = {
      command = [
        "${pkgs.ktlint}/bin/ktlint"
        "-F"
        "$FILE"
      ];
      extensions = [
        ".kt"
        ".kts"
      ];
    };
    clang-format = {
      command = [
        "${pkgs.clang-tools}/bin/clang-format"
        "-i"
        "$FILE"
      ];
      extensions = [
        ".c"
        ".h"
        ".cc"
        ".cpp"
        ".cxx"
        ".hpp"
      ];
    };
  };
  formatterLanguages = {
    nixfmt = [ "nix" ];
    prettier = [
      "javascript"
      "typescript"
      "json"
      "markdown"
      "yaml"
    ];
    shfmt = [ "shell" ];
    fish_indent = [ "shell" ];
    ruff = [ "python" ];
    gofumpt = [ "go" ];
    rustfmt = [ "rust" ];
    google-java-format = [ "java" ];
    ktlint = [ "kotlin" ];
    clang-format = [ "c" ];
    stylua = [ "lua" ];
    cmake-format = [ "cmake" ];
    sql-formatter = [ "sql" ];
    tofu-format = [ "terraform" ];
  };
  enabledDefaultFormatters = lib.filterAttrs (
    name: _formatter: builtins.any languageEnabled formatterLanguages.${name}
  ) defaultFormatters;
  formatterSettings = lib.mapAttrs (
    _name: formatter:
    {
      disabled = !(formatter.enable or true);
    }
    // lib.optionalAttrs (formatter.command != [ ]) { inherit (formatter) command; }
    // lib.optionalAttrs (formatter.extensions != [ ]) { inherit (formatter) extensions; }
    // lib.optionalAttrs ((formatter.environment or { }) != { }) {
      inherit (formatter) environment;
    }
  ) (enabledDefaultFormatters // cfg.formatter);
  lspSettings = lib.mapAttrs (
    _name: server:
    {
      disabled = !(server.enable or true);
    }
    // lib.optionalAttrs (server.command != [ ]) { inherit (server) command; }
    // lib.optionalAttrs (server.extensions != [ ]) { inherit (server) extensions; }
    // lib.optionalAttrs ((server.env or { }) != { }) { inherit (server) env; }
    // lib.optionalAttrs ((server.initialization or { }) != { }) {
      inherit (server) initialization;
    }
  ) (enabledDefaultLsp // cfg.lsp);
  providerSettings = lib.mapAttrs (
    name: provider:
    {
      models = lib.mapAttrs (modelName: model: modelSpec.toOpenCode modelName model) provider.models;
    }
    // lib.optionalAttrs (provider.name != null) { inherit (provider) name; }
    // lib.optionalAttrs (provider.package != null) { inherit (provider) package; }
    //
      lib.optionalAttrs
        (provider.baseURL != null || provider.apiKeySecret != null || provider.apiKey != null)
        {
          settings =
            lib.optionalAttrs (provider.baseURL != null) { baseURL = provider.baseURL; }
            // lib.optionalAttrs (provider.apiKeySecret != null || provider.apiKey != null) {
              apiKey = if provider.apiKey != null then provider.apiKey else "{env:${providerEnvName name}}";
            };
        }
  ) configuredProviders;
  providerSopsSecrets = lib.mapAttrs' (
    _name: provider: lib.nameValuePair provider.apiKeySecret { }
  ) providersWithSecrets;
  providerAccessPolicies = [
    {
      effect = "deny";
      action = "provider.use";
      resource = "*";
    }
  ]
  ++
    lib.mapAttrsToList
      (name: _provider: {
        effect = "allow";
        action = "provider.use";
        resource = name;
      })
      (
        configuredProviders
        // {
          openai = { };
          "opencode-go" = { };
        }
      );
  mcpServerSettings =
    name: server:
    {
      inherit (server) type;
      enabled = server.enable;
      timeout = server.timeout;
    }
    // lib.optionalAttrs (server.type == "remote") {
      inherit (server) url;
    }
    // lib.optionalAttrs (server.type == "local") { inherit (server) command; }
    // lib.optionalAttrs (server.headers != { } || server.tokenSecret != null || server.token != null) {
      headers =
        server.headers
        // lib.optionalAttrs (server.tokenSecret != null || server.token != null) {
          "${server.tokenHeader}" =
            if server.token != null then
              "${server.tokenPrefix}${server.token}"
            else
              "${server.tokenPrefix}{env:${mcpEnvName name}}";
        };
    }
    // lib.optionalAttrs (server.type == "remote" && server.oauth != null) {
      oauth =
        lib.optionalAttrs (server.oauth.clientId != null) {
          clientId = server.oauth.clientId;
        }
        //
          lib.optionalAttrs (server.oauth.clientSecretSecret != null || server.oauth.clientSecret != null)
            {
              clientSecret =
                if server.oauth.clientSecret != null then
                  server.oauth.clientSecret
                else
                  "{env:${mcpOAuthEnvName name}}";
            }
        // lib.optionalAttrs (server.oauth.scope != null) { scope = server.oauth.scope; }
        // lib.optionalAttrs (server.oauth.callbackPort != null) {
          callbackPort = server.oauth.callbackPort;
        }
        // lib.optionalAttrs (server.oauth.redirectUri != null) {
          redirectUri = server.oauth.redirectUri;
        };
    };
  mcpSettings = {
    servers = lib.mapAttrs mcpServerSettings cfg.mcp;
  };
  mcpSopsSecrets = lib.mapAttrs' (
    _name: server: lib.nameValuePair server.tokenSecret { }
  ) mcpWithSecrets;
  mcpOAuthSopsSecrets = lib.mapAttrs' (
    _name: server: lib.nameValuePair server.oauth.clientSecretSecret { }
  ) mcpWithOAuthSecrets;
  opencodeWithSecrets = pkgs.writeShellScriptBin "opencode" ''
    ${lib.optionalString mcpWithInsecureTls ''
      # OpenCode has no per-remote-MCP TLS exception; this affects this process.
      export NODE_TLS_REJECT_UNAUTHORIZED=0
    ''}
    ${providerSecretChecks}
    ${mcpSecretChecks}
    ${mcpOAuthSecretChecks}
    ${providerEnvAssignments}${mcpEnvAssignments}${mcpOAuthEnvAssignments}
    exec ${pkgs.opencode}/bin/opencode "$@"
  '';
in
{
  config = lib.mkIf (features.dev.enable && features.dev.opencode.enable) {
    sops.secrets = providerSopsSecrets // mcpSopsSecrets // mcpOAuthSopsSecrets;

    xdg.configFile."opencode/tui.json".text = builtins.toJSON {
      theme = opencodeTheme;
    };

    programs.opencode = {
      enable = true;
      package = opencodeWithSecrets;

      settings =
        lib.removeAttrs cfg.settings [
          "agent"
          "compaction"
          "formatter"
          "lsp"
          "mcp"
          "model"
          "plugin"
          "provider"
          "small_model"
          "theme"
        ]
        // {
          "$schema" = "https://opencode.ai/config.json";
          formatter = formatterSettings;
          lsp = {
            markdown = {
              command = [
                "${pkgs.marksman}/bin/marksman"
                "server"
              ];
              extensions = [ ".md" ];
            };
            json = {
              command = [
                "${pkgs.vscode-json-languageserver}/bin/vscode-json-languageserver"
                "--stdio"
              ];
              extensions = [
                ".json"
                ".jsonc"
              ];
            };
            toml = {
              command = [
                "${pkgs.taplo}/bin/taplo"
                "lsp"
                "stdio"
              ];
              extensions = [ ".toml" ];
            };
          }
          // lspSettings;
          model = cfg.defaultModel;
          default_agent = "build";
          agents =
            let
              configuredAgents = cfg.settings.agents or { };
            in
            configuredAgents
            // {
              build = (configuredAgents.build or { }) // {
                model = "${cfg.defaultModel}#high";
              };
              title = (configuredAgents.title or { }) // {
                model = cfg.defaultModel;
              };
            };

          mcp = mcpSettings;

          compaction =
            cfg.settings.compaction or {
              auto = true;
              keep.tokens = 15000;
              buffer = 20000;
            };

          experimental = (cfg.settings.experimental or { }) // {
            policies = providerAccessPolicies;
          };

          providers = providerSettings;
        };
    };

  };
}
