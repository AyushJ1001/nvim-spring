# What the existing Java and Spring editor ecosystem already covers

Ticket: [AyushJ1001/nvim-spring#2](https://github.com/AyushJ1001/nvim-spring/issues/2).

This is a fact record from **primary sources** (upstream docs, first-party READMEs, source on disk). It does not recommend a composition boundary.

The four opening surfaces named on the wayfinder map ([#1](https://github.com/AyushJ1001/nvim-spring/issues/1)) are:

1. **Project initialization** — generate a new Spring Boot project (typically via start.spring.io / Initializr).
2. **Scaffolds + package view** — create a Java type or Spring stereotype with the correct package / filename / boilerplate, and browse by source roots and packages rather than raw filesystem paths. Terms: `Scaffold`, `Package`, `Package view` (`CONTEXT.md`).
3. **Add-dependency from an unresolved import** — when a type is not on the classpath, add the corresponding Maven/Gradle dependency to the build file (not merely organize an import that is already on the classpath).
4. **Spring Boot run/reload** — start a Spring Boot application from the editor, and get reload after a change. Reload here includes both Spring Boot DevTools (classpath-directory watch → restart) and debugger Hot Code Replace. They are different mechanisms.

Legend for the per-surface verdict: **covers** / **partial** / **empty**.

---

## Coverage matrix

| Tool | Project initialization | Scaffolds + package view | Add-dependency from unresolved import | Spring Boot run/reload |
| --- | --- | --- | --- | --- |
| Eclipse JDT Language Server | empty | empty (no explorer UI; project/source data only) | empty | partial (autobuild / `java/buildWorkspace`; not Boot-aware) |
| `mfussenegger/nvim-jdtls` | empty | empty | empty | partial (explicit compile; DAP Hot Code Replace; not Boot-aware) |
| LazyVim `lang.java` extra | empty | empty | empty | partial (wires nvim-jdtls DAP + remote attach; no Boot run, no compile-on-save) |
| `nvim-java/nvim-java` | empty | empty | empty | partial (built-in `java -cp` runner + optional STS4 language server; no DevTools compile-on-save) |
| `JavaHello/spring-boot.nvim` | empty | empty | empty | empty (STS4 language features only) |
| `elmcgill/springboot-nvim` | covers (via Spring Boot CLI) | partial (class/interface/enum/record scaffolds; no package view) | empty | partial (`mvn spring-boot:run` / `gradlew bootRun` + incremental `jdtls.compile` on save) |
| `jkeresman01/spring-initializr.nvim` | covers | empty | empty | empty |
| `lazerfit/spring-gen.nvim` | covers | partial (stereotype scaffolds; no package view) | empty | partial (managed terminal run/stop; no DevTools compile-on-save) |
| VS Code Language Support for Java (Red Hat) | empty | partial (new-file templates; no package view) | empty | partial (autobuild / force compile; not Boot-aware) |
| VS Code Project Manager for Java | partial (create Java project, not Spring Initializr) | covers (Java Projects explorer + new class/package) | empty (JAR referenced libraries, not Maven/Gradle from an import) | empty |
| VS Code Maven for Java | partial (Maven archetype, not Initializr) | empty (Maven tree, not Java package view) | empty (has `maven.project.addDependency`, not from an unresolved import) | empty |
| VS Code Spring Initializr | covers | empty | partial (`Edit starters` on an existing Maven `pom.xml`, not from an import) | empty |
| VS Code Spring Boot Tools (STS4) | empty | empty | empty | partial (live JMX/actuator hovers; not DevTools compile/restart) |
| VS Code Spring Boot Dashboard | empty | empty | empty | covers (start / stop / debug Boot apps; not DevTools) |
| VS Code Debugger for Java | empty | empty | empty | partial (run/debug + Hot Code Replace; not DevTools) |
| Spring Boot CLI (`spring init`) | covers | empty | empty | empty |
| Spring Boot DevTools (runtime, not an editor) | empty | empty | empty | covers reload **if** the editor writes class files onto a watched classpath directory |

No first-party tool in this set implements “add a Maven/Gradle dependency from an unresolved import” as a single action. Closest neighbors: Maven `addDependency`, Initializr `Edit starters`, JDT organize-imports of types already on the classpath.

---

## Eclipse JDT Language Server

**Sources:** [eclipse.jdt.ls README](https://github.com/eclipse-jdtls/eclipse.jdt.ls/blob/master/README.md); [wiki: Running the JAVA LS server from the command line](https://raw.githubusercontent.com/wiki/eclipse-jdtls/eclipse.jdt.ls/Running-the-JAVA-LS-server-from-the-command-line.md).

### What it does

A Java implementation of the Language Server Protocol. It is based on Eclipse LSP4J, Eclipse JDT, M2Eclipse (Maven), and Buildship (Gradle). Documented features:

- Compiling projects from Java 1.8 through 25.
- Maven `pom.xml` and Gradle project support (experimental Android import).
- Standalone Java files.
- As-you-type syntax/compilation errors, completion, Javadoc hovers, organize imports, type search, code actions (quick fixes, source actions, refactorings), outline, folding, navigation, code lens, formatting, snippets, semantic highlighting, diagnostic tags, call/type hierarchy.
- Annotation processing (automatic for Maven).
- Automatic source resolution for classes in jars with Maven coordinates.
- Extensibility via extra OSGi bundles (`initializationOptions.bundles`).

The initialize request accepts `bundles`, `workspaceFolders`, and a large `settings.java` tree. Documented settings that matter for the four surfaces:

- `java.autobuild.enabled` — default **true** (wiki `EnabledOption` on `autobuild`).
- `java.configuration.updateBuildConfiguration` — how pom/gradle edits refresh the classpath (`disabled` / `interactive` / `automatic`).
- `java.project.referencedLibraries` — glob patterns for **local JARs**, not Maven coordinates.
- `java.templates.*` — file-header / type-comment / method-body snippets used when a client creates a new compilation unit.
- `java.saveActions.organizeImports` / `cleanup` — on-save cleanups.

The server is **not** a Spring Initializr, **not** a package explorer, and **not** a Boot runner. Clients consume LSP + off-spec JDT methods (`java/buildWorkspace`, `java/projectConfigurationUpdate`, `java/organizeImports`, `java/classFileContents`, `java.project.getAll`, `java.project.getSettings`, `java.project.updateSettings`, …).

### Requires

- **Host tool:** a JDK **21+** to *run* the server (`JAVA_HOME` or `PATH`). Projects may target JDK ≥ 8 if `java.configuration.runtimes` is set.
- Optional Python 3.9 if using the official `jdtls` wrapper script.
- A unique `-data` directory per workspace.
- Optional extra JARs in `bundles` (java-debug, vscode-java-test, STS4 jdtls extensions, Microsoft `jdtls.ext.core`, Maven JDT plugin, …).

### Four surfaces

| Surface | Verdict | Fact |
| --- | --- | --- |
| Project initialization | empty | No Initializr or project-generator endpoint. |
| Scaffolds + package view | empty | Templates exist for *clients* that create files. No package-explorer protocol. `java.project.getAll` / source-path settings are lists, not a package view. |
| Add-dependency from unresolved import | empty | Organize-imports / completion only for types already on the classpath. `referencedLibraries` is local JARs. Newly added Maven/Gradle deps require a project-config refresh (`java/projectConfigurationUpdate`). |
| Spring Boot run/reload | partial | Autobuild / `java/buildWorkspace` compile into the JDT output location (M2E/Buildship typically `target/classes` / Gradle output). No Boot run, no DevTools trigger-file UI. |

---

## `mfussenegger/nvim-jdtls`

**Sources:** [README](https://raw.githubusercontent.com/mfussenegger/nvim-jdtls/master/README.md); [`lua/jdtls.lua`](https://raw.githubusercontent.com/mfussenegger/nvim-jdtls/master/lua/jdtls.lua); [`lua/jdtls/setup.lua`](https://raw.githubusercontent.com/mfussenegger/nvim-jdtls/master/lua/jdtls/setup.lua).

### What it does

A thin Neovim client for eclipse.jdt.ls. Audience: users who already know Neovim, Java, Maven/Gradle; KISS, configuration-as-code. It starts/attaches jdtls and implements the extra client commands JDT LS expects (`java.apply.workspaceEdit`, organize-imports picker, generate constructors / toString / hashCodeEquals / delegates / override methods, extract/move/change-signature).

Documented extras:

- `organize_imports`, `extract_variable`, `extract_variable_all`, `extract_constant`, `extract_method`.
- Open class-file contents (`jdt://` / `java.decompile`).
- `extended_symbols`, `javap`, `jol`, `jshell`.
- Commands once attached: `JdtCompile`, `JdtSetRuntime`, `JdtUpdateConfig`, `JdtBytecode`, `JdtJol`, `JdtJshell`, `JdtRestart`, `JdtUpdateMavenActiveProfiles`, `JdtShowMavenActiveProfiles`.
- With nvim-dap + java-debug bundle: auto-discover main classes, `JdtUpdateDebugConfig`, `JdtUpdateHotcode` (DAP `redefineClasses`).
- With vscode-java-test bundles: `test_class` / `test_nearest_method` / `pick_test`, `jdtls.tests.generate()`, `goto_subjects()`.

`require('jdtls').compile(type)` sends `java/buildWorkspace` (`full` or `incremental`) and fills the quickfix list.

`JdtUpdateHotcode` is **debugger Hot Code Replace**, not Spring Boot DevTools.

There is no Initializr UI, no new-class scaffold API, no package view, no “add Maven dependency” command.

### Requires

- **Plugin:** itself; Neovim ≥ 0.6 (latest stable recommended).
- **Host tool:** eclipse.jdt.ls on `PATH` (`jdtls` wrapper needs Python 3.9) **or** a raw `java` command line. Java 21+ to run the server.
- **Optional plugin:** `mfussenegger/nvim-dap` for debug/test.
- **Optional host artifacts:** java-debug plugin JAR; vscode-java-test `server/*.jar` (excluding the runner and jacocoagent).

### Four surfaces

| Surface | Verdict |
| --- | --- |
| Project initialization | empty |
| Scaffolds + package view | empty |
| Add-dependency from unresolved import | empty (`:JdtUpdateConfig` only *refreshes* after the user edits the build file) |
| Spring Boot run/reload | partial — compile + debug HCR; no Boot-specific run |

---

## LazyVim `lang.java` extra

**Source on disk:** `/home/ayush/.local/share/nvim/lazy/LazyVim/lua/lazyvim/plugins/extras/lang/java.lua` (read in full for this ticket).

### What it does

A LazyVim extra that is recommended when the buffer filetype is `java` or the root has `build.gradle`, `build.gradle.kts`, `build.xml`, `pom.xml`, `settings.gradle`, or `settings.gradle.kts`.

It:

1. Adds Treesitter `java`.
2. If `nvim-dap` is present, installs Mason packages `java-debug-adapter` and `java-test`, and registers a single DAP config: **attach** to `127.0.0.1:5005` named `Debug (Attach) - Remote`.
3. Registers `jdtls` in `nvim-lspconfig` but `setup.jdtls` **returns `true`** so lspconfig does not start a second server.
4. Starts `mfussenegger/nvim-jdtls` on `ft = "java"`:
   - `cmd` is `exepath("jdtls")`, plus `--jvm-arg=-javaagent:$MASON/share/jdtls/lombok.jar` when Mason is present.
   - Per-project cache dirs: `stdpath("cache")/jdtls/<project>/config` and `.../workspace`.
   - `init_options.bundles` = java-debug plugin JAR + java-test JARs when installed.
   - `dap = { hotcodereplace = "auto" }`, `dap_main = {}`, `test = true`.
   - Inlay hints: `java.inlayHints.parameterNames.enabled = "all"`.
5. On `LspAttach` for client `jdtls`, which-key maps:
   - extract variable/constant/method, goto super, goto test subjects, organize imports.
   - `jdtls.setup_dap` + `setup_dap_main_class_configs`.
   - test class / nearest method / pick test.

The extra does **not** register `BufWritePost` compile, a Boot run command, an Initializr, scaffolds, a package view, or any add-dependency action.

### Requires

- **Plugin dependencies (via LazyVim):** `nvim-treesitter`, `nvim-lspconfig`, `mfussenegger/nvim-jdtls`, `folke/which-key.nvim`. Optional: `nvim-dap`, `mason.nvim`, `blink.cmp` or `cmp-nvim-lsp`.
- **Host tools (via Mason when present):** `jdtls`, `java-debug-adapter`, `java-test`, Lombok jar shipped with Mason’s jdtls. Underlying: Java 21+ for the language server.

### Four surfaces

| Surface | Verdict |
| --- | --- |
| Project initialization | empty |
| Scaffolds + package view | empty |
| Add-dependency from unresolved import | empty |
| Spring Boot run/reload | partial — debugger attach + auto HCR + main-class DAP configs; **no** Boot run, **no** compile-on-save for DevTools |

---

## `nvim-java/nvim-java`

**Sources:** [README](https://raw.githubusercontent.com/nvim-java/nvim-java/main/README.md); [`lua/java.lua`](https://raw.githubusercontent.com/nvim-java/nvim-java/main/lua/java.lua); [`lua/java/startup/lsp_setup.lua`](https://raw.githubusercontent.com/nvim-java/nvim-java/main/lua/java/startup/lsp_setup.lua); [`lua/java-runner/runner.lua`](https://raw.githubusercontent.com/nvim-java/nvim-java/main/lua/java-runner/runner.lua); [`plugin/java.lua`](https://raw.githubusercontent.com/nvim-java/nvim-java/main/plugin/java.lua).

### What it does

An all-in-one Neovim Java stack: auto-installs JDT LS and optional VS Code extension roots, then starts jdtls via `vim.lsp.config` / `vim.lsp.enable('jdtls')`. README feature list: Spring Boot Tools, diagnostics/completion, automatic debug config, organize imports & formatting, running tests, run & debug profiles, built-in application runner with log viewer, profile management UI, decompiler, code actions.

`setup()` (source) installs via its own `pkgm`:

- `jdtls` (default version `1.43.0`, `auto_install = true`)
- `java-test` `0.40.1`
- `java-debug-adapter` `0.58.2`
- `spring-boot-tools` `1.55.1` (VS Code extension root; passed to `JavaHello/spring-boot.nvim`)
- `lombok` `1.18.40`
- `openjdk` 17 if `jdk.auto_install`

When `spring_boot_tools.enable`, it `require('spring_boot').setup({ ls_path = <ext>/language-server })` and `init_lsp_commands()`, and adds the `spring-boot-tools` JDT bundle.

The built-in runner (`JavaRunnerRunMain`) asks JDT/DAP for main-class configs, then execs:

```text
java_exec [vm_args] -cp <classPaths> mainClass [prog_args]
```

That is a **plain JVM launch**, not `mvn spring-boot:run` / `gradlew bootRun`. It has stop / toggle logs / switch run / a profile UI. It is not DevTools-aware.

README still documents `JavaBuildBuildWorkspace`, `JavaBuildCleanWorkspace`, and extract-refactor commands. Current `plugin/java.lua` only registers: runtime change, DAP config, test run/debug, runner, profile. Cite the plugin file as the live command set; the README is broader than the plugin file on this snapshot.

There is no Initializr, no new-class/stereotype scaffold, no package view, no add-dependency command.

Architecture note in the README: nvim-java talks to JDT LS the way VS Code’s Extension Pack for Java does, loading `java-test` and `java-debug-adapter` as JDT extensions. Spring Boot language features are delegated to `spring-boot.nvim`.

### Requires

- **Host:** Neovim **0.11.5+**.
- **Plugin dependencies (README install examples):** `JavaHello/spring-boot.nvim`, `MunifTanjim/nui.nvim`, `mfussenegger/nvim-dap`. Conflicts with a separately configured `nvim-jdtls` (startup check `nvim_jdtls_conflict`).
- **Host tools it can auto-install:** JDT LS, JDK 17, Lombok, VS Code-format `java-test` / `java-debug-adapter` / `spring-boot-tools` extension trees. `path` may point at an already-installed copy.

### Four surfaces

| Surface | Verdict |
| --- | --- |
| Project initialization | empty |
| Scaffolds + package view | empty |
| Add-dependency from unresolved import | empty |
| Spring Boot run/reload | partial — JVM main runner + optional STS4 language server; no compile-on-save, no DevTools trigger |

---

## Similar Neovim wrappers

### `JavaHello/spring-boot.nvim`

**Sources:** [README_en.md](https://raw.githubusercontent.com/JavaHello/spring-boot.nvim/main/README_en.md); used by nvim-java as above.

Adapts **VS Code Spring Boot Tools** (STS4) into Neovim:

- Find beans (Spring-annotated) and web endpoints via LSP workspace symbols.
- Completion + navigation for `application.properties` / `application.yml`.
- Annotation dependency hints.
- Code actions.

It starts the STS4 language server (jars from Mason or `~/.vscode/extensions/vmware.vscode-spring-boot-*`) and injects STS4 JDT extension jars into jdtls `bundles`.

**Requires:** a jdtls client (`nvim-jdtls`, nvim-java, or nvim-lspconfig); optional `fzf-lua` / telescope for symbol UI; optional VS Code Spring Boot extension on disk.

**Four surfaces:** all empty except that STS4 live-hover / property intelligence can appear *while* an app is already running with actuator/JMX. The plugin does not start or reload the app.

### `elmcgill/springboot-nvim`

**Sources:** [README](https://raw.githubusercontent.com/elmcgill/springboot-nvim/main/README.md); [`lua/springboot-nvim/init.lua`](https://raw.githubusercontent.com/elmcgill/springboot-nvim/main/lua/springboot-nvim/init.lua); [`lua/create_springboot_project.lua`](https://raw.githubusercontent.com/elmcgill/springboot-nvim/main/lua/create_springboot_project.lua); [`lua/springboot-nvim/generateclass.lua`](https://raw.githubusercontent.com/elmcgill/springboot-nvim/main/lua/springboot-nvim/generateclass.lua).

Implemented:

1. `BufWritePost *.java` → `jdtls.compile("incremental")` (DevTools can then see `target/classes` / Gradle output change).
2. `boot_run` opens a split terminal and sends `mvn spring-boot:run` or `./gradlew bootRun`.
3. `BufReadPost *.java` on an empty file inserts a `package` line derived from the path under `src/`.
4. UI to generate class / interface / enum / record: writes `package …; public class Name{}` under `…/java/<package>/<Name>.java`, creating directories with `mkdir -p`.
5. `:SpringBootNewProject` — GET `https://start.spring.io/metadata/client`, prompt for build/language/Java/Boot/packaging/deps/GAV, then shells:

   `spring init --boot-version=… --java-version=… --build=… --dependencies=… --groupId=… --artifactId=… --name=… --package-name=… <name>`

   Requires the **Spring Boot CLI** host tool (`sdk install springboot` or `brew install spring-boot`). README also claims it “fetches from start.spring.io”; the implementation uses the metadata HTTP API plus the CLI, not a direct zip download.

**Requires:** plugin deps `nvim-lspconfig`, `nvim-jdtls`; optional `nvim-tree` (README lists it; recommended snippet omits it). Host: `curl` (metadata), `spring` CLI (generate), `fd` (opens first Java file after generate), Maven or Gradle to run.

**Four surfaces:** init **covers**; scaffolds **partial** (generic Java types, not Spring stereotypes; no package view); add-dep **empty**; run/reload **partial** (Boot run + incremental compile on save; DevTools must already be on the project).

### `jkeresman01/spring-initializr.nvim`

**Source:** [README](https://raw.githubusercontent.com/jkeresman01/spring-initializr.nvim/main/README.md).

TUI for start.spring.io inside Neovim. Commands: `:SpringInitializr`, `:SpringGenerateProject` (writes into cwd), `:SpringInitializrConfig`, `:SpringInitializrLog`. Fields: language, Java version, group/artifact, Boot version, dependencies (Telescope picker).

**Requires:** Neovim 0.9+; plugins `nui.nvim`, `plenary.nvim`, `telescope.nvim`. Network access to the Initializr service (default start.spring.io).

**Four surfaces:** init **covers**; the other three **empty**.

### `lazerfit/spring-gen.nvim`

**Source:** [README](https://raw.githubusercontent.com/lazerfit/spring-gen.nvim/main/README.md).

- Project initializer from `start.spring.io` (host tools: `curl`, `unzip`).
- Component generator: Controllers, Services, Repositories, “and more” via templates; directory pick uses `snacks.nvim`.
- Managed split-terminal run/stop with `vim.notify` on `Started…` / `BUILD FAILED`.

**Requires:** Neovim ≥ 0.9; `curl`; `unzip`; plugin `folke/snacks.nvim`. Optional `nvim-notify`.

**Four surfaces:** init **covers**; scaffolds **partial** (Spring stereotypes, no package view); add-dep **empty**; run/reload **partial** (terminal run/stop, no compile-on-save).

---

## Spring Initializr / start.spring.io — first-party and Neovim

**Sources:** [spring-io/initializr README](https://raw.githubusercontent.com/spring-io/initializr/main/README.adoc); vscode-spring-initializr README; Spring Boot CLI mentioned by initializr as a supported interface; Neovim plugins above.

### The service itself

Spring Initializr exposes:

- A metadata model (dependencies, JVM versions, platform versions).
- Web endpoints to generate a project zip and to serve metadata for third-party clients (`initializr-web`).
- Production instance: https://start.spring.io (config in [spring-io/start.spring.io](https://github.com/spring-io/start.spring.io)).

First-party **supported interfaces** listed by Initializr:

- Command line: Spring Boot CLI, or `curl` / HTTPie.
- IDEs: STS, IntelliJ IDEA Ultimate, NetBeans + `nb-springboot`, VS Code + [microsoft/vscode-spring-initializr](https://github.com/microsoft/vscode-spring-initializr).
- Custom web UI (start.spring.io).

Neovim is **not** a listed first-party client. Existing Neovim clients are third-party (above).

### VS Code Spring Initializr (`vscjava.vscode-spring-initializr`)

**Source:** [README](https://raw.githubusercontent.com/microsoft/vscode-spring-initializr/main/README.md).

- Generate Maven/Gradle Spring Boot projects.
- Customize language, Java version, groupId, artifactId, boot version, dependencies (search).
- Quickstart with last settings.
- **Edit Spring Boot dependencies of an existing Maven Spring Boot project** (`Edit starters` on `pom.xml`). Gradle edit-starters is explicitly *not* supported.

Settings: `spring.initializr.serviceUrl` default `https://start.spring.io`; defaults for language/Java/GAV/packaging/open method.

**Requires:** VS Code ≥ 1.19; JDK ≥ 1.8.

**Four surfaces:** init **covers**; scaffolds + package view **empty**; add-dep **partial** (starters on an existing Maven pom, not from an unresolved import); run/reload **empty**.

### Spring Boot CLI `spring init`

Named by Initializr as a first-party CLI. `elmcgill/springboot-nvim` shells out to it. It is a **host tool**, not an editor plugin.

---

## VS Code Java (Extension Pack + pieces)

### Extension Pack for Java (`vscjava.vscode-java-pack`)

**Source:** [README](https://raw.githubusercontent.com/microsoft/vscode-java-pack/main/README.md).

Bundles:

| Extension | Role the pack states |
| --- | --- |
| Language Support for Java by Red Hat (`redhat.java`) | Navigation, completion, refactoring, snippets |
| Debugger for Java | Debugging |
| Test Runner for Java | JUnit/TestNG |
| Maven for Java | Project scaffolding (archetypes), custom goals |
| Gradle for Java | Tasks, dependencies, Gradle file authoring, Gradle Build Server import |
| Project Manager for Java | Manage projects, referenced libraries, resource files, **packages, classes, class members** |

The pack **recommends** Spring Tools 4 / Spring Boot Extension Pack separately. It does not include Initializr or Boot Dashboard.

### Language Support for Java by Red Hat (`redhat-developer/vscode-java`)

**Source:** [README](https://raw.githubusercontent.com/redhat-developer/vscode-java/master/README.md).

VS Code client for eclipse.jdt.ls. Feature list matches JDT LS (Java 1.8–26, Maven/Gradle, completion, code/source actions, organize imports on save or paste, snippets, inlay hints, …).

Commands relevant here:

- `Java: Reload Projects` — refresh classpath after build-file changes.
- `Java: Force Java Compilation` / `Rebuild Projects`.
- `Java: Import Java Projects into Workspace`.
- Source-path add/remove (unmanaged folders only).
- `java.autobuild.enabled`, `java.configuration.updateBuildConfiguration`.
- `java.templates.newFile.enabled` — auto class body + package declaration when creating a new Java file (default true).

**Requires:** VS Code; on supported platforms an **embedded JRE** launches the language server; project JDKs via `java.configuration.runtimes`. Java 21+ for the tooling JRE on the universal build.

**Four surfaces:** init empty; scaffolds **partial** (new-file template, no package view); add-dep empty; run/reload **partial** (autobuild / force compile).

### Project Manager for Java (`microsoft/vscode-java-dependency`)

**Sources:** [README](https://raw.githubusercontent.com/microsoft/vscode-java-dependency/main/README.md); [`package.json`](https://raw.githubusercontent.com/microsoft/vscode-java-dependency/main/package.json).

This is the **package view** in the VS Code Java ecosystem: view `javaProjectExplorer` (“Java Projects”). `java.dependency.packagePresentation` is `flat` or `hierarchical`. It ships its own JDT LS extension JAR (`contributes.javaExtensions`: `com.microsoft.jdtls.ext.core-*.jar`) — the tree is **not** provided by stock eclipse.jdt.ls.

Commands (package.json):

- `java.project.create` — create a Java project (not Spring Initializr).
- `java.view.package.newJavaClass` / `newJavaInterface` / `newJavaEnum` / `newJavaRecord` / `newJavaAnnotation` / `newJavaAbstractClass` / `newPackage` / `newFile` / `newFolder`.
- `java.project.addLibraries` / `addLibraryFolders` / `removeLibrary` — **Referenced Libraries** (JARs / folders), including `java.project.referencedLibraries` globs.
- Build / rebuild / clean / update project.

**Requires:** VS Code ≥ 1.95; Language Support for Java by Red Hat.

**Four surfaces:** init **partial** (non-Spring Java project); scaffolds + package view **covers** (generic Java types, not Spring stereotypes); add-dep **empty** for Maven/Gradle-from-import (JAR libs only); run/reload empty.

### Maven for Java (`microsoft/vscode-maven`)

**Sources:** [README](https://raw.githubusercontent.com/microsoft/vscode-maven/main/README.md); [`package.json`](https://raw.githubusercontent.com/microsoft/vscode-maven/main/package.json).

- Maven explorer (projects + modules + plugins/goals).
- Generate from Maven Archetype (`maven.archetype.generate`).
- POM completion including GAV (`maven.completion.gavEnabled`).
- `maven.project.addDependency` — command palette / Maven explorer / Java Project Explorer Maven container. **Not** bound to an unresolved Java import.
- Lifecycle goals, history, favorites, effective POM, new module.
- Ships `com.microsoft.java.maven.plugin` as a JDT LS extension.

**Requires:** Java; Maven or Maven Wrapper.

**Four surfaces:** init **partial** (archetype, not Initializr); package view empty; add-dep **empty** for the “from unresolved import” action (manual add-dependency exists); run/reload empty (can run `spring-boot:run` as *a* Maven goal, but that is not Boot-aware UX).

### Debugger for Java (`microsoft/vscode-java-debug`)

**Source:** [README](https://raw.githubusercontent.com/microsoft/vscode-java-debug/main/README.md).

Launch/attach, breakpoints, no-config `debugjava`, run/debug code lens over main methods, **Hot Code Replace** (`java.debug.settings.hotCodeReplace`: `manual` / `auto` / `never`). `auto` applies after compilation when `java.autobuild.enabled` is on. This is JDWP redefine-classes, with the limitations of the JVM (typically no schema changes).

**Requires:** JDK ≥ 1.8; VS Code ≥ 1.19; `redhat.java` ≥ 0.14.

**Four surfaces:** run/reload **partial** (run + HCR). Others empty.

---

## VS Code Spring Boot Tools

### Spring Boot Extension Pack (`vmware.vscode-boot-dev-pack`)

**Source:** [Marketplace page](https://marketplace.visualstudio.com/items?itemName=vmware.vscode-boot-dev-pack) (first-party pack description).

Bundles:

1. **Spring Boot Tools** (`Pivotal.vscode-spring-boot` / `vmware.vscode-spring-boot`) — Java + `.properties`/`.yml` Spring tooling.
2. **Spring Initializr Java Support** — generate Boot projects.
3. **Spring Boot Dashboard** — explorer to start/stop/debug Boot apps.

### Spring Boot Tools / STS4 language server

**Sources:** [vscode-spring-boot README](https://raw.githubusercontent.com/spring-projects/sts4/main/vscode-extensions/vscode-spring-boot/README.md); [spring-projects/spring-tools README](https://raw.githubusercontent.com/spring-projects/spring-tools/main/README.md).

Activates on `*.java`, `application*.properties`, `application*.yml`.

For `.java`:

- Workspace/file symbols filtered to Spring elements (`@/` request mappings, `@+` beans, `@>` functions, `@` annotations).
- Live-app symbols (`//` mappings of **running** apps) and live hovers / code lenses (active profiles, bean wiring, `@ConditionalOn…` evaluation).
- Live data is scraped over **JMX from Spring Boot Actuator**. Requires `spring-boot-starter-actuator`. Since Boot 2.2, JMX actuator endpoints are off by default; apps must start with `-Dspring.jmx.enabled=true`.
- Command: “Manage Live Spring Boot Process Connections”.
- Templates (`@GetMapping` etc.) and smart completions (`@Value` keys, `@Scope` names).

For `.properties` / `.yml`: classpath-indexed Spring Boot configuration metadata → validation, completion, hovers. Maven and Gradle projects.

**Depends on** Language Support for Java by Red Hat.

**Four surfaces:** init empty; scaffolds + package view empty; add-dep empty; run/reload **partial** (observes a running process; does not start it; not DevTools compile).

### Spring Boot Dashboard (`microsoft/vscode-spring-boot-dashboard`)

**Source:** [README](https://raw.githubusercontent.com/microsoft/vscode-spring-boot-dashboard/main/README.md).

- View Boot apps in the workspace.
- Start / stop / debug.
- Open in browser.
- List beans / endpoint mappings; view bean dependencies.

**Requires:** JDK ≥ 1.8; VS Code ≥ 1.19; **Debugger for Java** and **Spring Boot Tools**.

**Four surfaces:** Boot run **covers** (start/stop/debug). Reload is whatever the launched process does (DevTools if on the classpath; debugger HCR if debugging). Init / scaffolds / add-dep empty.

---

## First-party pieces for the four surfaces (inventory)

### Project initialization

| First-party | What |
| --- | --- |
| start.spring.io + Initializr HTTP API | Generate zip / metadata |
| Spring Boot CLI `spring init` | CLI client of Initializr |
| VS Code Spring Initializr | Wizard + last-settings + Maven edit-starters |
| Project Manager `java.project.create` | New **Java** project, not Boot |
| Maven for Java archetypes | Maven scaffolding, not Boot starters |

Neovim: third-party only (`spring-initializr.nvim`, `spring-gen.nvim`, `springboot-nvim` + CLI).

### Scaffolds + package view

| First-party | What |
| --- | --- |
| Project Manager for Java | Package view + new class/interface/enum/record/annotation/abstract class/package |
| vscode-java `java.templates.*` | Package + class body when a `.java` file is created |
| JDT LS snippets / source actions | In-file generation (constructors, methods), not new types on disk |

Neovim: no package view. Scaffolds exist only in third-party plugins (`springboot-nvim` generic types; `spring-gen.nvim` Spring stereotypes). nvim-jdtls / LazyVim extra / nvim-java do not create types.

The Java Projects tree depends on Microsoft’s `jdtls.ext.core` bundle, not on stock eclipse.jdt.ls.

### Add-dependency from an unresolved import

| First-party | What it actually does |
| --- | --- |
| JDT LS / vscode-java organize imports | Adds an `import` if the type is **already** on the classpath |
| Maven for Java `maven.project.addDependency` | Search/add a coordinate into `pom.xml` from the Maven / Java Projects UI |
| Maven POM GAV completion | Edit `pom.xml` by hand with completion |
| Spring Initializr `Edit starters` | Rewrite Boot starters on an existing **Maven** project |
| Project Manager referenced libraries | Add **JARs**, not Maven/Gradle deps |
| nvim-jdtls `:JdtUpdateConfig` | Reload classpath **after** the build file changed |

None of the sources above describe a code action on an unresolved type that searches Maven Central / the Boot BOM and edits `pom.xml` / `build.gradle`.

### Spring Boot run / reload

Two different mechanisms, both first-party:

**A. Spring Boot DevTools** ([official docs](https://docs.spring.io/spring-boot/reference/using/devtools.html)):

- Add `spring-boot-devtools` (Maven optional / Gradle `developmentOnly`).
- “Applications that use `spring-boot-devtools` automatically restart whenever files on the classpath change.” Directory classpath entries are watched.
- “Spring Boot relies entirely on the IDE to compile and copy files into the location from where Spring Boot can read them.”
- Optional trigger file (`spring.devtools.restart.trigger-file`) for IDEs that compile continuously. Spring Tools for Eclipse has a reload button when the trigger is named `.reloadtrigger`. VS Code Spring Boot Tools README does **not** document an equivalent trigger-file button.
- LiveReload browser refresh is deprecated as of Boot 4.1.0.

So the editor’s job for DevTools is: **write `.class` files (or a trigger file) onto a watched classpath directory**. JDT autobuild / `java/buildWorkspace` / `jdtls.compile` incremental can do that. LazyVim `lang.java` does not hook save → compile. `springboot-nvim` does.

**B. Debugger Hot Code Replace** (vscode-java-debug / nvim-jdtls `JdtUpdateHotcode` / LazyVim `hotcodereplace = "auto"`):

- Redefine classes in a live JDWP session after compile.
- Not Boot-specific; JVM cannot generally add/remove methods or change hierarchy.

**C. Process start:**

| Tool | How it starts the app |
| --- | --- |
| Spring Boot Dashboard | Start / stop / debug Boot apps |
| vscode-java-debug / nvim-jdtls DAP | Launch discovered `main` |
| nvim-java runner | `java -cp … Main` |
| springboot-nvim / spring-gen.nvim | `mvn spring-boot:run` or `gradlew bootRun` / generic terminal |
| STS4 | Does not start the process; attaches to JMX/actuator |

---

## What each surface looks like if you stay on the LazyVim dogfood path

LazyVim `lang.java` + nvim-jdtls + Mason jdtls, as shipped:

| Surface | Present? |
| --- | --- |
| Project initialization | No |
| Scaffolds + package view | No |
| Add-dependency from unresolved import | No |
| Spring Boot run/reload | DAP attach `:5005` + auto HCR + main-class debug configs only. No Boot run command. No save → `jdtls.compile`. DevTools works only if something else (JDT autobuild, Maven/Gradle, or another plugin) writes classes to the watched output dir. |

Third-party Neovim plugins already cover init (several), generic or stereotype scaffolds (two), and Boot run + incremental compile (`springboot-nvim`). No Neovim plugin in this survey implements a Java package view or add-dependency-from-unresolved-import.

---

## Source index

- Eclipse JDT LS README + initialize-request wiki.
- `mfussenegger/nvim-jdtls` README, `lua/jdtls.lua`, `lua/jdtls/setup.lua`.
- LazyVim extra: `/home/ayush/.local/share/nvim/lazy/LazyVim/lua/lazyvim/plugins/extras/lang/java.lua`.
- `nvim-java/nvim-java` README, `lua/java.lua`, `lua/java/startup/lsp_setup.lua`, `lua/java-runner/runner.lua`, `plugin/java.lua`.
- `JavaHello/spring-boot.nvim` README_en.md.
- `elmcgill/springboot-nvim` README + `init.lua` + `create_springboot_project.lua` + `generateclass.lua`.
- `jkeresman01/spring-initializr.nvim` README.
- `lazerfit/spring-gen.nvim` README.
- `spring-io/initializr` README.adoc.
- `redhat-developer/vscode-java` README.
- `microsoft/vscode-java-pack` README.
- `microsoft/vscode-java-dependency` README + package.json.
- `microsoft/vscode-maven` README + package.json.
- `microsoft/vscode-java-debug` README.
- `microsoft/vscode-spring-initializr` README.
- `microsoft/vscode-spring-boot-dashboard` README.
- `spring-projects/sts4` `vscode-extensions/vscode-spring-boot/README.md`.
- `spring-projects/spring-tools` README.
- VMware Spring Boot Extension Pack marketplace description.
- Spring Boot DevTools reference: https://docs.spring.io/spring-boot/reference/using/devtools.html.
- `CONTEXT.md` (this repo) for the terms Plugin, Host tool, Plugin dependency, Dependency, Package, Scaffold, Package view, Spring Boot project.
