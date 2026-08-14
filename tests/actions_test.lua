local fakes = require("support.fakes")

local IN_CONTRACT_POM = [[
<project>
  <parent>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-parent</artifactId>
    <version>3.3.4</version>
  </parent>
  <properties>
    <java.version>17</java.version>
  </properties>
</project>
]]

-- Actions that need a workspace Build tool (not Initializr).
local EXISTING_PROJECT_ACTIONS = {
  "create",
  "packages",
  "add_dependency",
  "run",
  "stop",
}

local function each_existing_project_action(plugin)
  for _, name in ipairs(EXISTING_PROJECT_ACTIONS) do
    plugin[name](plugin)
  end
end

local JAVA_PATH = "/workspace/src/main/java/com/example/App.java"

local FQCN_JAVA = [[
package com.example;

public class App {
  com.google.common.collect.ImmutableList<String> xs;
}
]]

local FQCN_DIAG = {
  file = JAVA_PATH,
  code = 16777218,
  lnum = 3,
  col = 2,
  end_lnum = 3,
  end_col = 41,
}

local function type_local_plugin(opts)
  opts = opts or {}
  local files = opts.files or {
    ["pom.xml"] = IN_CONTRACT_POM,
    ["src/main/java/com/example/App.java"] = opts.java or FQCN_JAVA,
  }
  return fakes.plugin({
    files = files,
    ui = opts.ui or fakes.ui({ file = opts.file or JAVA_PATH }),
    jdtls = opts.jdtls or fakes.jdtls({
      present = opts.present ~= false,
      running = opts.running ~= false,
      diagnostics = opts.diagnostics or { FQCN_DIAG },
    }),
    central = opts.central,
  })
end

