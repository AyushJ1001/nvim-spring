#!/usr/bin/env luajit
-- Pure-Lua harness: require the Plugin action module without a Neovim UI.

local here = arg[0]:match("(.+)/[^/]+$") or "."
local root = here:match("(.+)/tests$") or (here .. "/..")

package.path = table.concat({
  root .. "/lua/?.lua",
  root .. "/lua/?/init.lua",
  here .. "/?.lua",
  here .. "/?/init.lua",
  package.path,
}, ";")

local failures = {}
local passed = 0
local current_file = "?"

local function fail(msg)
  error(msg, 2)
end

function _G.assert_eq(actual, expected, msg)
  if actual ~= expected then
    fail((msg and (msg .. ": ") or "") .. string.format("expected %q, got %q", tostring(expected), tostring(actual)))
  end
end

function _G.assert_true(cond, msg)
  if not cond then
    fail(msg or "expected true")
  end
end

function _G.assert_false(cond, msg)
  if cond then
    fail(msg or "expected false")
  end
end

function _G.assert_contains(haystack, needle, msg)
  haystack = haystack or ""
  if not tostring(haystack):find(needle, 1, true) then
    fail((msg and (msg .. ": ") or "") .. string.format("expected %q to contain %q", tostring(haystack), needle))
  end
end

function _G.assert_not_contains(haystack, needle, msg)
  haystack = haystack or ""
  if tostring(haystack):find(needle, 1, true) then
    fail((msg and (msg .. ": ") or "") .. string.format("expected %q not to contain %q", tostring(haystack), needle))
  end
end

local function run_file(path)
  current_file = path
  local chunk, err = loadfile(path)
  if not chunk then
    failures[#failures + 1] = { name = path, err = err }
    return
  end
  local tests = chunk()
  if type(tests) ~= "table" then
    failures[#failures + 1] = { name = path, err = "test file must return a list of {name, fn}" }
    return
  end
  for _, case in ipairs(tests) do
    local name, fn = case[1], case[2]
    local ok, perr = pcall(fn)
    if ok then
      passed = passed + 1
      io.write("  ok  " .. name .. "\n")
    else
      failures[#failures + 1] = { name = name, err = perr }
      io.write("  FAIL  " .. name .. "\n    " .. tostring(perr) .. "\n")
    end
  end
end

local files = {
  here .. "/actions_test.lua",
}

io.write("nvim-spring tests\n")
for _, path in ipairs(files) do
  io.write(path:sub(#here + 2) .. "\n")
  run_file(path)
end

io.write(string.format("\n%d passed, %d failed\n", passed, #failures))
if #failures > 0 then
  os.exit(1)
end
