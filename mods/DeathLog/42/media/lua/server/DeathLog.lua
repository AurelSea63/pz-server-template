-- DeathLog: prints each player death to the server console (read by a log watcher).
-- Output: [DEATHLOG] kills=<n> hours=<n> user=<name>
local function onDeath(character)
    if character == nil then return end
    if not instanceof(character, "IsoPlayer") then return end  -- players only (ignore zombies)
    local name = character:getUsername()
    if name == nil then name = "unknown" end
    local kills = character:getZombieKills()
    local hours = math.floor(character:getHoursSurvived())
    print("[DEATHLOG] kills=" .. tostring(kills) .. " hours=" .. tostring(hours) .. " user=" .. name)
end

Events.OnCharacterDeath.Add(onDeath)
