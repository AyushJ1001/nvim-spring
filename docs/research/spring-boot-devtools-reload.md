# What Spring Boot DevTools requires from the editor to reload

**Ticket:** [#5](https://github.com/AyushJ1001/nvim-spring/issues/5)
**Sources pinned:** Spring Boot **4.1.0** (current stable docs at research time), with **3.5.16** called out where LiveReload defaults differ. Maven/Gradle output paths from Apache Maven and Gradle Java plugin docs.

## Short answer

DevTools restart and LiveReload are **in-process features of the running application**. The editor (or a host tool such as `mvn`, `gradle`, or jdtls) does **not** talk to DevTools. It only has to **write updated class files and resources into a directory that is already a classpath entry** of that process. DevTools polls those directories and, after a quiet period, restarts the application context (or, for excluded static/template paths, triggers LiveReload instead).

Without `spring-boot-devtools` on the runtime classpath, none of that happens. Saving a `.java` file is never enough by itself.

There is **no separate DevTools product named “Fast Restart”**. The how-to heading “Fast Application Restarts” is the same automatic-restart feature.

## Restart vs LiveReload vs “Fast Restart”

### Automatic restart (the main DevTools feature)

Applications that include `spring-boot-devtools` **automatically restart whenever files on the classpath change**. By default **any classpath entry that points to a directory** is monitored. Restart is a **two-classloader** trick, not a JVM process exit:

- Third-party jars go in a long-lived **base** classloader.
- Application classes go in a disposable **restart** classloader.
- On change, the restart classloader is discarded and a new one is created. That is why Spring Boot calls it faster than a “cold start”.

Official name in the reference: **Automatic Restart**. Official how-to alias: **Fast Application Restarts**. Same module, same watcher.

Restart is **not** JRebel-style class reload. If JRebel is present, DevTools **disables automatic restarts** and leaves dynamic reloading to JRebel. It is also **not** JVM hot-swap (see below).

Defaults (4.1.0):

| Property | Default | Role |
| --- | --- | --- |
| `spring.devtools.restart.enabled` | `true` | Watch classpath and restart |
| `spring.devtools.restart.poll-interval` | `1s` | Poll period |
| `spring.devtools.restart.quiet-period` | `400ms` | Wait until writes settle |
| `spring.devtools.restart.exclude` | `META-INF/maven/**, META-INF/resources/**, resources/**, static/**, public/**, templates/**, **/*Test.class, **/*Tests.class, git.properties, META-INF/build-info.properties` | Changes here do **not** restart |
| `spring.devtools.restart.trigger-file` | unset | If set, only that classpath file’s update starts a check |

Setting `spring.devtools.restart.enabled=false` in `application.properties` still creates the restart classloader but **stops watching**. To skip the classloader entirely, set the **system** property `spring.devtools.restart.enabled=false` **before** `SpringApplication.run`.

Restart needs the application context **shutdown hook**. `SpringApplication.setRegisterShutdownHook(false)` breaks it. AspectJ weaving is unsupported. A trigger file is for IDEs that compile continuously so every keystroke does not restart.

### LiveReload (browser refresh, not app restart)

DevTools can run an **embedded LiveReload server** that tells a browser extension to refresh when a resource changes. That is **not** an application restart.

- Changes under the default restart exclusions (`/static`, `/public`, `/templates`, …) **do not restart** the app; they **do** trigger LiveReload.
- **Automatic restart must be enabled** for LiveReload to fire on file changes. Disabling restart disables LiveReload triggers even if the server is up.
- Only **one** LiveReload server can bind (default port **35729**). Multiple apps: only the first gets it.

**Version split:**

| Line | LiveReload |
| --- | --- |
| Spring Boot **3.5.x** | Server starts by default; set `spring.devtools.livereload.enabled=false` to stop it. |
| Spring Boot **4.1.0** | Feature is **deprecated with no replacement**. Server does **not** start unless `spring.devtools.livereload.enabled=true`. `DevToolsProperties.Livereload.enabled` defaults to `false`. |

The editor does not implement LiveReload. The **running app** hosts the server; the **browser extension** consumes it.

### “Fast Restart” / JVM hot-swap (not DevTools)

The how-to **Fast Application Restarts** section is DevTools automatic restart. Separately, Spring Boot documents **JVM hot swapping**: if you run in an IDE **with a debugger**, changes that do **not** alter class or method signatures can be swapped by the JVM. That path does not use DevTools, does not restart the context, and cannot pick up signature or configuration changes.

JRebel is documented as a third-party **reload** (rewrite classes on load), contrasted with DevTools **restart**.

## What the running app does vs what the editor must do

### The running app (DevTools)

Once `spring-boot-devtools` is on the **runtime classpath** of an exploded (not `java -jar`) process:

1. Installs the two classloaders (unless fully disabled via the system property).
2. Polls **directory** classpath entries (and `spring.devtools.restart.additional-paths`) via `FileSystemWatcher`.
3. After `quiet-period` with no further writes, either restarts the context or (for excluded patterns) signals LiveReload.
4. Applies development property defaults (template cache off, static resource cache period `0`, …) unless `spring.devtools.add-properties=false`.

Spring Boot is explicit: **it relies entirely on the IDE (or build) to compile and copy files** into a location it can read. DevTools does not compile `.java` sources.

Watched URLs are **directory** `file:` classpath entries (implementation: `ChangeableUrls` keeps `file:…/` URLs, plus anything matched by `restart.include`, minus `restart.exclude`). Plain `.jar` entries are not watched.

### The editor / host tools

Must do **only** this:

1. Ensure the process was started **exploded**, with `spring-boot-devtools` on the classpath (`optional` Maven dependency or Gradle `developmentOnly`).
2. **Compile** changed sources and **write `.class` / resource files** into those watched directories.
3. Optionally touch a trigger file on the classpath if continuous compile would restart too often.
4. Optionally increase `poll-interval` / `quiet-period` if writes are staggered.

Must **not**:

- Expect DevTools to watch `src/main/java`. Source trees are not on the classpath unless configured as `additional-paths`.
- Expect a protocol, LSP command, or HTTP call to “tell DevTools to reload”.
- Expect `java -jar` of a default repackaged archive to restart (devtools is excluded from the fat jar; a packaged launch is treated as production).

## Which directory is watched? Maven vs Gradle

DevTools does **not** hard-code `target/classes` or `build/classes`. It watches **whatever directory entries are on that JVM’s classpath**.

Those directories are the build’s **output**, not the sources.

### Maven

Apache Maven’s default `project.build.outputDirectory` is **`target/classes`** (`project.build.directory` is `${project.basedir}/target`). The compiler plugin writes there.

`spring-boot:run`’s `classesDirectory` defaults to **`${project.build.outputDirectory}`**, i.e. `target/classes`. That directory is a classpath entry, so DevTools watches **`target/classes`** (and any other directory entries the plugin adds).

`addResources=true` also puts `src/main/resources` on the classpath and **removes the copies from `target/classes`**. The Maven plugin now tells you to prefer DevTools instead; `addResources` defaults to `false`.

### Gradle

The Java plugin’s main compile output is **`build/classes/java/main`** (`layout.buildDirectory.dir("classes/java/$name")`). Processed resources go to **`build/resources/main`**. Both are part of the main source set output.

`bootRun` “is automatically configured to use the **runtime classpath of the main source set**”. So DevTools watches **`build/classes/java/main`** and **`build/resources/main`**, not a generic `build/classes` and not `src/`.

Gradle plugin: “If devtools has been added … it will automatically monitor your application’s classpath for changes. **Modified files need to be recompiled for the classpath to update.**” Alternatively, `bootRun { sourceResources sourceSets.main }` loads static resources from their **source** location so they can be edited in place without a copy.

The `restart.exclude` example regex in the DevTools docs lists local output folders as `(build|bin|out|target)` — that is how Spring Boot itself refers to Maven / Gradle / Eclipse / IntelliJ outputs when customizing classloaders.

## `spring-boot:run` / `bootRun` vs a forked `java` process vs `java -jar`

### Exploded run (what restart needs)

| Launch | Form | DevTools restart |
| --- | --- | --- |
| IDE “run main” / exploded classpath | Directory entries + jars | Yes, if the module is on the classpath and the launch classloader is treated as development |
| `mvn spring-boot:run` | Exploded; **always a forked JVM** in 4.1.0 | Yes. The `@SpringBootApplication` project is the restart classloader; other jars are base |
| `gradle bootRun` | Exploded `JavaExec`; runtime classpath of `main` | Same split as Maven |
| `java -cp … com.example.App` with exploded `target/classes` or `build/classes/java/main` plus the devtools jar | Exploded | Yes, if the context classloader name contains `AppClassLoader` (see below) |
| `java -jar app.jar` (default repackage) | Nested/packaged; **devtools omitted** from the archive | Treated as **production**. Restart off. Forcing `-Dspring.devtools.restart.enabled=true` is documented as a **security risk** and still has nothing to watch except what is inside the archive |

Spring Boot 4.1.0 Maven `run` docs: the application **is executed in a forked process**. There is **no `fork` parameter** on the 4.1.0 goal (forking is not optional). Older plugin docs said disabling fork disables **devtools** (no isolated classloader). Current reference still says: if you use the Maven/Gradle plugin, **leave forking enabled**; otherwise the isolated application classloader is not created and restarts misbehave.

DefaultRestartInitializer only installs restart URLs when:

- the thread is named `main`,
- tests / AOT / native-image have not disabled DevTools (`DevToolsEnablementDeducer`),
- the context classloader’s class name **contains `AppClassLoader`** (typical JDK application classloader used by Maven/Gradle forks and a normal `java` main).

A Spring Boot **loader** classloader (`java -jar`) fails that check unless you override with `-Dspring.devtools.restart.enabled=true`.

Repackaged archives **do not contain devtools by default** (`excludeDevtools`). Remote DevTools is a different, opt-in, non-local path and is out of scope for a local editor loop.

## Without DevTools on the classpath

- No classpath polling, no automatic context restart, no LiveReload server, no DevTools property defaults.
- The app is an ordinary Spring Boot process. Restart means you stop and start it, or use JVM hot-swap under a debugger for signature-preserving method-body edits.
- The Maven plugin’s pre-devtools `addResources` in-place resource refresh is still available but **disabled by default** and documented as inferior to adding the module.
- Excluding the dependency, or `-Dspring.devtools.restart.enabled=false`, is the official way to turn the module off.

## Is jdtls compile-on-save sufficient?

**Yes, if and only if the language server writes compiled output into a directory that is already on the running process classpath.** DevTools will then see the same file updates Eclipse would produce.

Official chain:

1. Spring Boot: **“Spring Boot relies entirely on the IDE to compile and copy files into the location from where Spring Boot can read them.”**
2. Spring Boot how-to: static/resource “build” **“happens automatically in Eclipse when you save”**. IntelliJ needs **Build Project**. That save→output write is the whole contract.
3. Eclipse JDT LS is **Eclipse JDT + M2Eclipse + Buildship**. It **compiles** Java projects (1.8–25) and understands Maven and Gradle.
4. Continuous compile is exactly the situation DevTools documents a **trigger file** for (“IDE that continuously compiles changed files”).

Implications for this plugin:

| Setup | Compile-on-save enough? |
| --- | --- |
| Maven + `mvn spring-boot:run` (or exploded `java` using `target/classes`) + jdtls/M2E writing to **`target/classes`** | **Yes** — same directory DevTools polls. |
| Gradle + `bootRun` (classpath is **`build/classes/java/main`** + **`build/resources/main`**) + jdtls/Buildship writing to Gradle’s **Eclipse** output (`bin/default` since Gradle 4.4’s Eclipse classpath default) | **Not by itself.** The running JVM is not watching `bin/`. Need `./gradlew classes` (or equivalent) into the source-set output, or put the Eclipse output on the runtime classpath, or point `additional-paths` at it. |
| App started as `java -jar` without an exploded classpath | **No.** Nothing useful is watched. |
| `spring-boot-devtools` not on the runtime classpath | **No.** |
| Only `.java` saved, classes never emitted (autobuild off, compile errors, wrong output folder) | **No.** |

jdtls does **not** need a DevTools-specific integration. It needs **autobuild (or an explicit compile) whose destination matches the run classpath**. If continuous compile restarts too often, set `spring.devtools.restart.trigger-file` and have the editor (or user) touch that classpath file when a restart is wanted — Spring Tools and IntelliJ Ultimate already do that; Neovim would have to provide the touch.

Resources: compiling Java is not enough for `src/main/resources` unless something copies them into `target/classes` / `build/resources/main`, or `bootRun` `sourceResources` / Maven `addResources` puts the source dir on the classpath.

## Editor / host-tool checklist

For a Neovim plugin, the official contract is:

1. **Do not implement a reloader.** Start (or tell the user to start) an **exploded** process that already has `spring-boot-devtools`.
2. **Compile into the run classpath** (`target/classes` or `build/classes/java/main` + resources). jdtls compile-on-save is sufficient **when those paths match**.
3. For Gradle, do not assume jdtls output equals `bootRun` output.
4. Treat LiveReload as optional/deprecated (off by default in 4.1; browser extension, not editor).
5. Optional: trigger file, poll/quiet tuning, `additional-paths`.

## Sources

- [Spring Boot 4.1.0 — Developer Tools](https://docs.spring.io/spring-boot/reference/using/devtools.html) (restart, LiveReload deprecation, forking, trigger file, watcher, `java -jar` disable, classloader split, `mvn spring-boot:run` / `gradle bootRun`)
- [Spring Boot 3.5.16 — Developer Tools](https://docs.spring.io/spring-boot/3.5/reference/using/devtools.html) (LiveReload on by default)
- [Spring Boot 4.1.0 — Hot Swapping / Fast Application Restarts](https://docs.spring.io/spring-boot/how-to/hotswapping.html)
- [Spring Boot 4.1.0 — Maven plugin `run`](https://docs.spring.io/spring-boot/maven-plugin/run.html) (forked process, `classesDirectory`, `addResources`, `target/classes`, DevTools refresh)
- [Spring Boot 4.1.0 — Gradle plugin running / `bootRun`](https://docs.spring.io/spring-boot/gradle-plugin/running.html)
- [Spring Boot 3.2.12 — Running your application](https://docs.spring.io/spring-boot/docs/3.2.12/reference/html/using.html#using.running-your-application) (exploded form of `spring-boot:run` / `bootRun`)
- [Common application properties — DevTools (4.1.0)](https://docs.spring.io/spring-boot/appendix/application-properties/index.html#appendix.application-properties.devtools)
- [Spring Boot 4.1 Release Notes — LiveReload deprecated](https://github.com/spring-projects/spring-boot/wiki/Spring-Boot-4.1-Release-Notes)
- Source, tag `v4.1.0`: [`DevToolsProperties`](https://raw.githubusercontent.com/spring-projects/spring-boot/v4.1.0/module/spring-boot-devtools/src/main/java/org/springframework/boot/devtools/autoconfigure/DevToolsProperties.java), [`ChangeableUrls`](https://raw.githubusercontent.com/spring-projects/spring-boot/v4.1.0/module/spring-boot-devtools/src/main/java/org/springframework/boot/devtools/restart/ChangeableUrls.java), [`DefaultRestartInitializer`](https://raw.githubusercontent.com/spring-projects/spring-boot/v4.1.0/module/spring-boot-devtools/src/main/java/org/springframework/boot/devtools/restart/DefaultRestartInitializer.java), [`RestartApplicationListener`](https://raw.githubusercontent.com/spring-projects/spring-boot/v4.1.0/module/spring-boot-devtools/src/main/java/org/springframework/boot/devtools/restart/RestartApplicationListener.java), [`DevToolsEnablementDeducer`](https://raw.githubusercontent.com/spring-projects/spring-boot/v4.1.0/module/spring-boot-devtools/src/main/java/org/springframework/boot/devtools/system/DevToolsEnablementDeducer.java)
- [Maven POM — `outputDirectory` default `target/classes`](https://maven.apache.org/ref/3.9.11/maven-model/maven.html); [POM build `directory` default `target`](https://maven.apache.org/pom.html)
- [Gradle Java plugin — `build/classes/java/main`, `build/resources/main`](https://docs.gradle.org/current/userguide/java_plugin.html#sec:source_set_properties)
- [Gradle 4.4.1 notes — Eclipse classpath output `bin/default`](https://docs.gradle.org/4.4.1/release-notes.html)
- [Eclipse JDT LS README — JDT + M2E + Buildship, compiles Java, Maven/Gradle](https://github.com/eclipse-jdtls/eclipse.jdt.ls/blob/main/README.md)
