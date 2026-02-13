{ pkgs, ... }:

{
  programs.neovim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;

    plugins = with pkgs.vimPlugins; [
      # UI
      lualine-nvim
      bufferline-nvim
      indent-blankline-nvim
      nvim-web-devicons
      noice-nvim
      nui-nvim
      nvim-notify

      # Navigation
      nvim-tree-lua
      telescope-nvim
      telescope-fzf-native-nvim
      plenary-nvim
      flash-nvim

      # Editing
      (nvim-treesitter.withPlugins (
        p: with p; [
          nix
          go
          rust
          javascript
          typescript
          java
          lua
          bash
          json
          yaml
          toml
        ]
      ))
      mini-nvim
      gitsigns-nvim
      todo-comments-nvim
      which-key-nvim

      # LSP & Completion
      blink-cmp
      conform-nvim

      # Tools
      claudecode-nvim
      grug-far-nvim
    ];

    extraPackages = with pkgs; [
      # LSP servers
      nil
      gopls
      rust-analyzer
      typescript-language-server
      jdt-language-server
      # Formatters
      nixfmt
      prettierd
      gofumpt
      google-java-format
    ];

    initLua = ''
        vim.g.mapleader = " "
        vim.g.maplocalleader = " "

        -- Editor settings
        vim.opt.number = true
        vim.opt.relativenumber = true
        vim.opt.signcolumn = "yes"
        vim.opt.showmode = false
        vim.opt.shortmess:append("I")
        vim.opt.mouse = "a"
        vim.opt.clipboard = "unnamedplus"
        vim.opt.undofile = true
        vim.opt.ignorecase = true
        vim.opt.smartcase = true
        vim.opt.breakindent = true
        vim.opt.splitright = true
        vim.opt.splitbelow = true
        vim.opt.cursorline = true
        vim.opt.scrolloff = 10
        vim.opt.updatetime = 250
        vim.opt.timeoutlen = 300
        vim.opt.confirm = true
        vim.opt.inccommand = "split"
        vim.opt.list = true
        vim.opt.listchars = { tab = "» ", trail = "·", nbsp = "␣" }

        vim.diagnostic.config({
          severity_sort = true,
          float = { border = "rounded", source = "if_many" },
          underline = { severity = vim.diagnostic.severity.ERROR },
          virtual_text = { spacing = 2 },
          signs = true,
        })

        --------------------------------------------------------
        -- UI
        --------------------------------------------------------
        require("lualine").setup({ options = { theme = "catppuccin" } })

        require("bufferline").setup({
          options = {
            numbers = "ordinal",
            show_close_icon = false,
            show_buffer_close_icons = true,
            separator_style = "thin",
            close_command = "bdelete! %d",
            middle_mouse_command = "bdelete! %d",
            diagnostics = "nvim_lsp",
            diagnostics_indicator = function(count, level)
              local icon = level:match("error") and " " or " "
              return icon .. count
            end,
            offsets = {
              { filetype = "NvimTree", text = "Explorer", text_align = "center", separator = true },
            },
          },
        })

        require("ibl").setup({
          indent = { char = "│" },
          scope = { enabled = true, show_start = false, show_end = false },
        })

        require("noice").setup({
          lsp = {
            override = {
              ["vim.lsp.util.convert_input_to_markdown_lines"] = true,
              ["vim.lsp.util.stylize_markdown"] = true,
              ["cmp.entry.get_documentation"] = true,
            },
          },
          presets = {
            bottom_search = true,
            command_palette = true,
            long_message_to_split = true,
            lsp_doc_border = true,
          },
        })

        --------------------------------------------------------
        -- Navigation
        --------------------------------------------------------
        require("nvim-tree").setup({})

        require("telescope").setup({ extensions = { fzf = {} } })
        pcall(require("telescope").load_extension, "fzf")

        require("flash").setup()

        --------------------------------------------------------
        -- Editing
        --------------------------------------------------------
        vim.api.nvim_create_autocmd("FileType", {
          callback = function() pcall(vim.treesitter.start) end,
        })

        vim.api.nvim_create_autocmd("TextYankPost", {
          callback = function() vim.hl.on_yank() end,
        })

        vim.api.nvim_create_autocmd({ "BufEnter", "WinEnter" }, {
          pattern = "term://*",
          callback = function() vim.cmd("startinsert") end,
        })

        require("mini.pairs").setup()

        require("gitsigns").setup({
          signs = {
            add = { text = "+" },
            change = { text = "~" },
            delete = { text = "_" },
            topdelete = { text = "‾" },
            changedelete = { text = "~" },
          },
          current_line_blame = true,
          current_line_blame_opts = { delay = 300 },
        })

        require("todo-comments").setup()

        require("grug-far").setup()

        require("which-key").setup()
        require("which-key").add({
          { "<leader>a", group = "Claude Code", icon = "󰚩" },
          { "<leader>b", group = "Buffers", icon = "󰓩" },
          { "<leader>c", group = "Code" },
          { "<leader>f", group = "Find" },
          { "<leader>g", group = "Git" },
        })

        --------------------------------------------------------
        -- LSP & Completion
        --------------------------------------------------------
        require("blink.cmp").setup({
          keymap = {
            preset = "default",
            ["<Tab>"] = { "select_next", "snippet_forward", "fallback" },
            ["<S-Tab>"] = { "select_prev", "snippet_backward", "fallback" },
            ["<CR>"] = { "accept", "fallback" },
          },
          completion = {
            list = { selection = { preselect = true, auto_insert = true } },
            menu = { border = "rounded" },
            documentation = { auto_show = true, window = { border = "rounded" } },
            ghost_text = { enabled = true },
          },
          sources = { default = { "lsp", "path", "snippets", "buffer" } },
        })

        vim.lsp.config("*", { capabilities = require("blink.cmp").get_lsp_capabilities() })
        vim.lsp.config("nil_ls", {
          cmd = { "nil" },
          filetypes = { "nix" },
          root_markers = { "flake.nix", "shell.nix", "default.nix" },
        })
        vim.lsp.config("gopls", {
          cmd = { "gopls" },
          filetypes = { "go", "gomod", "gowork", "gotmpl" },
          root_markers = { "go.mod" },
        })
        vim.lsp.config("rust_analyzer", {
          cmd = { "rust-analyzer" },
          filetypes = { "rust" },
          root_markers = { "Cargo.toml" },
        })
        vim.lsp.config("ts_ls", {
          cmd = { "typescript-language-server", "--stdio" },
          filetypes = { "javascript", "javascriptreact", "typescript", "typescriptreact" },
          root_markers = { "tsconfig.json", "jsconfig.json", "package.json" },
        })
        vim.lsp.config("jdtls", {
          cmd = { "jdtls" },
          filetypes = { "java" },
          root_markers = { "pom.xml", "build.gradle", ".project" },
        })
        vim.lsp.enable({ "nil_ls", "gopls", "rust_analyzer", "ts_ls", "jdtls" })

        require("conform").setup({
          formatters_by_ft = {
            nix = { "nixfmt" },
            go = { "gofumpt" },
            rust = { "rustfmt" },
            javascript = { "prettierd" },
            typescript = { "prettierd" },
            javascriptreact = { "prettierd" },
            typescriptreact = { "prettierd" },
            json = { "prettierd" },
            yaml = { "prettierd" },
            markdown = { "prettierd" },
            java = { "google-java-format" },
          },
          format_on_save = { timeout_ms = 500, lsp_format = "fallback" },
        })

        --------------------------------------------------------
        -- Claude Code
        --------------------------------------------------------
        require("claudecode").setup({
          terminal = { split_side = "right", split_width_percentage = 0.33 },
        })

        --------------------------------------------------------
        -- Keymaps
        --------------------------------------------------------
        local builtin = require("telescope.builtin")

        -- General
        vim.keymap.set("n", "<Esc>", "<cmd>nohlsearch<CR>", { desc = "Clear search" })
        vim.keymap.set("t", "<Esc><Esc>", "<C-\\><C-n>", { desc = "Exit terminal mode" })

        -- Find (Telescope)
        vim.keymap.set("n", "<leader>ff", builtin.find_files, { desc = "Find files" })
        vim.keymap.set("n", "<leader>fg", builtin.live_grep, { desc = "Grep" })
        vim.keymap.set("n", "<leader>fb", builtin.buffers, { desc = "Buffers" })
        vim.keymap.set("n", "<leader>fh", builtin.help_tags, { desc = "Help" })
        vim.keymap.set("n", "<leader>fd", builtin.diagnostics, { desc = "Diagnostics" })
        vim.keymap.set("n", "<leader>fr", builtin.resume, { desc = "Resume search" })
        vim.keymap.set("n", "<leader>f.", builtin.oldfiles, { desc = "Recent files" })
        vim.keymap.set("n", "<leader>ft", "<cmd>TodoTelescope<cr>", { desc = "TODOs" })
        vim.keymap.set("n", "<leader>/", function()
          builtin.current_buffer_fuzzy_find(require("telescope.themes").get_dropdown({ previewer = false }))
        end, { desc = "Search in buffer" })
        vim.keymap.set("n", "<leader>fs", "<cmd>GrugFar<cr>", { desc = "Search & Replace" })
        vim.keymap.set("v", "<leader>fs", "<cmd>GrugFarWithSelection<cr>", { desc = "Search & Replace selection" })

        -- Git
        vim.keymap.set("n", "<leader>gb", "<cmd>Gitsigns toggle_current_line_blame<cr>", { desc = "Toggle blame" })
        vim.keymap.set("n", "<leader>gp", "<cmd>Gitsigns preview_hunk<cr>", { desc = "Preview hunk" })
        vim.keymap.set("n", "<leader>gr", "<cmd>Gitsigns reset_hunk<cr>", { desc = "Reset hunk" })
        vim.keymap.set("n", "<leader>gs", "<cmd>Gitsigns stage_hunk<cr>", { desc = "Stage hunk" })

        -- Navigation
        vim.keymap.set("n", "<leader>e", "<cmd>NvimTreeFocus<cr>", { desc = "File explorer" })
        vim.keymap.set({ "n", "x", "o" }, "s", function() require("flash").jump() end, { desc = "Flash" })
        vim.keymap.set({ "n", "x", "o" }, "S", function() require("flash").treesitter() end, { desc = "Flash Treesitter" })

        -- Splits
        vim.keymap.set("n", "<leader>h", "<C-w>h", { desc = "Focus left" })
        vim.keymap.set("n", "<leader>j", "<C-w>j", { desc = "Focus down" })
        vim.keymap.set("n", "<leader>k", "<C-w>k", { desc = "Focus up" })
        vim.keymap.set("n", "<leader>l", "<C-w>l", { desc = "Focus right" })
        vim.keymap.set("n", "<leader><CR>", "<cmd>vsplit<cr>", { desc = "Vertical split" })
        vim.keymap.set("n", "<leader>-", "<cmd>split<cr>", { desc = "Horizontal split" })
        vim.keymap.set("n", "<leader>q", "<cmd>close<cr>", { desc = "Close split" })
        vim.keymap.set("n", "<leader>z", "<cmd>only<cr>", { desc = "Zoom (close other splits)" })

        -- Buffers (VSCode-style)
        for i = 1, 9 do
          vim.keymap.set("n", "<leader>" .. i, "<cmd>BufferLineGoToBuffer " .. i .. "<cr>", { desc = "Buffer " .. i })
        end
        vim.keymap.set("n", "<leader>t", "<cmd>enew<cr>", { desc = "New buffer" })
        vim.keymap.set("n", "<leader>w", "<cmd>bdelete<cr>", { desc = "Close buffer" })
        vim.keymap.set("n", "<C-Tab>", "<cmd>BufferLineCycleNext<cr>", { desc = "Next tab" })
        vim.keymap.set("n", "<C-S-Tab>", "<cmd>BufferLineCyclePrev<cr>", { desc = "Previous tab" })
        vim.keymap.set("n", "<A-Right>", "<cmd>BufferLineMoveNext<cr>", { desc = "Move tab right" })
        vim.keymap.set("n", "<A-Left>", "<cmd>BufferLineMovePrev<cr>", { desc = "Move tab left" })
        vim.keymap.set("n", "<leader>bp", "<cmd>BufferLinePick<cr>", { desc = "Pick buffer" })
        vim.keymap.set("n", "<leader>bc", "<cmd>BufferLinePickClose<cr>", { desc = "Pick buffer to close" })

        vim.keymap.set("c", "<CR>", function()
          if vim.fn.getcmdtype() ~= ":" then return "<CR>" end
          local cmd = vim.fn.getcmdline()
          local bufs = vim.tbl_filter(function(b) return vim.bo[b].buflisted end, vim.api.nvim_list_bufs())
          if #bufs > 1 then
            if cmd == "q" then return "<C-u>bdelete<CR>" end
            if cmd == "q!" then return "<C-u>bdelete!<CR>" end
            if cmd == "wq" then return "<C-u>write | bdelete<CR>" end
            if cmd == "wq!" then return "<C-u>write | bdelete!<CR>" end
          end
          return "<CR>"
        end, { expr = true })

        -- Code
        vim.keymap.set({ "n", "v" }, "<leader>cf", function()
          require("conform").format({ async = true, lsp_format = "fallback" })
        end, { desc = "Format" })

        -- Claude Code
        vim.keymap.set("n", "<leader>ac", "<cmd>ClaudeCode<cr>", { desc = "Toggle Claude" })
        vim.keymap.set("n", "<leader>af", "<cmd>ClaudeCodeFocus<cr>", { desc = "Focus Claude" })
        vim.keymap.set("n", "<leader>ar", "<cmd>ClaudeCode --resume<cr>", { desc = "Resume session" })
        vim.keymap.set("n", "<leader>aR", "<cmd>ClaudeCode --continue<cr>", { desc = "Continue session" })
        vim.keymap.set("n", "<leader>ab", "<cmd>ClaudeCodeAdd %<cr>", { desc = "Add buffer to context" })
        vim.keymap.set("v", "<leader>as", "<cmd>ClaudeCodeSend<cr>", { desc = "Send selection" })
        vim.keymap.set("n", "<leader>aa", "<cmd>ClaudeCodeDiffAccept<cr>", { desc = "Accept diff" })
        vim.keymap.set("n", "<leader>ad", "<cmd>ClaudeCodeDiffReject<cr>", { desc = "Reject diff" })

        -- LSP (attached per buffer)
        vim.api.nvim_create_autocmd("LspAttach", {
          callback = function(args)
            local map = function(keys, func, desc)
              vim.keymap.set("n", keys, func, { buffer = args.buf, desc = desc })
            end
            map("gd", vim.lsp.buf.definition, "Go to definition")
            map("gD", vim.lsp.buf.declaration, "Go to declaration")
            map("gr", vim.lsp.buf.references, "References")
            map("gi", vim.lsp.buf.implementation, "Go to implementation")
            map("K", vim.lsp.buf.hover, "Hover")
            map("<leader>ca", vim.lsp.buf.code_action, "Code action")
            map("<leader>rn", vim.lsp.buf.rename, "Rename")
            map("<leader>ds", builtin.lsp_document_symbols, "Document symbols")

            local client = vim.lsp.get_client_by_id(args.data.client_id)
            if client and client:supports_method("textDocument/documentHighlight") then
              local group = vim.api.nvim_create_augroup("lsp-highlight-" .. args.buf, { clear = true })
              vim.api.nvim_create_autocmd({ "CursorHold", "CursorHoldI" }, {
                buffer = args.buf, group = group,
                callback = vim.lsp.buf.document_highlight,
              })
              vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
                buffer = args.buf, group = group,
                callback = vim.lsp.buf.clear_references,
              })
            end
          end,
        })
      '';
  };
}
