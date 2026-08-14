local fakes = require("support.fakes")

local POM = [[
<project>
  <parent>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-parent</artifactId>
    <version>4.1.0</version>
  </parent>
  <groupId>com.example</groupId>
  <artifactId>demo</artifactId>
</project>
]]

local function happy_plugin(opts)
  opts = opts or {}
  local archive = opts.archive or {
    ["pom.xml"] = POM,
    ["src/main/java/com/example/demo/DemoApplication.java"] = "package com.example.demo;\nclass DemoApplication {}\n",
  }
  return fakes.plugin({
    http = fakes.http({
      body = opts.metadata or fakes.initializr_metadata(),
      archive = archive,
    }),
    host = opts.host or fakes.host({ jdk_major = opts.jdk_major }),
    ui = opts.ui,
    opts = opts.opts,
  })
end

local function generate_request(http)
  for _, req in ipairs(http.requests) do
    if (req.url or ""):find("starter.zip", 1, true) then
      return req
    end
  end
end

local function metadata_request(http)
  for _, req in ipairs(http.requests) do
    if not (req.url or ""):find("starter.zip", 1, true) then
      return req
    end
  end
end

return {
  {
    "Unreachable Initializr loud-refuses and writes no project",
    function()
      local plugin, adapters = fakes.plugin({
        http = fakes.http({ error = "unreachable" }),
      })
      plugin:setup({})
      plugin:init()
      assert_contains(fakes.notify_text(adapters.ui), "unreachable")
      assert_eq(#adapters.fs.writes, 0)
    end,
  },
  {
    "401 or 403 Initializr loud-refuses and writes no project",
    function()
      for _, status in ipairs({ 401, 403 }) do
        local plugin, adapters = fakes.plugin({
          http = fakes.http({ status = status, body = "denied" }),
        })
        plugin:setup({})
        plugin:init()
        assert_contains(fakes.notify_text(adapters.ui), tostring(status))
        assert_eq(#adapters.fs.writes, 0)
      end
    end,
  },
  {
    "Non-Initializr-shaped response loud-refuses and writes no project",
    function()
      local plugin, adapters = fakes.plugin({
        http = fakes.http({ status = 200, body = "<html>not initializr</html>" }),
      })
      plugin:setup({})
      plugin:init()
      assert_contains(fakes.notify_text(adapters.ui), "not Initializr")
      assert_eq(#adapters.fs.writes, 0)
    end,
  },
  {
    "Initializr with no Maven type loud-refuses and writes no project",
    function()
      local plugin, adapters = fakes.plugin({
        http = fakes.http({
          status = 200,
          body = fakes.initializr_metadata({
            types = {
              {
                id = "gradle-project",
                name = "Gradle Project",
                tags = { build = "gradle", format = "project" },
              },
            },
          }),
        }),
      })
      plugin:setup({})
      plugin:init()
      assert_contains(fakes.notify_text(adapters.ui), "Maven")
      assert_eq(#adapters.fs.writes, 0)
    end,
  },
  {
    "Maven project type is accepted by id when tags are omitted",
    function()
      local plugin, adapters = happy_plugin({
        jdk_major = 21,
        metadata = fakes.initializr_metadata({
          types = {
            { id = "maven-project", name = "Maven Project" },
          },
        }),
      })
      plugin:setup({})
      plugin:init()
      assert_contains(generate_request(adapters.http).url, "type=maven-project")
      assert_not_contains(fakes.notify_text(adapters.ui), "Maven")
    end,
  },
  {
    "Non-200 Initializr status other than 401/403 is treated as unreachable",
    function()
      local plugin, adapters = fakes.plugin({
        http = fakes.http({ status = 500, body = "boom" }),
      })
      plugin:setup({})
      plugin:init()
      assert_contains(fakes.notify_text(adapters.ui), "unreachable")
      assert_not_contains(fakes.notify_text(adapters.ui), "not Initializr")
      assert_eq(#adapters.fs.writes, 0)
    end,
  },
  {
    "Initializr Wizard generates a Maven project, unzips it, and opens it",
    function()
      local plugin, adapters = happy_plugin({ jdk_major = 21 })
      plugin:setup({})
      plugin:init()
      local wizard = adapters.ui.wizards[1]
      assert_true(wizard ~= nil, "wizard opened")
      assert_eq(#wizard.steps, 3)
      assert_eq(wizard.steps[1].title, "Identity")
      assert_eq(wizard.steps[2].title, "Platform")
      assert_eq(wizard.steps[3].title, "Dependencies")
      assert_eq(wizard.steps[1].fields[1].name, "groupId")
      assert_eq(wizard.steps[1].fields[2].name, "artifactId")
      assert_eq(wizard.steps[1].fields[3].name, "packageName")
      assert_eq(wizard.steps[2].fields[1].name, "bootVersion")
      assert_eq(wizard.steps[2].fields[2].name, "javaVersion")
      assert_true(type(wizard.preview) == "function", "preview-led Wizard")
      assert_contains(wizard.preview({
        groupId = "com.example",
        artifactId = "demo",
        packageName = "com.example.demo",
        bootVersion = "4.1.0",
        javaVersion = "21",
        dependencies = {},
      }), "demo/")
      local gen = generate_request(adapters.http)
      assert_true(gen ~= nil, "starter.zip requested")
      assert_contains(gen.url, "starter.zip")
      assert_contains(gen.url, "type=maven-project")
      assert_contains(gen.url, "groupId=com.example")
      assert_contains(gen.url, "artifactId=demo")
      assert_contains(gen.url, "packageName=com.example.demo")
      assert_eq(adapters.fs:read("demo/pom.xml"), POM)
      assert_true(adapters.fs:read("demo/src/main/java/com/example/demo/DemoApplication.java") ~= nil)
      assert_eq(adapters.ui.opened, "/workspace/demo")
    end,
  },
  {
    "New-project Language level defaults to the highest catalog value the Host JDK can compile",
    function()
      local plugin, adapters = happy_plugin({ jdk_major = 21 })
      plugin:setup({})
      plugin:init()
      local gen = generate_request(adapters.http)
      assert_contains(gen.url, "javaVersion=21")
      local java_field = adapters.ui.wizards[1].steps[2].fields[2]
      assert_eq(java_field.default, "21")
    end,
  },
  {
    "Unknown Host JDK falls back to the catalog Language level default",
    function()
      local plugin, adapters = happy_plugin({ jdk_major = nil })
      plugin:setup({})
      plugin:init()
      assert_contains(generate_request(adapters.http).url, "javaVersion=17")
    end,
  },
  {
    "Host JDK below every catalog Language level falls back to the catalog default",
    function()
      local plugin, adapters = happy_plugin({ jdk_major = 11 })
      plugin:setup({})
      plugin:init()
      assert_contains(generate_request(adapters.http).url, "javaVersion=17")
    end,
  },
  {
    "Host JDK newer than the catalog max falls back to the catalog max Language level",
    function()
      local plugin, adapters = happy_plugin({ jdk_major = 26 })
      plugin:setup({})
      plugin:init()
      assert_contains(generate_request(adapters.http).url, "javaVersion=25")
    end,
  },
  {
    "Boot default is the instance default, not a SNAPSHOT just because one is listed",
    function()
      local plugin, adapters = happy_plugin({ jdk_major = 21 })
      plugin:setup({})
      plugin:init()
      local gen = generate_request(adapters.http)
      assert_contains(gen.url, "bootVersion=4.1.0")
      assert_not_contains(gen.url, "SNAPSHOT")
      local boot_field = adapters.ui.wizards[1].steps[2].fields[1]
      assert_eq(boot_field.default, "4.1.0")
      local ids = {}
      for _, value in ipairs(boot_field.values) do
        ids[#ids + 1] = value.id
      end
      assert_contains(table.concat(ids, " "), "4.1.1-SNAPSHOT")
    end,
  },
  {
    "A SNAPSHOT Boot version stays selectable and is used when the Wizard picks it",
    function()
      local plugin, adapters = happy_plugin({
        jdk_major = 21,
        ui = fakes.ui({
          wizard_answers = {
            groupId = "com.example",
            artifactId = "demo",
            packageName = "com.example.demo",
            bootVersion = "4.1.1-SNAPSHOT",
            javaVersion = "21",
            dependencies = {},
          },
        }),
      })
      plugin:setup({})
      plugin:init()
      assert_contains(generate_request(adapters.http).url, "bootVersion=4.1.1-SNAPSHOT")
    end,
  },
  {
    "Metadata request pins Initializr v2.3 Accept and sends a Plugin User-Agent",
    function()
      local plugin, adapters = happy_plugin({ jdk_major = 21 })
      plugin:setup({})
      plugin:init()
      local meta = metadata_request(adapters.http)
      assert_eq(meta.headers.Accept, "application/vnd.initializr.v2.3+json")
      assert_eq(meta.headers["User-Agent"], "nvim-spring/0.1.0")
      local gen = generate_request(adapters.http)
      assert_eq(gen.headers["User-Agent"], "nvim-spring/0.1.0")
    end,
  },
  {
    "One configurable opaque Initializr base URL is used for metadata and generate",
    function()
      local plugin, adapters = happy_plugin({
        jdk_major = 21,
        opts = { initializr_url = "http://initializr.internal/" },
      })
      plugin:setup({ initializr_url = "http://initializr.internal/" })
      plugin:init()
      local meta = metadata_request(adapters.http)
      local gen = generate_request(adapters.http)
      assert_contains(meta.url, "http://initializr.internal")
      assert_contains(gen.url, "http://initializr.internal/starter.zip")
    end,
  },
  {
    "Selected Dependencies are requested on generate",
    function()
      local plugin, adapters = happy_plugin({
        jdk_major = 21,
        ui = fakes.ui({
          wizard_answers = {
            groupId = "com.example",
            artifactId = "demo",
            packageName = "com.example.demo",
            bootVersion = "4.1.0",
            javaVersion = "21",
            dependencies = { "web", "devtools" },
          },
        }),
      })
      plugin:setup({})
      plugin:init()
      local url = generate_request(adapters.http).url
      assert_contains(url, "dependencies=web%2Cdevtools")
    end,
  },
  {
    "Existing destination loud-refuses and does not download starter.zip",
    function()
      local plugin, adapters = happy_plugin({
        jdk_major = 21,
        ui = fakes.ui({
          wizard_answers = {
            groupId = "com.example",
            artifactId = "demo",
            packageName = "com.example.demo",
            bootVersion = "4.1.0",
            javaVersion = "21",
            dependencies = {},
          },
        }),
      })
      adapters.fs:write("demo/README", "already here")
      adapters.fs.writes = {}
      plugin:setup({})
      plugin:init()
      assert_contains(fakes.notify_text(adapters.ui), "already exists")
      assert_true(generate_request(adapters.http) == nil, "must not download")
      assert_eq(#adapters.fs.writes, 0)
    end,
  },
  {
    "Cancelled Wizard writes no project",
    function()
      local plugin, adapters = happy_plugin({
        jdk_major = 21,
        ui = fakes.ui({ wizard_answers = false }),
      })
      plugin:setup({})
      plugin:init()
      assert_true(generate_request(adapters.http) == nil, "must not download")
      assert_eq(#adapters.fs.writes, 0)
      assert_eq(adapters.ui.opened, nil)
    end,
  },
  {
    "Missing cwd loud-refuses and does not download starter.zip",
    function()
      local plugin, adapters = happy_plugin({ jdk_major = 21 })
      adapters.fs.cwd = function()
        return nil
      end
      plugin:setup({})
      plugin:init()
      assert_contains(fakes.notify_text(adapters.ui), "current directory")
      assert_true(generate_request(adapters.http) == nil, "must not download")
      assert_eq(#adapters.fs.writes, 0)
    end,
  },
  {
    "Invalid artifactId loud-refuses and does not download starter.zip",
    function()
      for _, artifact in ipairs({ "", ".", "..", "../demo", "/tmp/demo", "foo\\bar" }) do
        local plugin, adapters = happy_plugin({
          jdk_major = 21,
          ui = fakes.ui({
            wizard_answers = {
              groupId = "com.example",
              artifactId = artifact,
              packageName = "com.example.demo",
              bootVersion = "4.1.0",
              javaVersion = "21",
              dependencies = {},
            },
          }),
        })
        plugin:setup({})
        plugin:init()
        assert_contains(fakes.notify_text(adapters.ui), "not valid")
        assert_true(generate_request(adapters.http) == nil, "must not download")
        assert_eq(#adapters.fs.writes, 0)
        assert_eq(adapters.ui.opened, nil)
      end
    end,
  },
  {
    "Catalog entries that are not option tables are not Initializr metadata",
    function()
      local meta = fakes.initializr_metadata()
      meta.type.values = { "maven-project" }
      local plugin, adapters = fakes.plugin({
        http = fakes.http({ status = 200, body = meta }),
      })
      plugin:setup({})
      plugin:init()
      assert_contains(fakes.notify_text(adapters.ui), "not Initializr")
      assert_eq(#adapters.fs.writes, 0)
    end,
  },
}
