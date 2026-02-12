{ config, pkgs, ... }:

{
  programs.neovim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;
    plugins = with pkgs.vimPlugins; [
      catppuccin-nvim
      lualine-nvim
      nvim-tree-lua
      nvim-web-devicons
      (nvim-treesitter.withPlugins (p: with p; [ nix go rust javascript typescript java lua bash json yaml toml ]))
      telescope-nvim
      telescope-fzf-native-nvim
      plenary-nvim
      nvim-cmp
      cmp-nvim-lsp
      cmp-buffer
      cmp-path
      cmp_luasnip
      luasnip
      bufferline-nvim
      gitsigns-nvim
      which-key-nvim
    ];
    extraPackages = with pkgs; [
      nil
      gopls
      rust-analyzer
      typescript-language-server
      jdt-language-server
    ];
    initLua = let
      flavor = config.catppuccin.flavor;
    in ''
      -- Leader
      vim.g.mapleader = " "
      vim.g.maplocalleader = " "

      -- Settings (kickstart.nvim defaults)
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

      -- Diagnostics
      vim.diagnostic.config({
        severity_sort = true,
        float = { border = "rounded", source = "if_many" },
        underline = { severity = vim.diagnostic.severity.ERROR },
        virtual_text = { spacing = 2 },
        signs = true,
      })

      -- Catppuccin
      require("catppuccin").setup({
        flavour = "${flavor}",
        integrations = {
          bufferline = true,
          gitsigns = true,
          which_key = true,
          nvimtree = true,
        },
      })
      vim.cmd.colorscheme("catppuccin")

      -- Lualine
      require("lualine").setup({
        options = { theme = "catppuccin" },
      })

      -- Which-key (shows pending keybindings)
      require("which-key").setup()

      -- Git signs in gutter
      require("gitsigns").setup({
        signs = {
          add = { text = "+" },
          change = { text = "~" },
          delete = { text = "_" },
          topdelete = { text = "‾" },
          changedelete = { text = "~" },
        },
      })

      -- Treesitter (parsers installed via Nix)
      vim.api.nvim_create_autocmd("FileType", {
        callback = function() pcall(vim.treesitter.start) end,
      })

      -- Highlight on yank
      vim.api.nvim_create_autocmd("TextYankPost", {
        callback = function() vim.hl.on_yank() end,
      })

      -- File explorer
      require("nvim-tree").setup({
        on_attach = function(bufnr)
          local api = require("nvim-tree.api")
          api.config.mappings.default_on_attach(bufnr)
          vim.keymap.set("n", "<CR>", function()
            local node = api.tree.get_node_under_cursor()
            if node and (node.type == "directory" or node.name == "..") then
              api.tree.change_root_to_node()
            else
              api.node.open.edit()
            end
          end, { buffer = bufnr, noremap = true, silent = true })
        end,
        actions = { change_dir = { enable = true, global = true } },
      })
      vim.keymap.set("n", "<leader>e", "<cmd>NvimTreeToggle<cr>", { desc = "File explorer" })

      -- Buffer line (tabs)
      require("bufferline").setup({
        options = {
          numbers = "ordinal",
          show_close_icon = false,
          show_buffer_close_icons = true,
          separator_style = "thin",
        },
      })

      -- Telescope
      require("telescope").setup({
        extensions = { fzf = {} },
      })
      pcall(require("telescope").load_extension, "fzf")

      local builtin = require("telescope.builtin")
      vim.keymap.set("n", "<leader>ff", builtin.find_files, { desc = "Find files" })
      vim.keymap.set("n", "<leader>fg", builtin.live_grep, { desc = "Grep" })
      vim.keymap.set("n", "<leader>fb", builtin.buffers, { desc = "Buffers" })
      vim.keymap.set("n", "<leader>fh", builtin.help_tags, { desc = "Help" })
      vim.keymap.set("n", "<leader>fd", builtin.diagnostics, { desc = "Diagnostics" })
      vim.keymap.set("n", "<leader>fr", builtin.resume, { desc = "Resume search" })
      vim.keymap.set("n", "<leader>f.", builtin.oldfiles, { desc = "Recent files" })
      vim.keymap.set("n", "<leader>/", function()
        builtin.current_buffer_fuzzy_find(require("telescope.themes").get_dropdown({ previewer = false }))
      end, { desc = "Search in buffer" })

      -- General keymaps
      vim.keymap.set("n", "<Esc>", "<cmd>nohlsearch<CR>", { desc = "Clear search" })
      vim.keymap.set("t", "<Esc><Esc>", "<C-\\><C-n>", { desc = "Exit terminal mode" })

      -- Focus between splits (≈ Alt+H/J/K/L in tmux)
      vim.keymap.set("n", "<leader>h", "<C-w>h", { desc = "Focus left" })
      vim.keymap.set("n", "<leader>j", "<C-w>j", { desc = "Focus down" })
      vim.keymap.set("n", "<leader>k", "<C-w>k", { desc = "Focus up" })
      vim.keymap.set("n", "<leader>l", "<C-w>l", { desc = "Focus right" })

      -- Splits (≈ Alt+Enter / Alt+- in tmux)
      vim.keymap.set("n", "<leader><CR>", "<cmd>vsplit<cr>", { desc = "Vertical split" })
      vim.keymap.set("n", "<leader>-", "<cmd>split<cr>", { desc = "Horizontal split" })
      vim.keymap.set("n", "<leader>q", "<cmd>close<cr>", { desc = "Close split" })

      -- Fullscreen / zoom (≈ Alt+F in tmux)
      vim.keymap.set("n", "<leader>z", "<cmd>only<cr>", { desc = "Zoom (close other splits)" })

      -- Buffer/tab navigation (≈ Alt+1-0 in tmux)
      for i = 1, 9 do
        vim.keymap.set("n", "<leader>" .. i, "<cmd>BufferLineGoToBuffer " .. i .. "<cr>", { desc = "Buffer " .. i })
      end

      -- Buffer management (≈ Alt+T / Alt+W in tmux)
      vim.keymap.set("n", "<leader>t", "<cmd>enew<cr>", { desc = "New buffer" })
      vim.keymap.set("n", "<leader>w", "<cmd>bdelete<cr>", { desc = "Close buffer" })

      -- :q/:wq close buffer (like <leader>w), last buffer quits nvim
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

      -- LSP (Neovim 0.11+ native API)
      local capabilities = require("cmp_nvim_lsp").default_capabilities()
      vim.lsp.config("*", { capabilities = capabilities })
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

          -- Document highlight on CursorHold
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

      -- Completion
      local cmp = require("cmp")
      local luasnip = require("luasnip")
      cmp.setup({
        snippet = { expand = function(args) luasnip.lsp_expand(args.body) end },
        mapping = cmp.mapping.preset.insert({
          ["<Tab>"] = cmp.mapping(function(fallback)
            if cmp.visible() then cmp.select_next_item()
            elseif luasnip.expand_or_jumpable() then luasnip.expand_or_jump()
            else fallback() end
          end, { "i", "s" }),
          ["<S-Tab>"] = cmp.mapping(function(fallback)
            if cmp.visible() then cmp.select_prev_item()
            elseif luasnip.jumpable(-1) then luasnip.jump(-1)
            else fallback() end
          end, { "i", "s" }),
          ["<CR>"] = cmp.mapping.confirm({ select = true }),
        }),
        sources = cmp.config.sources(
          { { name = "nvim_lsp" }, { name = "luasnip" } },
          { { name = "buffer" }, { name = "path" } }
        ),
      })
    '';
  };
}
