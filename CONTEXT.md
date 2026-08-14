# nvim-spring

A Neovim plugin for general Java and Spring Boot work, used from a Neovim config by GitHub reference.

## Language

**Plugin**:
The Neovim plugin this repository is. A config pulls it by GitHub repo.
_Avoid_: overlay, extra, distribution (when meaning the product)

**Host tool**:
A program that must exist on the machine outside Neovim.
_Avoid_: system dependency, runtime (when meaning a PATH binary)

**Build tool**:
The project's Maven or Gradle system. It owns the build file, where a **Dependency** is declared, and the source roots and compile output a **Package view** and reload use.
_Avoid_: build system, compiler (when meaning Maven or Gradle)

**Plugin dependency**:
A Neovim plugin this plugin requires.
_Avoid_: host tool, dependency (when meaning another plugin)

**Dependency**:
A Maven or Gradle artifact declared in the project's build file.
_Avoid_: package, library, package install

**Package**:
A Java namespace, usually a directory under a source root.
_Avoid_: folder, directory, dependency (when meaning the Java namespace)

**Scaffold**:
A new Java type or Spring stereotype created with the correct package, filename, and boilerplate.
_Avoid_: snippet, template, generate (when meaning this product action)

**Package view**:
A separate, on-demand explorer organized by source roots and Java packages, not raw filesystem paths. It coexists with the file explorer; it is not a mode of it.
_Avoid_: file tree, project explorer (when meaning the Java-organized view), java file explorer

**Wizard**:
A multi-step, on-demand, floating flow that collects a decision before an action — creating a **Scaffold**, or driving Initializr. Not an always-on window.
_Avoid_: form, dialog, modal (when meaning this product surface)

**Spring Boot project**:
A Java project that uses Spring Boot.
_Avoid_: Spring project (when Boot-specific behaviour is meant)
