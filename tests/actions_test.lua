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

local JAVA_ONLY_POM = [[
<project>
  <properties>
    <java.version>17</java.version>
  </properties>
</project>
]]

local function wizard_kind_names(spec)
  local names = {}
  local step = spec and spec.steps and spec.steps[1]
  local field = step and step.fields and step.fields[1]
  for _, value in ipairs((field and field.values) or {}) do
    names[#names + 1] = value.name or value.id
  end
  return table.concat(names, ",")
end

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
    "missing Maven loud-refuses run and starts no process",
    function()
      local plugin, adapters = fakes.plugin({
        files = { ["pom.xml"] = IN_CONTRACT_POM },
        host = fakes.host({ bins = {} }),
      })
      plugin:run()
      assert_contains(fakes.notify_text(adapters.ui), "Neither mvnw nor mvn is available")
      assert_eq(#adapters.host.starts, 0)
      assert_eq(#adapters.fs.writes, 0)
    end,
  },
  {
    "run prefers ./mvnw spring-boot:run when the wrapper exists",
    function()
      local plugin, adapters = fakes.plugin({
        files = {
          ["pom.xml"] = IN_CONTRACT_POM,
          ["mvnw"] = "#!/bin/sh\n",
        },
        host = fakes.host({ bins = { mvn = true } }),
      })
      plugin:run()
      assert_eq(#adapters.host.starts, 1)
      local started = adapters.host.starts[1]
      assert_eq(started.argv[1], "./mvnw")
      assert_eq(started.argv[2], "spring-boot:run")
      assert_eq(#started.argv, 2)
    end,
  },
  {
    "run uses mvn spring-boot:run when there is no wrapper",
    function()
      local plugin, adapters = fakes.plugin({
        files = { ["pom.xml"] = IN_CONTRACT_POM },
        host = fakes.host({ bins = { mvn = true } }),
      })
      plugin:run()
      assert_eq(#adapters.host.starts, 1)
      local started = adapters.host.starts[1]
      assert_eq(started.argv[1], "mvn")
      assert_eq(started.argv[2], "spring-boot:run")
      assert_eq(#started.argv, 2)
    end,
  },
  {
    "missing DevTools still starts, says Reload will not happen, offers add-Dependency, and does not silent-edit the POM",
    function()
      local plugin, adapters = fakes.plugin({
        files = { ["pom.xml"] = IN_CONTRACT_POM },
        host = fakes.host({ bins = { mvn = true } }),
        ui = fakes.ui({ confirm = false }),
      })
      plugin:run()
      assert_eq(#adapters.host.starts, 1)
      assert_eq(adapters.host.starts[1].argv[2], "spring-boot:run")
      assert_contains(fakes.notify_text(adapters.ui), "Reload will not happen")
      assert_eq(adapters.ui.confirm_calls, 1)
      assert_contains(adapters.ui.last_confirm, "spring-boot-devtools")
      assert_eq(#adapters.fs.writes, 0)
      assert_eq(adapters.fs:read("pom.xml"), IN_CONTRACT_POM)
    end,
  },
  {
    "accepting the DevTools offer writes through the add-Dependency path",
    function()
      local plugin, adapters = fakes.plugin({
        files = { ["pom.xml"] = IN_CONTRACT_POM },
        host = fakes.host({ bins = { mvn = true } }),
        ui = fakes.ui({ confirm = true }),
        central = fakes.central({
          docs = {
            {
              g = "org.springframework.boot",
              a = "spring-boot-devtools",
              latestVersion = "3.3.4",
            },
          },
        }),
      })
      plugin:run()
      assert_eq(#adapters.host.starts, 1)
      local pom = adapters.fs:read("pom.xml")
      assert_contains(pom, "<artifactId>spring-boot-devtools</artifactId>")
      assert_eq(#adapters.fs.writes, 1)
      assert_eq(adapters.jdtls.refreshes, 1)
    end,
  },
  {
    "accepting the DevTools offer from a test buffer does not write test scope",
    function()
      local plugin, adapters = fakes.plugin({
        files = { ["pom.xml"] = IN_CONTRACT_POM },
        ui = fakes.ui({
          confirm = true,
          file = "/workspace/src/test/java/com/example/FooTest.java",
        }),
        central = fakes.central({
          docs = {
            {
              g = "org.springframework.boot",
              a = "spring-boot-devtools",
              latestVersion = "3.3.4",
            },
          },
        }),
      })
      plugin:run()
      assert_contains(adapters.fs:read("pom.xml"), "<artifactId>spring-boot-devtools</artifactId>")
      assert_not_contains(adapters.fs:read("pom.xml"), "<scope>test</scope>")
    end,
  },
  {
    "DevTools already on the classpath starts without an add-Dependency offer",
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
      <groupId>org.springframework.boot</groupId>
      <artifactId>spring-boot-devtools</artifactId>
      <optional>true</optional>
    </dependency>
  </dependencies>
</project>
]]
      local plugin, adapters = fakes.plugin({
        files = { ["pom.xml"] = pom },
        host = fakes.host({ bins = { mvn = true } }),
      })
      plugin:run()
      assert_eq(#adapters.host.starts, 1)
      assert_eq(adapters.host.starts[1].argv[2], "spring-boot:run")
      assert_not_contains(fakes.notify_text(adapters.ui), "Reload will not happen")
      assert_eq(adapters.ui.confirm_calls, 0)
      assert_eq(#adapters.fs.writes, 0)
    end,
  },
  {
    "test-scoped DevTools is treated as missing from the runtime classpath",
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
      <groupId>org.springframework.boot</groupId>
      <artifactId>spring-boot-devtools</artifactId>
      <scope>test</scope>
    </dependency>
  </dependencies>
</project>
]]
      local plugin, adapters = fakes.plugin({
        files = { ["pom.xml"] = pom },
        ui = fakes.ui({ confirm = false }),
      })
      plugin:run()
      assert_eq(#adapters.host.starts, 1)
      assert_contains(fakes.notify_text(adapters.ui), "Reload will not happen")
      assert_eq(adapters.ui.confirm_calls, 1)
      assert_eq(#adapters.fs.writes, 0)
    end,
  },
  {
    "stop does not kill a foreign spring-boot:run process",
    function()
      local plugin, adapters = fakes.plugin({
        files = { ["pom.xml"] = IN_CONTRACT_POM },
        host = fakes.host({ bins = { mvn = true } }),
      })
      local foreign = {
        id = 99,
        argv = { "mvn", "spring-boot:run" },
      }
      adapters.host.running[99] = foreign
      plugin:stop()
      assert_eq(#adapters.host.stops, 0)
      assert_true(adapters.host.running[99] ~= nil, "foreign process is left alone")
    end,
  },
  {
    "stop kills only the Plugin-started process",
    function()
      local plugin, adapters = fakes.plugin({
        files = { ["pom.xml"] = IN_CONTRACT_POM },
        host = fakes.host({ bins = { mvn = true } }),
      })
      adapters.host.running[99] = {
        id = 99,
        argv = { "mvn", "spring-boot:run" },
      }
      plugin:run()
      assert_eq(#adapters.host.starts, 1)
      local owned = adapters.host.starts[1]
      plugin:stop()
      assert_eq(#adapters.host.stops, 1)
      assert_eq(adapters.host.stops[1].id, owned.id)
      assert_true(adapters.host.running[owned.id] == nil, "Plugin-started process is stopped")
      assert_true(adapters.host.running[99] ~= nil, "foreign process is left alone")
    end,
  },
  {
    "saving a Java file asks jdtls for an incremental compile",
    function()
      local plugin, adapters = fakes.plugin({
        files = { ["pom.xml"] = IN_CONTRACT_POM },
      })
      plugin:setup({})
      adapters.ui:fire_write("src/main/java/com/example/App.java")
      assert_eq(adapters.jdtls.compiles, 1)
      assert_eq(adapters.jdtls.last_compile, "incremental")
    end,
  },
  {
    "saving application.yml copies it into Maven target/classes",
    function()
      local yml = "server:\n  port: 8080\n"
      local plugin, adapters = fakes.plugin({
        files = {
          ["pom.xml"] = IN_CONTRACT_POM,
          ["src/main/resources/application.yml"] = yml,
        },
      })
      plugin:setup({})
      adapters.ui:fire_write("src/main/resources/application.yml")
      assert_eq(adapters.fs:read("target/classes/application.yml"), yml)
      assert_eq(adapters.jdtls.last_compile, "incremental")
    end,
  },
  {
    "saving templates and static resources copies them into target/classes",
    function()
      local html = "<html></html>\n"
      local css = "body{}\n"
      local plugin, adapters = fakes.plugin({
        files = {
          ["pom.xml"] = IN_CONTRACT_POM,
          ["src/main/resources/templates/index.html"] = html,
          ["src/main/resources/static/app.css"] = css,
        },
      })
      plugin:setup({})
      adapters.ui:fire_write("/workspace/src/main/resources/templates/index.html")
      adapters.ui:fire_write("/workspace/src/main/resources/static/app.css")
      assert_eq(adapters.fs:read("target/classes/templates/index.html"), html)
      assert_eq(adapters.fs:read("target/classes/static/app.css"), css)
    end,
  },
  {
    "compile-on-save does not run on a non-Boot Maven project",
    function()
      local plugin, adapters = fakes.plugin({
        files = {
          ["pom.xml"] = [[
<project>
  <properties>
    <java.version>17</java.version>
  </properties>
</project>
]],
          ["src/main/resources/application.yml"] = "x: 1\n",
        },
      })
      plugin:setup({})
      adapters.ui:fire_write("src/main/java/com/example/App.java")
      adapters.ui:fire_write("src/main/resources/application.yml")
      assert_eq(adapters.jdtls.compiles, 0)
      assert_eq(adapters.fs:read("target/classes/application.yml"), nil)
    end,
  },
  {
    "compile-on-save does not write or notify on a Gradle root",
    function()
      local plugin, adapters = fakes.plugin({
        files = {
          ["build.gradle"] = "plugins { id 'java' }\n",
          ["src/main/resources/application.yml"] = "x: 1\n",
        },
      })
      plugin:setup({})
      adapters.ui:fire_write("src/main/java/com/example/App.java")
      adapters.ui:fire_write("src/main/resources/application.yml")
      assert_eq(adapters.jdtls.compiles, 0)
      assert_eq(adapters.fs:read("target/classes/application.yml"), nil)
      assert_not_contains(fakes.notify_text(adapters.ui), "not implemented yet")
    end,
  },
  {
    "run loud-refuses a non-Boot Maven project and starts no process",
    function()
      local plugin, adapters = fakes.plugin({
        files = {
          ["pom.xml"] = [[
<project>
  <properties>
    <java.version>17</java.version>
  </properties>
</project>
]],
        },
      })
      plugin:run()
      assert_contains(fakes.notify_text(adapters.ui), "Not a Spring Boot project")
      assert_eq(#adapters.host.starts, 0)
    end,
  },
  {
    "a second run does not start another process",
    function()
      local plugin, adapters = fakes.plugin({
        files = { ["pom.xml"] = IN_CONTRACT_POM },
      })
      plugin:run()
      plugin:run()
      assert_eq(#adapters.host.starts, 1)
      assert_contains(fakes.notify_text(adapters.ui), "already running")
    end,
  },
  {
    "Java-only project offers Class Interface Record Enum and writes a Class from the buffer Package",
    function()
      local plugin, adapters = fakes.plugin({
        files = {
          ["pom.xml"] = JAVA_ONLY_POM,
          ["src/main/java/com/example/App.java"] = "package com.example;\npublic class App {}\n",
        },
        ui = fakes.ui({
          file = "/workspace/src/main/java/com/example/App.java",
          wizard_answers = { kind = "Class", package = "com.example", name = "Hello" },
        }),
      })
      plugin:create()
      assert_eq(#adapters.ui.wizards, 1)
      assert_eq(adapters.ui.wizards[1].steps[1].title, "Kind")
      assert_eq(adapters.ui.wizards[1].steps[2].title, "Package")
      assert_eq(adapters.ui.wizards[1].steps[3].title, "Type name")
      assert_eq(wizard_kind_names(adapters.ui.wizards[1]), "Class,Interface,Record,Enum")
      local written = adapters.fs:read("src/main/java/com/example/Hello.java")
      assert_contains(written, "package com.example;")
      assert_contains(written, "public class Hello {")
      assert_not_contains(written, "@")
      assert_eq(adapters.ui.opened, "src/main/java/com/example/Hello.java")
    end,
  },
  {
    "Spring Boot project offers stereotype kinds and writes RestController boilerplate",
    function()
      local plugin, adapters = fakes.plugin({
        files = {
          ["pom.xml"] = IN_CONTRACT_POM,
          ["src/main/java/com/example/App.java"] = "package com.example;\npublic class App {}\n",
        },
        ui = fakes.ui({
          file = "/workspace/src/main/java/com/example/App.java",
          wizard_answers = {
            kind = "RestController",
            package = "com.example",
            name = "HomeController",
          },
        }),
      })
      plugin:create()
      assert_eq(
        wizard_kind_names(adapters.ui.wizards[1]),
        "Class,Interface,Record,Enum,RestController,Controller,Service,Repository,Component,Configuration"
      )
      local written = adapters.fs:read("src/main/java/com/example/HomeController.java")
      assert_contains(written, "package com.example;")
      assert_contains(written, "import org.springframework.web.bind.annotation.RestController;")
      assert_contains(written, "@RestController")
      assert_contains(written, "public class HomeController {")
      assert_eq(adapters.ui.opened, "src/main/java/com/example/HomeController.java")
    end,
  },
  {
    "selected Package stays on the Package view node",
    function()
      local plugin, adapters = fakes.plugin({
        files = {
          ["pom.xml"] = JAVA_ONLY_POM,
          ["src/main/java/com/example/App.java"] = "package com.example;\npublic class App {}\n",
          ["src/main/java/com/example/web/Home.java"] = "package com.example.web;\npublic class Home {}\n",
        },
        ui = fakes.ui({
          file = "/workspace/src/main/java/com/example/web/Home.java",
          selection = { root = "src/main/java", package = "com.example" },
          wizard_answers = { kind = "Interface", package = "com.example", name = "Named" },
        }),
      })
      plugin:create()
      local pkg_field = adapters.ui.wizards[1].steps[2].fields[1]
      assert_eq(pkg_field.default, "com.example")
      local offered = {}
      for _, value in ipairs(pkg_field.values) do
        offered[#offered + 1] = value.id
      end
      assert_eq(table.concat(offered, ","), "com.example,com.example.web")
      local written = adapters.fs:read("src/main/java/com/example/Named.java")
      assert_contains(written, "package com.example;")
      assert_contains(written, "public interface Named {")
      assert_eq(adapters.fs:read("src/main/java/com/example/web/Named.java"), nil)
    end,
  },
  {
    "new-nest Package that does not exist yet is created under the selection",
    function()
      local plugin, adapters = fakes.plugin({
        files = {
          ["pom.xml"] = JAVA_ONLY_POM,
          ["src/main/java/com/example/App.java"] = "package com.example;\npublic class App {}\n",
        },
        ui = fakes.ui({
          selection = { root = "src/main/java", package = "com.example" },
          wizard_answers = {
            kind = "Record",
            package = "web.internal",
            name = "Payment",
          },
        }),
      })
      plugin:create()
      local written = adapters.fs:read("src/main/java/com/example/web/internal/Payment.java")
      assert_contains(written, "package com.example.web.internal;")
      assert_contains(written, "public record Payment() {")
      assert_eq(adapters.ui.opened, "src/main/java/com/example/web/internal/Payment.java")
    end,
  },
}
