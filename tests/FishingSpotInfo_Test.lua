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
--   5. menu hook: adds the option on water, not on the shore land tile
--   6. window opens for the tile
--   7. ground highlight: tile + 1-tile border on the 40x40 area, green when full, orange
--      after another catch; screenshot from the area's north-west corner
--   8. only with ARGS realclick=1 (tests/tools/uitest.sh, real mouse via clicker.ps1): right-click
--      the land tile (menu, no option), right-click the water tile (menu with the option,
--      screenshot), left-click the option (window opens for that tile)
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

-- the shore water tile nearest the player (a land tile next to it), so the land menu and the
-- real clicks have both on screen; returns water, land
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
    -- the window and menus are UI, so a full screenshot (the "shot" step hides the UI)
    getCore():TakeFullScreenshot("pzt_fishingspotinfo_" .. name .. "_" .. getTimestamp() .. ".png")
end

-- real mouse clicks through tests/tools/clicker.ps1 (tests/tools/uitest.sh)
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

-- game window pixel of a tile's centre
local function tileScreen(sq)
    local sx, sy = ISCoordConversion.ToScreen(sq:getX() + 0.5, sq:getY() + 0.5, 0)
    local zoom = getCore():getZoom(0)
    return sx / zoom, sy / zoom
end

local function visibleMenu()
    local menu = getPlayerContextMenu(0)
    if menu and menu:isVisible() and menu.numOptions and menu.numOptions > 1 then return menu end
    return nil
end

