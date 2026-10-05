-- Mock WoW client for RunBook tests. boot() builds a fresh client, loads the
-- addon files in TOC order, and returns a handle for driving events and time.
local H = {}
local ADDON_DIR = assert(os.getenv("RL_DIR"), "RL_DIR unset: run tests/run.sh")

-- A secret value like the real client's: arithmetic, comparison (<, >),
-- concatenation, indexing or calling it throws. (Lua 5.1 can't make `==` or a
-- truthiness test throw; tests_source.lua scans the code for those instead.)
local SECRET = newproxy(true)
do
  local mt = getmetatable(SECRET)
  local function boom() error("secret value touched", 2) end
  for _, k in ipairs({ "__index", "__newindex", "__lt", "__le", "__add", "__sub", "__mul", "__div", "__mod",
      "__unm", "__concat", "__len", "__call" }) do mt[k] = boom end
  mt.__tostring = function() return "<secret>" end
end
H.SECRET = SECRET
local rawtype = type

local function readToc()
  local files = {}
  for line in io.lines(ADDON_DIR .. "VulcanRunBook.toc") do
    if line:match("%.lua%s*$") then files[#files + 1] = line:match("^%s*(.-)%s*$") end
  end
  return files
end
H.readToc = readToc
H.ADDON_DIR = ADDON_DIR

-- Quality colors as the modern client writes them in links.
local QHEX = { [0] = "9d9d9d", "ffffff", "1eff00", "0070dd", "a335ee", "ff8000" }

function H.boot(opts)
  opts = opts or {}
  local c = {
    now = 1000, wall = 1700000000, serverOffset = opts.serverOffset or 0,
    xp = 1000, xpMax = 5000, level = 20, money = 50000,
    dead = false, feign = false, name = opts.name or "Tavlius",
    instance = nil,     -- { name=, map=, diff=, kind= }
    group = {},         -- { { name=, dead=, feign= } }  (party1..)
    raid = false,
    printed = {}, sent = {}, addonSent = {}, frames = {}, items = {}, cached = {},
    secret = {}, loadRequests = {},
  }
  local function sec(key, v) if c.secret[key] then return SECRET end return v end
  c.SECRET = SECRET
  if opts.saved then
    c.wall = (opts.saved.wall or c.wall) + (opts.gap or 1)
    c.now = (opts.saved.now or c.now) + (opts.gap or 1)
  end
  _G.VulcanRunBookDB = opts.saved and opts.saved.db or nil
  _G.VulcanRunBookCharDB = opts.saved and opts.saved.char or nil

  _G.issecretvalue = opts.secretAware == false and nil or function(v) return rawequal(v, SECRET) end
  -- Real secrets keep their Lua type (a secret name is still a "string"), so
  -- type() checks alone don't filter them.
  _G.type = function(v)
    if rawequal(v, SECRET) then return c.secretType or "string" end
    return rawtype(v)
  end
  _G.print = function(...)
    local t = {}
    for i = 1, select("#", ...) do t[#t + 1] = tostring(select(i, ...)) end
    c.printed[#c.printed + 1] = table.concat(t, " ")
  end
  _G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
  _G.GetTime = function() return c.now end
  _G.time = function() return c.wall end
  _G.GetServerTime = opts.noServerTime and nil or function() return sec("server", c.wall + c.serverOffset) end
  -- The weekly reset: Tuesdays 15:00 UTC (c.weeklyAt overrides the phase).
  _G.C_DateAndTime = (not opts.noWeekly) and {
    GetSecondsUntilWeeklyReset = function()
      local t = c.wall + c.serverOffset - (c.weeklyAt or (5 * 86400 + 15 * 3600))
      return sec("weekly", 604800 - (t % 604800))
    end,
  } or nil
  -- Your realm, as the real client has it (partners' messages come as "Mirel-Realm").
  _G.GetNormalizedRealmName = (not opts.noRealm) and function() return c.realm or "Realm" end or nil
  _G.date = function(fmt, t) return os.date("!" .. fmt, t) end
  _G.UnitXP = function() return sec("xp", c.xp) end
  _G.UnitXPMax = function() return sec("xpMax", c.xpMax) end
  _G.GetMoney = function() return sec("money", c.money) end

  -- Units: "player", "party1".., "raid1".. (raid1 = player in a raid)
  local function unitInfo(u)
    if u == "player" then return { name = c.name, dead = c.dead, feign = c.feign } end
    local n = u:match("^party(%d+)$")
    if n then return c.group[tonumber(n)] end
    n = u:match("^raid(%d+)$")
    if n then
      n = tonumber(n)
      if n == 1 then return { name = c.name, dead = c.dead, feign = c.feign } end
      return c.group[n - 1]
    end
    return nil
  end
  c.unitInfo = unitInfo
  _G.UnitName = function(u)
    local i = unitInfo(u)
    if not i then return nil end
    if i.secretName then return SECRET end
    -- (Like the real API: someone from another realm is name, realm.)
    local n, r = tostring(i.name):match("^([^%-]+)%-(.+)$")
    if n then return n, r end
    return i.name
  end
  _G.UnitIsDeadOrGhost = function(u)
    local i = unitInfo(u)
    if not i then return false end
    if i.secretDead or c.secret.dead then return SECRET end
    return i.dead and true or false
  end
  -- Like the real API: it never reports your own Feign Death.
  _G.UnitIsFeignDeath = not opts.noFeign and function(u)
    if u == "player" or u == "raid1" then return false end
    local i = unitInfo(u)
    return i and i.feign or false
  end or nil
  _G.UnitIsUnit = function(a, b)
    local function norm(u) return (u == "raid1") and "player" or u end
    return norm(a) == norm(b)
  end
  _G.UnitIsConnected = function(u)
    local i = unitInfo(u)
    if not i then return false end
    return not i.offline
  end
  -- Friends: c.friends[name] = true (friends list), c.bnet[name] = "Tag#1234"
  -- (Battle.net friend). opts.noFriendAPI: neither API exists.
  c.friends, c.bnet = {}, {}
  _G.UnitGUID = function(u)
    local i = unitInfo(u)
    if not i then return nil end
    if i.secretGUID then return SECRET end
    return "Player-1-" .. tostring(i.name)
  end
  local function guidName(g) return type(g) == "string" and g:match("^Player%-1%-(.+)$") or nil end
  _G.C_BattleNet = (not opts.noFriendAPI) and {
    GetAccountInfoByGUID = function(g)
      local n = guidName(g)
      local tag = n and c.bnet[n]
      if not tag then return nil end
      -- (A table: { tag, isFriend } for an account the game knows that isn't a friend.)
      if type(tag) == "table" then return { battleTag = tag[1], isFriend = tag[2] } end
      return { battleTag = tag, isFriend = true }
    end,
  } or nil
  _G.C_FriendList = (not opts.noFriendAPI) and {
    IsFriend = function(g)
      local n = guidName(g)
      return n ~= nil and c.friends[n] == true
    end,
    GetFriendInfo = function(n)
      if c.friendInfoOff then return nil end  -- (only IsFriend answers)
      if c.friends[n] then return { name = n, connected = true } end
      return nil
    end,
  } or nil
  _G.GetNumGroupMembers = function() return #c.group > 0 and (#c.group + 1) or 0 end
  _G.IsInGroup = function() return #c.group > 0 end
  _G.IsInRaid = function() return c.raid end
  _G.Ambiguate = function(n) return (n:match("^[^%-]+")) end

  -- Maps: each instance has a ui map (its wing/floor); c.instance.uiMap.
  _G.C_Map = {
    -- c.away[name] = a group member's map when they're somewhere else.
    GetBestMapForUnit = function(unit)
      if c.secret.uimap then return SECRET end
      if unit and unit ~= "player" and c.away then
        local n = _G.UnitName(unit)
        if n and c.away[n] then return c.away[n] end
      end
      if unit and unit ~= "player" and c.lastInstance then return c.lastInstance.uiMap or 1429 end  -- (still inside)
      return c.instance and c.instance.uiMap or 1429
    end,
    GetMapGroupID = function(ui) return c.mapGroups and c.mapGroups[ui] or nil end,
    -- c.groupFloors[group] = { { mapID =, name = } } (a group's floors and their names)
    GetMapGroupMembersInfo = function(group) return c.groupFloors and c.groupFloors[group] or nil end,
    -- A dungeon's map is usually named like the dungeon ("The Deadmines").
    GetMapInfo = function(ui)
      local name = c.mapNames and c.mapNames[ui] or (c.instance and ("The " .. c.instance.name)) or "Elwynn Forest"
      -- c.mapTypes[ui]: Enum.UIMapType (3 zone, 4 dungeon, 5 micro); outdoors 3.
      local kind = c.mapTypes and c.mapTypes[ui] or (ui == 1429 and 3 or 4)
      return { mapID = ui, name = name, mapType = kind }
    end,
  }
  -- Bags: c.bagSlots = { { id =, n = } } (all in the backpack); c.equipped[slot] = itemID
  c.bagSlots, c.equipped = {}, {}
  _G.C_Container = {
    GetContainerNumSlots = function(bag) return bag == 0 and math.max(16, #c.bagSlots) or 0 end,
    GetContainerItemInfo = function(bag, slot)
      local it = bag == 0 and c.bagSlots[slot]
      if not it then return nil end
      return { itemID = it.id, stackCount = it.n, hyperlink = c.items[it.id] and c.link(it.id, c.items[it.id][1],
        c.items[it.id][2]) or nil }
    end,
  }
  _G.GetInventoryItemID = function(_, slot) return c.equipped[slot] end
  _G.GetInventoryItemCount = function(_, slot) return c.equipped[slot] and 200 or 0 end
  _G.NUM_BAG_SLOTS = 4
  _G.NUM_TOTAL_EQUIPPED_BAG_SLOTS = nil

  _G.IsInInstance = function()
    if not c.instance then return false, "none" end
    return true, c.instance.kind or "party"
  end
  _G.GetInstanceInfo = function()
    local i = c.instance
    if not i then return "Elwynn Forest", "none", 0, "", 0, false, false, 0 end
    return sec("iname", i.name), i.kind or "party", i.diff or 1, i.diff == 2 and "Heroic" or "Normal", 5, false,
      false, sec("map", i.map)
  end

  local L = opts.locale or {}
  _G.LOOT_ITEM_SELF = L.self or "You receive loot: %s."
  _G.LOOT_ITEM_SELF_MULTIPLE = L.selfMulti or "You receive loot: %sx%d."
  _G.LOOT_ITEM = L.other or "%s receives loot: %s."
  _G.LOOT_ITEM_MULTIPLE = L.otherMulti or "%s receives loot: %sx%d."
  _G.INSTANCE_RESET_SUCCESS = "%s has been reset."
  _G.TRANSFER_ABORT_TOO_MANY_INSTANCES = "You have entered too many instances recently."

  -- c.items[id] = { name, quality, sellPrice }; c.cached[id] = item data loaded
  _G.C_Item = {
    GetItemInfo = function(x)
      local id = rawtype(x) == "number" and x or tonumber(tostring(x):match("item:(%d+)"))
      if not c.cached[id] then return nil end
      local it = c.items[id]
      return it[1], nil, it[2], nil, nil, nil, nil, nil, nil, nil, it[3]
    end,
    GetItemQualityByID = opts.noQualityAPI and nil or function(id)
      if not c.cached[id] then return nil end
      return c.items[id][2]
    end,
    RequestLoadItemDataByID = function(id) c.loadRequests[#c.loadRequests + 1] = id end,
  }
  _G.GetItemInfo = nil
  -- Like the real client: in a chat lockdown a send is blocked silently (no error).
  _G.C_ChatInfo = {
    InChatMessagingLockdown = function() return c.chatLockdown and true or false end,
    SendChatMessage = function(msg, ch, _, target)
      if c.chatLockdown then c.blockedChat = (c.blockedChat or 0) + 1 return end
      if c.chatFails then error("chat failed") end
      c.sent[#c.sent + 1] = { msg = msg, ch = ch, target = target }
    end,
    SendAddonMessage = function(prefix, msg, ch)
      if #msg > 255 then return 2 end
      if c.addonResult and c.addonResult ~= 0 then return c.addonResult end
      c.addonSent[#c.addonSent + 1] = { prefix = prefix, msg = msg, ch = ch }
      return 0
    end,
    RegisterAddonMessagePrefix = function() return opts.prefixResult or 0 end,
  }
  _G.Enum = { PlayerInteractionType = { Merchant = 5, MailInfo = 17, TradePartner = 1 } }
  _G.Auctionator = opts.auctionator and {
    API = { v1 = { GetAuctionPriceByItemID = function(_, id)
      if opts.auctionatorThrows then error("Auctionator internal error") end
      return opts.auctionator[id]
    end } },
  } or nil
  _G.BackdropTemplateMixin = {}
  _G.GetBuildInfo = function() return "1.60.1", "69893", "Sep 2026", 16001 end
  -- TOC fields as the client reads them; opts.tocVersion stands in for a packaged release.
  _G.GetAddOnMetadata = function(addon, field)
    if addon ~= "VulcanRunBook" then return nil end
    for line in io.lines(ADDON_DIR .. "VulcanRunBook.toc") do
      local k, v = line:match("^## ([%w%-]+): (.-)%s*$")
      if k == field then return (field == "Version" and opts.tocVersion) or v end
    end
  end
  _G.C_AddOns = nil
  -- Saved-data safety (Persist.lua): a UI reload only records it was asked for.
  _G.ReloadUI = function() c.reloads = (c.reloads or 0) + 1 end
  _G.ChatFontNormal = {}
  _G.UISpecialFrames = {}
  _G.UIParent = {}
  _G.SlashCmdList = {}
  for _, g in ipairs({ "VulcanRunBook_ToggleLive", "VulcanRunBook_ToggleHistory", "VulcanRunBook_OnAddonCompartmentClick",
      "VulcanRunBookFrame", "VulcanRunBookHistoryFrame", "VulcanRunBookCopyFrame" }) do _G[g] = nil end

  local function newFS()
    local fs = { shown = true, text = "" }
    function fs:SetPoint() end
    function fs:ClearAllPoints() end
    function fs:SetWidth() end
    function fs:SetText(t)
      if rawequal(t, SECRET) then error("secret text") end
      self.text = t
    end
    function fs:GetText() return self.text end
    function fs:SetJustifyH() end
    function fs:SetJustifyV() end
    function fs:SetTextColor(r, g, b) self.color = { r, g, b } end
    function fs:SetWordWrap() end
    function fs:Show() self.shown = true end
    function fs:Hide() self.shown = false end
    return fs
  end
  _G.CreateFrame = function(kind, name, parent)
    local f = { kind = kind, scripts = {}, events = {}, shown = true, fontstrings = {}, w = 0, h = 0, scale = 1,
      parent = parent, enabled = true }
    -- Unknown methods (Capitalized, like the client's) are no-ops; unknown
    -- fields are nil, as on a real frame.
    setmetatable(f, { __index = function(_, k)
      if type(k) == "string" and k:match("^%u") then return function() end end
      return nil
    end })
    function f:RegisterEvent(e)
      if c.unknownEvents and c.unknownEvents[e] then error("unknown event " .. e) end
      self.events[e] = true
    end
    function f:SetScript(n, fn) self.scripts[n] = fn end
    function f:CreateFontString() local fs = newFS() table.insert(self.fontstrings, fs) return fs end
    function f:Show()
      local was = self.shown
      self.shown = true
      if not was and self.scripts.OnShow then self.scripts.OnShow(self) end
    end
    function f:Hide() self.shown = false end
    function f:IsShown() return self.shown end
    function f:SetSize(w, h) self.w, self.h = w, h end
    function f:SetHeight(h) self.h = h end
    function f:SetText(t) rawset(self, "text", t) end
    function f:GetText() return rawget(self, "text") end
    function f:SetScale(s) self.scale = s end
    function f:GetPoint() return "TOP", nil, "TOP", 10, -20 end
    function f:SetPoint(...) rawset(self, "lastPoint", { ... }) end
    function f:SetEnabled(v) self.enabled = v and true or false end
    function f:Enable() self.enabled = true end
    function f:Disable() self.enabled = false end
    function f:IsEnabled() return self.enabled end
    function f:EnableMouse(v) rawset(self, "mouse", v) end
    function f:SetVerticalScroll(v) rawset(self, "scrollPos", v) end
    function f:Click(button)
      if self.scripts.OnClick then self.scripts.OnClick(self, button or "LeftButton") end
    end
    c.frames[#c.frames + 1] = f
    if name then _G[name] = f end
    return f
  end
  local ticker
  _G.C_Timer = { NewTicker = function(_, fn) ticker = fn end }
  c.unknownEvents = opts.unknownEvents

  local ns = {}
  for _, file in ipairs(readToc()) do
    local chunk = assert(loadfile(ADDON_DIR .. file:gsub("\\", "/")))  -- (the TOC uses Windows separators)
    chunk("VulcanRunBook", ns)
  end
  c.ns = ns
  c.eventFrame = c.frames[1]

  function c.fire(event, ...)
    c.eventFrame.scripts.OnEvent(c.eventFrame, event, ...)
  end
  -- n seconds pass, one tick each (step seconds per tick)
  function c.tick(n, step)
    for _ = 1, n or 1 do
      c.now = c.now + (step or 1)
      c.wall = c.wall + (step or 1)
      ticker()
    end
  end
  function c.slash(s) _G.SlashCmdList.VULCANRUNBOOK(s) end
  function c.printedMatch(pat, plainFind)
    for i = #c.printed, 1, -1 do
      if c.printed[i]:find(pat, 1, plainFind) then return c.printed[i] end
    end
    return nil
  end
  function c.clearPrinted() c.printed = {} end
  function c.login()
    c.fire("ADDON_LOADED", "VulcanRunBook")
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD", true, false)
    ticker()
  end
  -- Zoning: a loading screen, then PLAYER_ENTERING_WORLD.
  function c.enter(name, map, opts2)
    opts2 = opts2 or {}
    c.instance = { name = name, map = map, diff = opts2.diff or 1, kind = opts2.kind or "party",
      uiMap = opts2.uiMap or (map and (10000 + map)) }
    c.lastInstance = c.instance
    c.now = c.now + 15  -- loading screen (a long gap: not counted)
    c.wall = c.wall + 15
    c.fire("PLAYER_ENTERING_WORLD", false, false)
    ticker()
  end
  function c.leave()
    c.instance = nil
    c.now = c.now + 15
    c.wall = c.wall + 15
    c.fire("PLAYER_ENTERING_WORLD", false, false)
    ticker()
  end
  function c.party(...)
    c.group = {}
    for _, n in ipairs({ ... }) do c.group[#c.group + 1] = { name = n, dead = false, feign = false } end
    c.fire("GROUP_ROSTER_UPDATE")
  end
  function c.member(name)
    for _, m in ipairs(c.group) do if m.name == name then return m end end
    return nil
  end
  function c.item(id, name, quality, price, cached)
    c.items[id] = { name, quality, price }
    c.cached[id] = cached ~= false
  end
  function c.link(id, name, quality, oldStyle)
    if oldStyle then
      return string.format("|cff%s|Hitem:%d::::::::20:::::|h[%s]|h|r", QHEX[quality or 1], id, name)
    end
    return string.format("|cnIQ%d:|Hitem:%d::::::::20:::::|h[%s]|h|r", quality or 1, id, name)
  end
  -- Loot message. who = nil for you, else the looter's name (as chat shows it).
  function c.lootMsg(who, id, qty, oldStyle)
    local it = c.items[id]
    local link = c.link(id, it[1], it[2], oldStyle)
    local itemPart = qty and qty > 1 and (link .. "x" .. qty) or link
    local msg
    if who then
      msg = who .. " receives loot: " .. itemPart .. "."
    else
      msg = "You receive loot: " .. itemPart .. "."
    end
    c.fire("CHAT_MSG_LOOT", msg, who or c.name)
  end
  function c.encounter(id, name, success, fightSeconds)
    c.fire("ENCOUNTER_START", id, name, 1, 5)
    c.tick(fightSeconds or 30)
    c.fire("ENCOUNTER_END", id, name, 1, 5, success == false and 0 or 1)
  end
  function c.gainMoney(n) c.money = c.money + n c.fire("PLAYER_MONEY") end
  -- You die (the death event fires; Feign Death doesn't fire it).
  function c.die()
    c.dead = true
    c.fire("PLAYER_DEAD")
  end
  -- Items reach your bags; the bag event fires (scanned a second later).
  function c.toBags(id, n)
    for _, it in ipairs(c.bagSlots) do
      if it.id == id then
        it.n = it.n + (n or 1)
        c.fire("BAG_UPDATE_DELAYED")
        return
      end
    end
    c.bagSlots[#c.bagSlots + 1] = { id = id, n = n or 1 }
    c.fire("BAG_UPDATE_DELAYED")
  end
  -- Looting for real: the loot line (unless hidden) and the item in your bags.
  function c.lootReal(id, qty, hidden)
    if hidden then
      c.fire("CHAT_MSG_LOOT", SECRET, SECRET)
    else
      c.lootMsg(nil, id, qty)
    end
    c.toBags(id, qty)
  end
  function c.gainXP(n)
    c.xp = c.xp + n
    if c.xp >= c.xpMax then
      c.xp = c.xp - c.xpMax
      c.level = c.level + 1
    end
    c.fire("PLAYER_XP_UPDATE", "player")
  end
  function c.addonMsg(sender, text, prefix, channel)
    c.fire("CHAT_MSG_ADDON", prefix or "VulcanRunBook", text, channel or (c.raid and "RAID" or "PARTY"), sender)
  end
  function c.system(msg) c.fire("CHAT_MSG_SYSTEM", msg) end
  -- Logging out fires PLAYER_LOGOUT before SavedVariables are written.
  function c.saved()
    c.fire("PLAYER_LOGOUT")
    return { db = _G.VulcanRunBookDB, char = _G.VulcanRunBookCharDB, wall = c.wall, now = c.now }
  end
  -- Round-trips saved data through a serializer like the client's: tables
  -- that are shared between two SavedVariables come back as separate copies.
  function c.savedCopy(dropAccount)
    local s = c.saved()
    local function copy(v)
      if rawtype(v) ~= "table" then return v end
      local out = {}
      for k, x in pairs(v) do out[copy(k)] = copy(x) end
      return out
    end
    return { db = (not dropAccount) and copy(s.db) or nil, char = copy(s.char), wall = s.wall, now = s.now }
  end
  function c.errors()
    local out = {}
    for _, p in ipairs(c.printed) do if p:find("error in") then out[#out + 1] = p end end
    return out
  end
  function c.liveText()
    local f = _G.VulcanRunBookFrame
    local out = {}
    for _, fs in ipairs(f.fontstrings) do
      if fs.shown then out[#out + 1] = c.strip(fs.text) end
    end
    return table.concat(out, "\n")
  end
  function c.strip(t)
    return (tostring(t):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|cnIQ%d+:", ""):gsub("|r", ""))
  end
  function c.run() return c.ns.run end
  function c.history() return _G.VulcanRunBookDB.history end
  return c
end

local passed, failed = 0, 0
local currentGroup = ""
function H.group(name) currentGroup = name end
function H.check(name, cond, detail)
  if cond then
    passed = passed + 1
  else
    failed = failed + 1
    io.write("FAIL [" .. currentGroup .. "] " .. name .. (detail ~= nil and ("  [" .. tostring(detail) .. "]") or "")
      .. "\n")
  end
end
function H.eq(name, got, want)
  H.check(name, got == want, "got " .. tostring(got) .. ", want " .. tostring(want))
end
-- Prints the counts; a suite with any failure exits non-zero (so run.sh stops).
function H.summary(label)
  io.write(string.format("%s: %d passed, %d failed\n", label or "tests", passed, failed))
  if failed > 0 then os.exit(1) end
  return true
end
return H
