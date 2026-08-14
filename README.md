# nvim-spring

A Neovim **Plugin** for general Java and Spring Boot work. Install it from this GitHub repo. It is LazyVim-blind: it does not require `lazyvim` or `lang.java`.

## Install

lazy.nvim:

```lua
{
  "AyushJ1001/nvim-spring",
  opts = {},
}
```

Or any other manager that puts the repo on `runtimepath` and calls `require("nvim-spring").setup()`.

## Setup

```lua
require("nvim-spring").setup({
  -- One Initializr base URL (https or http).
  initializr_url = "https://start.spring.io",
  -- Recommended <leader>s skin. Set false to ship no maps.
  keymaps = true,
})
```

`nvim-jdtls` is an optional **Plugin dependency**. If it is present and no jdtls client is running, the Plugin starts a minimal one (no extra keybinds, no DAP). If a client is already up, it is left alone. Missing nvim-jdtls is fine.

## Commands

| Command | Action |
| --- | --- |
| `:SpringInit` | Initializr Wizard |
| `:SpringCreate` | Scaffold Wizard |
| `:SpringPackages` | Package view |
| `:SpringAddDependency` | add a Dependency |
| `:SpringRun` | start `spring-boot:run` |
| `:SpringStop` | stop the Plugin-started process |

Recommended maps (not a frozen chord contract): `<leader>si`, `<leader>sc`, `<leader>sp`, `<leader>sa`, `<leader>sr`, `<leader>ss`.

## Workspace contract

First cut is one non-reactor Maven project at the workspace root, Spring Boot 3.0+ / 4.x at **Language level** 17+.

- **Gradle** roots and Maven reactors: **Build tool** actions loud-refuse as not implemented yet. No Gradle file is written.
- Boot 2 and Language levels 11/8: Plugin actions loud-refuse as out of contract.
- Those refuses do not detach jdtls.

## Tests

```sh
luajit tests/run.lua
```
