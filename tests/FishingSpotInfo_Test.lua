-- Single-player in-game test, test environment only: pzt (PZTestHarness) installs this file
-- into the test copy of the mod (TEST_FILES in pzt.conf); its script calls
-- FishingSpotInfoTest.start() and FishingSpotInfoTest.poll().
--   1. find a shore: a water tile with land 2 tiles south-east, near one of the candidate spots
--      (teleport, scan the loaded cell); the player then stands on that land
--   2. query: fish number and multiplier match Fishing.Utils.getFishNumParams; the time-of-day
--      bonus matches Fishing.Utils.getTimeParams at every hour, and the next change is a bonus edge
--   3. a catch (FishSchoolManager:catchFish, the call Fish.lua:247 makes) creates or bumps the
--      40x40 "Fishing" area: caught +1, restock time about 5 days
--   4. vanilla restock: with the last catch stamped 5 days back, updateFishingData sets the
--      area back to 0 (checks the rule the mod reports)
--   5. bite chance and wait between tries with a rod (hook / no hook) match vanilla Bobber code
--   6. spot score formula and its colours
--   7. the box for an aimed tile (FishingSpotInfo.testAim): visible, score colour on the tile,
--      orange border of the fished area, beside the cursor; hidden again without an aim
--   9. tiles around by fishing level (0-2: none, 3-5: +4, 6-8: +8, 9-10: +12): shapes, and at
--      levels 1/4/7/10 the box colours every water tile of the step in its own score colour
--   8. (runs after 9, at level 10) only with ARGS realclick=1 (tests/tools/uitest.sh, real mouse and Ctrl via clicker.ps1):
--      hold Ctrl with the cursor aimed at the water tile (box shows for vanilla's bobber tile),
--      then at land (no box), then let go (no box)
-- Results: "[FishingSpotInfoTest]" lines in console.txt, failures also as "[PZTest] FAIL".

local function log(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
    print("[FishingSpotInfoTest] " .. table.concat(parts, " "))
end

local T = { tick = 0, phase = "idle", pass = 0, fail = 0, candidate = 0 }

local function harness() return PZTest ~= nil and PZTest.active() end

local function check(label, ok, extra)
    if ok then T.pass = T.pass + 1 else T.fail = T.fail + 1 end
    log(ok and "PASS" or "FAIL", label, extra or "")
    if not ok and harness() then PZTest.fail("FishingSpotInfoTest " .. label .. " " .. tostring(extra or "")) end
end

local function player() return getSpecificPlayer(0) end

-- river and lake spots (Fishing.RiverZones and around towns); the first one with water wins
local CANDIDATES = {
    { 6560, 5110 }, { 6400, 5060 }, { 10900, 9400 }, { 7250, 8300 }, { 11800, 6900 }, { 12600, 1100 },
}

local function isLand(sq)
    return sq ~= nil and sq:getFloor() ~= nil and not FishingSpotInfo.isWater(sq)
end

-- the shore water tile nearest the player (a land tile next to it), so the real aim has both
-- on screen; returns water, land
local function findShore()
    local p = player()
    local px, py = math.floor(p:getX()), math.floor(p:getY())
    local best, bestLand, bestD
    for dx = -40, 40 do
        for dy = -40, 40 do
            local x, y = px + dx, py + dy
            local sq = getCell():getGridSquare(x, y, 0)
            if FishingSpotInfo.isWater(sq) and not Fishing.isNoFishZone(x, y) then
                local d = dx * dx + dy * dy
                if not bestD or d < bestD then
                    -- land two tiles south-east: it is drawn below the water tile, clear of it
                    local land = getCell():getGridSquare(x + 2, y + 2, 0)
                    if isLand(land) then best, bestLand, bestD = sq, land, d end
                end
            end
        end
    end
    return best, bestLand
end

local function fullShot(name)
    -- the box is UI, so a full screenshot (the "shot" step hides the UI)
    getCore():TakeFullScreenshot("pzt_fishingspotinfo_" .. name .. "_" .. getTimestamp() .. ".png")
end

-- real mouse and keys through tests/tools/clicker.ps1 (tests/tools/uitest.sh)
local clickId = 0
local function requestClick(button, x, y)
    clickId = clickId + 1
    local w = getFileWriter("fsi_click_req.txt", true, false)
    w:write(clickId .. " " .. button .. " " .. math.floor(x) .. " " .. math.floor(y) .. " "
        .. getCore():getScreenWidth() .. " " .. getCore():getScreenHeight() .. "\n")
    w:close()
    log("click request", clickId, button, math.floor(x), math.floor(y))
    return clickId
end

-- nil until the clicker answered request id, then its answer ("ok ..." or "error ...")
local function clickDone(id)
    local r = getFileReader("fsi_click_done.txt", false)
    if not r then return nil end
    local line = r:readLine()
    r:close()
    if not line then return nil end
    local doneId, rest = line:match("^(%d+)%s+(.*)$")
    if tonumber(doneId) ~= id then return nil end
    return rest
end

-- UI pixel for the cursor so that vanilla's aim (Fishing.Utils.getAimCoords: the world point
-- at the zoomed mouse position plus 100 pixels down) lands on this tile's centre
local function aimCursorFor(sq)
    local sx, sy = ISCoordConversion.ToScreen(sq:getX() + 0.5, sq:getY() + 0.5, 0)
    local zoom = getCore():getZoom(0)
    return sx / zoom, (sy - 100) / zoom
end

-- the cursor moved by the screen distance from where vanilla aims now to this tile's centre
local function correctedCursor(sq)
    local ax, ay = Fishing.Utils.getAimCoords(player())
    local zoom = getCore():getZoom(0)
    local tx, ty = ISCoordConversion.ToScreen(sq:getX() + 0.5, sq:getY() + 0.5, 0)
    local px, py = ISCoordConversion.ToScreen(ax, ay, 0)
    return getMouseX() + (tx - px) / zoom, getMouseY() + (ty - py) / zoom
end

local function logLines(prefix, info)
    for _, line in ipairs(FishingSpotInfo.lines(info)) do log(prefix, line[1]) end
end

-- 2: time of day at hh:30 for every hour, against Fishing.Utils.getTimeParams
local function testTime()
    local gt = getGameTime()
    local saved = gt:getTimeOfDay()
    local bad = {}
    for h = 0, 23 do
        gt:setTimeOfDay(h + 0.5)
        local t = FishingSpotInfo.timeInfo()
        local vanillaBonus = Fishing.Utils.getTimeParams().coeff > 1
        local nextChange = (t.minute + t.minutesLeft) % 1440
        local edges = { [240] = true, [420] = true, [1080] = true, [1260] = true }
        if t.minute ~= h * 60 + 30 or t.bonus ~= vanillaBonus or not edges[nextChange]
                or t.minutesLeft <= 0 or t.minutesLeft > 660 then
            bad[#bad + 1] = h .. ":" .. tostring(t.bonus) .. "/" .. tostring(vanillaBonus) .. "/" .. nextChange .. "/" .. t.minutesLeft
        end
        if h == 5 or h == 12 then
            logLines("line " .. h .. ":30", FishingSpotInfo.query(T.water:getX(), T.water:getY(), player()))
        end
    end
    gt:setTimeOfDay(saved)
    check("2 time bonus = vanilla for 24 hours", #bad == 0, table.concat(bad, " "))
end

-- the rod in hand (vanilla's own handler starts its fishing manager, as on a real equip)
local function equipRod(hookType)
    local p = player()
    local rod = p:getPrimaryHandItem()
    if not (rod and rod:hasTag(ItemTag.FISHING_ROD)) then
        rod = p:getInventory():AddItem("Base.FishingRod")
        p:setPrimaryHandItem(rod)
        p:setSecondaryHandItem(rod)
        Fishing.Handler.handleFishing(p, rod)
    end
    rod:getModData().fishing_HookType = hookType
    return rod
end

local function testQuery(sq)
    local x, y = sq:getX(), sq:getY()
    equipRod("Base.FishingHook")
    local info = FishingSpotInfo.query(x, y, player())
    local params = Fishing.Utils.getFishNumParams(x, y)
    log("water", x, y, "fish", info.fish, "coeff", info.coeff, "caught", tostring(info.caught))
    check("2 query fish = vanilla", info.fish == params.value and info.coeff == params.coeff,
        info.fish .. "/" .. params.value)
    logLines("line", info)
    testTime()

    local before = info.caught or 0
    FishSchoolManager.getInstance():catchFish(x, y)
    local after = FishingSpotInfo.query(x, y, player())
    check("3 catch adds 1", after.caught == before + 1, tostring(before) .. " -> " .. tostring(after.caught))
    check("3 area is 40x40", after.zoneW == 40 and after.zoneH == 40, tostring(after.zoneW) .. "x" .. tostring(after.zoneH))
    check("3 restock about 5 days", after.minutesLeft and after.minutesLeft > 7190 and after.minutesLeft <= 7200,
        tostring(after.minutesLeft))
    check("3 fish not more than before", after.fish <= info.fish, info.fish .. " -> " .. after.fish)
    logLines("line", after)

    -- 4: stamp the last catch 5 days back; vanilla resets it on its own update
    local zone = FishingSpotInfo.getZone(x, y)
    zone:setLastActionTimestamp(FishingSpotInfo.nowMinutes() - 7201)
    FishSchoolManager.getInstance():getFishAbundance(x, y)   -- puts the area in the vanilla cache
    local stale = FishingSpotInfo.query(x, y, player())
    check("4 past 5 days shows ready", stale.caught == 0 or stale.minutesLeft <= 0, tostring(stale.minutesLeft))
    logLines("line", stale)
end

-- 5: bite chance and wait between tries, against vanilla Bobber code
local function testBite()
    local p = player()
    local x, y = T.water:getX(), T.water:getY()
    equipRod("Base.FishingHook")
    local info = FishingSpotInfo.query(x, y, p)
    local fish = Fishing.Utils.getFishNumParams(x, y).coeff
    local want = 0.8 * Fishing.Utils.getTemperatureParams(p).coeff * Fishing.Utils.getWeatherParams().coeff
        * Fishing.Utils.getTimeParams().coeff * Fishing.hook["Base.FishingHook"] * fish
    check("5 bite chance = vanilla attractFish", math.abs(info.chance - want) < 1e-9, info.chance .. "/" .. want)
    local fake = { player = p, getX = function() return x end, getY = function() return y end }
    local vanillaWait = Fishing.Bobber.getNibbleTime(fake)
    check("5 wait = vanilla getNibbleTime", info.nibbleTime == vanillaWait, info.nibbleTime .. "/" .. vanillaWait)
    check("5 near shore = vanilla", info.nearShore == Fishing.Utils.isNearShore(x, y), tostring(info.nearShore))
    logLines("line", info)
    -- every hour: the mod's wait against vanilla's (the time of day moves the buckets)
    local gt = getGameTime()
    local saved = gt:getTimeOfDay()
    local bad = {}
    for h = 0, 23 do
        gt:setTimeOfDay(h + 0.5)
        local i = FishingSpotInfo.query(x, y, p)
        local v = Fishing.Bobber.getNibbleTime(fake)
        if i.nibbleTime ~= v then bad[#bad + 1] = h .. ":" .. i.nibbleTime .. "/" .. v end
    end
    gt:setTimeOfDay(saved)
    check("5 wait = vanilla for 24 hours", #bad == 0, table.concat(bad, " "))
    equipRod(nil)
    local bare = FishingSpotInfo.query(x, y, p)
    check("5 no hook: no bites", not bare.hasHook and bare.chance == 0)
    local hasNoHookLine = false
    for _, line in ipairs(FishingSpotInfo.lines(bare)) do
        if line[1] == getText("IGUI_FishingSpotInfo_NoHook") then hasNoHookLine = true end
    end
    check("5 no hook line", hasNoHookLine)
    equipRod("Base.FishingHook")
end

-- 6: spot score and its colour
local function testScore()
    local info = FishingSpotInfo.query(T.water:getX(), T.water:getY(), player())
    local t, w, h = info.tempCoeff, info.weatherCoeff, info.timeCoeff
    local nib = function(c) return FishingSpotInfo.nibbleTime(c, t, w, h) end
    local fishNib = info.fish == 0 and 0 or info.coeff
    local want = (info.coeff / (nib(fishNib) * info.slowdown)) / (1.5 / nib(1.5))
    check("6 score formula", math.abs(info.score - want) < 1e-9, info.score .. "/" .. want)
    check("6 slowdown", info.slowdown == (info.nearShore and 2 or 1) * (info.close and 3 or 1),
        info.slowdown .. " shore " .. tostring(info.nearShore) .. " close " .. tostring(info.close) .. " dist " .. info.dist)
    log("score", info.score, "fish", info.fish, "coeff", info.coeff, "slow", info.slowdown)
    local C = FishingSpotInfo.SCORE_COLOURS
    check("6 colours by score", FishingSpotInfo.scoreColour(1) == C[1] and FishingSpotInfo.scoreColour(0.67) == C[2]
        and FishingSpotInfo.scoreColour(0.2) == C[3] and FishingSpotInfo.scoreColour(0.05) == C[4]
        and FishingSpotInfo.scoreColour(0) == C[4])
end

local function besideCursor(box)
    return box:getX() >= getMouseX() + 20 or box:getX() + box:getWidth() <= getMouseX() - 20
end

-- 7: the box for an aimed tile (FishingSpotInfo.testAim, no real aim)
local function testBox()
    local box = FishingSpotInfo.boxes[0]
    check("7 box visible", box ~= nil and box:isVisible())
    if not box or not box.info then return end
    local info = box.info
    check("7 box is for the tile", info.x == T.water:getX() and info.y == T.water:getY())
    local c = FishingSpotInfo.scoreColour(info.score)
    local tile = box.rects[1]
    check("7 tile highlight in the score colour",
        tile[1] == info.x and tile[2] == info.y and tile[5] == c.r and tile[6] == c.g and tile[7] == c.b)
    check("7 fished area border", info.caught ~= nil and info.caught > 0 and #box.rects == 5 + #box.around,
        "#" .. #box.rects .. " around " .. #box.around .. " caught " .. tostring(info.caught))
    check("7 box beside the cursor", besideCursor(box),
        box:getX() .. "," .. box:getY() .. " " .. box:getWidth() .. "x" .. box:getHeight() .. " mouse " .. getMouseX() .. "," .. getMouseY())
    for _, line in ipairs(box.lines) do log("box line", line[1]) end
end

-- 9a: tiles around by level: counts and shapes
local function testSteps()
    local want = { [0] = 0, 0, 0, 4, 4, 4, 8, 8, 8, 12, 12 }
    local bad = {}
    for level = 0, 10 do
        local offs = FishingSpotInfo.aroundOffsets(level)
        local shapeOk = true
        for _, o in ipairs(offs) do
            local m, c = math.abs(o[1]) + math.abs(o[2]), math.max(math.abs(o[1]), math.abs(o[2]))
            if m == 0 or (#offs == 4 and m ~= 1) or (#offs == 8 and c ~= 1) or (#offs == 12 and m > 2) then
                shapeOk = false
            end
        end
        if #offs ~= want[level] or not shapeOk then bad[#bad + 1] = level .. ":" .. #offs end
    end
    check("9 tiles around by level (0-2:0, 3-5:4, 6-8:8, 9-10:12)", #bad == 0, table.concat(bad, " "))
end

-- 9b: the box at this fishing level colours every water tile of its step, each by its own score
local function testAround(level)
    local box = FishingSpotInfo.boxes[0]
    if not (box and box.info) then
        check("9 level " .. level .. " box", false)
        return
    end
    local p = player()
    local cx, cy = box.info.x, box.info.y
    local water = 0
    for _, o in ipairs(FishingSpotInfo.aroundOffsets(level)) do
        if FishingSpotInfo.isWater(getCell():getGridSquare(cx + o[1], cy + o[2], 0)) then water = water + 1 end
    end
    check("9 level " .. level .. " colours the water tiles around", #box.around == water,
        #box.around .. "/" .. water .. " (step " .. #FishingSpotInfo.aroundOffsets(level) .. ")")
    local bad = {}
    for i, t in ipairs(box.around) do
        local rc = box.rects[i + 1]
        local c = FishingSpotInfo.scoreColour(FishingSpotInfo.query(t[1], t[2], p).score)
        if not (rc[1] == t[1] and rc[2] == t[2] and rc[5] == c.r and rc[6] == c.g and rc[7] == c.b
                and rc[8] == FishingSpotInfo.AROUND_ALPHA) then
            bad[#bad + 1] = t[1] .. "," .. t[2]
        end
    end
    check("9 level " .. level .. " each tile in its own score colour, lighter", #bad == 0, table.concat(bad, " "))
    local scores = {}
    for _, t in ipairs(box.around) do scores[#scores + 1] = string.format("%d,%d=%.2f", t[1] - cx, t[2] - cy, t[3]) end
    log("around level", level, table.concat(scores, " "))
end

local function setLevel(level)
    player():setPerkLevelDebug(Perks.Fishing, level)
end

local function settled(res)
    if res and not T.settle then T.settle = T.tick + 60 end
    if (T.settle and T.tick >= T.settle) or T.tick >= T.wait then
        T.settle = nil
        return true
    end
    return false
end

Events.OnRenderTick.Add(function()
    if T.phase == "idle" or T.phase == "done" then return end
    T.tick = T.tick + 1
    local pl = player()
    if pl and not (pl:isGhostMode() and pl:isZombiesDontAttack()) then FishingSpotInfoTest_protect(true) end
    local ok, err = pcall(function()
        if T.phase == "teleport" then
            T.candidate = T.candidate + 1
            local c = CANDIDATES[T.candidate]
            if not c then
                check("1 water found", false, "no water near any candidate")
                T.phase = "done"
                return
            end
            PZTest.teleport(c[1], c[2], 0)
            T.wait, T.phase = T.tick + 300, "scan"
        elseif T.phase == "scan" and T.tick >= T.wait then
            local sq, land = findShore()
            if not sq then
                log("no shore near candidate", T.candidate)
                T.phase = "teleport"
                return
            end
            check("1 shore found", true, "water " .. sq:getX() .. "," .. sq:getY() .. " land " .. land:getX() .. "," .. land:getY())
            T.water, T.land = sq, land
            PZTest.teleport(land:getX(), land:getY(), 0)
            T.wait, T.phase = T.tick + 120, "query"
        elseif T.phase == "query" and T.tick >= T.wait then
            testQuery(T.water)
            T.wait, T.phase = T.tick + 600, "reset"
        elseif T.phase == "reset" then
            local info = FishingSpotInfo.query(T.water:getX(), T.water:getY())
            if info.caught == 0 or T.tick >= T.wait then
                check("4 vanilla resets the area after 5 days", info.caught == 0,
                    "caught " .. tostring(info.caught) .. " after " .. (T.tick - T.wait + 600) .. " frames")
                testBite()
                testScore()
                -- 7: catch again so the box shows a fished area and its orange border
                FishSchoolManager.getInstance():catchFish(T.water:getX(), T.water:getY())
                FishingSpotInfo.testAim = { T.water:getX(), T.water:getY() }
                T.wait, T.phase = T.tick + 20, "box"
            end
        elseif T.phase == "box" and T.tick >= T.wait then
            testBox()
            fullShot("box")
            FishingSpotInfo.testAim = nil
            T.wait, T.phase = T.tick + 5, "box_hidden"
        elseif T.phase == "box_hidden" and T.tick >= T.wait then
            local box = FishingSpotInfo.boxes[0]
            check("7 box hidden when not aiming", box == nil or not box:isVisible())
            -- 9: more tiles around as the fishing level rises; a tile further out into the water
            -- (3 tiles north-west) so the larger shapes have water all round, else the shore tile
            testSteps()
            local deep = getCell():getGridSquare(T.water:getX() - 3, T.water:getY() - 3, 0)
            if not FishingSpotInfo.isWater(deep) then deep = T.water end
            T.levels, T.levelIndex, T.deep = { 1, 4, 7, 10 }, 1, deep
            setLevel(T.levels[1])
            FishingSpotInfo.testAim = { deep:getX(), deep:getY() }
            T.wait, T.phase = T.tick + 30, "level"
        elseif T.phase == "level" and T.tick >= T.wait then
            local level = T.levels[T.levelIndex]
            check("9 level set", player():getPerkLevel(Perks.Fishing) == level, tostring(player():getPerkLevel(Perks.Fishing)))
            testAround(level)
            fullShot("level" .. level)
            T.levelIndex = T.levelIndex + 1
            if T.levels[T.levelIndex] then
                setLevel(T.levels[T.levelIndex])
                T.wait = T.tick + 30
                return
            end
            -- the real aim below runs at level 10, so its shot shows the largest shape
            FishingSpotInfo.testAim = nil
            T.wait, T.phase = T.tick + 5, "level_done"
        elseif T.phase == "level_done" and T.tick >= T.wait then
            if PZTest.arg("realclick") ~= "1" then
                log("real aim skipped (run tests/tools/uitest.sh)")
                T.phase = "done"
                return
            end
            -- 8: real mouse and Ctrl: aim at the water tile, then at land, then let go
            local x, y = aimCursorFor(T.water)
            T.click, T.wait, T.phase = requestClick("aim", x, y), T.tick + 900, "aim_water"
        elseif T.phase == "aim_water" then
            local res = clickDone(T.click)
            if settled(res) and not T.corrected then
                -- the camera may have moved since the cursor was computed: move the cursor by
                -- the screen distance between the aimed point and the tile centre, once
                T.corrected = true
                local x, y = correctedCursor(T.water)
                log("aim correction", "aim", Fishing.Utils.getAimCoords(player()))
                T.click, T.wait = requestClick("aim", x, y), T.tick + 900
            elseif T.corrected and settled(clickDone(T.click)) then
                T.corrected = nil
                check("8 clicker aim", res ~= nil and res:sub(1, 2) == "ok", tostring(res))
                local p = player()
                local ax, ay = Fishing.Utils.getAimCoords(p)
                local tx, ty = FishingSpotInfo.aimTile(p)
                log("aim", "isAiming", tostring(p:isAiming()), "aim", tostring(ax), tostring(ay),
                    "tile", tostring(tx), tostring(ty), "mouse", getMouseX(), getMouseY())
                check("8 real Ctrl aims the rod", p:isAiming())
                check("8 aim tile is the vanilla bobber tile",
                    tx ~= nil and tx == math.floor(ax) and ty == math.floor(ay), tostring(tx) .. "," .. tostring(ty))
                local box = FishingSpotInfo.boxes[0]
                check("8 box shows while aiming at water", box ~= nil and box:isVisible())
                if box and box:isVisible() then
                    check("8 box beside the cursor", besideCursor(box), box:getX() .. " mouse " .. getMouseX())
                    for _, line in ipairs(box.lines) do log("real line", line[1]) end
                end
                fullShot("aim")
                local lx, ly = correctedCursor(T.land)
                T.click, T.wait, T.phase = requestClick("aim", lx, ly), T.tick + 900, "aim_land"
            end
        elseif T.phase == "aim_land" then
            local res = clickDone(T.click)
            if settled(res) then
                local box = FishingSpotInfo.boxes[0]
                local ax, ay = Fishing.Utils.getAimCoords(player())
                log("aim land", tostring(ax), tostring(ay), "aiming", tostring(player():isAiming()))
                check("8 no box while aiming at land", box == nil or not box:isVisible())
                T.click, T.wait, T.phase = requestClick("release", 0, 0), T.tick + 900, "release"
            end
        elseif T.phase == "release" then
            local res = clickDone(T.click)
            if settled(res) then
                local box = FishingSpotInfo.boxes[0]
                check("8 clicker release", res ~= nil and res:sub(1, 2) == "ok", tostring(res))
                check("8 box gone after Ctrl is let go", box == nil or not box:isVisible())
                T.phase = "done"
            end
        end
    end)
    if not ok then
        T.fail = T.fail + 1
        log("ERROR", T.phase, err)
        if harness() then PZTest.fail("FishingSpotInfoTest ERROR " .. tostring(err)) end
        FishingSpotInfo.testAim = nil
        -- never leave the clicker holding Ctrl
        if T.phase == "aim_water" or T.phase == "aim_land" then requestClick("release", 0, 0) end
        T.phase = "done"
    end
end)

FishingSpotInfoTest = {}

-- the test character is protected while the test runs (zombies near the shore must not kill
-- or move it), and back to normal at the end
-- (ghost mode too: zombies still went for the character with the other three alone; and it is
-- set again every frame below, since a teleport or load may clear it)
local function protect(on)
    local p = player()
    if not p then return end
    p:setGodMod(on)
    p:setInvisible(on)
    p:setZombiesDontAttack(on)
    p:setGhostMode(on)
end
FishingSpotInfoTest_protect = protect

function FishingSpotInfoTest.start()
    T = { tick = 0, phase = "teleport", pass = 0, fail = 0, candidate = 0 }
    T.origLevel = player():getPerkLevel(Perks.Fishing)
    protect(true)
    log("start", "protected", tostring(player():isGodMod()), tostring(player():isInvisible()))
end

------------------------------------------------------------------------------
-- Showcase (not a test): screenshots for the Workshop page. Run with
--   PZT_STEPS="lua FishingSpotInfoTest.showcase();lua FishingSpotInfoTest.poll()" bash tests/tools/uitest.sh
-- Looks around every candidate for a water tile whose level-10 diamond shows the most colours;
-- (fish multiplier, halved near the shore);
-- stands on land 5-12 tiles from it and really aims there (clicker), then shoots.

-- colour class (1 green .. 4 red) a water tile would roughly get with the player away from it:
-- fish multiplier / 1.5, halved near the shore (Bobber:update x2), no-fish zone red
local classCache = {}
local function tileClass(x, y)
    local key = x * 100000 + y
    local c = classCache[key]
    if c ~= nil then return c end
    c = false
    if FishingSpotInfo.isWater(getCell():getGridSquare(x, y, 0)) then
        local s = 0
        if not Fishing.isNoFishZone(x, y) then
            s = Fishing.Utils.getFishNumParams(x, y).coeff / 1.5
            if Fishing.Utils.isNearShore(x, y) then s = s / 2 end
        end
        for i, col in ipairs(FishingSpotInfo.SCORE_COLOURS) do
            if s >= col.min then c = i break end
        end
    end
    classCache[key] = c
    return c
end

-- a tile whose level-10 diamond shows the most colours (best colour first), the diamond mostly water
local function findShowcase()
    classCache = {}
    local p = player()
    local px, py = math.floor(p:getX()), math.floor(p:getY())
    local best, bestS, bestInfo
    for dx = -36, 36 do
        for dy = -36, 36 do
            local x, y = px + dx, py + dy
            local cc = tileClass(x, y)
            if cc then
                local seen, n, top = {}, 1, cc
                seen[cc] = true
                for _, o in ipairs(FishingSpotInfo.aroundOffsets(10)) do
                    local k = tileClass(x + o[1], y + o[2])
                    if k then
                        n = n + 1
                        seen[k] = true
                        if k < top then top = k end
                    end
                end
                local kinds = 0
                for _ in pairs(seen) do kinds = kinds + 1 end
                if n >= 11 then
                    local s = kinds * 10 + (5 - top) * 3 + (5 - cc)
                    if not bestS or s > bestS then best, bestS, bestInfo = { x, y }, s, kinds .. " colours, best " .. top .. ", centre " .. cc end
                end
            end
        end
    end
    if not best then return nil end
    log("showcase best here", best[1], best[2], bestInfo)
    -- land to stand on: 4-12 tiles away, south-east side preferred (drawn below the water)
    local stand, standD
    for dx = -12, 12 do
        for dy = -12, 12 do
            local sq = getCell():getGridSquare(best[1] + dx, best[2] + dy, 0)
            local d = math.sqrt(dx * dx + dy * dy)
            if isLand(sq) and d >= 4 and d <= 12 and sq:isFree(false) then
                local rank = d - (dx + dy) * 0.3
                if not standD or rank < standD then stand, standD = sq, rank end
            end
        end
    end
    if not stand then return nil end
    return getCell():getGridSquare(best[1], best[2], 0), stand, bestS
end


local S = { phase = "idle" }

-- settled() for the showcase clock
local function settledS(res)
    if res and not S.settle then S.settle = S.tick + 60 end
    if (S.settle and S.tick >= S.settle) or S.tick >= S.wait then
        S.settle = nil
        return true
    end
    return false
end

local function showcaseDone()
    S.phase = "done"
    T.phase = "done"
end

Events.OnRenderTick.Add(function()
    if S.phase == "idle" or S.phase == "done" then return end
    S.tick = S.tick + 1
    local pl = player()
    if pl and not (pl:isGhostMode() and pl:isZombiesDontAttack()) then FishingSpotInfoTest_protect(true) end
    local ok, err = pcall(function()
        if S.phase == "teleport" then
            S.candidate = S.candidate + 1
            local c = CANDIDATES[S.candidate]
            if not c then
                if S.found then
                    S.water, S.stand = S.found[1], S.found[2]
                    log("showcase pick", S.water:getX(), S.water:getY(), "stand", S.stand:getX(), S.stand:getY(), "score", S.found[3])
                    PZTest.teleport(S.stand:getX(), S.stand:getY(), 0)
                    S.wait, S.phase = S.tick + 300, "goto"
                else
                    log("showcase: no spot found")
                    showcaseDone()
                end
                return
            end
            PZTest.teleport(c[1], c[2], 0)
            S.wait, S.phase = S.tick + 300, "scan"
        elseif S.phase == "scan" and S.tick >= S.wait then
            local w, st, s = findShowcase()
            log("showcase candidate", S.candidate, w and (w:getX() .. "," .. w:getY() .. " score " .. s) or "none")
            if w and (not S.found or s > S.found[3]) then
                S.found = { w, st, s, CANDIDATES[S.candidate] }
            end
            S.phase = "teleport"
        elseif S.phase == "goto" and S.tick >= S.wait then
            -- squares are objects of the loaded cell: look them up again after the teleport
            S.water = getCell():getGridSquare(S.water:getX(), S.water:getY(), 0)
            S.stand = getCell():getGridSquare(S.stand:getX(), S.stand:getY(), 0)
            getGameTime():setTimeOfDay(13)
            player():setPerkLevelDebug(Perks.Fishing, 10)
            equipRod("Base.FishingHook")
            S.wait, S.phase = S.tick + 200, "aim"
        elseif S.phase == "aim" and S.tick >= S.wait then
            local x, y = aimCursorFor(S.water)
            S.click, S.wait, S.phase = requestClick("aim", x, y), S.tick + 900, "aim_fix"
        elseif S.phase == "aim_fix" then
            if settledS(clickDone(S.click)) then
                local x, y = correctedCursor(S.water)
                S.click, S.wait, S.phase = requestClick("aim", x, y), S.tick + 900, "shoot"
            end
        elseif S.phase == "shoot" then
            if settledS(clickDone(S.click)) then
                local box = FishingSpotInfo.boxes[0]
                local ax, ay = Fishing.Utils.getAimCoords(player())
                log("showcase aim", ax, ay, "box", tostring(box and box:isVisible()))
                if box and box.around then
                    local scores = {}
                    for _, t in ipairs(box.around) do scores[#scores + 1] = string.format("%.2f", t[3]) end
                    log("showcase centre", box.info.score, "around", table.concat(scores, " "))
                    for _, line in ipairs(box.lines) do log("showcase line", line[1]) end
                end
                fullShot("showcase")
                S.shots = (S.shots or 0) + 1
                if S.shots < 2 then
                    -- a second spot: 2 tiles toward the shore side for another mix
                    local alt = getCell():getGridSquare(S.water:getX() + 2, S.water:getY() + 2, 0)
                    if FishingSpotInfo.isWater(alt) then
                        S.water = alt
                        local x, y = correctedCursor(alt)
                        S.click, S.wait, S.phase = requestClick("aim", x, y), S.tick + 900, "shoot"
                        return
                    end
                end
                S.click, S.wait, S.phase = requestClick("release", 0, 0), S.tick + 900, "release"
            end
        elseif S.phase == "release" then
            if settledS(clickDone(S.click)) then showcaseDone() end
        end
    end)
    if not ok then
        log("showcase ERROR", S.phase, err)
        if S.phase == "aim_fix" or S.phase == "shoot" then requestClick("release", 0, 0) end
        showcaseDone()
    end
end)

function FishingSpotInfoTest.showcase()
    T = { tick = 0, phase = "showcase", pass = 0, fail = 0, candidate = 0 }
    S = { phase = "teleport", tick = 0, candidate = 0 }
    T.origLevel = player():getPerkLevel(Perks.Fishing)
    protect(true)
    log("showcase start protected", tostring(player():isGhostMode()))
end

-- Manual shots (not a test): stops the showcase, keeps the character protected and healthy for as
-- long as the client is open, Fishing level 10 and a hooked rod in hand. Insert saves a full
-- screenshot (UI included) as Zomboid/Screenshots/pzt_fishingspotinfo_manual_<time>.png.
--   PZT_STEPS="lua FishingSpotInfoTest.manual()" bash ../PZTestHarness/pzt live
local manualOn = false

Events.OnPlayerUpdate.Add(function(p)
    if not manualOn or p ~= player() then return end
    if not (p:isGhostMode() and p:isGodMod() and p:isZombiesDontAttack()) then protect(true) end
    local body = p:getBodyDamage()
    if body:IsInfected() or body:getHealth() < 90 then body:RestoreToFullHealth() end
end)

Events.OnKeyPressed.Add(function(key)
    if manualOn and key == Keyboard.KEY_INSERT then
        local name = "pzt_fishingspotinfo_manual_" .. getTimestamp() .. ".png"
        getCore():TakeFullScreenshot(name)
        log("manual shot", name)
    end
end)

-- hides the -debug command console window (zombie.ui.UIDebugConsole) for clean shots
function FishingSpotInfoTest.hideConsole()
    local c = UIManager.getDebugConsole()
    if c then c:setVisible(false) end
    log("console visible", tostring(c and c:isVisible()))
end

function FishingSpotInfoTest.manual()
    S.phase = "done"
    T = { tick = 0, phase = "idle", pass = 0, fail = 0, candidate = 0 }
    manualOn = true
    local p = player()
    protect(true)
    p:getBodyDamage():RestoreToFullHealth()
    p:setPerkLevelDebug(Perks.Fishing, 10)
    equipRod("Base.FishingHook")
    FishingSpotInfoTest.hideConsole()
    log("manual on", "dead", tostring(p:isDead()), "infected", tostring(p:getBodyDamage():IsInfected()))
end

-- keeps the harness script running until the test is done
function FishingSpotInfoTest.poll()
    if T.phase == "done" and not T.shot then
        T.shot = true
        protect(false)
        if T.origLevel then setLevel(T.origLevel) end
        fullShot("end")
        PZTest.step("wait 30")
        PZTest.step("lua FishingSpotInfoTest.poll()")
        return
    end
    if T.phase == "done" then
        PZTest.log("FishingSpotInfoTest pass " .. T.pass .. " fail " .. T.fail)
        return
    end
    PZTest.step("wait 30")
    PZTest.step("lua FishingSpotInfoTest.poll()")
end
