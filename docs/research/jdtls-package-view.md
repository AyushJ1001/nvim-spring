# Does JDT-LS expose a Package view?

**Ticket:** [#6](https://github.com/AyushJ1001/nvim-spring/issues/6)
**Question:** Does Eclipse JDT Language Server (and nvim-jdtls, and VS Code Java's Project Explorer) expose a Package view — source roots, packages, types — that a Neovim plugin can query or render, or is that view entirely a VS Code client invention?

**Answer, in one sentence:** Core JDT-LS and nvim-jdtls do **not** expose a package/type tree. VS Code's **Java Projects** explorer is a client TreeView in [microsoft/vscode-java-dependency](https://github.com/microsoft/vscode-java-dependency) that incrementally queries a **Microsoft JDT-LS extension bundle** (`java.getPackageData` / `java.project.list` / `java.resolvePath`). A Neovim explorer can reuse that bundle the same way nvim-jdtls already loads java-debug, but it still has to build the tree, refresh, and reveal-in-view itself.

---

## 1. Core JDT-LS: no Package view command

JDT-LS is a Language Server Protocol implementation plus a `workspace/executeCommand` extension point. Commands are registered in `org.eclipse.jdt.ls.core/plugin.xml` under `org.eclipse.jdt.ls.core.delegateCommandHandler` and dispatched by `JDTDelegateCommandHandler`.

Source: [plugin.xml (main)](https://github.com/eclipse-jdtls/eclipse.jdt.ls/blob/main/org.eclipse.jdt.ls.core/plugin.xml), [JDTDelegateCommandHandler.java](https://github.com/eclipse-jdtls/eclipse.jdt.ls/blob/main/org.eclipse.jdt.ls.core/src/org/eclipse/jdt/ls/core/internal/JDTDelegateCommandHandler.java), [WorkspaceExecuteCommandHandler.java](https://github.com/eclipse-jdtls/eclipse.jdt.ls/blob/main/org.eclipse.jdt.ls.core/src/org/eclipse/jdt/ls/core/internal/handlers/WorkspaceExecuteCommandHandler.java).

There is **no** `java.getPackageData`, `java.project.list`, or `java.resolvePath` in core JDT-LS. The closest built-in commands:

| Command | What it returns | Source |
|---|---|---|
| `java.project.getAll` | `List<URI>` of project folder URIs. Optional arg `{ includeNonJava: boolean }`. Default is Java projects only. | [ProjectCommand.getAllJavaProjects / getAllProjects](https://github.com/eclipse-jdtls/eclipse.jdt.ls/blob/main/org.eclipse.jdt.ls.core/src/org/eclipse/jdt/ls/core/internal/commands/ProjectCommand.java) |
| `java.project.listSourcePaths` | `{ status, message, data: SourcePath[] }` where each `SourcePath` has `path`, `displayPath`, `classpathEntry`, `projectName`, `projectType`. | [BuildPathCommand.listSourcePaths](https://github.com/eclipse-jdtls/eclipse.jdt.ls/blob/main/org.eclipse.jdt.ls.core/src/org/eclipse/jdt/ls/core/internal/commands/BuildPathCommand.java) |
| `java.project.getSettings` | `Map<String, Object>` for a file/project URI and a list of keys. The key `org.eclipse.jdt.ls.core.sourcePaths` returns that project's source-root OS paths. Also: nature ids, VM location, output path, referenced libraries, classpath entries. | [ProjectCommand.getProjectSettings](https://github.com/eclipse-jdtls/eclipse.jdt.ls/blob/main/org.eclipse.jdt.ls.core/src/org/eclipse/jdt/ls/core/internal/commands/ProjectCommand.java) |
| `java.project.getClasspaths` | `{ projectRoot, classpaths[], modulepaths[] }` for a URI + `{ scope }`. Runtime classpath, not a package tree. | same file |
| `java.project.addToSourcePath` / `removeFromSourcePath` | Mutate unmanaged-folder source roots. | [BuildPathCommand](https://github.com/eclipse-jdtls/eclipse.jdt.ls/blob/main/org.eclipse.jdt.ls.core/src/org/eclipse/jdt/ls/core/internal/commands/BuildPathCommand.java) |

Standard LSP that is **not** a Package view but can help a client invent one:

- `textDocument/documentSymbol` and `workspace/symbol` are supported ([wiki: Language Server Protocol support](https://github.com/eclipse-jdtls/eclipse.jdt.ls/wiki/Language-Server-Protocol-support)).
- Initialize options include `bundles?: string[]` — JAR paths of JDT-LS extension plugins loaded at start ([wiki: Running the JAVA LS server from the command line](https://github.com/eclipse-jdtls/eclipse.jdt.ls/wiki/Running-the-JAVA-LS-server-from-the-command-line)).
- Extra bundles can be added later with `java.reloadBundles` ([JDTDelegateCommandHandler](https://github.com/eclipse-jdtls/eclipse.jdt.ls/blob/main/org.eclipse.jdt.ls.core/src/org/eclipse/jdt/ls/core/internal/JDTDelegateCommandHandler.java)).

How third-party commands get into the server: implement `IDelegateCommandHandler`, register commands on `org.eclipse.jdt.ls.core.delegateCommandHandler`, put the JAR on `initializationOptions.bundles` ([wiki: Contribute an extension bundle](https://github.com/eclipse-jdtls/eclipse.jdt.ls/wiki/Contribute-an-extension-bundle)). That is how the Package view data API is added — it is not in the core product.

---

## 2. VS Code Java (redhat.java): no Project Explorer

[Language Support for Java by Red Hat](https://github.com/redhat-developer/vscode-java) is the JDT-LS client. Its `package.json` contributes language features, settings, and commands such as `java.execute.workspaceCommand` (the VS Code wrapper around `workspace/executeCommand`). It does **not** contribute a `javaProjectExplorer` view.

Source: [vscode-java package.json](https://github.com/redhat-developer/vscode-java/blob/master/package.json), [commands.ts `EXECUTE_WORKSPACE_COMMAND`](https://github.com/redhat-developer/vscode-java/blob/master/src/commands.ts).

Core vscode-java *does* wrap a few JDT-LS project commands as user-facing actions (`java.project.listSourcePaths.command`, `java.project.getAll`, `java.project.getSettings`, add/remove source path). Those are source-path / project-URI helpers, not a package tree. See the same `commands.ts` (`LIST_SOURCEPATHS`, `GET_ALL_JAVA_PROJECTS`).

How a sibling extension injects a server bundle: contribute `"javaExtensions": ["./server/my.java.plugin.jar"]` in `package.json`; talk to the plugin via `java.execute.workspaceCommand` ([wiki: Contribute a Java Extension](https://github.com/redhat-developer/vscode-java/wiki/Contribute-a-Java-Extension)).

---

## 3. The Package view lives in Project Manager for Java

Official VS Code docs: the **Java Projects** view is provided by [Project Manager for Java](https://marketplace.visualstudio.com/items?itemName=vscjava.vscode-java-dependency), not by Language Support for Java itself. ([Managing Java Projects in VS Code](https://code.visualstudio.com/docs/java/java-project).)

The extension's own README: "A lightweight extension to provide additional Java project explorer features. It works with Language Support for Java by Red Hat." It documents a Project View screenshot, flat vs hierarchical package presentation (`java.dependency.packagePresentation`), member display (`java.dependency.showMembers`), and non-Java resource toggle. ([README](https://github.com/microsoft/vscode-java-dependency/blob/main/README.md).)

### 3.1 Server half: a JDT-LS bundle

`package.json` contributes the bundle:

```json
"contributes": {
  "javaExtensions": [
    "./server/com.microsoft.jdtls.ext.core-0.24.1.jar"
  ]
}
```

Source: [package.json](https://github.com/microsoft/vscode-java-dependency/blob/main/package.json).

That JAR's `plugin.xml` registers:

| Command id | Handler |
|---|---|
| `java.project.list` | `ProjectCommand.listProjects` |
| `java.getPackageData` | `PackageCommand.getChildren` |
| `java.resolvePath` | `PackageCommand.resolvePath` |
| `java.project.refreshLib` | libraries |
| `java.project.getMainClasses` | export-jar |
| `java.project.generateJar` | export-jar |
| `java.project.checkImportStatus` | import banner |
| `java.project.getImportClassContent` | Copilot context |
| `java.project.getDependencies` | Copilot / checkup |
| `java.project.getFileImports` | Copilot |

Source: [jdtls.ext/.../plugin.xml](https://github.com/microsoft/vscode-java-dependency/blob/main/jdtls.ext/com.microsoft.jdtls.ext.core/plugin.xml), [CommandHandler.java](https://github.com/microsoft/vscode-java-dependency/blob/main/jdtls.ext/com.microsoft.jdtls.ext.core/src/com/microsoft/jdtls/ext/core/CommandHandler.java).

### 3.2 `java.project.list`

Arguments: `[workspaceUri: string, filterNonJava?: boolean]`.

Returns: `List<PackageNode>` of kind `PROJECT` (skips Eclipse's default project). Each node has name, URI of the real project folder, nature ids in `metaData.NatureId`, `MaxSourceVersion`, and optionally `UnmanagedFolderInnerPath`.

Source: [ProjectCommand.listProjects](https://github.com/microsoft/vscode-java-dependency/blob/main/jdtls.ext/com.microsoft.jdtls.ext.core/src/com/microsoft/jdtls/ext/core/ProjectCommand.java), [PackageNode.createNodeForProject](https://github.com/microsoft/vscode-java-dependency/blob/main/jdtls.ext/com.microsoft.jdtls.ext.core/src/com/microsoft/jdtls/ext/core/model/PackageNode.java).

### 3.3 `java.getPackageData` — the tree API

This is **children of one node**, not the whole tree.

Argument: one `PackageParams` object ([PackageParams.java](https://github.com/microsoft/vscode-java-dependency/blob/main/jdtls.ext/com.microsoft.jdtls.ext.core/src/com/microsoft/jdtls/ext/core/PackageParams.java)):

| Field | Role |
|---|---|
| `kind` | Which loader: `PROJECT`, `CONTAINER`, `PACKAGEROOT`, `PACKAGE`, `FOLDER` |
| `projectUri` | Project folder URI |
| `path` | Container / folder portable path (`REFERENCED_LIBRARIES_PATH` for referenced JARs) |
| `handlerIdentifier` | JDT `IJavaElement.getHandleIdentifier()` |
| `rootPath` | Package-fragment-root path (needed for JARs in Referenced Libraries) |
| `isHierarchicalView` | If true, package-root listing uses a Trie so only "interesting" parent packages appear |
| `syncPaths` | Optional changed-file URIs so auto-refresh deep-refreshes only those subtrees |

Returns: `List<PackageNode>`. Dispatch is `commands.get(params.kind)` in [PackageCommand.getChildren](https://github.com/microsoft/vscode-java-dependency/blob/main/jdtls.ext/com.microsoft.jdtls.ext.core/src/com/microsoft/jdtls/ext/core/PackageCommand.java).

What each kind expands to:

- **PROJECT** — source `IPackageFragmentRoot`s, classpath containers (JRE, Maven, Gradle), non-Java resources, plus a synthetic "Referenced Libraries" container when needed.
- **CONTAINER** — JARs / package roots inside that container, or referenced libraries when `path == REFERENCED_LIBRARIES_PATH`.
- **PACKAGEROOT** — packages (flat or hierarchical) plus non-Java resources under the source/binary root. Empty intermediate packages are omitted.
- **PACKAGE** — primary types (`IType`) in that package (inner `$` class files filtered), plus non-Java resources.
- **FOLDER** — files/folders (including JAR entry directories).

### 3.4 `java.resolvePath`

Argument: one URI string of a `.java` / `.class` / resource.

Returns: `List<PackageNode>` from project down to the file/type — used to reveal the active editor in the tree.

Source: [PackageCommand.resolvePath](https://github.com/microsoft/vscode-java-dependency/blob/main/jdtls.ext/com.microsoft.jdtls.ext.core/src/com/microsoft/jdtls/ext/core/PackageCommand.java).

### 3.5 Node shape

`NodeKind` (same integers on Java and TypeScript): `WORKSPACE=1`, `PROJECT=2`, `PACKAGEROOT=3`, `PACKAGE=4`, `PRIMARYTYPE=5`, `COMPILATIONUNIT=6`, `CLASSFILE=7`, `CONTAINER=8`, `FOLDER=9`, `FILE=10`.

Sources: [NodeKind.java](https://github.com/microsoft/vscode-java-dependency/blob/main/jdtls.ext/com.microsoft.jdtls.ext.core/src/com/microsoft/jdtls/ext/core/model/NodeKind.java), [nodeData.ts](https://github.com/microsoft/vscode-java-dependency/blob/main/src/java/nodeData.ts).

`PackageNode` / `INodeData` JSON fields: `name`, `displayName`, `moduleName`, `path`, `handlerIdentifier`, `uri`, `kind`, `children`, `metaData`. Type nodes set `metaData.TypeKind` to `1=class`, `2=interface`, `3=enum`. Package-root nodes may carry Maven GAV in metadata and a computed `displayName` of `groupId:artifactId:version`.

Source: [PackageNode.java](https://github.com/microsoft/vscode-java-dependency/blob/main/jdtls.ext/com.microsoft.jdtls.ext.core/src/com/microsoft/jdtls/ext/core/model/PackageNode.java).

### 3.6 Client half: a VS Code TreeView

The explorer id is `javaProjectExplorer` ("Java Projects"), contributed under `views.explorer` ([package.json](https://github.com/microsoft/vscode-java-dependency/blob/main/package.json)).

Call path:

1. Roots: `Jdtls.getProjects(workspaceUri)` → `java.execute.workspaceCommand` + `java.project.list` ([jdtls.ts](https://github.com/microsoft/vscode-java-dependency/blob/main/src/java/jdtls.ts), [dependencyDataProvider.ts](https://github.com/microsoft/vscode-java-dependency/blob/main/src/views/dependencyDataProvider.ts)).
2. Project children: `ProjectNode.loadData` → `Jdtls.getPackageData({ kind: Project, projectUri })` ([projectNode.ts](https://github.com/microsoft/vscode-java-dependency/blob/main/src/views/projectNode.ts)).
3. Source-root children: `PackageRootNode.loadData` → `getPackageData({ kind: PackageRoot, handlerIdentifier, isHierarchicalView, syncPaths })` ([packageRootNode.ts](https://github.com/microsoft/vscode-java-dependency/blob/main/src/views/packageRootNode.ts)).
4. Reveal: `java.resolvePath` then walk the tree.
5. Members under a type (optional `java.dependency.showMembers`): **not** the Microsoft bundle — `vscode.executeDocumentSymbolProvider` on the type's URI ([PrimaryTypeNode.ts](https://github.com/microsoft/vscode-java-dependency/blob/main/src/views/PrimaryTypeNode.ts)). That is standard LSP `textDocument/documentSymbol` via JDT-LS.

Client-only work (not returned by the server as a ready-to-render tree):

- VS Code `TreeDataProvider` + node cache + debounce refresh (`java.dependency.refreshDelay`, default 2000 ms).
- Hierarchical package nesting on the **client** as well (`HierarchicalPackageNodeData`), in addition to the server Trie when `isHierarchicalView` is set.
- Filtering folders/files when `java.project.explorer.showNonJavaResources` is false, plus VS Code `files.exclude`.
- Progressive root population while import is still running.
- New type/package/file commands, export-jar, link-with-editor, icons, context menus.

---

## 4. nvim-jdtls: no Package view

nvim-jdtls is a Neovim LSP client for eclipse.jdt.ls. Its advertised extras are organize-imports, extract, generate constructors/`toString`/`equals`, class-file contents, DAP, and vscode-java-test helpers. There is no explorer, package view, or `java.getPackageData` wrapper.

Source: [README](https://github.com/mfussenegger/nvim-jdtls/blob/master/README.md) (local checkout: `/home/ayush/.local/share/nvim/lazy/nvim-jdtls/README.md`).

It already uses the **core** command `java.project.getAll` to pick project URIs for `java/buildProjects`:

```lua
local command = { command = 'java.project.getAll' }
local err, projects = util.execute_command(command, nil, bufnr)
```

Source: `/home/ayush/.local/share/nvim/lazy/nvim-jdtls/lua/jdtls.lua` (`pick_projects`). Other core commands it calls: `java.project.getSettings`, `java.project.updateSettings`, `java.project.getClasspaths`, `java.project.isTestFile`. Grep of that tree finds no `getPackageData`, `java.project.list`, or `java.resolvePath`.

It already documents the hook a Neovim plugin would use to load the Microsoft bundle: `init_options.bundles` (same path used for java-debug). Commands go out as LSP `workspace/executeCommand` via `jdtls.util.execute_command`.

---

## 5. What a Neovim explorer would still have to build

Two viable data strategies:

### A. Reuse the Microsoft bundle (same data as VS Code)

1. Ship or download `com.microsoft.jdtls.ext.core-*.jar` from vscode-java-dependency.
2. Add it to nvim-jdtls `init_options.bundles` (or `java.reloadBundles` after start).
3. After JDT-LS reports the new commands in `executeCommandProvider`, call:
   - `java.project.list` for roots
   - `java.getPackageData` on expand
   - `java.resolvePath` to reveal the current buffer
4. Still implement: tree UI (Snacks picker, neo-tree source, or a dedicated window), lazy expand, hierarchical vs flat grouping, refresh/watch (optionally pass `syncPaths`), filter non-Java resources, icons, and any "new class / new package" actions. Type members can use stock `textDocument/documentSymbol`.

The bundle is a JDT-LS plugin, not VS Code-specific, so this is a real reuse path — not a VS Code-only invention at the *data* layer. The **view** is a VS Code TreeView invention.

### B. Stay on core JDT-LS only

1. `java.project.getAll` → project URIs.
2. `java.project.listSourcePaths` or `java.project.getSettings` + `org.eclipse.jdt.ls.core.sourcePaths` → source roots.
3. Walk those directories, treat folder names as packages, list `*.java` as types.
4. Optionally `workspace/symbol` / `documentSymbol` for types and members.

You lose JDT-model facts the Microsoft command has: classpath containers, referenced libraries / JAR internals, default-package handling, empty-package elision, test-vs-main metadata, unmanaged-folder quirks, `handlerIdentifier`s, and a server-side reveal path. You do not need an extra OSGi bundle.

### Not enough by themselves

- `workspace/symbol` — flat symbol search, not source-root → package → type.
- `textDocument/documentSymbol` — one file's outline (what VS Code uses only *under* a type).
- nvim-jdtls `extended_symbols` — document-level, including base classes; not a project explorer.

---

## 6. Sources

- [eclipse.jdt.ls plugin.xml](https://github.com/eclipse-jdtls/eclipse.jdt.ls/blob/main/org.eclipse.jdt.ls.core/plugin.xml)
- [JDTDelegateCommandHandler.java](https://github.com/eclipse-jdtls/eclipse.jdt.ls/blob/main/org.eclipse.jdt.ls.core/src/org/eclipse/jdt/ls/core/internal/JDTDelegateCommandHandler.java)
- [ProjectCommand.java (core)](https://github.com/eclipse-jdtls/eclipse.jdt.ls/blob/main/org.eclipse.jdt.ls.core/src/org/eclipse/jdt/ls/core/internal/commands/ProjectCommand.java)
- [BuildPathCommand.java](https://github.com/eclipse-jdtls/eclipse.jdt.ls/blob/main/org.eclipse.jdt.ls.core/src/org/eclipse/jdt/ls/core/internal/commands/BuildPathCommand.java)
- [JDT-LS wiki: LSP support](https://github.com/eclipse-jdtls/eclipse.jdt.ls/wiki/Language-Server-Protocol-support)
- [JDT-LS wiki: Contribute an extension bundle](https://github.com/eclipse-jdtls/eclipse.jdt.ls/wiki/Contribute-an-extension-bundle)
- [JDT-LS wiki: Initialize `bundles`](https://github.com/eclipse-jdtls/eclipse.jdt.ls/wiki/Running-the-JAVA-LS-server-from-the-command-line)
- [vscode-java package.json](https://github.com/redhat-developer/vscode-java/blob/master/package.json)
- [vscode-java commands.ts](https://github.com/redhat-developer/vscode-java/blob/master/src/commands.ts)
- [vscode-java wiki: Contribute a Java Extension](https://github.com/redhat-developer/vscode-java/wiki/Contribute-a-Java-Extension)
- [VS Code docs: Managing Java Projects](https://code.visualstudio.com/docs/java/java-project)
- [vscode-java-dependency README](https://github.com/microsoft/vscode-java-dependency/blob/main/README.md)
- [vscode-java-dependency package.json](https://github.com/microsoft/vscode-java-dependency/blob/main/package.json)
- [com.microsoft.jdtls.ext.core plugin.xml](https://github.com/microsoft/vscode-java-dependency/blob/main/jdtls.ext/com.microsoft.jdtls.ext.core/plugin.xml)
- [PackageCommand.java](https://github.com/microsoft/vscode-java-dependency/blob/main/jdtls.ext/com.microsoft.jdtls.ext.core/src/com/microsoft/jdtls/ext/core/PackageCommand.java)
- [ProjectCommand.java (ext)](https://github.com/microsoft/vscode-java-dependency/blob/main/jdtls.ext/com.microsoft.jdtls.ext.core/src/com/microsoft/jdtls/ext/core/ProjectCommand.java)
- [jdtls.ts (client)](https://github.com/microsoft/vscode-java-dependency/blob/main/src/java/jdtls.ts)
- nvim-jdtls `/home/ayush/.local/share/nvim/lazy/nvim-jdtls` — `README.md`, `lua/jdtls.lua`, `lua/jdtls/util.lua`
