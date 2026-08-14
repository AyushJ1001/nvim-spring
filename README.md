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

## Run and Reload

`:SpringRun` starts vanilla `spring-boot:run` in a Plugin-owned terminal buffer. It prefers `./mvnw` when a wrapper exists, otherwise `mvn`. There is no profile picker, no extra-args UI, no exploded-`java` launcher, and no `java -jar` Reload path. Missing `mvnw` and `mvn` is a loud-refuse.

`:SpringStop` stops only the Plugin-started process. A `spring-boot:run` you started yourself is not hijacked.

**Reload** is Spring Boot DevTools automatically restarting the application context when classes and resources land in Maven `target/classes`. It is not LiveReload, not JRebel-style rewrite, and not JVM hot-swap. There is no trigger file — DevTools uses its default poll and quiet period.

The Plugin owns compile-on-save: incremental jdtls compile of `.java` files, plus a copy of `src/main/resources` (including `application.yml`, templates, and static) into `target/classes`. A user-started `spring-boot:run` still Reloads when that compile, DevTools, and an exploded Maven run are in place.

If `spring-boot-devtools` is not on the runtime classpath, the app still starts. The Plugin says Reload will not happen and offers to add the Dependency through the add-Dependency path. It never silent-edits the POM.

### Debug

Generic DAP is compose-if-present only. This Plugin does not add a Spring-specific debug launch, attach, Actuator live, or test-debug.

Reload and DAP Hot Code Replace fight if a debugger is attached to a Plugin-started `spring-boot:run`. The Plugin does not detect JDWP and does not disable DevTools while debugging.

Spring-specific debugging is next-version WIP.

## Workspace contract

First cut is one non-reactor Maven project at the workspace root, Spring Boot 3.0+ / 4.x at **Language level** 17+.

- **Gradle** roots and Maven reactors: **Build tool** actions loud-refuse as not implemented yet. No Gradle file is written.
- Boot 2 and Language levels 11/8: Plugin actions loud-refuse as out of contract.
- Those refuses do not detach jdtls.

## Tests

```sh
luajit tests/run.lua
```
