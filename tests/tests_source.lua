-- RunBook source checks: things a mock client can't catch.
package.path = "./?.lua;" .. package.path
local H = require("harness")
local check = H.check
local DIR = H.ADDON_DIR

local function readFile(path)
  local f = assert(io.open(path))
  local s = f:read("*a")
  f:close()
  return s
end

local toc = H.readToc()
local sources = {}
for _, file in ipairs(toc) do sources[file] = readFile(DIR .. file:gsub("\\", "/")) end  -- (the TOC uses Windows separators)

H.group("toc")
do
  local p = io.popen('ls "' .. DIR .. '"')
  local listed = {}
  for _, f in ipairs(toc) do listed[f] = true end
  for f in p:lines() do
    if f:match("%.lua$") then check("in toc: " .. f, listed[f]) end
  end
  p:close()
  local tocText = readFile(DIR .. "VulcanRunBook.toc")
  check("interface 16001", tocText:find("## Interface: 16001", 1, true) ~= nil)
  check("saved variables", tocText:find("## SavedVariables: VulcanRunBookDB", 1, true) ~= nil
    and tocText:find("## SavedVariablesPerCharacter: VulcanRunBookCharDB", 1, true) ~= nil)
  check("bindings file present", io.open(DIR .. "Bindings.xml") ~= nil)
end

-- Values these APIs return can be secret on Forever: each direct call must go
-- through plain() on the same or the next line (ns.Call() does it for you, and
-- passes the function rather than calling it, so it isn't matched here).
H.group("secret-safe API calls")
local SECRET_APIS = { "UnitName", "UnitIsDeadOrGhost", "UnitIsFeignDeath", "GetMoney", "UnitXP", "UnitXPMax",
  "GetInstanceInfo", "IsInInstance", "GetServerTime", "GetNumGroupMembers", "UnitIsUnit", "UnitIsConnected", "UnitGUID",
  "GetBestMapForUnit", "GetMapGroupID", "GetMapInfo", "GetContainerNumSlots", "GetContainerItemInfo",
  "GetInventoryItemID", "GetInventoryItemCount", "InChatMessagingLockdown", "GetItemQualityByID" }
for file, src in pairs(sources) do
  local lines = {}
  for l in (src .. "\n"):gmatch("(.-)\n") do lines[#lines + 1] = l end
  for i, l in ipairs(lines) do
    local code = l:gsub("%-%-.*$", "")
    for _, api in ipairs(SECRET_APIS) do
      -- A direct call "Api(" or a call through ns.Call(..Api, ...), which plain()s its result.
      if code:find("[^%w_.]" .. api .. "%(") or code:find("^" .. api .. "%(")
          or code:find("%." .. api .. "%(") then
        local ok = code:find("plain(", 1, true) or (lines[i + 1] or ""):find("plain(", 1, true)
        check(string.format("%s:%d %s wrapped in plain()", file, i, api), ok, l)
      end
    end
  end
end

-- Display only: nothing that acts for the player.
H.group("no automation")
local FORBIDDEN = { "CastSpell", "UseAction", "TargetUnit", "RunMacro", "LootSlot", "RollOnLoot", "ConfirmLootRoll",
  "ResetInstances", "SendMail", "PickupContainerItem", "UseContainerItem", "AcceptGroup", "InviteUnit",
  "LeaveParty", "C_PartyInfo", "MoveForward", "InteractUnit" }
for file, src in pairs(sources) do
  for _, api in ipairs(FORBIDDEN) do
    check(file .. " doesn't call " .. api, not src:find(api, 1, true))
  end
end

H.group("structure")
for file, src in pairs(sources) do
  check(file .. " uses the addon namespace", src:find("local [%w_]+, ns = %.%.%.") ~= nil)
end

os.exit(H.summary("tests_source.lua") and 0 or 1)
