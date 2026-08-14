-- Maven Central: live Solr search and repo1 POM fetch.

local M = {}

local SOLR = "https://search.maven.org/solrsearch/select"
local REPO1 = "https://repo1.maven.org/maven2"

local function url_encode(s)
  return (tostring(s):gsub("([^%w%-_%.~])", function(c)
    return string.format("%%%02X", string.byte(c))
  end))
end

local function http_get(url)
  local out = vim.fn.system({
    "curl",
    "-sS",
    "-L",
    "--max-time",
    "15",
    "-A",
    "nvim-spring",
    "-w",
    "\n%{http_code}",
    url,
  })
  if vim.v.shell_error ~= 0 then
    return nil, "network"
  end
  local body, status = tostring(out):match("^(.*)\n(%d+)%s*$")
  status = tonumber(status)
  if not body or not status then
    return nil, "network"
  end
  if status < 200 or status >= 300 then
    return nil, "http"
  end
  return body
end

local function decode_docs(body)
  local ok, data = pcall(vim.json.decode, body)
  if not ok or type(data) ~= "table" then
    return nil, "decode"
  end
  local docs = data.response and data.response.docs
  if type(docs) ~= "table" then
    return {}
  end
  return docs
end

local function solr_select(q, extra)
  extra = extra or ""
  local url = SOLR .. "?q=" .. url_encode(q) .. "&rows=50&wt=json" .. extra
  local body, err = http_get(url)
  if not body then
    return nil, err
  end
  return decode_docs(body)
end

function M:search_coordinates(g, a, v)
  local q = "g:" .. g .. " AND a:" .. a
  local extra = ""
  if v then
    q = q .. " AND v:" .. v
    extra = "&core=gav"
  end
  return solr_select(q, extra)
end

function M:search_class(name, fqcn)
  local field = fqcn and "fc" or "c"
  return solr_select(field .. ":" .. name)
end

function M:search_keyword(keyword)
  return solr_select(keyword)
end

function M:fetch_pom(g, a, v)
  if not (g and a and v) then
    return nil
  end
  local path = g:gsub("%.", "/") .. "/" .. a .. "/" .. v .. "/" .. a .. "-" .. v .. ".pom"
  local body = http_get(REPO1 .. "/" .. path)
  return body
end

return M
