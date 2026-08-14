local fakes = require("support.fakes")

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
}
