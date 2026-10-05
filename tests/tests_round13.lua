-- RunBook tests for the audit round 13 fixes.
package.path = "./?.lua;" .. package.path
local H = require("harness")
local check, eq = H.check, H.eq

local function fresh(opts)
  local c = H.boot(opts)
  c.login()
  return c
end

local function noErrors(...)
  local all = {}
  for _, c in ipairs({ ... }) do for _, e in ipairs(c.errors()) do all[#all + 1] = e end end
  check("no errors", #all == 0, table.concat(all, "; "))
end

local function anyPrinted(c, text)
  for _, p in ipairs(c.printed) do
    if c.strip(p):find(text, 1, true) then return true end
  end
  return false
end

local function names(run)
  local t = {}
  for _, b in ipairs(run.bosses) do t[#t + 1] = b.name end
  return table.concat(t, ",")
end

local function duo(c)
  c.party("Mirel")
  c.slash("partner Mirel")
end

---------------------------------------------------------------------------
H.group("your partner finds the reset after you came back in and stepped out again")
do
  local c = fresh()
  duo(c)
  c.enter("Deadmines", 36)
  local old = c.run()
  c.tick(60)
  c.encounter(644, "Rhahk'Zor")
  c.tick(30)
  c.leave()
  c.tick(60)
  c.enter("Deadmines", 36)                    -- (the new copy; nobody saw the reset)
  local back = c.ns.ServerTime()
  c.gainMoney(500)
  c.tick(30)
  c.leave()                                   -- out again
  c.tick(30)
  c.addonMsg("Mirel", string.format("B3|beef01|36|Deadmines||%d|k.7|644|Rhahk'Zor", back - 5))
  local new = c.run()
  check("split", new ~= old and old.ended)
  eq("your coin from the new copy moved", new.coin, 500)
  check("still outside", not c.ns.inside)
  eq("his kill", names(new), "Rhahk'Zor")
  noErrors(c)
end

H.group("a reopened run and a partner run that began while it was ended")
do
  local c = fresh()
  duo(c)
  c.enter("Deadmines", 36)
  local run = c.run()
  c.tick(100)
  c.slash("end")
  c.tick(20)
  local p = c.ns.ServerTime()
  c.addonMsg("Mirel", string.format("S3|beef01|36|Deadmines||%d|0|0|0|0|0|0", p))
  c.tick(20)
  c.addonMsg("Mirel", string.format("S3|beef01|36|Deadmines||%d|20|20000|0|0|0|0", p))
  c.slash("start")
  c.tick(20)
  c.addonMsg("Mirel", string.format("S3|beef01|36|Deadmines||%d|40|20500|0|0|0|0", p))
  eq("only since the reopen", run.partners.Mirel and run.partners.Mirel.coin, 500)
  c.slash("note #" .. run.id .. " reopened fine")
  eq("note #id reaches the reopened run", #run.notes, 1)
  noErrors(c)
end

---------------------------------------------------------------------------
H.group("partner names with accents, any case")
do
  local c = fresh()
  c.party("Élan")
  c.slash("partner élan")
  c.enter("Deadmines", 36)
  c.addonMsg("Élan", string.format("S3|beef01|36|Deadmines||%d|10|300|0|0|0|0", c.run().serverStart))
  eq("synced", c.run().partners["Élan"] and c.run().partners["Élan"].coin, 300)
  check("same name", c.ns.SameName("Élan", "élan") and not c.ns.SameName("Élan", "Elan"))
  noErrors(c)
end

H.group("mark key messages")
do
  local c = fresh()
  duo(c)
  c.enter("Deadmines", 36)
  local run = c.run()
  c.tick(60)
  c.encounter(644, "Rhahk'Zor")
  c.tick(3)
  _G.VulcanRunBook_MarkBoss()
  check("no 'pressed twice'", not anyPrinted(c, "pressed twice"))
  check("plain note", anyPrinted(c, "Rhahk'Zor was just recorded."))
  c.tick(60)
  c.addonMsg("Mirel", string.format("B3|beef01|36|Deadmines||%d|k.3|0|", run.serverStart))
  c.clearPrinted()
  c.tick(2)
  _G.VulcanRunBook_MarkBoss()
  eq("one line for the pair (his)", #c.printed, 0)
  noErrors(c)
end

H.group("/runbook final for another dungeon")
do
  local c = fresh()
  c.enter("Molten Core", 409, { kind = "raid" })
  c.encounter(1, "Lucifron") c.encounter(2, "Magmadar")
  c.leave()
  c.system("Molten Core has been reset.")
  c.tick(5)
  c.enter("Deadmines", 36)
  c.encounter(644, "Rhahk'Zor")
  c.leave()
  c.system("Deadmines has been reset.")
  c.tick(5)
  c.slash("final magmadar")
  check("set for Molten Core", anyPrinted(c, "Final boss for Molten Core is now Magmadar."))
  noErrors(c)
end

H.group("raid drops: you two's in the details and the export")
do
  local c = fresh()
  c.party("Mirel", "A", "B", "C", "D", "E", "F", "G", "H", "I")
  c.raid = true
  c.slash("partner Mirel")
  c.enter("Molten Core", 409, { kind = "raid" })
  c.item(3001, "Raider Epic", 4, 1000)
  c.item(3002, "Duo Epic", 4, 1000)
  c.tick(70)
  c.lootMsg("A", 3001)
  c.lootMsg("Mirel", 3002)
  c.leave()
  c.system("Molten Core has been reset.")
  c.tick(5)
  local run = c.history()[1]
  local detail = c.strip(table.concat(c.ns.RunDetailLines(run), "\n"))
  check("details: duo only", detail:find("Duo Epic", 1, true) ~= nil and not detail:find("Raider Epic", 1, true),
    detail)
  local csv = table.concat(c.ns.ExportLines(), "\n")
  check("csv: duo only", csv:find("Duo Epic", 1, true) ~= nil and not csv:find("Raider Epic", 1, true))
  noErrors(c)
end

H.summary("tests_round13.lua")
