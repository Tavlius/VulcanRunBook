function P(...) local t={} for i=1,select("#",...) do t[#t+1]=tostring(select(i,...)) end io.write(table.concat(t," "),"\n") end
D = dofile("duo.lua")
function names(r) local t={} for _,b in ipairs(r.bosses) do t[#t+1]=b.name end return table.concat(t,",") end
function pinfo(r) local t={} for n,x in pairs(r.partners) do t[#t+1]=string.format("%s=c%d/xp%d/el%d%s",n,x.coin,x.xp or 0,x.elapsed or 0,x.stale and "(stale)" or "") end return table.concat(t," ") end
function dump(c, label)
  D.use(c)
  P("== " .. c.name .. (label and (" " .. label) or ""))
  local runs = {}
  if c.ns.run then runs[#runs+1] = c.ns.run end
  for _, r in ipairs(_G.VulcanRunBookDB.history) do runs[#runs+1] = r end
  for _, r in ipairs(runs) do
    P(string.format("  #%s %s start=%d el=%d coin=%d xp=%d end=%s bosses=[%s] partners: %s", tostring(r.id), r.label, r.serverStart, r.elapsed, r.coin, r.xp, tostring(r.endReason), names(r), pinfo(r)))
  end
  local e = c.errors() if #e > 0 then P("  ERRORS: " .. table.concat(e, "; ")) end
end
function duo()
  local A = D.boot("Tavlius")
  local B = D.boot("Mirel")
  D.on(A, function(c) c.party("Mirel") c.slash("partner Mirel") end)
  D.on(B, function(c) c.party("Tavlius") c.slash("partner Tavlius") end)
  return A, B
end
