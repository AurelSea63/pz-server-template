-- DeathLog: prints player death info to the server console (read by the Discord watcher).
-- Username is put LAST so names containing spaces are parsed correctly.
local function onPlayerDeath(player)
    if player == nil then return end
    local name = player:getUsername()
    if name == nil then name = "unknown" end
    local kills = player:getZombieKills()
    local hours = math.floor(player:getHoursSurvived())
    print("[DEATHLOG] kills=" .. tostring(kills) .. " hours=" .. tostring(hours) .. " user=" .. name)
end

Events.OnPlayerDeath.Add(onPlayerDeath)