local function menuNames(menu)
    local names = {}
    for i = 1, menu.numOptions - 1 do
        local o = menu.options[i]
        if o and o.name then names[#names + 1] = o.name end
    end
    return names
end

-- runs the mod's world context menu hook with a fake menu, returns the option names
-- (not triggerEvent: vanilla handlers need a real menu and fail on the fake one)
local function menuOptions(sq)
    local names = {}
    local fake = { addOption = function(self, name) names[#names + 1] = name; return {} end }
    FishingSpotInfo.onFillWorldObjectContextMenu(0, fake, { sq:getFloor() }, false)
    return names
end

local function hasOption(names)
    local want = getText("IGUI_FishingSpotInfo_Menu")
    for _, n in ipairs(names) do if n == want then return true end end
    return false
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
            for _, line in ipairs(FishingSpotInfo.lines(FishingSpotInfo.query(T.water0:getX(), T.water0:getY()))) do
                log("line", h .. ":30", line)
            end
        end
    end
    gt:setTimeOfDay(saved)
    check("2 time bonus = vanilla for 24 hours", #bad == 0, table.concat(bad, " "))
end

local function testQuery(sq)
    local x, y = sq:getX(), sq:getY()
    T.water0 = sq
    local info = FishingSpotInfo.query(x, y)
    local params = Fishing.Utils.getFishNumParams(x, y)
    log("water", x, y, "fish", info.fish, "coeff", info.coeff, "caught", tostring(info.caught))
    check("2 query fish = vanilla", info.fish == params.value and info.coeff == params.coeff,
        info.fish .. "/" .. params.value)
    for _, line in ipairs(FishingSpotInfo.lines(info)) do log("line", line) end
    testTime()

    local before = info.caught or 0
    FishSchoolManager.getInstance():catchFish(x, y)
    local after = FishingSpotInfo.query(x, y)
    check("3 catch adds 1", after.caught == before + 1, tostring(before) .. " -> " .. tostring(after.caught))
    check("3 area is 40x40", after.zoneW == 40 and after.zoneH == 40, tostring(after.zoneW) .. "x" .. tostring(after.zoneH))
    check("3 restock about 5 days", after.minutesLeft and after.minutesLeft > 7190 and after.minutesLeft <= 7200,
        tostring(after.minutesLeft))
    check("3 fish not more than before", after.fish <= info.fish, info.fish .. " -> " .. after.fish)
    for _, line in ipairs(FishingSpotInfo.lines(after)) do log("line", line) end

    -- 4: stamp the last catch 5 days back; vanilla resets it on its own update
    local zone = FishingSpotInfo.getZone(x, y)
    zone:setLastActionTimestamp(FishingSpotInfo.nowMinutes() - 7201)
    FishSchoolManager.getInstance():getFishAbundance(x, y)   -- puts the area in the vanilla cache
    local stale = FishingSpotInfo.query(x, y)
    check("4 past 5 days shows ready", stale.caught == 0 or stale.minutesLeft <= 0, tostring(stale.minutesLeft))
    for _, line in ipairs(FishingSpotInfo.lines(stale)) do log("line", line) end

    -- 5: menu on water and on land
    check("5 menu on water", hasOption(menuOptions(sq)))
    check("5 no menu on land", not hasOption(menuOptions(T.land)), T.land:getX() .. "," .. T.land:getY())

    -- 6: window
    local window = FishingSpotInfo.open(0, x, y)
    check("6 window open", window ~= nil and window:isVisible())
    T.water = sq
end

-- 7: ground highlight: the tile, then a 1-tile border on the area's edge in the state colour
local function checkRects(info, label, rgb)
    local rects = FishingSpotInfo.areaRects(info)
    local tile = rects[1]
    check("7 " .. label .. " tile highlight", tile[1] == info.x and tile[2] == info.y and tile[3] == info.x + 1)
    check("7 " .. label .. " border has 4 strips", #rects == 5, "#" .. #rects)
    if #rects ~= 5 then return end
    local x1, y1, x2, y2 = info.zoneX, info.zoneY, info.zoneX + info.zoneW, info.zoneY + info.zoneH
    local minX, minY, maxX, maxY, cells = 1e9, 1e9, -1e9, -1e9, 0
    local colourOk = true
    for i = 2, 5 do
        local r = rects[i]
        minX, minY = math.min(minX, r[1]), math.min(minY, r[2])
        maxX, maxY = math.max(maxX, r[3]), math.max(maxY, r[4])
        cells = cells + (r[3] - r[1]) * (r[4] - r[2])
        colourOk = colourOk and r[5] == rgb[1] and r[6] == rgb[2] and r[7] == rgb[3]
    end
    check("7 " .. label .. " border covers the area edge",
        minX == x1 and minY == y1 and maxX == x2 and maxY == y2 and cells == 2 * info.zoneW + 2 * info.zoneH - 4,
        minX .. "," .. minY .. "-" .. maxX .. "," .. maxY .. " cells " .. cells)
    check("7 " .. label .. " border colour", colourOk)
end

Events.OnRenderTick.Add(function()
    if T.phase == "idle" or T.phase == "done" then return end
    T.tick = T.tick + 1
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
                for _, line in ipairs(FishingSpotInfo.lines(info)) do log("line", line) end
                checkRects(info, "full", { 0.3, 1.0, 0.3 })
                -- 7: catch again so the screenshot shows a depleted (orange) area
                FishSchoolManager.getInstance():catchFish(T.water:getX(), T.water:getY())
                checkRects(FishingSpotInfo.query(T.water:getX(), T.water:getY()), "depleted", { 1.0, 0.55, 0.1 })
                -- the border is 20 tiles away, off screen: stand near its north-west corner
                local after = FishingSpotInfo.query(T.water:getX(), T.water:getY())
                log("zoom", getCore():getZoom(0), "corner", after.zoneX, after.zoneY)
                PZTest.teleport(after.zoneX + 4, after.zoneY + 4, 0)
                T.wait, T.phase = T.tick + 240, "shot"
            end
        elseif T.phase == "shot" and T.tick >= T.wait then
            fullShot("border")
            if PZTest.arg("realclick") ~= "1" then
                log("real clicks skipped (run tests/tools/uitest.sh)")
                T.phase = "done"
                return
            end
            -- 8: real mouse: right-click land (no option), right-click water (option),
            -- left-click the option (window opens for that tile)
            FishingSpotInfo.window:close()
            PZTest.teleport(T.land:getX(), T.land:getY(), 0)
            T.wait, T.phase = T.tick + 180, "rc_land"
        elseif T.phase == "rc_land" and T.tick >= T.wait then
            local x, y = tileScreen(T.land)
            T.click, T.wait, T.phase = requestClick("right", x, y), T.tick + 900, "rc_land_wait"
        elseif T.phase == "rc_land_wait" then
            local res = clickDone(T.click)
            if res or T.tick >= T.wait then
                local menu = visibleMenu()
                if not menu and res and T.tick < T.wait and not T.settle then
                    T.settle = T.tick + 60   -- give the menu a second to appear
                end
                if menu or T.tick >= T.wait or (T.settle and T.tick >= T.settle) then
                    T.settle = nil
                    check("8 clicker right-click land", res ~= nil and res:sub(1, 2) == "ok", tostring(res))
                    check("8 real menu on land opens", menu ~= nil)
                    if menu then
                        log("land menu", table.concat(menuNames(menu), " | "))
                        check("8 real menu on land has no option", not hasOption(menuNames(menu)))
                        menu:closeAll()
                    end
                    T.wait, T.phase = T.tick + 60, "rc_water"
                end
            end
        elseif T.phase == "rc_water" and T.tick >= T.wait then
            local x, y = tileScreen(T.water)
            T.click, T.wait, T.phase = requestClick("right", x, y), T.tick + 900, "rc_water_wait"
        elseif T.phase == "rc_water_wait" then
            local res = clickDone(T.click)
            if res or T.tick >= T.wait then
                local menu = visibleMenu()
                if not menu and res and T.tick < T.wait and not T.settle then T.settle = T.tick + 60 end
                if menu or T.tick >= T.wait or (T.settle and T.tick >= T.settle) then
                    T.settle = nil
                    check("8 clicker right-click water", res ~= nil and res:sub(1, 2) == "ok", tostring(res))
                    check("8 real menu on water opens", menu ~= nil)
                    if not menu then T.phase = "done"; return end
                    log("water menu", table.concat(menuNames(menu), " | "))
                    local want, index = getText("IGUI_FishingSpotInfo_Menu"), nil
                    for i = 1, menu.numOptions - 1 do
                        if menu.options[i] and menu.options[i].name == want then index = i end
                    end
                    check("8 real menu on water has the option", index ~= nil)
                    if not index then T.phase = "done"; return end
                    fullShot("menu")
                    T.menuIndex, T.menu = index, menu
                    T.wait, T.phase = T.tick + 30, "rc_option"
                end
            end
        elseif T.phase == "rc_option" and T.tick >= T.wait then
            local menu = T.menu
            local dy = (menu:getScrollHeight() > menu:getScrollAreaHeight()) and menu.scrollIndicatorHgt or 0
            local x = menu:getAbsoluteX() + menu:getWidth() / 2
            local y = menu:getAbsoluteY() + menu.padTopBottom + dy + (T.menuIndex - 0.5) * menu.itemHgt
            T.click, T.wait, T.phase = requestClick("left", x, y), T.tick + 900, "rc_option_wait"
        elseif T.phase == "rc_option_wait" then
            local res = clickDone(T.click)
            local w = FishingSpotInfo.window
            if (res and w) or T.tick >= T.wait then
                check("8 clicker left-click option", res ~= nil and res:sub(1, 2) == "ok", tostring(res))
                check("8 real option opens the window for that tile",
                    w ~= nil and w:isVisible() and w.tileX == T.water:getX() and w.tileY == T.water:getY(),
                    w and (w.tileX .. "," .. w.tileY) or "no window")
                check("8 menu closed after the click", visibleMenu() == nil)
                T.phase = "done"
            end
        end
    end)
    if not ok then
        T.fail = T.fail + 1
        log("ERROR", T.phase, err)
        if harness() then PZTest.fail("FishingSpotInfoTest ERROR " .. tostring(err)) end
        T.phase = "done"
    end
end)

FishingSpotInfoTest = {}

function FishingSpotInfoTest.start()
    T.phase = "teleport"
    log("start")
end

-- keeps the harness script running until the test is done
function FishingSpotInfoTest.poll()
    if T.phase == "done" and not T.shot then
        T.shot = true
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
