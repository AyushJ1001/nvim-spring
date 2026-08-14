# Add a build dependency from an unresolved import

Research ticket: [#4](https://github.com/AyushJ1001/nvim-spring/issues/4).

How IntelliJ IDEA and VS Code's Java extensions offer to add a Maven or Gradle **dependency** when a Java file names a type that is not on the project classpath, and which public indexes or APIs a Neovim plugin could use to do the same.

Primary sources only. Claims cite the document or source file that owns them.

## Short answer

| Surface | From unresolved Java type? | What it edits | How it finds GAV |
| --- | --- | --- | --- |
| IntelliJ Maven | Yes. Quick-fix **Add Maven Dependency…** on an unresolved Java reference. | The module's `pom.xml` (`<dependency>` under `<dependencies>`). Scope `test` if the source is a test root. Reloads the Maven project. | Local **Maven repository class indexes** (Nexus/Lucene class-name index) for the project's configured repos, via **Maven Artifact Search**. |
| IntelliJ Gradle | Official docs describe adding by editing `build.gradle` / `build.gradle.kts` with completion, not a Java-file quick-fix. | The Gradle build script. Module-settings libraries are discarded on reload. | Completion against Gradle's configurations and indexed artifacts. The separate Package Search plugin is **deprecated**. |
| VS Code + Maven for Java | Yes. Code action / hover **Resolve unknown type** on JDT diagnostics `UNDEFINED_TYPE` / `UNDEFINED_NAME`. | The Java file (simple name + import) **and** the module `pom.xml`. Maven-only. | Bundled Lucene Maven class index, then Maven Central Solr (`c:` / `fc:`). Ranked by a shipped usage JSON. |
| VS Code + Project Manager | No class-name path. **+** on Maven Dependencies is a keyword search. | `pom.xml` via `maven.project.addDependency`. Unmanaged folders: `java.project.referencedLibraries` (jars), not Maven/Gradle. | Maven Central Solr keyword search (`search.maven.org/solrsearch/select`). |
| JDT-LS / nvim-jdtls | No add-dependency command. | — | — |

Maven now has a supported CLI to insert a GAV into `pom.xml`: `mvn dependency:add` (plugin 3.11.0). Gradle's CLI can list/report dependencies and bootstrap a build; it has no "add this artifact to the script" command.

## IntelliJ IDEA

### Maven: Alt+Enter on an unresolved type

IntelliJ registers `AddMavenDependencyQuickFix` as an `UnresolvedReferenceQuickFixProvider` for `PsiJavaCodeReferenceElement` (skipped for `module-info` files).

- Family / text: **Add Maven Dependency…** (`fix.add.dependency`).
- Available only if the file belongs to a Maven project **and** the reference text matches a class-name pattern (`identifier(.identifier)*` ending in an uppercase-start simple name).
- Invoke: collect the fully-qualified name by walking up nested `PsiJavaCodeReferenceElement`s, then open `MavenArtifactSearchDialog.searchForClass(project, className)`.
- On accept: write into the Maven DOM model (`MavenDomUtil.createDomDependency`). If the Java file is under test source roots, set `<scope>test</scope>`. If the same GAV already exists with test scope and the new use is not a test source, clear the scope.
- Then save documents and `MavenProjectsManager.forceUpdateAllProjectsOrFindAllAvailablePomFiles()`.

Sources:

- [AddMavenDependencyQuickFix.java](https://github.com/JetBrains/intellij-community/blob/master/plugins/maven/src/main/java/org/jetbrains/idea/maven/dom/intentions/AddMavenDependencyQuickFix.java)
- [AddMavenDependencyQuickFixProvider.java](https://github.com/JetBrains/intellij-community/blob/master/plugins/maven/src/main/java/org/jetbrains/idea/maven/dom/intentions/AddMavenDependencyQuickFixProvider.java)
- [MavenDomBundle.properties](https://github.com/JetBrains/intellij-community/blob/master/plugins/maven/src/main/resources/messages/MavenDomBundle.properties) (`fix.add.dependency=Add Maven Dependency…`)

The same dialog is used from the POM: **Generate → Dependency** (`Alt+Insert` in `pom.xml`) opens **Maven Artifact Search** and inserts the chosen coordinates into the POM. IntelliJ's Maven docs say to declare dependencies in the POM; libraries added only in module settings are discarded on the next Maven reload.

Source: [Maven dependencies | IntelliJ IDEA](https://www.jetbrains.com/help/idea/work-with-maven-dependencies.html) (21 July 2026).

### What the Maven dialog searches

`MavenArtifactSearchDialog` has two tabs:

1. **Search for artifact** (`searchForArtifact`) — GAV / name.
2. **Search for class** (`searchForClass`) — class name; this is the unresolved-import path. The class tab is selected when `classMode` is true.

The class tab's empty-state text links to **Settings → Maven Repositories** to update indexes.

`MavenClassSearcher.searchImpl` asks `MavenLuceneIndexer` for every repository known to the project (`MavenIndexUtils.getAllRepositories`). The indexer looks up `MavenSystemIndicesManager.getClassIndexForRepository` and calls `search(pattern, maxResult)` on that class index. Results are grouped by FQCN; versions are collected and sorted with `VersionComparatorUtil` (newest first).

`MavenLuceneClassIndexServer` is a Nexus/Lucene class index (`MavenIndexerWrapper.search`). Updating indexes is a user action: **Settings → Build, Execution, Deployment → Build Tools → Maven → Repositories → Update**. Docs state this index is what powers both POM completion and **Maven Artifact Search**, including newly deployed versions.

Sources:

- [MavenArtifactSearchDialog.java](https://github.com/JetBrains/intellij-community/blob/master/plugins/maven/src/main/java/org/jetbrains/idea/maven/indices/MavenArtifactSearchDialog.java)
- [MavenArtifactSearchPanel.java](https://github.com/JetBrains/intellij-community/blob/master/plugins/maven/src/main/java/org/jetbrains/idea/maven/indices/MavenArtifactSearchPanel.java)
- [MavenClassSearcher.kt](https://github.com/JetBrains/intellij-community/blob/master/plugins/maven/src/main/java/org/jetbrains/idea/maven/indices/MavenClassSearcher.kt)
- [MavenLuceneIndexer.kt](https://github.com/JetBrains/intellij-community/blob/master/plugins/maven/src/main/java/org/jetbrains/idea/maven/indices/searcher/MavenLuceneIndexer.kt)
- [MavenLuceneClassIndexServer.kt](https://github.com/JetBrains/intellij-community/blob/master/plugins/maven/src/main/java/org/jetbrains/idea/maven/indices/MavenLuceneClassIndexServer.kt)
- [Maven. Repositories | IntelliJ IDEA](https://www.jetbrains.com/help/idea/maven-repositories.html)

IntelliJ therefore does **not** call `search.maven.org` on each keystroke for this flow. It searches **local copies of repository class indexes** (the same Nexus Maven Indexer class-name field used by Central). Stale indexes → missing artifacts. Private repos work only if they publish a Nexus-style index.

### Maven BOM / `dependencyManagement`

From the POM (not from a Java import), **Generate → Managed Dependency** lists coordinates already declared in parent `dependencyManagement` **and** in imported BOM files. The inserted `<dependency>` omits `<version>` so Maven takes it from management. Overriding the managed version requires writing `<version>` explicitly.

The artifact-search panel also highlights versions that match `dependencyManagement` ("from dependency management").

Sources: [Maven dependencies | IntelliJ IDEA](https://www.jetbrains.com/help/idea/work-with-maven-dependencies.html) (section *Centralize dependency information*); [MavenArtifactSearchPanel.java](https://github.com/JetBrains/intellij-community/blob/master/plugins/maven/src/main/java/org/jetbrains/idea/maven/indices/MavenArtifactSearchPanel.java).

The Java quick-fix path always writes a concrete `MavenId` (group, artifact, version) via `createDomDependency`. It does **not** drop the version when a BOM already manages it. That is a failure mode for Spring Boot parent / `spring-boot-dependencies` (see below).

### Gradle: official path is the build script

IntelliJ's Gradle docs: "The best way to add or manage a dependency is in the `build.gradle.kts` file." Open the script, type a configuration name or artifact, use completion (`Ctrl+Space`), then reload. Dependencies added only in module settings are discarded on Gradle reload. The listed configurations come from the `plugins {}` block.

There is **no** documented "Add Gradle Dependency" quick-fix on an unresolved Java import equivalent to `AddMavenDependencyQuickFix`. Package Search (the former unified "search Maven Central and write Maven or Gradle" UI) is **not bundled** and is **deprecated** (docs last updated 6 November 2024; current page points at IDEA 2024.2 help).

Sources:

- [Gradle dependencies | IntelliJ IDEA](https://www.jetbrains.com/help/idea/work-with-gradle-dependency-diagram.html) (30 June 2026)
- [Package Search | IntelliJ IDEA](https://www.jetbrains.com/help/idea/package-search.html)

So for a Neovim plugin: do not assume IntelliJ writes `build.gradle`, `build.gradle.kts`, or `gradle/libs.versions.toml` from an unresolved Java type. The first-party, still-supported class→GAV→build-file loop is **Maven + `pom.xml`**.

## VS Code Java extensions

Three extensions matter. They are not the same product as JDT-LS.

### 1. Maven for Java (`vscjava.vscode-maven`) — the class-name path

This is the only VS Code Java extension that implements "unresolved type → pick artifact → edit `pom.xml`".

**Trigger.** On language `java`, a code-action provider and a hover provider look at JDT diagnostics:

| JDT diagnostic code | Meaning (comment in source) | Treated as unresolved type? |
| --- | --- | --- |
| `16777218` (`UNDEFINED_TYPE`) | e.g. `Unknown var;` | Always |
| `570425394` (`UNDEFINED_NAME`) | e.g. `Unknown.foo();` | Only if the range text starts with A–Z |

Code action title: `Resolve unknown type '<simpleName>'`. Hover: a trusted markdown link that runs `maven.artifactSearch`.

**Search.** `java.maven.initializeSearcher` is given `resources/IndexData` (a shipped Lucene Maven class index + `ArtifactUsage.json`). `java.maven.searchArtifact` with `searchType: CLASSNAME` runs `ArtifactSearcher.searchByClassName`:

1. Query the local Lucene index (`MAVEN.CLASSNAMES`, prefix + fuzzy `~`, edit distance ≤ 2).
2. If fewer than 5 hits, also query Maven Central Solr:
   - simple name: `q=c:<name>` and `q=c:<name>*`
   - dotted / FQCN: `q=fc:<name>` and `q=fc:<name>*`
   - `https://search.maven.org/solrsearch/select?...&rows=10&wt=json`, 2s timeout
3. Rank by exact/prefix vs fuzzy, then by usage counts from `ArtifactUsage.json`. Azure artifactIds get a bonus slot. Fuzzy hits with usage &lt; 1000 are dropped.
4. The UI shows up to all remaining hits; the first `min(round(n/5), 5)` are starred.

**Edit.** `java.maven.addDependency` (JDT-LS *delegate* command, **not** a core JDT-LS command) returns three workspace edits:

0. Replace the identifier with the chosen simple name.
1. Add an import for the FQCN (`ImportRewrite`).
2. Insert into **that Java project's `pom.xml` only**:
   - create `<dependencies>` if missing, or
   - append `<dependency><groupId/><artifactId/><version/></dependency>` if the GAV is not already present.

If the POM is missing or not parseable, the client shows: "Sorry, the pom.xml file is inexistent or invalid." It always writes a version. It does not write Gradle files, version catalogs, or `<dependencyManagement>`.

**Manual add (not from a Java type).** Command `maven.project.addDependency` ("Add a dependency…"): prompt for keywords (min length 3), query Solr `q=<keywords>&rows=50&wt=json`, sort by shipped usage, insert GAV + `latestVersion` into the chosen `pom.xml`. Also offered as a code action inside a `<dependencies>` tag. Accepts a pre-filled `{groupId, artifactId, version}` from another extension (this is how Project Manager can pass a coordinate).

Sources:

- [artifactSearcher.ts](https://github.com/microsoft/vscode-maven/blob/main/src/jdtls/artifactSearcher.ts)
- [addDependencyHandler.ts](https://github.com/microsoft/vscode-maven/blob/main/src/handlers/dependency/addDependencyHandler.ts)
- [requestUtils.ts](https://github.com/microsoft/vscode-maven/blob/main/src/utils/requestUtils.ts) (`URL_MAVEN_SEARCH_API = "https://search.maven.org/solrsearch/select"`)
- [ArtifactSearcher.java](https://github.com/microsoft/vscode-maven/blob/main/jdtls.ext/com.microsoft.java.maven.plugin/src/main/java/com/microsoft/java/maven/ArtifactSearcher.java)
- [AddDependencyHandler.java](https://github.com/microsoft/vscode-maven/blob/main/jdtls.ext/com.microsoft.java.maven.plugin/src/main/java/com/microsoft/java/maven/AddDependencyHandler.java)
- [DelegateCommandHandler.java](https://github.com/microsoft/vscode-maven/blob/main/jdtls.ext/com.microsoft.java.maven.plugin/src/main/java/com/microsoft/java/maven/handler/DelegateCommandHandler.java)

Those `java.maven.*` commands exist only while the vscode-maven JDT bundle is loaded. A stock JDT-LS + nvim-jdtls session does not register them.

### 2. Project Manager for Java (`vscjava.vscode-java-dependency`)

Official VS Code docs: for a Maven project, add a dependency by clicking **+** next to **Maven Dependencies** in **Java Projects**. That UI is documented here; the implementation of the search/insert lives in vscode-maven (`addDependencyHandler` comments: "for 'Maven dependencies' nodes from Project Manager").

Project Manager's own command list has `java.project.addLibraries` / `addLibraryFolders` / `removeLibrary` for **unmanaged** folders (raw jars). It has `java.project.update` for Maven/Gradle refresh. It does **not** register an add-Maven/Gradle-dependency command of its own.

Unmanaged folders persist jars via `java.project.referencedLibraries` in `settings.json` (glob include/exclude + optional source attachments). That is not a Maven/Gradle dependency.

Sources:

- [Managing Java Projects in VS Code](https://code.visualstudio.com/docs/java/java-project) (Dependency management)
- [vscode-java-dependency package.json](https://github.com/microsoft/vscode-java-dependency/blob/main/package.json)
- [commands.ts](https://github.com/microsoft/vscode-java-dependency/blob/main/src/commands.ts)

### 3. Language Support for Java / JDT-LS

JDT-LS `plugin.xml` delegate commands include project classpath, source path, import, JDK, organize imports, etc. There is **no** `java.*.addDependency` / search-artifact command in core JDT-LS.

Relevant nearby commands (after someone else edits the build file):

- `java.project.import` / `java.project.changeImportedProjects`
- `java.projectConfiguration.update` (used by clients as "reload Maven/Gradle")
- `java.project.updateClassPaths` — writes the **Eclipse JDT classpath**, not `pom.xml` / `build.gradle`

Source: [org.eclipse.jdt.ls.core/plugin.xml](https://github.com/eclipse-jdtls/eclipse.jdt.ls/blob/main/org.eclipse.jdt.ls.core/plugin.xml); [ProjectCommand.java](https://github.com/eclipse-jdtls/eclipse.jdt.ls/blob/master/org.eclipse.jdt.ls.core/src/org/eclipse/jdt/ls/core/internal/commands/ProjectCommand.java).

### nvim-jdtls

`mfussenegger/nvim-jdtls` documents organize imports, compile/build, `update_project_config` / `update_projects_config` (reload Gradle or Maven), extract refactorings, DAP, tests. **No** add-dependency or artifact-search API.

Source: [jdtls.txt](https://github.com/mfussenegger/nvim-jdtls/blob/master/doc/jdtls.txt).

## Public indexes and APIs a plugin can call

### Maven Central Solr (search.maven.org) — documented, class-capable

Sonatype's Central REST API guide documents `https://search.maven.org/solrsearch/select` with `wt=json|xml` and `rows`. Relevant queries:

| Query | Meaning |
| --- | --- |
| `q=guice` | Basic search: groupId / artifactId text; **latest** version only |
| `q=g:GROUP+AND+a:ARTIFACT&core=gav` | All versions of one artifact |
| `q=a:ARTIFACT` | Any group with that artifactId; latest version |
| `q=c:junit` | **Class name** (advanced search). Returns artifacts **down to a specific version** that contain the class |
| `q=fc:org.specs.runner.JUnit` | **Fully-qualified class name**. Same, version-specific |

This is exactly what vscode-maven's `NetSearcher` uses (`c:` vs `fc:`). It is the only **HTTP, no-index-download** public API in this survey that maps a class name to GAV+version.

Caveats owned by that guide / the clients:

- Docs note most example URLs are decoded; programmatic callers must encode.
- Default (non-`core=gav`) hits return `latestVersion` for coordinate search, but **class** search returns a concrete version that contains the class (often not the newest).
- vscode-maven's keyword search takes `response.docs[].latestVersion` and does not resolve a BOM-managed omission.
- Ambiguous simple names (`c:Logger`, `c:JsonNode`) return many artifacts; both IDEs make the user pick.

Source: [REST API – Maven Central](https://central.sonatype.org/search/rest-api-guide/).

### Maven repository class index (Nexus / Lucene)

IntelliJ (and vscode-maven's shipped `IndexData`) search a **Lucene Maven Indexer** with a `CLASSNAMES` field (`JarFileContentsIndexCreator`). That is the same family of index Maven Central publishes for download (Nexus indexer), not a JSON search API. Using it means: download/update a multi-hundred-MB index, keep it fresh, query locally. IntelliJ does this per configured repository and requires the remote to expose the indexing service.

Sources: IntelliJ indexer files above; vscode-maven `ArtifactSearcher.java` (`DefaultIndexer`, `JarFileContentsIndexCreator`, `MAVEN.CLASSNAMES`).

### What is *not* a public class→GAV API here

- **Google "class indexer".** Neither IntelliJ's Maven plugin nor vscode-maven calls a Google class-search HTTP API in the sources above. vscode-maven's network path is Solr only.
- **JetBrains Package Search.** Deprecated; not a supported plugin API for new work ([Package Search docs](https://www.jetbrains.com/help/idea/package-search.html)).
- **repo1.maven.org file layout.** Can fetch `maven-metadata.xml` and POMs by known GAV (vscode-maven `fetchPluginMetadataXml`); cannot search by class name.
- **JDT-LS.** No artifact search.

## Do Maven or Gradle expose a CLI to "add this artifact"?

### Maven: yes, as of dependency-plugin 3.11.0

`dependency:add` writes the project's `pom.xml` from the command line.

```text
mvn dependency:add -Dgav=org.apache.commons:commons-lang3:3.17.0
mvn dependency:add -Dgav=org.apache.commons:commons-lang3:3.17.0 -Dscope=test
mvn dependency:add -Dgav=org.apache.commons:commons-lang3 -Dmanaged   # dependencyManagement
mvn dependency:add -Dgav=org.springframework.boot:spring-boot-dependencies:pom:3.2.0 -Dscope=import -Dmanaged
mvn dependency:add -Dgav=org.apache.commons:commons-lang3:3.17.0 -pl my-service
```

Documented behaviour that matters for a plugin:

- `gav` format: `groupId:artifactId[:extension[:classifier]]:version`. Scope is **not** in GAV (`-Dscope`).
- **Version inference:** if adding to `<dependencies>` and a parent/`dependencyManagement` already manages the version, omit version; the goal writes no `<version>`. If no managed version exists, it **fails**.
- Duplicate GAV (group, artifact, type, classifier) **fails**; remove first.
- Property-interpolated existing coords (`${my.group}`) **fail** rather than duplicate.
- `-Dmanaged` targets `<dependencyManagement>`; BOM import is `-Dscope=import -Dmanaged` with type `pom`.
- `-pl` selects a module; `-Dprofile=` requires an existing profile.

`dependency:get` only **resolves/downloads** an artifact; it does not edit the POM.

This CLI is a reasonable implementation backend for **Maven** once the plugin already knows GAV (and optionally whether a BOM manages the version). It is not a class-name search.

Sources: [Usage – Maven Dependency Plugin](https://maven.apache.org/plugins/maven-dependency-plugin/usage.html) (`dependency:add`); [Managing Dependencies](https://maven.apache.org/plugins/maven-dependency-plugin/examples/managing-dependencies.html).

### Gradle: no

Gradle's command-line reference covers task execution, `dependencies` / `dependencyInsight` / `buildEnvironment` reports, locking (`--write-locks`), verification, and `gradle init` / `wrapper`. There is no built-in task or flag that inserts `implementation("g:a:v")` into `build.gradle(.kts)` or a version catalog.

Source: [Command-Line Interface](https://docs.gradle.org/current/userguide/command_line_interface.html) (Gradle 9.7.0).

A Neovim plugin that supports Gradle must **edit the build script or catalog itself** (or a third-party helper, which is out of scope for this primary-source note).

## Failure modes

### Ambiguous class names

`c:List` / `c:Logger` / `c:Json` hit many artifacts. Both UIs force a pick:

- IntelliJ: tree of FQCN + GAV, versions as children, newest first.
- VS Code: QuickPick of `className` / `fullClassName` / `g : a : v`, usage-ranked, Azure bias in vscode-maven.

A plugin should never auto-apply a simple-name hit. FQCN (`fc:`) is much tighter when the import is already written.

### Missing or wrong version

- Solr **coordinate** search returns `latestVersion` of the artifact, which may not be the version that first contained the class, and may be a milestone.
- Solr **class** search returns *a* version that contains the class, not necessarily the latest.
- IntelliJ's index can be stale until the user clicks **Update**.
- vscode-maven's bundled Lucene index is a snapshot shipped with the extension; Solr is only a fallback when local hits &lt; 5.
- Writing `latestVersion` into a Spring Boot project often **overrides** the BOM (see next).

### Gradle version catalogs

Gradle auto-imports `gradle/libs.versions.toml` as `libs`. Build scripts then use `implementation(libs.foo.bar)` instead of a string GAV. Catalogs hold only group/name/version (no classifier/type/exclude). Neither IntelliJ's Maven quick-fix nor vscode-maven's POM editor writes this file. Naively inserting `implementation("g:a:v")` into `build.gradle.kts` on a catalog-first project is the wrong edit.

Source: [Version Catalogs](https://docs.gradle.org/current/userguide/version_catalogs.html).

### BOMs and Spring Boot dependency management

Spring Boot publishes a curated BOM (`spring-boot-dependencies`) used from Maven and Gradle. You **do not need to provide a version** for curated dependencies; upgrading Boot upgrades those versions together. You may still pin a version to override.

Gradle consumes that BOM with `implementation(platform("org.springframework.boot:spring-boot-dependencies:…"))` (or the Spring Boot plugin's equivalent) and then `implementation("g:a")` **without** a version.

Maven typically inherits `spring-boot-starter-parent` or imports the BOM in `<dependencyManagement>` (`type=pom`, `scope=import`) and then lists `<dependency>` without `<version>`.

IntelliJ's Java quick-fix and vscode-maven's `pomEdit` **always write `<version>`**. That can:

- silently override Boot's curated version, or
- add a second, versioned declaration next to an existing managed one.

Maven `dependency:add` is the only first-party tool in this survey that **omits** `<version>` when management already supplies it.

IntelliJ *can* insert a versionless managed dependency, but only from **Generate → Managed Dependency** in the POM, not from the Java quick-fix.

Sources: [Spring Boot – Build Systems](https://docs.spring.io/spring-boot/reference/using/build-systems.html); [Gradle Platforms](https://docs.gradle.org/current/userguide/platforms.html); IntelliJ Maven "Managed Dependency" docs; vscode-maven `AddDependencyHandler.pomEdit`; Maven `dependency:add` version inference.

### Other Gradle / Maven edit traps

| Trap | Why it matters |
| --- | --- |
| Multi-module POM | vscode-maven writes `javaProject/pom.xml` next to the Java project root. IntelliJ writes the containing Maven module's POM. Wrong module → dependency on the unused classpath. Maven CLI: use `-pl`. |
| `build.gradle` vs `.kts` | Groovy string vs Kotlin `implementation("…")`. IDEs' Gradle completion follows the file that exists. |
| Test vs main | IntelliJ Maven quick-fix sets `test` scope from source-root membership. vscode-maven does not. |
| Unmanaged / invisible JDT project | VS Code "Referenced Libraries" edits settings, not a build file. JDT-LS `updateClassPaths` is the same idea. |
| Duplicate / property GAV | Maven `dependency:add` refuses. vscode-maven skips POM edit if `GetPosHandler` thinks the dependency exists. |
| Catalogs + platforms together | A correct Gradle add may need: catalog alias + `platform(...)` and **no** version. No first-party CLI does that. |

## Implications for a Neovim plugin (nvim-spring)

Not an implementation plan — just what the sources allow.

1. **Class → candidates:** call Maven Central Solr `c:` / `fc:` (documented, no index to host). Optionally ship or download a Lucene Central class index like IntelliJ / vscode-maven if offline or recall matters.
2. **User must pick** when more than one GAV matches.
3. **Maven write:** prefer `mvn dependency:add` (3.11.0+) so BOM/version inference and duplicate detection are Maven's. Fallback: same XML insert as vscode-maven (always-versioned `<dependency>`).
4. **Gradle write:** no supported CLI. The plugin would have to edit `build.gradle` / `build.gradle.kts` / `gradle/libs.versions.toml` itself and then ask JDT-LS to reload (`java.projectConfiguration.update` / nvim-jdtls `update_project_config`).
5. **Do not expect JDT-LS or nvim-jdtls to add the dependency.** After the build file changes, use their existing **reload project** commands so the classpath updates.
6. **Spring Boot:** detect parent BOM / `platform("spring-boot-dependencies")` and omit the version (Maven CLI already does this when management exists).

## Sources (absolute)

- IntelliJ: https://www.jetbrains.com/help/idea/work-with-maven-dependencies.html
- IntelliJ: https://www.jetbrains.com/help/idea/maven-repositories.html
- IntelliJ: https://www.jetbrains.com/help/idea/work-with-gradle-dependency-diagram.html
- IntelliJ: https://www.jetbrains.com/help/idea/package-search.html
- IntelliJ source: https://github.com/JetBrains/intellij-community/blob/master/plugins/maven/src/main/java/org/jetbrains/idea/maven/dom/intentions/AddMavenDependencyQuickFix.java
- IntelliJ source: https://github.com/JetBrains/intellij-community/blob/master/plugins/maven/src/main/java/org/jetbrains/idea/maven/indices/MavenClassSearcher.kt
- VS Code: https://code.visualstudio.com/docs/java/java-project
- vscode-maven: https://github.com/microsoft/vscode-maven/blob/main/src/jdtls/artifactSearcher.ts
- vscode-maven: https://github.com/microsoft/vscode-maven/blob/main/jdtls.ext/com.microsoft.java.maven.plugin/src/main/java/com/microsoft/java/maven/ArtifactSearcher.java
- JDT-LS: https://github.com/eclipse-jdtls/eclipse.jdt.ls/blob/main/org.eclipse.jdt.ls.core/plugin.xml
- nvim-jdtls: https://github.com/mfussenegger/nvim-jdtls/blob/master/doc/jdtls.txt
- Maven Central Solr: https://central.sonatype.org/search/rest-api-guide/
- Maven Dependency Plugin: https://maven.apache.org/plugins/maven-dependency-plugin/usage.html
- Maven Dependency Plugin: https://maven.apache.org/plugins/maven-dependency-plugin/examples/managing-dependencies.html
- Gradle CLI: https://docs.gradle.org/current/userguide/command_line_interface.html
- Gradle catalogs: https://docs.gradle.org/current/userguide/version_catalogs.html
- Gradle platforms: https://docs.gradle.org/current/userguide/platforms.html
- Spring Boot: https://docs.spring.io/spring-boot/reference/using/build-systems.html
