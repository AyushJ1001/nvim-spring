# How Spring Initializr can be driven without a browser

Research for [issue #3](https://github.com/AyushJ1001/nvim-spring/issues/3).
Captured 2026-08-14. Primary sources only.

## Answer

There are three Spring-owned, first-party ways to create a Spring Boot project without a browser:

1. **start.spring.io HTTP API** — the hosted Initializr. `GET` the root for metadata; `GET` or `POST` `/starter.zip`, `/starter.tgz`, `/pom.xml`, or `/build.gradle` to generate. Official user guide: [USING.adoc](https://github.com/spring-io/start.spring.io/blob/main/USING.adoc). Protocol: [Spring Initializr Reference Guide, current](https://docs.spring.io/initializr/docs/current/reference/html/).
2. **Spring Boot CLI `spring init`** — still current as of Spring Boot 4.1.0. It is an HTTP client for start.spring.io. Docs: [Using the CLI](https://docs.spring.io/spring-boot/cli/using-the-cli.html). Source: [`InitCommand.java` at `v4.1.0`](https://github.com/spring-projects/spring-boot/blob/v4.1.0/cli/spring-boot-cli/src/main/java/org/springframework/boot/cli/command/init/InitCommand.java).
3. **Embedding `io.spring.initializr`** — the official generator library. Not a user-facing CLI. You host an instance or call `ProjectGenerator` from Java. Docs: [Configuration Guide](https://docs.spring.io/initializr/docs/current/reference/html/#configuration-guide).

A fourth Spring-owned tool, **Spring CLI** (`spring boot new`, `spring initializr new`), exists in docs but is **not current**: the repo is in [spring-attic/spring-cli](https://github.com/spring-attic/spring-cli), archived 2025-05-14, README: “THIS REPOSITORY IS NO LONGER ACTIVELY MAINTAINED”.

IDE integrations (STS, IntelliJ Ultimate, NetBeans, VS Code) are official clients of the same HTTP API ([USING.adoc, IDEs](https://github.com/spring-io/start.spring.io/blob/main/USING.adoc)) but they are not headless.

There is **no official offline project factory** for end users. Both curl and `spring init` need a network path to an Initializr (default `https://start.spring.io`). Offline generation is only possible by embedding the Initializr library and supplying your own metadata.

## What is official

| Thing | Official? | Role |
| --- | --- | --- |
| [start.spring.io](https://start.spring.io) | Yes — Spring-hosted Initializr instance ([start.spring.io README](https://github.com/spring-io/start.spring.io/blob/main/README.adoc)) | Public HTTP service + web UI |
| [spring-io/initializr](https://github.com/spring-io/initializr) library + HTTP contract | Yes — [docs.spring.io/initializr](https://docs.spring.io/initializr/docs/current/reference/html/) | Generator engine and versioned JSON metadata |
| Spring Boot CLI `spring init` | Yes, current in Boot 4.1.0 ([CLI index](https://docs.spring.io/spring-boot/cli/index.html), [USING.adoc](https://github.com/spring-io/start.spring.io/blob/main/USING.adoc)) | Headless client of start.spring.io |
| cURL / HTTPie against the service | Yes — documented first-party usage, not Spring-owned binaries ([USING.adoc](https://github.com/spring-io/start.spring.io/blob/main/USING.adoc); [Initializr §8](https://docs.spring.io/initializr/docs/current/reference/html/#configuration-access)) | Discover + generate |
| Spring CLI (`spring-attic/spring-cli`) | Was Spring-owned; **not maintained** ([README.adoc](https://raw.githubusercontent.com/spring-attic/spring-cli/main/README.adoc)) | Clone-a-sample (`boot new`) and a separate Initializr client (`initializr new`) |
| IDE plugins listed in USING.adoc | Official clients | Not headless |
| Third-party CLIs wrapping start.spring.io | Not official | Out of scope |

The Initializr library “does not provide a Web UI”; start.spring.io adds the UI ([Initializr §5](https://docs.spring.io/initializr/docs/current/reference/html/#supported-clients); [start.spring.io README](https://github.com/spring-io/start.spring.io/blob/main/README.adoc)).

---

## 1. start.spring.io HTTP API

### Host tools and network

- **Network:** HTTPS to `https://start.spring.io` (or another Initializr `--target` / instance).
- **Client:** any HTTP client. First-party docs show `curl` and `HTTPie` ([USING.adoc](https://github.com/spring-io/start.spring.io/blob/main/USING.adoc)).
- **Java / Maven / Gradle on the host:** not required to *download* a project. Generated archives include Maven Wrapper (`./mvnw`) or Gradle Wrapper (`./gradlew`) ([USING.adoc](https://github.com/spring-io/start.spring.io/blob/main/USING.adoc)).
- **User-Agent:** Initializr asks third-party clients to send `User-Agent: clientId/clientVersion` on **each** request ([API Guide §11](https://docs.spring.io/initializr/docs/current/reference/html/#metadata-format)). The Boot CLI sends `SpringBootCli/<version>` ([`InitializrService.java`](https://github.com/spring-projects/spring-boot/blob/v4.1.0/cli/spring-boot-cli/src/main/java/org/springframework/boot/cli/command/init/InitializrService.java)).
- **Content negotiation:** a curl-like User-Agent that accepts `text/plain` gets a human-readable capabilities page. `Accept: application/json` or `application/vnd.initializr.v2.x+json` gets HAL JSON. Observed 2026-08-14: `curl -A 'curl/8.0.0' https://start.spring.io` → `Content-Type: text/plain`. Same URL with a non-curl User-Agent and no Accept → `application/vnd.initializr.v2.1+json`.

### List metadata (boot versions, Java versions, dependencies, types)

**Text (curl/HTTPie):**

```bash
curl https://start.spring.io
# or
http https://start.spring.io
```

The body is three sections: project types, request parameters (with defaults), then dependency ids + descriptions + version ranges, then examples ([USING.adoc](https://github.com/spring-io/start.spring.io/blob/main/USING.adoc); [Initializr §8](https://docs.spring.io/initializr/docs/current/reference/html/#configuration-access)).

**JSON (clients / a plugin):**

```http
GET / HTTP/1.1
Host: start.spring.io
Accept: application/vnd.initializr.v2.3+json
User-Agent: nvim-spring/0.0.0
```

Pin the media type. Metadata “may evolve in a non backward compatible way”; the Accept header selects the format you expect ([API Guide §11.1](https://docs.spring.io/initializr/docs/current/reference/html/#service-capabilities)).

Supported metadata versions ([same section](https://docs.spring.io/initializr/docs/current/reference/html/#service-capabilities)):

| Version | Meaning |
| --- | --- |
| `v2` | Initial; V1 platform-version strings only |
| `v2.1` | Compatibility ranges + dependency links |
| `v2.2` | V1 and V2 (SemVer) platform version formats |
| `v2.3` (current) | Adds `configurationFileFormat` |

The JSON document is HAL. Top-level capabilities ([§11.1](https://docs.spring.io/initializr/docs/current/reference/html/#service-capabilities)):

| Field | Type | What it lists |
| --- | --- | --- |
| `bootVersion` | `single-select` | Platform / Spring Boot versions (`id`, `name`, `default`) |
| `javaVersion` | `single-select` | Java language levels |
| `dependencies` | `hierarchical-multi-select` | Groups → `{id, name, description, versionRange?, _links?}` |
| `type` | `action` | Project types + `action` path + `tags` (`build`, `format`, `dialect`) |
| `language` | `single-select` | `java`, `kotlin`, `groovy` |
| `packaging` | `single-select` | `jar`, `war` |
| `configurationFileFormat` | `single-select` | `properties`, `yaml` (v2.3 only) |
| `groupId`, `artifactId`, `version`, `name`, `description`, `packageName` | `text` | Defaults |
| `_links` | HAL | Templated generation URLs + `dependencies{?bootVersion}` |

Each capability has `type`, `default`, and optional `values`. Use `default` as the UI hint ([§11.2](https://docs.spring.io/initializr/docs/current/reference/html/#defaults)).

**Resolved dependency coordinates** (not just ids):

```
GET https://start.spring.io/dependencies?bootVersion=<id>
```

Documented as `_links.dependencies` ([example in §11.1](https://docs.spring.io/initializr/docs/current/reference/html/#service-capabilities)). Observed 2026-08-14 for `bootVersion=4.1.0.RELEASE`: JSON with `bootVersion`, `dependencies` (id → `groupId`/`artifactId`/`scope`/`bom`), `repositories`, `boms`.

### Download a project

Default endpoints on an Initializr instance ([§7.4](https://docs.spring.io/initializr/docs/current/reference/html/#create-instance-types); implemented in [`ProjectGenerationController`](https://github.com/spring-io/initializr/blob/v0.24.0/initializr-web/src/main/java/io/spring/initializr/web/controller/ProjectGenerationController.java)):

| Path | Methods | Result |
| --- | --- | --- |
| `/starter.zip` | GET, POST | Full project zip (`application/zip`) |
| `/starter.tgz` | GET, POST | Full project tar.gz (`application/x-compress`) |
| `/pom.xml` (also `/pom`) | GET, POST | Maven POM only |
| `/build.gradle` (also `/build`) | GET, POST | Gradle build file only |

Query (or form) parameters match the metadata field names. Text help on start.spring.io (2026-08-14) lists:

| Parameter | Meaning | Live default |
| --- | --- | --- |
| `type` | Project type | `gradle-project` |
| `dependencies` | Comma-separated ids | none |
| `bootVersion` | Spring Boot version | `4.1.0` |
| `javaVersion` | Language level | `17` |
| `language` | `java` / `kotlin` / `groovy` | `java` |
| `packaging` | `jar` / `war` | `jar` |
| `groupId` | Maven group | `com.example` |
| `artifactId` | Maven artifact (also archive name) | `demo` |
| `name` | Project / app name | (empty in text table; infer) |
| `applicationName` | Override inferred application class name | `Application` |
| `description` | Project description | (empty) |
| `packageName` | Root package | `com.example.demo` |
| `version` | Project version | `0.0.1-SNAPSHOT` |
| `configurationFileFormat` | `properties` / `yaml` | `properties` |
| `baseDir` | Directory inside the archive | none (unlike the web UI) |

`applicationName` and `baseDir` exist on the HTTP API but not on the web form ([USING.adoc](https://github.com/spring-io/start.spring.io/blob/main/USING.adoc)). Without `baseDir`, unzipping lands files in the current directory. The `-o` filename does **not** set `name` / `artifactId` ([USING.adoc](https://github.com/spring-io/start.spring.io/blob/main/USING.adoc)).

Documented examples ([USING.adoc](https://github.com/spring-io/start.spring.io/blob/main/USING.adoc); live text help prefers `-G` GET):

```bash
# default archive
curl -G https://start.spring.io/starter.zip -o demo.zip

# Maven zip, explicit Boot + starters
curl https://start.spring.io/starter.zip \
  -d dependencies=web,devtools \
  -d bootVersion=3.0.8 \
  -d type=maven-project \
  -d baseDir=my-project \
  -o my-project.zip

# Gradle project unpacked (live help)
curl -G https://start.spring.io/starter.tgz \
  -d dependencies=web,data-jpa \
  -d type=gradle-project \
  -d baseDir=my-dir | tar -xzvf -

# POM only
curl -G https://start.spring.io/pom.xml -d packaging=war -o pom.xml

# HTTPie
http https://start.spring.io/starter.zip dependencies==web,devtools bootVersion==3.0.8 -d
```

Do not trust the filename from your client flag; use `Content-Disposition` (`filename="…"`) ([API Guide §11.1.2](https://docs.spring.io/initializr/docs/current/reference/html/#project-types)). Observed: `/starter.zip?type=maven-project&…` → `attachment; filename="demo.zip"`; `/starter.tgz` → `demo.tar.gz`.

### Maven vs Gradle output

Types advertised by start.spring.io (v2.3 JSON, 2026-08-14):

| `type` id | Name | `action` | tags |
| --- | --- | --- | --- |
| `gradle-project` | Gradle - Groovy | `/starter.zip` | `build=gradle`, `dialect=groovy`, `format=project` |
| `gradle-project-kotlin` | Gradle - Kotlin | `/starter.zip` | `build=gradle`, `dialect=kotlin`, `format=project` |
| `gradle-build` | Gradle Config | `/build.gradle` | `build=gradle`, `format=build` |
| `maven-project` | Maven | `/starter.zip` | `build=maven`, `format=project` |
| `maven-build` | Maven POM | `/pom.xml` | `build=maven`, `format=build` |

`format=project` is a full tree (wrapper + sources + tests + `HELP.md`). `format=build` is only the build file ([§7.4](https://docs.spring.io/initializr/docs/current/reference/html/#create-instance-types), [§11.1.2](https://docs.spring.io/initializr/docs/current/reference/html/#project-types)).

**Default type on the live service is Gradle Groovy**, not Maven. That is what the text help and v2.3 `type.default` both said on 2026-08-14. USING.adoc still says “start.spring.io defaults to Java and Maven” — that sentence is stale relative to the running service.

A typical Maven archive contains `mvnw`, `pom.xml`, `src/main/java/…/DemoApplication.java`, tests, `application.properties`, and (for web) `static/` + `templates/` ([USING.adoc](https://github.com/spring-io/start.spring.io/blob/main/USING.adoc)). Gradle archives use the same layout with the Gradle wrapper.

Dependencies that do not apply to the chosen `bootVersion` are rejected or omitted; the UI/text table shows ranges such as `Requires Spring Boot >=3.2.0` ([USING.adoc](https://github.com/spring-io/start.spring.io/blob/main/USING.adoc)).

### Live values (start.spring.io, 2026-08-14)

These change as Spring Boot releases. Re-query the service; do not hard-code.

- **Boot (`bootVersion`):** default `4.1.0` (v2.3 id) / `4.1.0.RELEASE` (v2.1 id). Also `4.1.1-SNAPSHOT`, `4.0.8-SNAPSHOT`, `4.0.7`. v2.1 uses `*.RELEASE` / `*.BUILD-SNAPSHOT`; v2.3 uses SemVer (`4.1.0`, `4.1.1-SNAPSHOT`) — see [§9.9](https://docs.spring.io/initializr/docs/current/reference/html/#howto-platform-version-format).
- **Java:** `26`, `25`, `21`, `17` (default `17`).
- **Language:** `java` (default), `kotlin`, `groovy`.
- **Dependencies:** 205 ids in grouped metadata; 177 resolved under Boot 4.1.0.RELEASE.
- **Default type:** `gradle-project`.

The curl example “Java 11” in the live text help is stale: `11` is not in the current `javaVersion` list.

---

## 2. Spring Boot CLI — `spring init` (current)

This is the `spring` binary shipped as **Spring Boot CLI**, artifact `org.springframework.boot:spring-boot-cli`. The tool’s own banner says `Spring CLI v4.1.0`; that is **not** the attic Spring CLI project ([Using the CLI](https://docs.spring.io/spring-boot/cli/using-the-cli.html)).

### Status

Current. Documented for Boot 4.1.0 (stable) and listed on the 4.2.0-SNAPSHOT docs tree. start.spring.io names it as a supported client ([USING.adoc](https://github.com/spring-io/start.spring.io/blob/main/USING.adoc)). Commands in 4.1.0: `init`, `encodepassword`, `shell` ([Using the CLI](https://docs.spring.io/spring-boot/cli/using-the-cli.html)). Groovy-script prototyping is no longer the headline; the CLI index now says it bootstraps a project from start.spring.io or encodes a password ([CLI index](https://docs.spring.io/spring-boot/cli/index.html)).

### Host tools and network

- **Java 17+** on the host ([Installing Spring Boot](https://docs.spring.io/spring-boot/installing.html)).
- **Install the CLI:** zip/tar from Maven Central (`spring-boot-cli-4.1.0-bin.{zip,tar.gz}`), SDKMAN (`sdk install springboot`), Homebrew (`brew tap spring-io/tap && brew install spring-boot`), MacPorts, or Scoop ([same page](https://docs.spring.io/spring-boot/installing.html)).
- **Network:** HTTP GET to `--target` (default `https://start.spring.io`) for metadata **and** for the archive ([`InitializrService`](https://github.com/spring-projects/spring-boot/blob/v4.1.0/cli/spring-boot-cli/src/main/java/org/springframework/boot/cli/command/init/InitializrService.java), [`ProjectGenerationRequest.DEFAULT_SERVICE_URL`](https://github.com/spring-projects/spring-boot/blob/v4.1.0/cli/spring-boot-cli/src/main/java/org/springframework/boot/cli/command/init/ProjectGenerationRequest.java)).
- Accept used for metadata: `application/vnd.initializr.v2.1+json,application/vnd.initializr.v2+json` (not v2.3). Accept used for `--list`: `text/plain` first, then those JSON types ([`InitializrService`](https://github.com/spring-projects/spring-boot/blob/v4.1.0/cli/spring-boot-cli/src/main/java/org/springframework/boot/cli/command/init/InitializrService.java)).

### List capabilities

```bash
spring init --list
```

Prints dependencies and project types from the service ([Using the CLI](https://docs.spring.io/spring-boot/cli/using-the-cli.html)). That is the CLI’s way to list Boot-related types and dependency ids. Boot versions and Java versions are on the same service; `--list` is the documented discovery switch.

### Download / extract a project

```bash
# service default type (today: Gradle Groovy project), extracted if location has no extension
spring init my-project

# explicit starters
spring init --dependencies=web,data-jpa my-project

# zip on disk
spring init -d=web my-app.zip

# Gradle + Java 17 + war
spring init --build=gradle --java-version=17 --dependencies=websocket --packaging=war sample-app.zip

# other Initializr
spring init --target https://example.invalid
```

`--extract` / `-x` unpacks; inferred when the location has no extension ([`InitCommand`](https://github.com/spring-projects/spring-boot/blob/v4.1.0/cli/spring-boot-cli/src/main/java/org/springframework/boot/cli/command/init/InitCommand.java)). `--force` overwrites.

Documented flags ([Using the CLI](https://docs.spring.io/spring-boot/cli/using-the-cli.html)): `--artifact-id`, `--boot-version`, `--build`, `--dependencies`, `--description`, `--force`, `--format` (`project` | `build`), `--group-id`, `--java-version`, `--language`, `--list`, `--name`, `--packaging`, `--package-name`, `--type`, `--target`, `--version`, `--extract`.

`--build` + `--format` select a type via metadata tags (`build=maven|gradle`, `format=project|build`) so you often skip `--type` ([Initializr §7.4](https://docs.spring.io/initializr/docs/current/reference/html/#create-instance-types); [`ProjectGenerationRequest.determineProjectType`](https://github.com/spring-projects/spring-boot/blob/v4.1.0/cli/spring-boot-cli/src/main/java/org/springframework/boot/cli/command/init/ProjectGenerationRequest.java)). If several types share those tags (Groovy vs Kotlin Gradle), the CLI errors and asks for `--type`.

### Maven vs Gradle in the CLI

- Docs still print `--build` default **`maven`** ([Using the CLI](https://docs.spring.io/spring-boot/cli/using-the-cli.html)).
- Source at `v4.1.0` defaults `--build` to **`gradle`** ([`InitCommand.java` line with `.defaultsTo("gradle")`](https://github.com/spring-projects/spring-boot/blob/v4.1.0/cli/spring-boot-cli/src/main/java/org/springframework/boot/cli/command/init/InitCommand.java)).
- If you omit `--build` / `--format` / `--type`, the CLI uses the **service** default type ([`determineProjectType`](https://github.com/spring-projects/spring-boot/blob/v4.1.0/cli/spring-boot-cli/src/main/java/org/springframework/boot/cli/command/init/ProjectGenerationRequest.java)), which is currently `gradle-project`.

For a plugin: pass `--type=maven-project` or `--type=gradle-project` (or `gradle-project-kotlin`) explicitly.

---

## 3. Spring CLI (attic — not current)

Repo: [spring-attic/spring-cli](https://github.com/spring-attic/spring-cli). Archived 2025-05-14. README: not actively maintained.

Two different generators, both named `spring`:

| Command | What it actually does | Source |
| --- | --- | --- |
| `spring boot new` | **Clones a GitHub sample** (default catalog `rd-1-2022/…`) and optionally refactors package / GAV. Not Initializr. | [Creating New Projects (0.8)](https://docs.spring.io/spring-cli/reference/0.8/creating-new-projects.html); current 0.9 index still describes this |
| `spring initializr new` | Initializr client; defaults to start.spring.io; can prompt | [Initializr (0.8)](https://docs.spring.io/spring-cli/reference/0.8/initializr.html) |
| `spring initializr dependencies` | Search/list dependency ids | same |
| `spring initializr {list,set,remove}` | Extra Initializr server URLs | same |

`boot new` needs **git** and network to GitHub. It does not list Boot/Java versions from start.spring.io.

Treat this stack as historical. Do not depend on it for a Neovim plugin.

---

## 4. Initializr as a library (official, not a CLI)

`io.spring.initializr:initializr-generator` + `initializr-generator-spring` + `initializr-web` ([§6](https://docs.spring.io/initializr/docs/current/reference/html/#project-generation-overview), current BOM `0.24.0`). `ProjectGenerator` takes a `ProjectDescription` (GAV, build system, language, dependencies, platform version, package, base dir) and writes a tree.

This is how you would generate **without start.spring.io**, but you then own metadata (Boot versions, Java versions, dependency catalog) and must refresh it (`SpringIoInitializrMetadataUpdateStrategy` pulls from `https://api.spring.io/projects/spring-boot/releases` — [§7.3](https://docs.spring.io/initializr/docs/current/reference/html/#create-instance-platform-versions)). That is a hosted-service problem, not a one-shot CLI.

WireMock stubs of the JSON API ship as `initializr-web` classifier `stubs` ([§12](https://docs.spring.io/initializr/docs/current/reference/html/#using-the-stubs)) — useful for testing a client, not for generating user projects.

---

## Implications for a headless Neovim plugin

1. **Preferred protocol:** HTTP to `https://start.spring.io` with `Accept: application/vnd.initializr.v2.3+json` and a `User-Agent` like `nvim-spring/<version>`. Cache metadata (`Cache-Control: max-age=7200` observed).
2. **Lists:** `bootVersion.values`, `javaVersion.values`, `dependencies.values[*].values`, `type.values`. Filter deps by `versionRange` against the chosen Boot id.
3. **Download:** `GET /starter.zip?type=…&dependencies=…&bootVersion=…&javaVersion=…&baseDir=<artifactId>` (add `baseDir` so extract is safe). Maven: `type=maven-project`. Gradle Groovy: `gradle-project`. Gradle Kotlin DSL: `gradle-project-kotlin`.
4. **Host tools:** `curl` is enough; or Neovim’s HTTP client. No need to require the `spring` CLI. Network to start.spring.io is required unless you vendor a full Initializr.
5. **Do not** require Spring CLI (attic). **Do not** assume Maven is the service default.
6. **Do not** hard-code Boot/Java/dep catalogs; they move with the service.

## Sources

- [start.spring.io USING.adoc (main)](https://github.com/spring-io/start.spring.io/blob/main/USING.adoc)
- [start.spring.io README.adoc (main)](https://github.com/spring-io/start.spring.io/blob/main/README.adoc)
- [Spring Initializr Reference Guide (current, 0.24.0)](https://docs.spring.io/initializr/docs/current/reference/html/)
- [`ProjectGenerationController.java` v0.24.0](https://github.com/spring-io/initializr/blob/v0.24.0/initializr-web/src/main/java/io/spring/initializr/web/controller/ProjectGenerationController.java)
- [Spring Boot CLI](https://docs.spring.io/spring-boot/cli/index.html), [Using the CLI](https://docs.spring.io/spring-boot/cli/using-the-cli.html), [Installing](https://docs.spring.io/spring-boot/installing.html) (4.1.0)
- Boot CLI `v4.1.0` source: [`InitCommand.java`](https://github.com/spring-projects/spring-boot/blob/v4.1.0/cli/spring-boot-cli/src/main/java/org/springframework/boot/cli/command/init/InitCommand.java), [`InitializrService.java`](https://github.com/spring-projects/spring-boot/blob/v4.1.0/cli/spring-boot-cli/src/main/java/org/springframework/boot/cli/command/init/InitializrService.java), [`ProjectGenerationRequest.java`](https://github.com/spring-projects/spring-boot/blob/v4.1.0/cli/spring-boot-cli/src/main/java/org/springframework/boot/cli/command/init/ProjectGenerationRequest.java)
- [Spring CLI 0.9 index](https://docs.spring.io/spring-cli/reference/index.html), [0.8 Initializr](https://docs.spring.io/spring-cli/reference/0.8/initializr.html), [0.8 Creating New Projects](https://docs.spring.io/spring-cli/reference/0.8/creating-new-projects.html)
- [spring-attic/spring-cli README](https://github.com/spring-attic/spring-cli)
- Live `GET https://start.spring.io` (text/plain and v2.1 / v2.3 JSON) and `GET /dependencies?bootVersion=4.1.0.RELEASE`, 2026-08-14