return {
  {
    "Plugin action module requires without lazyvim or lang.java",
    function()
      package.loaded["lazyvim"] = nil
      package.loaded["lazyvim.plugins.extras.lang.java"] = nil
      package.preload["lazyvim"] = function()
        error("Plugin must not require lazyvim")
      end
      package.preload["lazyvim.plugins.extras.lang.java"] = function()
        error("Plugin must not require lang.java")
      end
      package.loaded["nvim-spring.actions"] = nil
      local actions = require("nvim-spring.actions")
      assert_true(type(actions.new) == "function", "action module exposes new()")
      local spring = require("nvim-spring")
      for _, name in ipairs({
        "setup",
        "init",
        "create",
        "packages",
        "add_dependency",
        "run",
        "stop",
      }) do
        assert_true(type(spring[name]) == "function", "require('nvim-spring')." .. name)
      end
    end,
  },
  {
    "Gradle Kotlin DSL root loud-refuses and writes no Gradle file",
    function()
      local plugin, adapters = fakes.plugin({
        files = { ["settings.gradle.kts"] = "rootProject.name = \"demo\"\n" },
      })
      plugin:create()
      assert_contains(fakes.notify_text(adapters.ui), "not implemented yet")
      assert_eq(#adapters.fs.writes, 0)
    end,
  },
  {
    "Initializr does not loud-refuse a Gradle root as not-yet-implemented",
    function()
      local plugin, adapters = fakes.plugin({
        files = { ["build.gradle"] = "plugins { id 'java' }\n" },
      })
      plugin:init()
      assert_not_contains(fakes.notify_text(adapters.ui), "not implemented yet")
      assert_not_contains(fakes.notify_text(adapters.ui), "out of contract")
    end,
  },
  {
    "Gradle root loud-refuses actions that need a Build tool, writes no Gradle file, leaves jdtls up",
    function()
      local plugin, adapters = fakes.plugin({
        files = { ["build.gradle"] = "plugins { id 'java' }\n" },
        jdtls = fakes.jdtls({ present = true, running = true }),
      })
      local before = adapters.fs:read("build.gradle")
      each_existing_project_action(plugin)
      local text = fakes.notify_text(adapters.ui)
      assert_contains(text, "not implemented yet")
      assert_eq(adapters.fs:read("build.gradle"), before)
      assert_eq(#adapters.fs.writes, 0, "must not write Gradle files")
      assert_eq(adapters.jdtls.stops, 0, "must not detach jdtls")
      assert_true(adapters.jdtls.running, "jdtls stays up")
    end,
  },
  {
    "Maven reactor loud-refuses actions that need a Build tool as not-yet-implemented and leaves jdtls up",
    function()
      local plugin, adapters = fakes.plugin({
        files = {
          ["pom.xml"] = [[
<project>
  <modules>
    <module>api</module>
  </modules>
</project>
]],
        },
        jdtls = fakes.jdtls({ present = true, running = true }),
      })
      each_existing_project_action(plugin)
      local text = fakes.notify_text(adapters.ui)
      assert_contains(text, "not implemented yet")
      assert_eq(#adapters.fs.writes, 0)
      assert_eq(adapters.jdtls.stops, 0)
      assert_true(adapters.jdtls.running)
    end,
  },
  {
    "Boot 2 loud-refuses Plugin actions as out of contract and leaves jdtls up",
    function()
      local plugin, adapters = fakes.plugin({
        files = {
          ["pom.xml"] = [[
<project>
  <parent>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-parent</artifactId>
    <version>2.7.18</version>
  </parent>
  <properties>
    <java.version>17</java.version>
  </properties>
</project>
]],
        },
        jdtls = fakes.jdtls({ present = true, running = true }),
      })
      each_existing_project_action(plugin)
      local text = fakes.notify_text(adapters.ui)
      assert_contains(text, "out of contract")
      assert_not_contains(text, "not implemented yet")
      assert_eq(adapters.jdtls.stops, 0)
      assert_true(adapters.jdtls.running)
    end,
  },
  {
    "Language level 11 loud-refuses Plugin actions as out of contract",
    function()
      local plugin, adapters = fakes.plugin({
        files = {
          ["pom.xml"] = [[
<project>
  <parent>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-parent</artifactId>
    <version>3.3.4</version>
  </parent>
  <properties>
    <java.version>11</java.version>
  </properties>
</project>
]],
        },
      })
      each_existing_project_action(plugin)
      assert_contains(fakes.notify_text(adapters.ui), "out of contract")
      assert_eq(adapters.jdtls.stops, 0)
    end,
  },
  {
    "Language level 8 loud-refuses Plugin actions as out of contract",
    function()
      local plugin, adapters = fakes.plugin({
        files = {
          ["pom.xml"] = [[
<project>
  <properties>
    <maven.compiler.release>1.8</maven.compiler.release>
  </properties>
</project>
]],
        },
      })
      each_existing_project_action(plugin)
      assert_contains(fakes.notify_text(adapters.ui), "out of contract")
    end,
  },
  {
    "In-contract Maven project does not refuse for Gradle, reactor, Boot 2, or Language level",
    function()
      local plugin, adapters = fakes.plugin({
        files = {
          ["pom.xml"] = [[
<project>
  <parent>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-parent</artifactId>
    <version>3.3.4</version>
  </parent>
  <properties>
    <java.version>17</java.version>
  </properties>
</project>
]],
        },
      })
      each_existing_project_action(plugin)
      local text = fakes.notify_text(adapters.ui)
      assert_not_contains(text, "not implemented yet")
      assert_not_contains(text, "out of contract")
      assert_eq(#adapters.fs.writes, 0)
    end,
  },
  {
    "ensure_jdtls starts a minimal jdtls only when nvim-jdtls is present and no client is up",
    function()
      local plugin, adapters = fakes.plugin({
        jdtls = fakes.jdtls({ present = true, running = false }),
      })
      plugin:setup({})
      assert_eq(adapters.jdtls.starts, 0)
      plugin:ensure_jdtls()
      assert_eq(adapters.jdtls.starts, 1)
      assert_true(adapters.jdtls.running)
    end,
  },
  {
    "setup does not double-start jdtls when a client is already up",
    function()
      local plugin, adapters = fakes.plugin({
        jdtls = fakes.jdtls({ present = true, running = true }),
      })
      plugin:setup({})
      plugin:ensure_jdtls()
      assert_eq(adapters.jdtls.starts, 0)
    end,
  },
  {
    "Plugin still loads and acts when nvim-jdtls is missing",
    function()
      package.preload["jdtls"] = function()
        error("nvim-jdtls must not be required when missing")
      end
      local plugin, adapters = fakes.plugin({
        jdtls = fakes.jdtls({ present = false, running = false }),
        files = { ["build.gradle"] = "plugins { id 'java' }\n" },
      })
      plugin:setup({})
      plugin:create()
      assert_eq(adapters.jdtls.starts, 0)
      assert_contains(fakes.notify_text(adapters.ui), "not implemented yet")
    end,
  },
  {
    "setup registers recommended <leader>s keymaps by default",
    function()
      local plugin, adapters = fakes.plugin()
      plugin:setup({})
      local lhs = {}
      for _, map in ipairs(adapters.ui.keymaps) do
        lhs[#lhs + 1] = map.lhs
      end
      local joined = table.concat(lhs, " ")
      assert_contains(joined, "<leader>s")
      assert_true(#adapters.ui.keymaps >= 6, "one map per user command")
    end,
  },
  {
    "setup can disable default keymaps",
    function()
      local plugin, adapters = fakes.plugin()
      plugin:setup({ keymaps = false })
      assert_eq(#adapters.ui.keymaps, 0)
    end,
  },
  {
    "Package view from Maven source roots without jdtls renders one project of roots and packages",
    function()
      local plugin, adapters = fakes.plugin({
        jdtls = fakes.jdtls({ present = false, running = false }),
        files = {
          ["pom.xml"] = [[
<project>
  <parent>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-parent</artifactId>
    <version>3.3.4</version>
  </parent>
  <artifactId>demo</artifactId>
  <properties>
    <java.version>17</java.version>
  </properties>
</project>
]],
          ["src/main/java/com/example/App.java"] = "package com.example;\n",
          ["src/main/java/com/example/web/Home.java"] = "package com.example.web;\n",
          ["src/test/java/com/example/AppTest.java"] = "package com.example;\n",
        },
      })
      plugin:packages()
      local model = fakes.last_package_view(adapters.ui)
      assert_true(model ~= nil, "editor adapter is asked to render a Package view")
      assert_eq(model.name, "demo")
      assert_eq(#model.roots, 2)
      assert_eq(model.roots[1].path, "src/main/java")
      assert_eq(table.concat(model.roots[1].packages, ","), "com.example,com.example.web")
      assert_eq(model.roots[2].path, "src/test/java")
      assert_eq(table.concat(model.roots[2].packages, ","), "com.example")
      assert_eq(adapters.jdtls.list_source_path_calls, 0)
      assert_eq(#adapters.fs.writes, 0)
    end,
  },
  {
    "Package view uses jdtls listSourcePaths when a client is up and keeps one project",
    function()
      local plugin, adapters = fakes.plugin({
        jdtls = fakes.jdtls({
          present = true,
          running = true,
          source_paths = {
            {
              path = "/workspace/src/main/java",
              projectName = "demo",
            },
            {
              path = "/workspace/src/test/java",
              projectName = "demo-tests",
            },
            {
              path = "file:///workspace/target/generated-sources/annotations",
              projectName = "demo",
            },
          },
        }),
        files = {
          ["pom.xml"] = [[
<project>
  <parent>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-parent</artifactId>
    <version>3.3.4</version>
  </parent>
  <artifactId>demo</artifactId>
  <properties>
    <java.version>17</java.version>
  </properties>
</project>
]],
          ["src/main/java/com/example/App.java"] = "package com.example;\n",
          ["src/test/java/com/example/AppTest.java"] = "package com.example;\n",
          ["target/generated-sources/annotations/com/example/Generated.java"] = "package com.example;\n",
        },
      })
      plugin:packages()
      local model = fakes.last_package_view(adapters.ui)
      assert_true(model ~= nil, "editor adapter is asked to render a Package view")
      assert_eq(model.name, "demo")
      assert_eq(#model.roots, 3, "jdtls extra roots of the same POM are included")
      assert_eq(model.roots[1].path, "src/main/java")
      assert_eq(table.concat(model.roots[1].packages, ","), "com.example")
      assert_eq(model.roots[2].path, "src/test/java")
      assert_eq(table.concat(model.roots[2].packages, ","), "com.example")
      assert_eq(model.roots[3].path, "target/generated-sources/annotations")
      assert_eq(table.concat(model.roots[3].packages, ","), "com.example")
      for _, root in ipairs(model.roots) do
        assert_true(root.path:sub(1, 1) ~= "/", "Package view uses project-relative source roots, not filesystem paths")
      end
      assert_eq(adapters.jdtls.list_source_path_calls, 1)
    end,
  },
  {
    "Package view falls back to Maven layout when jdtls is up but listSourcePaths is empty",
    function()
      local plugin, adapters = fakes.plugin({
        jdtls = fakes.jdtls({
          present = true,
          running = true,
          source_paths = {},
        }),
        files = {
          ["pom.xml"] = [[
<project>
  <artifactId>demo</artifactId>
  <properties>
    <java.version>17</java.version>
  </properties>
</project>
]],
          ["src/main/java/com/example/App.java"] = "package com.example;\n",
        },
      })
      plugin:packages()
      local model = fakes.last_package_view(adapters.ui)
      assert_eq(#model.roots, 1)
      assert_eq(model.roots[1].path, "src/main/java")
      assert_eq(table.concat(model.roots[1].packages, ","), "com.example")
      assert_eq(adapters.jdtls.list_source_path_calls, 1)
    end,
  },
  {
    "Package view uses POM sourceDirectory of the workspace-root POM without jdtls",
    function()
      local plugin, adapters = fakes.plugin({
        jdtls = fakes.jdtls({ present = false, running = false }),
        files = {
          ["pom.xml"] = [[
<project>
  <artifactId>demo</artifactId>
  <properties>
    <java.version>17</java.version>
  </properties>
  <build>
    <sourceDirectory>src</sourceDirectory>
    <testSourceDirectory>test</testSourceDirectory>
  </build>
</project>
]],
          ["src/com/example/App.java"] = "package com.example;\n",
          ["test/com/example/AppTest.java"] = "package com.example;\n",
        },
      })
      plugin:packages()
      local model = fakes.last_package_view(adapters.ui)
      assert_eq(#model.roots, 2)
      assert_eq(model.roots[1].path, "src")
      assert_eq(table.concat(model.roots[1].packages, ","), "com.example")
      assert_eq(model.roots[2].path, "test")
      assert_eq(table.concat(model.roots[2].packages, ","), "com.example")
    end,
  },
  {
    "Package view keeps only source roots under the workspace-root POM when jdtls lists extras",
    function()
      local plugin, adapters = fakes.plugin({
        jdtls = fakes.jdtls({
          present = true,
          running = true,
          source_paths = {
            { path = "/workspace/src/main/java", projectName = "demo" },
            { path = "/other/project/src/main/java", projectName = "other" },
          },
        }),
        files = {
          ["pom.xml"] = [[
<project>
  <artifactId>demo</artifactId>
  <properties>
    <java.version>17</java.version>
  </properties>
</project>
]],
          ["src/main/java/com/example/App.java"] = "package com.example;\n",
        },
      })
      plugin:packages()
      local model = fakes.last_package_view(adapters.ui)
      assert_eq(#model.roots, 1)
      assert_eq(model.roots[1].path, "src/main/java")
    end,
  },
  {
    "Build-tool refuse does not open a Package view",
    function()
      local plugin, adapters = fakes.plugin({
        files = { ["build.gradle"] = "plugins { id 'java' }\n" },
      })
      plugin:packages()
      assert_eq(#adapters.ui.package_views, 0)
      assert_contains(fakes.notify_text(adapters.ui), "not implemented yet")
    end,
  },
  {
    "unique exact GAV applies without a picker and writes an unmanaged version",
    function()
      local plugin, adapters = fakes.plugin({
        files = { ["pom.xml"] = IN_CONTRACT_POM },
        central = fakes.central({
          docs = {
            { g = "com.google.guava", a = "guava", latestVersion = "33.2.1-jre" },
          },
        }),
      })
      plugin:add_dependency("com.google.guava:guava")
      local pom = adapters.fs:read("pom.xml")
      assert_contains(pom, "<groupId>com.google.guava</groupId>")
      assert_contains(pom, "<artifactId>guava</artifactId>")
      assert_contains(pom, "<version>33.2.1-jre</version>")
      assert_eq(adapters.ui.pick_calls, 0)
      assert_eq(adapters.jdtls.refreshes, 1)
    end,
  },
  {
    "unique exact GAV with version applies without a picker",
    function()
      local plugin, adapters = fakes.plugin({
        files = { ["pom.xml"] = IN_CONTRACT_POM },
        central = fakes.central({
          docs = {
            { g = "com.google.guava", a = "guava", v = "33.2.1-jre" },
          },
        }),
      })
      plugin:add_dependency("com.google.guava:guava:33.2.1-jre")
      assert_eq(adapters.ui.pick_calls, 0)
      assert_contains(adapters.fs:read("pom.xml"), "<version>33.2.1-jre</version>")
    end,
  },
  {
    "unique FQCN hit applies without a picker",
    function()
      local plugin, adapters = fakes.plugin({
        files = { ["pom.xml"] = IN_CONTRACT_POM },
        central = fakes.central({
          docs = {
            { g = "com.google.guava", a = "guava", v = "33.2.1-jre" },
          },
        }),
      })
      plugin:add_dependency("com.google.common.collect.ImmutableList")
      assert_eq(adapters.ui.pick_calls, 0)
      assert_contains(adapters.fs:read("pom.xml"), "<artifactId>guava</artifactId>")
      assert_eq(adapters.jdtls.refreshes, 1)
    end,
  },
  {
    "simple-name search always goes through a picker",
    function()
      local plugin, adapters = fakes.plugin({
        files = { ["pom.xml"] = IN_CONTRACT_POM },
        ui = fakes.ui({ pick_choice = 1 }),
        central = fakes.central({
          docs = {
            { g = "org.slf4j", a = "slf4j-api", latestVersion = "2.0.16" },
          },
        }),
      })
      plugin:add_dependency("Logger")
      assert_eq(adapters.ui.pick_calls, 1)
      assert_contains(adapters.fs:read("pom.xml"), "<artifactId>slf4j-api</artifactId>")
    end,
  },
  {
    "keyword search always goes through a picker",
    function()
      local plugin, adapters = fakes.plugin({
        files = { ["pom.xml"] = IN_CONTRACT_POM },
        ui = fakes.ui({ pick_choice = 1 }),
        central = fakes.central({
          docs = {
            { g = "com.fasterxml.jackson.core", a = "jackson-databind", latestVersion = "2.17.2" },
          },
        }),
      })
      plugin:add_dependency("jackson")
      assert_eq(adapters.ui.pick_calls, 1)
      assert_contains(adapters.fs:read("pom.xml"), "<artifactId>jackson-databind</artifactId>")
    end,
  },
  {
    "BOM-managed GAV omits version",
    function()
      local plugin, adapters = fakes.plugin({
        files = { ["pom.xml"] = IN_CONTRACT_POM },
        central = fakes.central({
          docs = {
            {
              g = "org.springframework.boot",
              a = "spring-boot-starter-web",
              latestVersion = "3.3.4",
            },
          },
          poms = {
            ["org.springframework.boot:spring-boot-starter-parent:3.3.4"] = [[
<project>
  <dependencyManagement>
    <dependencies>
      <dependency>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-dependencies</artifactId>
        <version>3.3.4</version>
        <type>pom</type>
        <scope>import</scope>
      </dependency>
    </dependencies>
  </dependencyManagement>
</project>
]],
            ["org.springframework.boot:spring-boot-dependencies:3.3.4"] = [[
<project>
  <dependencyManagement>
    <dependencies>
      <dependency>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter-web</artifactId>
        <version>3.3.4</version>
      </dependency>
    </dependencies>
  </dependencyManagement>
</project>
]],
          },
        }),
      })
      plugin:add_dependency("org.springframework.boot:spring-boot-starter-web")
      local pom = adapters.fs:read("pom.xml")
      local deps = pom:match("<dependencies>(.-)</dependencies>")
      assert_contains(deps, "<artifactId>spring-boot-starter-web</artifactId>")
      assert_not_contains(deps, "<version>")
      assert_eq(adapters.jdtls.refreshes, 1)
    end,
  },
  {
    "query from a test source root writes test scope",
    function()
      local plugin, adapters = fakes.plugin({
        files = { ["pom.xml"] = IN_CONTRACT_POM },
        ui = fakes.ui({ file = "/workspace/src/test/java/com/example/FooTest.java" }),
        central = fakes.central({
          docs = {
            { g = "org.junit.jupiter", a = "junit-jupiter", latestVersion = "5.10.3" },
          },
        }),
      })
      plugin:add_dependency("org.junit.jupiter:junit-jupiter")
      assert_contains(adapters.fs:read("pom.xml"), "<scope>test</scope>")
    end,
  },
  {
    "main source root does not write test scope",
    function()
      local plugin, adapters = fakes.plugin({
        files = { ["pom.xml"] = IN_CONTRACT_POM },
        ui = fakes.ui({ file = "/workspace/src/main/java/com/example/Foo.java" }),
        central = fakes.central({
          docs = {
            { g = "com.google.guava", a = "guava", latestVersion = "33.2.1-jre" },
          },
        }),
      })
      plugin:add_dependency("com.google.guava:guava")
      assert_not_contains(adapters.fs:read("pom.xml"), "<scope>test</scope>")
    end,
  },
  {
    "duplicate GAV does not rewrite the POM and still refreshes Maven / JDT",
    function()
      local pom = [[
<project>
  <parent>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-parent</artifactId>
    <version>3.3.4</version>
  </parent>
  <properties>
    <java.version>17</java.version>
  </properties>
  <dependencies>
    <dependency>
      <groupId>com.google.guava</groupId>
      <artifactId>guava</artifactId>
      <version>33.0.0-jre</version>
    </dependency>
  </dependencies>
</project>
]]
      local plugin, adapters = fakes.plugin({
        files = { ["pom.xml"] = pom },
        central = fakes.central({
          docs = {
            { g = "com.google.guava", a = "guava", latestVersion = "33.2.1-jre" },
          },
        }),
      })
      plugin:add_dependency("com.google.guava:guava")
      assert_eq(#adapters.fs.writes, 0)
      assert_eq(adapters.fs:read("pom.xml"), pom)
      assert_eq(adapters.jdtls.refreshes, 1)
    end,
  },
  {
    "Solr failure loud-refuses and writes nothing",
    function()
      local plugin, adapters = fakes.plugin({
        files = { ["pom.xml"] = IN_CONTRACT_POM },
        central = fakes.central({ error = "network" }),
      })
      plugin:add_dependency("com.google.guava:guava")
      assert_contains(fakes.notify_text(adapters.ui), "Maven Central search failed")
      assert_eq(#adapters.fs.writes, 0)
      assert_eq(adapters.jdtls.refreshes, 0)
    end,
  },
  {
    "zero hits loud-refuse and write nothing",
    function()
      local plugin, adapters = fakes.plugin({
        files = { ["pom.xml"] = IN_CONTRACT_POM },
        central = fakes.central({ docs = {} }),
      })
      plugin:add_dependency("com.google.guava:guava")
      assert_contains(fakes.notify_text(adapters.ui), "No artifacts found")
      assert_eq(#adapters.fs.writes, 0)
      assert_eq(adapters.jdtls.refreshes, 0)
    end,
  },
  {
    "missing POM loud-refuses and writes nothing",
    function()
      local plugin, adapters = fakes.plugin({
        files = {},
        central = fakes.central({
          docs = {
            { g = "com.google.guava", a = "guava", latestVersion = "33.2.1-jre" },
          },
        }),
      })
      plugin:add_dependency("com.google.guava:guava")
      assert_contains(fakes.notify_text(adapters.ui), "pom.xml is missing or invalid")
      assert_eq(#adapters.fs.writes, 0)
    end,
  },
  {
    "unparseable POM loud-refuses and writes nothing",
    function()
      local plugin, adapters = fakes.plugin({
        files = { ["pom.xml"] = "not a project" },
        central = fakes.central({
          docs = {
            { g = "com.google.guava", a = "guava", latestVersion = "33.2.1-jre" },
          },
        }),
      })
      plugin:add_dependency("com.google.guava:guava")
      assert_contains(fakes.notify_text(adapters.ui), "pom.xml is missing or invalid")
      assert_eq(#adapters.fs.writes, 0)
    end,
  },
  {
    "add-Dependency works on an in-contract Maven project without jdtls",
    function()
      local plugin, adapters = fakes.plugin({
        files = { ["pom.xml"] = IN_CONTRACT_POM },
        jdtls = fakes.jdtls({ present = false, running = false }),
        central = fakes.central({
          docs = {
            { g = "com.google.guava", a = "guava", latestVersion = "33.2.1-jre" },
          },
        }),
      })
      plugin:add_dependency("com.google.guava:guava")
      assert_contains(adapters.fs:read("pom.xml"), "<artifactId>guava</artifactId>")
      assert_eq(adapters.jdtls.refreshes, 0)
    end,
  },
  {
    "add-Dependency command does not edit a Java buffer",
    function()
      local java = "package com.example;\npublic class App {}\n"
      local plugin, adapters = fakes.plugin({
        files = {
          ["pom.xml"] = IN_CONTRACT_POM,
          ["src/main/java/com/example/App.java"] = java,
        },
        central = fakes.central({
          docs = {
            { g = "com.google.guava", a = "guava", latestVersion = "33.2.1-jre" },
          },
        }),
      })
      plugin:add_dependency("com.google.guava:guava")
      assert_eq(adapters.fs:read("src/main/java/com/example/App.java"), java)
      assert_eq(#adapters.fs.writes, 1)
    end,
  },
  {
    "inserts under project dependencies, not dependencyManagement",
    function()
      local pom = [[
<project>
  <parent>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-parent</artifactId>
    <version>3.3.4</version>
  </parent>
  <properties>
    <java.version>17</java.version>
  </properties>
  <dependencyManagement>
    <dependencies>
      <dependency>
        <groupId>com.example</groupId>
        <artifactId>bom-item</artifactId>
        <version>1.0.0</version>
      </dependency>
    </dependencies>
  </dependencyManagement>
</project>
]]
      local plugin, adapters = fakes.plugin({
        files = { ["pom.xml"] = pom },
        central = fakes.central({
          docs = {
            { g = "com.google.guava", a = "guava", latestVersion = "33.2.1-jre" },
          },
        }),
      })
      plugin:add_dependency("com.google.guava:guava")
      local written = adapters.fs:read("pom.xml")
      local dm = written:match("<dependencyManagement>(.-)</dependencyManagement>")
      assert_not_contains(dm, "guava")
      local deps = written:match("</dependencyManagement>.-<dependencies>(.-)</dependencies>")
      assert_contains(deps, "<artifactId>guava</artifactId>")
    end,
  },
  {
    "prompts for a query when the command has no argument",
    function()
      local plugin, adapters = fakes.plugin({
        files = { ["pom.xml"] = IN_CONTRACT_POM },
        ui = fakes.ui({ input_text = "com.google.guava:guava" }),
        central = fakes.central({
          docs = {
            { g = "com.google.guava", a = "guava", latestVersion = "33.2.1-jre" },
          },
        }),
      })
      plugin:add_dependency()
      assert_eq(adapters.ui.last_input_prompt, "Dependency: ")
      assert_contains(adapters.fs:read("pom.xml"), "<artifactId>guava</artifactId>")
    end,
  },
  {
    "ambiguous FQCN goes through a picker",
    function()
      local plugin, adapters = fakes.plugin({
        files = { ["pom.xml"] = IN_CONTRACT_POM },
        ui = fakes.ui({ pick_choice = 2 }),
        central = fakes.central({
          docs = {
            { g = "org.example", a = "one", v = "1.0.0" },
            { g = "com.other", a = "two", v = "2.0.0" },
          },
        }),
      })
      plugin:add_dependency("com.example.SharedType")
      assert_eq(adapters.ui.pick_calls, 1)
      assert_contains(adapters.fs:read("pom.xml"), "<artifactId>two</artifactId>")
      assert_not_contains(adapters.fs:read("pom.xml"), "<artifactId>one</artifactId>")
    end,
  },
  {
    "imported BOM in local dependencyManagement omits version",
    function()
      local pom = [[
<project>
  <properties>
    <java.version>17</java.version>
  </properties>
  <dependencyManagement>
    <dependencies>
      <dependency>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-dependencies</artifactId>
        <version>3.3.4</version>
        <type>pom</type>
        <scope>import</scope>
      </dependency>
    </dependencies>
  </dependencyManagement>
</project>
]]
      local plugin, adapters = fakes.plugin({
        files = { ["pom.xml"] = pom },
        central = fakes.central({
          docs = {
            {
              g = "org.springframework.boot",
              a = "spring-boot-starter-web",
              latestVersion = "3.3.4",
            },
          },
          poms = {
            ["org.springframework.boot:spring-boot-dependencies:3.3.4"] = [[
<project>
  <dependencyManagement>
    <dependencies>
      <dependency>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter-web</artifactId>
        <version>3.3.4</version>
      </dependency>
    </dependencies>
  </dependencyManagement>
</project>
]],
          },
        }),
      })
      plugin:add_dependency("org.springframework.boot:spring-boot-starter-web")
      local deps = adapters.fs:read("pom.xml"):match("</dependencyManagement>.-<dependencies>(.-)</dependencies>")
      assert_contains(deps, "<artifactId>spring-boot-starter-web</artifactId>")
      assert_not_contains(deps, "<version>")
    end,
  },
  {
    "local dependencyManagement omits version without a parent fetch",
    function()
      local pom = [[
<project>
  <properties>
    <java.version>17</java.version>
  </properties>
  <dependencyManagement>
    <dependencies>
      <dependency>
        <groupId>com.example</groupId>
        <artifactId>lib</artifactId>
        <version>9.9.9</version>
      </dependency>
    </dependencies>
  </dependencyManagement>
</project>
]]
      local plugin, adapters = fakes.plugin({
        files = { ["pom.xml"] = pom },
        central = fakes.central({
          docs = {
            { g = "com.example", a = "lib", latestVersion = "9.9.9" },
          },
        }),
      })
      plugin:add_dependency("com.example:lib")
      local deps = adapters.fs:read("pom.xml"):match("</dependencyManagement>.-<dependencies>(.-)</dependencies>")
      assert_contains(deps, "<artifactId>lib</artifactId>")
      assert_not_contains(deps, "<version>")
    end,
  },
  {
    "type-local add-Dependency code action appears on UNDEFINED_TYPE when jdtls is up",
    function()
      local plugin = type_local_plugin()
      local offered = plugin:code_actions()
      assert_eq(#offered, 1)
      assert_contains(offered[1].title, "ImmutableList")
      assert_eq(offered[1].query, "com.google.common.collect.ImmutableList")
    end,
  },
  {
    "type-local add-Dependency is absent without a jdtls client",
    function()
      local plugin = type_local_plugin({ present = true, running = false })
      assert_eq(#plugin:code_actions(), 0)
    end,
  },
  {
    "type-local add-Dependency is absent when nvim-jdtls is missing",
    function()
      local plugin = type_local_plugin({ present = false, running = false })
      assert_eq(#plugin:code_actions(), 0)
    end,
  },
  {
    "type-local add-Dependency appears when a jdtls client is up without nvim-jdtls",
    function()
      local plugin = type_local_plugin({ present = false, running = true })
      assert_eq(#plugin:code_actions(), 1)
    end,
  },
  {
    "type-local add-Dependency is absent without an unresolved-type diagnostic",
    function()
      local plugin = type_local_plugin({
        diagnostics = {
          {
            file = JAVA_PATH,
            code = 33554515,
            lnum = 3,
            col = 2,
            end_lnum = 3,
            end_col = 41,
          },
        },
      })
      assert_eq(#plugin:code_actions(), 0)
    end,
  },
  {
    "UNDEFINED_NAME starting with a capital is a type-local offer",
    function()
      local plugin = type_local_plugin({
        java = [[
package com.example;

public class App {
  ImmutableList xs = ImmutableList.of();
}
]],
        diagnostics = {
          {
            file = JAVA_PATH,
            code = 570425394,
            lnum = 3,
            col = 2,
            end_lnum = 3,
            end_col = 15,
          },
        },
      })
      local offered = plugin:code_actions()
      assert_eq(#offered, 1)
      assert_eq(offered[1].query, "ImmutableList")
    end,
  },
  {
    "UNDEFINED_NAME starting with lowercase is not a type-local offer",
    function()
      local plugin = type_local_plugin({
        java = [[
package com.example;

public class App {
  unknown.foo();
}
]],
        diagnostics = {
          {
            file = JAVA_PATH,
            code = 570425394,
            lnum = 3,
            col = 2,
            end_lnum = 3,
            end_col = 9,
          },
        },
      })
      assert_eq(#plugin:code_actions(), 0)
    end,
  },
  {
    "Init, run, and Package view are not code actions",
    function()
      local plugin = type_local_plugin()
      local offered = plugin:code_actions()
      assert_eq(#offered, 1)
      local title = offered[1].title:lower()
      assert_not_contains(title, "init")
      assert_not_contains(title, "run")
      assert_not_contains(title, "package")
      assert_contains(offered[1].title, "Resolve unknown type")
    end,
  },
  {
    "choosing the type-local action writes the POM and reloads like the command",
    function()
      local plugin, adapters = type_local_plugin({
        central = fakes.central({
          docs = {
            { g = "com.google.guava", a = "guava", latestVersion = "33.2.1-jre" },
          },
        }),
      })
      local offered = plugin:code_actions()
      plugin:apply_code_action(offered[1])
      local pom = adapters.fs:read("pom.xml")
      assert_contains(pom, "<groupId>com.google.guava</groupId>")
      assert_contains(pom, "<artifactId>guava</artifactId>")
      assert_contains(pom, "<version>33.2.1-jre</version>")
      assert_eq(adapters.ui.pick_calls, 0)
      assert_eq(adapters.jdtls.refreshes, 1)
    end,
  },
  {
    "type-local action on an FQCN writes import and simple name",
    function()
      local plugin, adapters = type_local_plugin({
        central = fakes.central({
          docs = {
            { g = "com.google.guava", a = "guava", latestVersion = "33.2.1-jre" },
          },
        }),
      })
      plugin:apply_code_action(plugin:code_actions()[1])
      local java = adapters.fs:read("src/main/java/com/example/App.java")
      assert_contains(java, "import com.google.common.collect.ImmutableList;")
      assert_contains(java, "  ImmutableList<String> xs;")
      assert_not_contains(java, "  com.google.common.collect.ImmutableList<String> xs;")
    end,
  },
  {
    "duplicate GAV still fixes the Java buffer and reloads",
    function()
      local pom = [[
<project>
  <parent>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-parent</artifactId>
    <version>3.3.4</version>
  </parent>
  <properties>
    <java.version>17</java.version>
  </properties>
  <dependencies>
    <dependency>
      <groupId>com.google.guava</groupId>
      <artifactId>guava</artifactId>
      <version>33.0.0-jre</version>
    </dependency>
  </dependencies>
</project>
]]
      local plugin, adapters = type_local_plugin({
        files = {
          ["pom.xml"] = pom,
          ["src/main/java/com/example/App.java"] = FQCN_JAVA,
        },
        central = fakes.central({
          docs = {
            { g = "com.google.guava", a = "guava", latestVersion = "33.2.1-jre" },
          },
        }),
      })
      plugin:apply_code_action(plugin:code_actions()[1])
      assert_eq(adapters.fs:read("pom.xml"), pom)
      local java = adapters.fs:read("src/main/java/com/example/App.java")
      assert_contains(java, "import com.google.common.collect.ImmutableList;")
      assert_contains(java, "  ImmutableList<String> xs;")
      assert_eq(adapters.jdtls.refreshes, 1)
    end,
  },
  {
    "type-local action on an unresolved import keeps the import and does not rewrite it",
    function()
      local java = [[
package com.example;

import com.google.common.collect.ImmutableList;

public class App {
  ImmutableList<String> xs;
}
]]
      local plugin, adapters = type_local_plugin({
        java = java,
        diagnostics = {
          {
            file = JAVA_PATH,
            code = 16777218,
            lnum = 2,
            col = 7,
            end_lnum = 2,
            end_col = 46,
          },
        },
        central = fakes.central({
          docs = {
            { g = "com.google.guava", a = "guava", latestVersion = "33.2.1-jre" },
          },
        }),
      })
      plugin:apply_code_action(plugin:code_actions()[1])
      assert_eq(adapters.fs:read("src/main/java/com/example/App.java"), java)
      assert_contains(adapters.fs:read("pom.xml"), "<artifactId>guava</artifactId>")
    end,
  },
  {
    "type-local Java fix uses the open buffer, not a stale file",
    function()
      local plugin, adapters = type_local_plugin({
        java = FQCN_JAVA,
        ui = fakes.ui({
          file = JAVA_PATH,
          buffer = [[
package com.example;

public class App {
  com.google.common.collect.ImmutableList<String> xs;
  int extra;
}
]],
        }),
        central = fakes.central({
          docs = {
            { g = "com.google.guava", a = "guava", latestVersion = "33.2.1-jre" },
          },
        }),
      })
      plugin:apply_code_action(plugin:code_actions()[1])
      local java = adapters.fs:read("src/main/java/com/example/App.java")
      assert_contains(java, "import com.google.common.collect.ImmutableList;")
      assert_contains(java, "int extra;")
    end,
  },
  {
    "type-local Solr failure writes neither POM nor Java buffer",
    function()
      local plugin, adapters = type_local_plugin({
        central = fakes.central({ error = "network" }),
      })
      plugin:apply_code_action(plugin:code_actions()[1])
      assert_contains(fakes.notify_text(adapters.ui), "Maven Central search failed")
      assert_eq(adapters.fs:read("src/main/java/com/example/App.java"), FQCN_JAVA)
      assert_eq(#adapters.fs.writes, 0)
      assert_eq(adapters.jdtls.refreshes, 0)
    end,
  },
}
