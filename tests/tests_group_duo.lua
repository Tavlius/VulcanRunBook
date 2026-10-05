-- Two clients: Tavlius and Mirel, Battle.net friends, in a group with two
-- players who don't run RunBook. Neither sets a partner by hand.
package.path = "./?.lua;" .. package.path
dofile("duo_common.lua")
local passed, failed, group = 0, 0, "?"
local function Group(g) group = g end
local function check(name, ok, detail)
  if ok then passed = passed + 1 else
    failed = failed + 1
    io.write("FAIL [" .. group .. "] " .. name .. (detail ~= nil and ("  [" .. tostring(detail) .. "]") or "") .. "\n")
  end
end

Group("friends in a 4-player group pair up on their own, both ways")
do
  local A = D.boot("Tavlius")
  local B = D.boot("Mirel")
  D.on(A, function(c) c.party("Mirel", "Pug1", "Pug2") c.bnet.Mirel = "Mirel#1111" end)
  D.on(B, function(c) c.party("Tavlius", "Pug1", "Pug2") c.bnet.Tavlius = "Tavlius#2222" end)
  for _, c in ipairs({ A, B }) do D.on(c, function(x) x.enter("Deadmines", 36) end) end
  D.tick(A, B, 60)
  D.on(B, function(c) c.gainMoney(4000) end)
  D.on(A, function(c) c.gainMoney(1000) end)
  D.tick(A, B, 40)
  D.use(A)
  check("Tavlius's partner", A.ns.DB.partner == "Mirel", A.ns.DB.partner)
  check("Tavlius keeps Mirel's tag", A.ns.DB.partnerTag == "Mirel#1111", A.ns.DB.partnerTag)
  check("Mirel's gold as a partner's", A.ns.run.partners.Mirel and A.ns.run.partners.Mirel.coin == 4000,
    A.ns.run.partners.Mirel and A.ns.run.partners.Mirel.coin)
  check("Together", A.liveText():find("Together: 50 silver", 1, true) ~= nil, A.liveText())
  check("no group line (only the two of you run it)", not A.liveText():find("Group (", 1, true))
  D.use(B)
  check("Mirel's partner", B.ns.DB.partner == "Tavlius", B.ns.DB.partner)
  check("Tavlius's gold on Mirel's side", B.ns.run.partners.Tavlius and B.ns.run.partners.Tavlius.coin == 1000)
  for _, c in ipairs({ A, B }) do D.use(c) check(c.name .. ": no errors", #c.errors() == 0, c.errors()[1]) end
end

io.write(string.format("tests_group_duo.lua: %d passed, %d failed\n", passed, failed))
os.exit(failed == 0 and 0 or 1)
