# nvim-spring

A Neovim plugin for general Java and Spring Boot work, used from a Neovim config by GitHub reference.

## Language

**Plugin**:
The Neovim plugin this repository is. A config pulls it by GitHub repo.
_Avoid_: overlay, extra, distribution (when meaning the product)

**Host tool**:
A program that must exist on the machine outside Neovim.
_Avoid_: system dependency, runtime (when meaning a PATH binary)

**Language level**:
The project's Java release (`maven.compiler.release` / `java.version`), not the **Host tool** JDK on PATH.
_Avoid_: Java version (when it is unclear which of the two is meant), JDK version (when meaning the project)

**Build tool**:
The project's Maven or Gradle system. It owns the build file, where a **Dependency** is declared, and the source roots and compile output a **Package view** and **Reload** use.
_Avoid_: build system, compiler (when meaning Maven or Gradle)

**Plugin dependency**:
A Neovim plugin this plugin uses when it is present. Presence is not required unless a decision says so.
_Avoid_: host tool, dependency (when meaning another plugin)

**Dependency**:
A Maven or Gradle artifact declared in the project's build file.
_Avoid_: package, library, package install

**Package**:
A Java namespace, usually a directory under a source root.
_Avoid_: folder, directory, dependency (when meaning the Java namespace)

**Scaffold**:
A new Java type or Spring stereotype created with the correct package, filename, and boilerplate. Its **Package** is the **Package view** or buffer selection, or a nest under that selection, including a **Package** that does not yet exist.
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

**Initializr**:
An HTTP service that creates a **Spring Boot project**. start.spring.io is one instance; the Plugin uses a single base URL.
_Avoid_: initializer, generator, starter.io

**Reload**:
A DevTools automatic restart of a running **Spring Boot project**'s application context, triggered by changes in exploded classpath output.
_Avoid_: LiveReload, HMR, hot reload, fast restart
