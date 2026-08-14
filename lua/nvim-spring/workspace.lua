-- Workspace contract classification. Internal to the action module.

local M = {}

local GRADLE_MARKERS = {
  "build.gradle",
  "build.gradle.kts",
  "settings.gradle",
  "settings.gradle.kts",
}

local function is_gradle(fs)
  for _, name in ipairs(GRADLE_MARKERS) do
    if fs:exists(name) then
      return true
    end
  end
  return false
end

local function tag(xml, name)
  local escaped = name:gsub("(%W)", "%%%1")
  return xml and xml:match("<" .. escaped .. "[^>]*>%s*(.-)%s*</" .. escaped .. ">")
end

local function parse_language_level(raw)
  if not raw then
    return nil
  end
  if raw == "1.8" or raw == "8" then
    return 8
  end
  return tonumber(raw:match("^(%d+)"))
end

local function parse_major(raw)
  if not raw then
    return nil
  end
  return tonumber(raw:match("^(%d+)"))
end

local function boot_version_from_pom(xml)
  local parent = tag(xml, "parent")
  if parent then
    local artifact = tag(parent, "artifactId")
    if artifact == "spring-boot-starter-parent" then
      return tag(parent, "version")
    end
  end
  for dep in xml:gmatch("<dependency[^>]*>(.-)</dependency>") do
    local artifact = tag(dep, "artifactId")
    if artifact == "spring-boot-dependencies" then
      return tag(dep, "version")
    end
  end
  return nil
end

local function language_level_from_pom(xml)
  local raw = tag(xml, "maven.compiler.release")
    or tag(xml, "java.version")
    or tag(xml, "maven.compiler.source")
    or tag(xml, "maven.compiler.target")
  if not raw then
    local compiler = xml:match("<artifactId>%s*maven%-compiler%-plugin%s*</artifactId>(.-)</plugin>")
    if compiler then
      raw = tag(compiler, "release") or tag(compiler, "source")
    end
  end
  return parse_language_level(raw)
end

function M.is_spring_boot(fs)
  local pom = fs:read("pom.xml")
  if not pom then
    return false
  end
  local parent = tag(pom, "parent")
  if parent and tag(parent, "artifactId") == "spring-boot-starter-parent" then
    return true
  end
  for dep in pom:gmatch("<dependency[^>]*>(.-)</dependency>") do
    local artifact = tag(dep, "artifactId") or ""
    if artifact == "spring-boot-dependencies" or artifact:find("^spring%-boot%-starter") then
      return true
    end
  end
  return false
end

function M.classify(fs)
  if is_gradle(fs) then
    return {
      refuse = true,
      reason = "gradle",
      message = "Gradle is not implemented yet.",
    }
  end

  if not fs:exists("pom.xml") then
    return { refuse = false, reason = "ok" }
  end

  local pom = fs:read("pom.xml") or ""

  if tag(pom, "modules") then
    return {
      refuse = true,
      reason = "reactor",
      message = "Maven reactors are not implemented yet.",
    }
  end

  local boot_version = boot_version_from_pom(pom)
  local boot_major = parse_major(boot_version)
  if boot_major and boot_major < 3 then
    return {
      refuse = true,
      reason = "boot",
      message = "Spring Boot " .. boot_major .. " is out of contract.",
    }
  end

  local level = language_level_from_pom(pom)
  if level and level < 17 then
    return {
      refuse = true,
      reason = "language_level",
      message = "Language level " .. level .. " is out of contract.",
    }
  end

  return { refuse = false, reason = "ok" }
end

function M.is_boot(fs)
  if not fs or not fs.exists or not fs:exists("pom.xml") then
    return false
  end
  local pom = fs:read("pom.xml") or ""
  if boot_version_from_pom(pom) then
    return true
  end
  for dep in pom:gmatch("<dependency[^>]*>(.-)</dependency>") do
    local artifact = tag(dep, "artifactId") or ""
    if artifact == "spring-boot-dependencies" or artifact:find("^spring%-boot%-starter") then
      return true
    end
  end
  return false
end

return M
