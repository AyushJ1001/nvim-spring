# What LazyVim's `lang.java` extra provides

Inventory of the extra as it exists on this dogfood machine, plus what the extra's plugins actually implement. No coupling recommendation.

**Question (issue #7):** What does LazyVim's `lang.java` extra actually enable in this dogfood setup, from its source and from the plugins it pulls?

## Scope and versions (this machine)

| Piece | Pin / path |
| --- | --- |
| Extra enabled | `lazyvim.plugins.extras.lang.java` in `/home/ayush/.config/nvim/lazyvim.json` lines 2–9 |
| Extra source | `/home/ayush/.local/share/nvim/lazy/LazyVim/lua/lazyvim/plugins/extras/lang/java.lua` |
| LazyVim | lock `c10948c50b18fae7f256433afdef09e432410480` (`16.0.0`) — `/home/ayush/.config/nvim/lazy-lock.json` line 2; `/home/ayush/.local/share/nvim/lazy/LazyVim` `git log -1` |
| nvim-jdtls | lock `6e9d953f0b82bccdb834cfde0e893f3119c22592` — `lazy-lock.json` line 39 |
| Extra docs (same spec) | <https://www.lazyvim.org/extras/lang/java> |
| Extra upstream | <https://github.com/LazyVim/LazyVim/blob/c10948c50b18fae7f256433afdef09e432410480/lua/lazyvim/plugins/extras/lang/java.lua> |

The extra is imported because `lazyvim.json` lists it, and LazyVim's extras loader adds every non-deprecated entry from that list (`/home/ayush/.local/share/nvim/lazy/LazyVim/lua/lazyvim/plugins/xtras.lua` lines 31–46, 79–81). The starter `require("lazy").setup` spec imports `lazyvim.plugins` then `plugins` (`/home/ayush/.config/nvim/lua/config/lazy.lua` lines 17–23).

Other extras enabled in the same `lazyvim.json`: `editor.neo-tree`, `lang.json`, `lang.markdown`, `lang.rust`, `lang.toml`. None of `dap.core` or `test.core` is listed.

## What the extra spec contains

The extra file is a lazy.nvim spec table. It does not `require` other extra modules. It returns:

1. A `recommended` detector (not a plugin).
2. Four plugin specs: treesitter, optional `nvim-dap`, `nvim-lspconfig`, `nvim-jdtls`.

Official extra page: plugins marked optional are configured only if already installed (<https://www.lazyvim.org/extras/lang/java>).

### Recommended detector

```19:31:/home/ayush/.local/share/nvim/lazy/LazyVim/lua/lazyvim/plugins/extras/lang/java.lua
  recommended = function()
    return LazyVim.extras.wants({
      ft = "java",
      root = {
        "build.gradle",
        "build.gradle.kts",
        "build.xml", -- Ant
        "pom.xml", -- Maven
        "settings.gradle", -- Gradle
        "settings.gradle.kts", -- Gradle
      },
    })
  end,
```

`LazyVim.extras.wants` is true if the current buffer filetype is listed, else if a root detector finds one of the files (`/home/ayush/.local/share/nvim/lazy/LazyVim/lua/lazyvim/util/extras.lua` lines 43–56). This only drives `:LazyExtras` recommendations. It does not gate the extra once listed in `lazyvim.json`.

No Spring Boot marker (`application.properties`, `application.yml`, `spring-boot` plugin id, etc.) is in that list.

## Treesitter

The extra merges `ensure_installed = { "java" }` into `nvim-treesitter` (`java.lua` lines 33–37). LazyVim's treesitter plugin uses `opts_extend = { "ensure_installed" }` (`/home/ayush/.local/share/nvim/lazy/LazyVim/lua/lazyvim/plugins/treesitter.lua` lines 25–36). Core already installs a default language set that does **not** include `java` (same file, lines 33–49).

On this machine the Java parser is present at `/home/ayush/.local/share/nvim/site/parser/java.so`. Query files ship with nvim-treesitter at `/home/ayush/.local/share/nvim/lazy/nvim-treesitter/runtime/queries/java`.

The extra does not add `javadoc` (or any other parser).

## Mason packages

### `jdtls` (eclipse.jdt.ls) — extra, via lspconfig + mason-lspconfig

The extra sets `servers.jdtls = {}` so LazyVim's LSP layer will ask mason-lspconfig to install the `jdtls` server, then **refuses to start it** through lspconfig:

```65:79:/home/ayush/.local/share/nvim/lazy/LazyVim/lua/lazyvim/plugins/extras/lang/java.lua
  -- Configure nvim-lspconfig to install the server automatically via mason, but
  -- defer actually starting it to our configuration of nvim-jtdls below.
  {
    "neovim/nvim-lspconfig",
    opts = {
      -- make sure mason installs the server
      servers = {
        jdtls = {},
      },
      setup = {
        jdtls = function()
          return true -- avoid duplicate servers
        end,
      },
    },
  },
```

LazyVim iterates `opts.servers`, and a setup hook that returns true is treated as "do not `vim.lsp.config` / `vim.lsp.enable` this server"; the server name is still passed to `mason-lspconfig.setup({ ensure_installed = ... })` (`/home/ayush/.local/share/nvim/lazy/LazyVim/lua/lazyvim/plugins/lsp/init.lua` lines 245–275). Returning true also puts the server on `automatic_enable.exclude` (same block, `mason_exclude`).

**This machine:** Mason package `jdtls` is installed. Receipt (`/home/ayush/.local/share/nvim/mason/packages/jdtls/mason-receipt.json`):

- Registry name `jdtls`
- Source `pkg:generic/eclipse/eclipse.jdt.ls@v1.60.0`
- Binary link `jdtls` → package `jdtls`
- Share link `jdtls/lombok.jar` → `lombok.jar`

Mason registry metadata (local registry `/home/ayush/.local/share/nvim/mason/registries/github/mason-org/mason-registry/registry.json`, package `jdtls`):

- Description: "Java language server."
- Homepage: <https://github.com/eclipse/eclipse.jdt.ls>
- Category: LSP
- Also shares `jdtls/plugins/` and `jdtls/config/`

The installed tree includes Eclipse Maven (m2e) and Gradle (Buildship) importers (`org.eclipse.m2e.*`, `org.eclipse.buildship.*` jars under `packages/jdtls/plugins/`). Those are part of eclipse.jdt.ls, not a Spring extra.

### `java-debug-adapter` and `java-test` — extra *only if* `nvim-dap` is already a plugin

```39:63:/home/ayush/.local/share/nvim/lazy/LazyVim/lua/lazyvim/plugins/extras/lang/java.lua
  -- Ensure java debugger and test packages are installed.
  {
    "mfussenegger/nvim-dap",
    optional = true,
    opts = function()
      -- Simple configuration to attach to remote java debug process
      -- Taken directly from https://github.com/mfussenegger/nvim-dap/wiki/Java
      ...
    end,
    dependencies = {
      {
        "mason-org/mason.nvim",
        opts = { ensure_installed = { "java-debug-adapter", "java-test" } },
      },
    },
  },
```

`optional = true` means this spec is applied only when `nvim-dap` is already in the plugin set (LazyVim extra page: "Plugins marked as optional will only be configured if they are installed.").

`lang.java` does **not** add `nvim-dap` itself. This dogfood `lazyvim.json` does not enable `lazyvim.plugins.extras.dap.core`. `nvim-dap` is absent from `lazy-lock.json`.

Therefore the mason `ensure_installed` for `java-debug-adapter` and `java-test` is not applied here.

**This machine:** those two Mason packages are not installed. `/home/ayush/.local/share/nvim/mason/packages/` contains `codelldb`, `jdtls`, `json-lsp`, `lemminx`, `lua-language-server`, `markdown-toc`, `markdownlint-cli2`, `marksman`, `shfmt`, `stylua`, `taplo`. `/home/ayush/.local/share/nvim/mason/share/` has `jdtls` and `mason-schemas` only. `codelldb` is from `lang.rust` (`/home/ayush/.local/share/nvim/lazy/LazyVim/lua/lazyvim/plugins/extras/lang/rust.lua` lines 49–50), not from `lang.java`.

Registry metadata (same `registry.json`) if they *were* installed:

| Mason package | Source | Role |
| --- | --- | --- |
| `java-debug-adapter` | `pkg:openvsx/vscjava/vscode-java-debug@0.59.0` | "The debug server implementation for Java." Homepage <https://github.com/microsoft/java-debug>. Shares `java-debug-adapter/com.microsoft.java.debug.plugin.jar`. |
| `java-test` | `pkg:openvsx/vscjava/vscode-java-test@0.45.0` | Test runner that works with java-debug-adapter. Frameworks listed in the registry: JUnit 4 (v4.8.0+), JUnit 5 (v5.1.0+), JUnit 6 (v6.0.1+), TestNG (v6.8.0+). Homepage <https://github.com/microsoft/vscode-java-test>. |

The extra later globs those share paths into jdtls `init_options.bundles` (`java.lua` lines 150–157):

- `$MASON/share/java-debug-adapter/com.microsoft.java.debug.plugin-*jar`
- `$MASON/share/java-test/*.jar` (only if `opts.test` and the package is installed)

nvim-jdtls docs require those same JARs as eclipse.jdt.ls plugin bundles for debug and tests (`/home/ayush/.local/share/nvim/lazy/nvim-jdtls/README.md` lines 247–248, 282–292, 348–375). The extra does **not** apply nvim-jdtls's documented exclusions (`com.microsoft.java.test.runner-jar-with-dependencies.jar`, `jacocoagent.jar` — README lines 360–368); it globs every `java-test` jar.

### Mason packages the extra does not request

The extra does not `ensure_installed` `google-java-format`, `java-language-server`, `vscode-java-decompiler`, `vscode-java-dependency`, or `lemminx`. `lemminx` is present on this machine but is not referenced by `lang.java`.

## nvim-jdtls configuration the extra applies

Plugin spec: `mfussenegger/nvim-jdtls`, `ft = { "java" }`, dependency `folke/which-key.nvim` (`java.lua` lines 82–86). `which-key` is already a LazyVim core plugin (`lazy-lock.json` line 57).

### Command line

- Base: `{ vim.fn.exepath("jdtls") }` (`java.lua` lines 88–89).
- If mason is present, appends `--jvm-arg=-javaagent:$MASON/share/jdtls/lombok.jar` (lines 89–92).
- `full_cmd` then adds `-configuration` and `-data` under `stdpath("cache") .. "/jdtls/" .. project_name .. "/{config,workspace}"` (lines 104–127).

`project_name` is `vim.fs.basename(root_dir)` (lines 99–101).

### Root directory

```94:96:/home/ayush/.local/share/nvim/lazy/LazyVim/lua/lazyvim/plugins/extras/lang/java.lua
        root_dir = function(path)
          return vim.fs.root(path, vim.lsp.config.jdtls.root_markers)
        end,
```

That defers to whatever Neovim has in `vim.lsp.config.jdtls.root_markers` at runtime. Two `lsp/jdtls.lua` files exist on this machine:

- nvim-jdtls: `{".git", "gradlew", "mvnw"}` (`/home/ayush/.local/share/nvim/lazy/nvim-jdtls/lsp/jdtls.lua` lines 1–4).
- nvim-lspconfig: two-tier markers — first `mvnw` / `gradlew` / `settings.gradle` / `settings.gradle.kts` / `.git`, then `build.xml` / `pom.xml` / `build.gradle` / `build.gradle.kts` (`/home/ayush/.local/share/nvim/lazy/nvim-lspconfig/lsp/jdtls.lua` lines 53–100).

The extra does not set `root_markers` itself.

### Settings the extra sends to the server

Only this:

```135:143:/home/ayush/.local/share/nvim/lazy/LazyVim/lua/lazyvim/plugins/extras/lang/java.lua
        settings = {
          java = {
            inlayHints = {
              parameterNames = {
                enabled = "all",
              },
            },
          },
        },
```

No `java.configuration.runtimes`, format profile, Maven/Gradle settings, or Spring keys.

LazyVim core LSP already enables inlay hints globally (`lsp/init.lua` lines 36–42), so this is the jdtls-side switch for parameter-name hints.

### Start / attach

On `FileType java` and once immediately (because the plugin is filetype-loaded, so the autocmd misses the first buffer), the extra calls `require("jdtls").start_or_attach(config)` (`java.lua` lines 160–188, 283–284).

`config` is:

- `cmd` = `opts.full_cmd(opts)`
- `root_dir` = `opts.root_dir(fname)`
- `init_options.bundles` = debug/test jars if the DAP gates pass, else `{}`
- `settings` = the inlay-hints table
- `capabilities` from `blink.cmp` if that plugin exists, else `cmp-nvim-lsp`, else `nil` (lines 171–174)

`opts.jdtls` (if a user spec sets it) is merged via `extend_or_override` (lines 164–175, helper at lines 9–16). This dogfood local override does **not** set `opts.jdtls`.

`start_or_attach` is nvim-jdtls's API (`/home/ayush/.local/share/nvim/lazy/nvim-jdtls/lua/jdtls.lua` lines 36–38 → `jdtls.setup`). The extra comment notes `jdtls.setup.add_commands()` is not needed because start adds commands (`java.lua` line 179).

### Commands nvim-jdtls registers (plugin, not extra-specific)

From `jdtls.setup` (`/home/ayush/.local/share/nvim/lazy/nvim-jdtls/lua/jdtls/setup.lua` lines 193–236) and the README (`README.md` lines 219–229):

Always (once the client starts): `JdtCompile`, `JdtSetRuntime`, `JdtUpdateConfig`, `JdtJol`, `JdtBytecode`, `JdtJshell`, `JdtRestart`, `JdtUpdateMavenActiveProfiles`.

Only if `nvim-dap` is loadable **and** the server advertises `vscode.java.startDebugSession`: `JdtUpdateDebugConfig`, `JdtUpdateHotcode`. On this machine `nvim-dap` is not a plugin, so those two commands are not registered.

### Keymaps the extra adds on `LspAttach` (client name `jdtls`)

Normal mode (`java.lua` lines 198–208):

| Key | Call | Description in spec |
| --- | --- | --- |
| `<leader>cxv` | `jdtls.extract_variable_all` | Extract Variable |
| `<leader>cxc` | `jdtls.extract_constant` | Extract Constant |
| `<leader>cgs` | `jdtls.super_implementation` | Goto Super |
| `<leader>cgS` | `jdtls.tests.goto_subjects` | Goto Subjects |
| `<leader>co` | `jdtls.organize_imports` | Organize Imports |

Visual mode (lines 210–230): `<leader>cxm` extract method, `<leader>cxv` extract variable (all), `<leader>cxc` extract constant.

These refactor/test-navigation maps are **not** gated on `java-test` / `nvim-dap`. `goto_subjects` itself calls vscode-java-test commands (`/home/ayush/.local/share/nvim/lazy/nvim-jdtls/lua/jdtls/tests.lua` lines 58–126: `java.project.isTestFile`, `vscode.java.test.navigateToTestOrTarget`, falling back to `vscode.java.test.generateTests`). Without the `java-test` bundles those commands will not be on the server.

nvim-jdtls implementations:

- `organize_imports` — `jdtls.lua` lines 891–894
- `extract_*` — `jdtls.lua` lines 1083–1105
- `super_implementation` — `jdtls.lua` lines 1108–1114 (`java/findLinks`)

The extra does not map `jdtls.tests.generate` itself.

LazyVim core already maps `<leader>co` to `source.organizeImports` when that code action exists (`lsp/init.lua` lines 102–113). The extra adds a second, jdtls-specific organize-imports binding on Java buffers.

### `opts.on_attach` hook

After keymaps (and after DAP setup if gated), the extra calls `opts.on_attach(args)` if set (`java.lua` lines 275–278). That is the hook the local compile-on-save spec uses.

## DAP / debug wiring

### What the extra *would* do if `nvim-dap` + mason `java-debug-adapter` were present

1. Register one attach configuration: type `java`, request `attach`, name `Debug (Attach) - Remote`, `127.0.0.1:5005` (`java.lua` lines 43–55). Source cited in-file: <https://github.com/mfussenegger/nvim-dap/wiki/Java>.
2. Pass java-debug (and maybe java-test) jars as `init_options.bundles` (lines 150–157).
3. On `LspAttach`, `require("jdtls").setup_dap(opts.dap)` with default `opts.dap = { hotcodereplace = "auto", config_overrides = {} }` (lines 131, 235–237).
4. If `opts.dap_main` is truthy (default `{}`), `require("jdtls.dap").setup_dap_main_class_configs(opts.dap_main)` (lines 132–133, 238–240). Extra comment: set `dap_main` to `false` to skip main-class scan ("performance killer for large project").

nvim-jdtls `setup_dap` (`/home/ayush/.local/share/nvim/lazy/nvim-jdtls/lua/jdtls/dap.lua` lines 709–739):

- No-ops if `dap.adapters.java` already exists.
- Registers `dap.adapters.java` as a server on `127.0.0.1` whose port comes from the jdtls command `vscode.java.startDebugSession` (`dap.lua` lines 85–108, 739).
- If `hotcodereplace == "auto"`, on `event_hotcodereplace` with `BUILD_COMPLETE` it requests `redefineClasses` (lines 727–734).

`setup_dap_main_class_configs` discovers main classes and writes `dap.configurations.java` launch entries (`dap.lua` lines 665–698). README: `:DapNew` auto-discovers main classes when java-debug bundles are loaded (`README.md` lines 306–308).

### What this dogfood setup actually has

| Gate | Status |
| --- | --- |
| `opts.dap` default (not `false`) | yes, in extra opts |
| `LazyVim.has("nvim-dap")` | no — plugin not in lockfile / extras |
| `mason_registry.is_installed("java-debug-adapter")` | no |

All three are required (`java.lua` lines 152, 235). Result: empty `bundles`, no `setup_dap`, no remote attach table, no main-class DAP configs.

The extra does not install or configure `nvim-dap-ui`, `nvim-dap-virtual-text`, or LazyVim `dap.core`.

## Test runners

### Extra wiring (gated)

Default `test = true` (`java.lua` line 134). Test keymaps are added only if DAP gates pass **and** mason `java-test` is installed (lines 242–270). Extra comment: "custom keymaps for Java test runner (not yet compatible with neotest)" (line 244).

| Key | Call | Desc |
| --- | --- | --- |
| `<leader>tt` | `jdtls.dap.test_class` | Run All Test |
| `<leader>tr` | `jdtls.dap.test_nearest_method` | Run Nearest Test |
| `<leader>tT` | `jdtls.dap.pick_test` | Run Test |

If `opts.test` is a table, `config_overrides` is forwarded; if it is the boolean `true`, overrides are `nil` (lines 253–264).

### What nvim-jdtls's runner actually is

Not neotest. Tests go through DAP + vscode-java-test:

- Candidate search: `vscode.java.test.search.codelens` or `vscode.java.test.findTestTypesAndMethods` (`dap.lua` lines 183–222). Missing client message tells you to add vscode-java-test JARs to `init_options.bundles` (lines 209–211).
- Launch args: `vscode.java.test.junit.argument` plus `java.project.getClasspaths` with `scope = "test"` (lines 244–287).
- `TestKind`: `JUnit = 0`, `JUnit5 = 1`, `TestNG = 2` (`dap.lua` lines 111–116). TestNG can use `com.microsoft.java.test.runner.Launcher` if that runner JAR is among the bundles (lines 334–356, 372–393).
- `test_class` / `test_nearest_method` / `pick_test`: `dap.lua` lines 521–591. They require `nvim-dap` (`run` at line 432–436: "`nvim-dap` must be installed to run and debug methods").

README: debug of JUnit classes/methods needs both java-debug and vscode-java-test (`README.md` lines 247–255).

### This machine

`java-test` is not installed; `nvim-dap` is not a plugin; neotest is not in `lazy-lock.json`. The `<leader>t*` maps from this extra are not registered. `<leader>cgS` (goto subjects) is still mapped.

## Spring-specific pieces

None in the extra. Grep of `java.lua` for `spring`/`Spring` is empty except Lombok's `-javaagent` (not Spring). nvim-jdtls source and README have no Spring matches.

eclipse.jdt.ls on disk has Maven/Gradle importers (m2e, Buildship) but no Spring Boot language-server bundle.

The only Spring mention in the dogfood nvim config is a **comment** on the local compile-on-save override (next section): it names `spring-boot-devtools` as the process that watches `target/classes`. That file does not configure DevTools, Spring, or a Boot run.

## Local override: compile-on-save

File: `/home/ayush/.config/nvim/lua/plugins/java-compile-on-save.lua` (loaded because `lazy.lua` imports the `plugins` module).

```1:21:/home/ayush/.config/nvim/lua/plugins/java-compile-on-save.lua
-- Incremental compile on write via jdtls (LazyVim extra: lang.java).
-- Eclipse already imported the Maven project, so output is target/classes —
-- the same directory spring-boot-devtools watches. Without DevTools the
-- running process still will not restart; this only closes the compile gap.
return {
  {
    "mfussenegger/nvim-jdtls",
    opts = {
      on_attach = function(args)
        local buf = args.buf
        vim.api.nvim_create_autocmd("BufWritePost", {
          buffer = buf,
          group = vim.api.nvim_create_augroup("jdtls_compile_on_save_" .. buf, { clear = true }),
          callback = function()
            pcall(require("jdtls").compile, "incremental")
          end,
        })
      end,
    },
  },
}
```

This is **not** part of the extra. The extra only exposes `opts.on_attach` (`java.lua` lines 275–278).

`jdtls.compile("incremental")` sends LSP `java/buildWorkspace` with `isFullBuild = false` (`jdtls.lua` lines 956–964). Errors go to the quickfix list (`on_build_result`, lines 903–915). The README documents `:JdtCompile` / `require('jdtls').compile('full')` (`README.md` lines 221, 413).

No other local plugin spec touches Java. `lua/plugins/example.lua` is disabled (`if true then return {} end`, line 3). `lua/config/keymaps.lua` and `lua/config/autocmds.lua` have no Java hooks.

## Extra vs this machine (inventory)

| Item | Ships in `lang.java` extra | On this dogfood machine |
| --- | --- | --- |
| Extra enabled | n/a (user choice) | yes, `lazyvim.json` |
| Treesitter `java` | yes | parser present (`site/parser/java.so`) |
| Mason `jdtls` (eclipse.jdt.ls + lombok share) | yes, via `servers.jdtls = {}` | installed, `v1.60.0` |
| Lombok javaagent on jdtls cmd | yes, if mason present | mason present; `$MASON/share/jdtls/lombok.jar` exists |
| nvim-jdtls start on `ft=java` | yes | plugin locked, started by extra |
| Inlay parameter-name hints (`settings.java.inlayHints`) | yes | comes from extra; no local override |
| Refactor keymaps (`<leader>cx*`, `<leader>cg*`, `<leader>co`) | yes, on `LspAttach` | active once jdtls attaches |
| `opts.on_attach` hook | yes (empty by default) | used by local compile-on-save |
| Incremental compile on `BufWritePost` | **no** | **local only** (`java-compile-on-save.lua`) |
| Mason `java-debug-adapter` | only if `nvim-dap` already installed | **not** installed |
| Mason `java-test` | same gate | **not** installed |
| `nvim-dap` plugin / `dap.core` extra | optional consumer; extra does not add it | **not** present |
| Remote attach DAP config `:5005` | in optional `nvim-dap` spec | **not** applied |
| `setup_dap` + hot code replace `auto` | gated | **not** applied |
| Main-class DAP configs | gated (`dap_main = {}`) | **not** applied |
| Test keymaps `<leader>tt/tr/tT` | gated on DAP + `java-test` | **not** applied |
| neotest | explicitly "not yet compatible" | not installed |
| Spring Boot LS / Spring keymaps / Boot run | **none** | comment-only mention of DevTools |
| `lemminx`, `codelldb`, other mason pkgs | no | present for other extras / leftover, not `lang.java` |

## What nvim-jdtls can do that the extra does not map

From the plugin README (`README.md` lines 20–43, 196–229) and source, available once jdtls is attached, even without extra keymaps:

- LSP code-action extensions: generate constructors, `toString`, `hashCode`/`equals`, delegate methods, move, signature refactor
- `extended_symbols`, `javap` (`:JdtBytecode`), `jol` (`:JdtJol`, needs `jol_path`), `jshell` (`:JdtJshell`)
- `:JdtUpdateConfig`, `:JdtSetRuntime`, `:JdtRestart`, `:JdtUpdateMavenActiveProfiles`
- `:JdtCompile [full|incremental]`
- `jdtls.tests.generate()` (needs vscode-java-test)

The extra maps a subset (extract / organize / goto super / goto subjects / optional DAP tests). It does not wrap the code-action generators or jshell/javap.

## Sources

- Extra: `/home/ayush/.local/share/nvim/lazy/LazyVim/lua/lazyvim/plugins/extras/lang/java.lua`
- Extra HTML: <https://www.lazyvim.org/extras/lang/java>
- Extra loader: `/home/ayush/.local/share/nvim/lazy/LazyVim/lua/lazyvim/plugins/xtras.lua`
- LazyVim LSP/mason: `/home/ayush/.local/share/nvim/lazy/LazyVim/lua/lazyvim/plugins/lsp/init.lua`
- LazyVim treesitter: `/home/ayush/.local/share/nvim/lazy/LazyVim/lua/lazyvim/plugins/treesitter.lua`
- nvim-jdtls: `/home/ayush/.local/share/nvim/lazy/nvim-jdtls/README.md`, `lua/jdtls.lua`, `lua/jdtls/dap.lua`, `lua/jdtls/tests.lua`, `lua/jdtls/setup.lua`, `lsp/jdtls.lua`
- nvim-lspconfig jdtls: `/home/ayush/.local/share/nvim/lazy/nvim-lspconfig/lsp/jdtls.lua`
- Mason registry (local): `/home/ayush/.local/share/nvim/mason/registries/github/mason-org/mason-registry/registry.json`
- Mason jdtls receipt: `/home/ayush/.local/share/nvim/mason/packages/jdtls/mason-receipt.json`
- Dogfood config: `/home/ayush/.config/nvim/lazyvim.json`, `lua/config/lazy.lua`, `lua/plugins/java-compile-on-save.lua`, `lazy-lock.json`
