-- Release checks: TOC fields, the version token and the addon-message prefix.
package.path = "./?.lua;" .. package.path
local H = require("harness")
local check, eq = H.check, H.eq
local DIR = H.ADDON_DIR

local function read(name)
  local f = assert(io.open(DIR .. name, "rb"))
  local s = f:read("*a")
  f:close()
  return s
end

H.group("TOC")
local toc = read("VulcanRunBook.toc")
check("version is the packager token", toc:find("\n## Version: @project-version@\n", 1, true) ~= nil)
check("author is Tavlius", toc:find("\n## Author: Tavlius\n", 1, true) ~= nil)
check("title", toc:find("\n## Title: Vulcan RunBook\n", 1, true) ~= nil)
check("interface is Forever 1.60.1 (16001)", toc:find("^## Interface: 16001\n") ~= nil)

-- The one place the version is read must cope with the unreplaced token, so a
-- copy run from source shows "dev" instead of "@project-version@".
H.group("version token")
do
  local readers = {}
  for file in toc:gmatch("\n([%w_\\]+%.lua)") do
    local src = read(file:gsub("\\", "/"))
    if src:find("GetAddOnMetadata") then readers[#readers + 1] = file end
  end
  eq("only Util.lua reads the version", table.concat(readers, ","), "Util.lua")
  local c = H.boot() c.login()
  eq("from source the version is dev", c.ns.VERSION, "dev")
  local c2 = H.boot({ tocVersion = "@project-version@" }) c2.login()
  eq("an unreplaced token is never shown", c2.ns.VERSION, "dev")
  local c3 = H.boot({ tocVersion = "v2.0.0" }) c3.login()
  eq("a release shows its tag", c3.ns.VERSION, "v2.0.0")
  -- Sync goes by the protocol number: a dev copy and a release still talk.
  local s = read("Sync.lua")
  check("sync never sends or compares the version string", not s:find("ns.VERSION", 1, true))
end

-- Addon-message prefixes: at most 16 characters, and every Vulcan add-on's is different.
H.group("prefix")
do
  local SUITE_PREFIXES = {
    VulcanGrindWatch = "VulcanGrindWatch", VulcanRunBook = "VulcanRunBook", VulcanDuoQuest = "VulcanDuoQuest",
  }
  local prefix = read("Sync.lua"):match('local PREFIX = "([^"]+)"')
  eq("prefix is this add-on's suite prefix", prefix, SUITE_PREFIXES.VulcanRunBook)
  local seen, distinct = {}, true
  for _, p in pairs(SUITE_PREFIXES) do
    check("prefix " .. p .. " fits 16 characters", #p <= 16, #p)
    if seen[p] then distinct = false end
    seen[p] = true
  end
  check("suite prefixes are all different", distinct)
  local c = H.boot() c.login()
  c.party("Mirel") c.slash("partner Mirel")
  c.enter("Deadmines", 36)
  c.tick(40)
  local sent = c.addonSent[1]
  check("sync sends with that prefix", sent ~= nil and sent.prefix == prefix, sent and sent.prefix)
end

os.exit(H.summary() and 0 or 1)
