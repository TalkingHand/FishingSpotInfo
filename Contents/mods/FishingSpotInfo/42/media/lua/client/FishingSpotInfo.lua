-- Fishing Spot Info
-- Hold a fishing rod and aim (the aim key, Ctrl by default): the tile the bobber is aimed at
-- is coloured by how well fish bite there (with more water tiles around it, lighter, as the
-- fishing level rises: AREA_STEPS), and a box right of the mouse cursor shows, live:
--   - the fish number there and its bite multiplier (Fishing.Utils.getFishNumParams)
--   - the bite chance per try now (Bobber:attractFish: 0.8 x temperature x weather x time of
--     day x hook x fish number) and its factors
--   - slower tries near the shore (x2) or within 3 tiles of the player (x3) (Bobber:update)
--   - how many fish were caught in the 40x40 fishing area around it, and when it restocks
--   - the time-of-day bonus (x1.2 from 04:00 to 06:59 and 18:00 to 20:59) and when it changes
--
-- How vanilla depletes and recovers (zombie.iso.FishSchoolManager, 42.21):
--   - The first catch registers a 40x40 metagrid zone of type "Fishing"
--     centred on the bobber. Its name is the number of fish caught in it;
--     every catch inside adds 1 and stamps LastActionTimestamp (game minutes).
--   - Each fish point counts rand*40*FishAbundance/5 minus that number.
--   - FishSchoolManager.updateFishingData sets the name back to "0" once
--     7200 game minutes (5 days) passed since the last catch. It only looks at
--     zones in its cache, which is cleared every day and refilled when fish
--     are counted nearby, so a recovered area may show the old count until
--     someone fishes there again.
-- Read only: the mod never changes fishing.

FishingSpotInfo = FishingSpotInfo or {}

-- FishSchoolManager.updateFishingData: getLastActionTimestamp() + 7200
FishingSpotInfo.RESET_MINUTES = 7200

-- Fishing.Utils.getTimeParams: x1.2 when the hour is 4-6 or 18-20; as {start, end} in
-- minutes of the day, end exclusive
FishingSpotInfo.BONUS_TIMES = { { 4 * 60, 7 * 60 }, { 18 * 60, 21 * 60 } }

-- Fishing.Utils.isAccessibleAimDist: casts only below this distance
FishingSpotInfo.MAX_CAST_DIST = 16

-- Bobber:update: the wait between tries is doubled near the shore (Fishing.Utils.isNearShore)
-- and tripled when the bobber is closer than 3 tiles to the player
FishingSpotInfo.SHORE_SLOWDOWN = 2
FishingSpotInfo.CLOSE_DIST = 3
FishingSpotInfo.CLOSE_SLOWDOWN = 3

-- Tile colours by spot score (bites per minute here / at the best spot under the same weather
-- and time; 1 = best). First row whose min the score reaches.
FishingSpotInfo.SCORE_COLOURS = {
    { min = 0.9, r = 0.2, g = 1.0, b = 0.3 },    -- best: many fish, away from the shore
    { min = 0.5, r = 0.75, g = 1.0, b = 0.2 },   -- good
    { min = 0.15, r = 1.0, g = 0.6, b = 0.1 },   -- poor
    { min = -1, r = 1.0, g = 0.2, b = 0.2 },     -- bad: almost no fish
}

-- Water tiles around the aimed one that are coloured too, by fishing level: the first row whose
-- minLevel the player reaches. 1 tile, +4 (cross), +8 (3x3), +12 (diamond of 2 tiles).
-- A reward for the skill, not the bobber's scatter (that shrinks with the level).
local function ring(maxDist, square)
    local offsets = {}
    for dy = -maxDist, maxDist do
        for dx = -maxDist, maxDist do
            local d = square and math.max(math.abs(dx), math.abs(dy)) or (math.abs(dx) + math.abs(dy))
            if d > 0 and d <= maxDist then table.insert(offsets, { dx, dy }) end
        end
    end
    return offsets
end
FishingSpotInfo.AREA_STEPS = {
    { minLevel = 9, offsets = ring(2, false) },   -- 12 around
    { minLevel = 6, offsets = ring(1, true) },    -- 8 around
    { minLevel = 3, offsets = ring(1, false) },   -- 4 around
    { minLevel = 0, offsets = {} },               -- the aimed tile only
}

-- alpha of the aimed tile and of the tiles around it (lighter, so the aimed one stands out)
FishingSpotInfo.AIM_ALPHA = 0.7
FishingSpotInfo.AROUND_ALPHA = 0.35

function FishingSpotInfo.aroundOffsets(level)
    for _, step in ipairs(FishingSpotInfo.AREA_STEPS) do
        if level >= step.minLevel then return step.offsets end
    end
    return {}
end

-- Same clock as FishSchoolManager.getCurrentGameTimeInMinutes
function FishingSpotInfo.nowMinutes()
    return math.floor(getGameTime():getCalender():getTimeInMillis() / 60000)
end

function FishingSpotInfo.getZone(x, y)
    local zones = getWorld():getMetaGrid():getZonesAt(x, y, 0)
    if not zones then return nil end
    for i = 0, zones:size() - 1 do
        local zone = zones:get(i)
        if zone and zone:getType() == "Fishing" then
            return zone
        end
    end
    return nil
end

function FishingSpotInfo.isWater(square)
    local floor = square and square:getFloor()
    return floor ~= nil and floor:hasProperty(IsoFlagType.water)
end

-- Time of day: the vanilla multiplier now, and minutes until the bonus starts or ends
function FishingSpotInfo.timeInfo()
    local params = Fishing.Utils.getTimeParams()
    local minute = math.floor(getGameTime():getTimeOfDay() * 60) % 1440
    local info = { minute = minute, coeff = params.coeff, bonus = false }
    for _, range in ipairs(FishingSpotInfo.BONUS_TIMES) do
        if minute >= range[1] and minute < range[2] then
            info.bonus = true
            info.minutesLeft = range[2] - minute
        end
    end
    if not info.bonus then
        for _, range in ipairs(FishingSpotInfo.BONUS_TIMES) do
            -- Kahlua's % keeps the sign of the left side
            local wait = range[1] - minute
            if wait < 0 then wait = wait + 1440 end
            if not info.minutesLeft or wait < info.minutesLeft then info.minutesLeft = wait end
        end
    end
    return info
end

-- Bobber:getNibbleTime with the factors given: the wait before the next try (game ticks)
function FishingSpotInfo.nibbleTime(fishNibbleCoeff, temperatureCoeff, weatherCoeff, timeCoeff)
    local nibbleChance = 1 * fishNibbleCoeff * temperatureCoeff * weatherCoeff * timeCoeff * 100
    if nibbleChance == 0 then return 2000
    elseif nibbleChance < 40 then return 1500
    elseif nibbleChance < 65 then return 1000
    elseif nibbleChance < 80 then return 650
    end
    return 500
end

-- Bobber:getNibbleTime counts no fish as 0 (attractFish uses 0.1)
local function nibbleFishCoeff(fish, coeff)
    if fish == 0 then return 0 end
    return coeff
end

-- Everything shown for one tile, as numbers (tests read this too). player may be nil (no
-- bite chance then).
function FishingSpotInfo.query(x, y, player)
    local params = Fishing.Utils.getFishNumParams(x, y)
    local info = { x = x, y = y, fish = params.value, coeff = params.coeff, time = FishingSpotInfo.timeInfo() }
    local zone = FishingSpotInfo.getZone(x, y)
    if zone then
        info.caught = tonumber(zone:getName()) or 0
        info.zoneX, info.zoneY = zone:getX(), zone:getY()
        info.zoneW, info.zoneH = zone:getWidth(), zone:getHeight()
        info.minutesLeft = zone:getLastActionTimestamp() + FishingSpotInfo.RESET_MINUTES - FishingSpotInfo.nowMinutes()
    end
    if player then
        FishingSpotInfo.addBite(info, player)
    end
    return info
end

-- Bite chance per try (Bobber:attractFish), the wait between tries and the spot score
function FishingSpotInfo.addBite(info, player)
    local temp = Fishing.Utils.getTemperatureParams(player).coeff
    local weather = Fishing.Utils.getWeatherParams().coeff
    local time = Fishing.Utils.getTimeParams().coeff
    local rod = player:getPrimaryHandItem()
    local hookType = rod and rod:getModData().fishing_HookType
    local hook = Fishing.Utils.getHookParams(hookType).coeff
    info.tempCoeff, info.weatherCoeff, info.timeCoeff, info.hookCoeff = temp, weather, time, hook
    info.hasHook = hook > 0
    info.chance = 0.8 * temp * weather * time * hook * info.coeff

    info.nearShore = Fishing.Utils.isNearShore(info.x, info.y)
    info.dist = IsoUtils.DistanceTo(player:getX(), player:getY(), info.x + 0.5, info.y + 0.5)
    info.close = info.dist < FishingSpotInfo.CLOSE_DIST
    info.inRange = info.dist < FishingSpotInfo.MAX_CAST_DIST
    info.noFishZone = Fishing.isNoFishZone(info.x, info.y)
    local slow = 1
    if info.nearShore then slow = slow * FishingSpotInfo.SHORE_SLOWDOWN end
    if info.close then slow = slow * FishingSpotInfo.CLOSE_SLOWDOWN end
    info.slowdown = slow
    info.nibbleTime = FishingSpotInfo.nibbleTime(nibbleFishCoeff(info.fish, info.coeff), temp, weather, time)

    -- bites per tick, without the hook (same everywhere): chance / wait. The best spot now
    -- has x1.5 fish, away from the shore and the player.
    local rate = (temp * weather * time * info.coeff) / (info.nibbleTime * slow)
    local best = (temp * weather * time * 1.5) / FishingSpotInfo.nibbleTime(1.5, temp, weather, time)
    info.score = rate / best
    if info.noFishZone then info.score = 0 end
    return info
end

function FishingSpotInfo.scoreColour(score)
    for _, c in ipairs(FishingSpotInfo.SCORE_COLOURS) do
        if score >= c.min then return c end
    end
    return FishingSpotInfo.SCORE_COLOURS[#FishingSpotInfo.SCORE_COLOURS]
end

local function formatMinutes(minutes)
    local days = math.floor(minutes / 1440)
    local hours = math.floor((minutes % 1440) / 60)
    local mins = minutes % 60
    if days > 0 then
        return getText("IGUI_FishingSpotInfo_DaysHours", days, hours)
    end
    return getText("IGUI_FishingSpotInfo_HoursMinutes", hours, mins)
end

-- as a "58%" string: a literal % in a translation makes getText garble the placeholders
-- ("%1%" came out as "58$s%"), so the sign comes with the argument
local function percent(v)
    return tostring(math.floor(v * 100 + 0.5)) .. "%"
end

local WHITE = { 1, 1, 1 }
local GREY = { 0.75, 0.75, 0.75 }
local WARN = { 1, 0.6, 0.3 }

-- Lines for the box, as { text, {r, g, b} }
function FishingSpotInfo.lines(info)
    local lines = {}
    local function add(text, rgb) table.insert(lines, { text, rgb or WHITE }) end
    if info.noFishZone then
        add(getText("IGUI_FishingSpotInfo_NoFishZone"), WARN)
        return lines
    end
    if not info.inRange then
        add(getText("IGUI_FishingSpotInfo_TooFar", FishingSpotInfo.MAX_CAST_DIST), WARN)
    end
    local c = FishingSpotInfo.scoreColour(info.score)
    add(getText("IGUI_FishingSpotInfo_Score", percent(info.score), info.fish, info.coeff), { c.r, c.g, c.b })
    if info.hasHook then
        add(getText("IGUI_FishingSpotInfo_Chance", percent(info.chance)))
    else
        add(getText("IGUI_FishingSpotInfo_NoHook"), WARN)
    end
    add(getText("IGUI_FishingSpotInfo_Factors", info.coeff, info.timeCoeff, info.weatherCoeff, info.tempCoeff, info.hookCoeff), GREY)
    if info.close then
        add(getText("IGUI_FishingSpotInfo_Close", FishingSpotInfo.CLOSE_DIST, FishingSpotInfo.CLOSE_SLOWDOWN * (info.nearShore and FishingSpotInfo.SHORE_SLOWDOWN or 1)), WARN)
    elseif info.nearShore then
        add(getText("IGUI_FishingSpotInfo_Shore", FishingSpotInfo.SHORE_SLOWDOWN), WARN)
    end
    if not info.caught then
        add(getText("IGUI_FishingSpotInfo_NoArea"), GREY)
    elseif info.caught == 0 then
        add(getText("IGUI_FishingSpotInfo_Full"), GREY)
    elseif info.minutesLeft > 0 then
        add(getText("IGUI_FishingSpotInfo_Caught", info.caught, formatMinutes(info.minutesLeft)), GREY)
    else
        add(getText("IGUI_FishingSpotInfo_CaughtReady", info.caught), GREY)
    end
    local time = info.time
    if time.bonus then
        add(getText("IGUI_FishingSpotInfo_TimeBonus", time.coeff, formatMinutes(time.minutesLeft)), GREY)
    else
        add(getText("IGUI_FishingSpotInfo_TimeNormal", formatMinutes(time.minutesLeft)), GREY)
    end
    return lines
end

-- The water tiles around (x, y) coloured at this fishing level, as {x, y, score}; land is
-- left out (no-fish water scores 0, red)
function FishingSpotInfo.aroundTiles(x, y, player)
    local level = player and player:getPerkLevel(Perks.Fishing) or 0
    local tiles = {}
    for _, o in ipairs(FishingSpotInfo.aroundOffsets(level)) do
        local tx, ty = x + o[1], y + o[2]
        if FishingSpotInfo.isWater(getCell():getGridSquare(tx, ty, 0)) then
            local info = FishingSpotInfo.query(tx, ty, player)
            table.insert(tiles, { tx, ty, info.score or 0 })
        end
    end
    return tiles
end

-- Ground highlights, as {x1, y1, x2, y2, r, g, b, a} (x2/y2 exclusive, like
-- addAreaHighlightForPlayer): the aimed tile in its score colour (first), the tiles around it
-- (aroundTiles) lighter in theirs, and the 1-tile border of a fished (depleted) area in orange
function FishingSpotInfo.areaRects(info, around)
    local c = FishingSpotInfo.scoreColour(info.score or 0)
    local rects = { { info.x, info.y, info.x + 1, info.y + 1, c.r, c.g, c.b, FishingSpotInfo.AIM_ALPHA } }
    for _, t in ipairs(around or {}) do
        local tc = FishingSpotInfo.scoreColour(t[3])
        table.insert(rects, { t[1], t[2], t[1] + 1, t[2] + 1, tc.r, tc.g, tc.b, FishingSpotInfo.AROUND_ALPHA })
    end
    if info.caught and info.caught > 0 then
        local r, g, b = 1.0, 0.55, 0.1
        local x1, y1 = info.zoneX, info.zoneY
        local x2, y2 = x1 + info.zoneW, y1 + info.zoneH
        table.insert(rects, { x1, y1, x2, y1 + 1, r, g, b, 0.35 })
        table.insert(rects, { x1, y2 - 1, x2, y2, r, g, b, 0.35 })
        table.insert(rects, { x1, y1 + 1, x1 + 1, y2 - 1, r, g, b, 0.35 })
        table.insert(rects, { x2 - 1, y1 + 1, x2, y2 - 1, r, g, b, 0.35 })
    end
    return rects
end

------------------------------------------------------------------------------
-- When to show: rod in hand, aiming, not yet cast

local function holdsRod(player)
    local item = player:getPrimaryHandItem()
    return item ~= nil and item:hasTag(ItemTag.FISHING_ROD)
end

-- the vanilla fishing manager is in None or Idle (aiming), not casting or reeling
local function notCast(player)
    local index = isMultiplayer() and player:getUsername() or player:getPlayerNum()
    local manager = Fishing.ManagerInstances and Fishing.ManagerInstances[index]
    if not manager or not manager.state or not manager.states then return true end
    return manager.state == manager.states["None"] or manager.state == manager.states["Idle"]
end

-- the tile the bobber is aimed at (Fishing.Utils.getAimCoords, the point FishingRod:cast uses),
-- or nil when the box should not show
function FishingSpotInfo.aimTile(player)
    if not player or player:isDead() or not holdsRod(player) or not player:isAiming() then return nil end
    if not notCast(player) then return nil end
    local x, y = Fishing.Utils.getAimCoords(player)
    if not x then return nil end
    x, y = math.floor(x), math.floor(y)
    if not FishingSpotInfo.isWater(getCell():getGridSquare(x, y, 0)) then return nil end
    return x, y
end

------------------------------------------------------------------------------
-- Box next to the cursor

FishingSpotInfoBox = ISUIElement:derive("FishingSpotInfoBox")

local FONT = UIFont.Small
local FONT_HGT = getTextManager():getFontHeight(FONT)
local PAD = 6
local CURSOR_GAP = 24
local REFRESH_TICKS = 15

function FishingSpotInfoBox:new(playerNum)
    local o = ISUIElement.new(self, 0, 0, 10, 10)
    o.playerNum = playerNum
    o.anchorLeft, o.anchorTop = true, true
    return o
end

-- the box never sits under the cursor, so it does not take clicks; say so anyway
function FishingSpotInfoBox:onMouseDown() return false end
function FishingSpotInfoBox:onMouseUp() return false end

function FishingSpotInfoBox:setTile(x, y)
    local player = getSpecificPlayer(self.playerNum)
    if x ~= self.tileX or y ~= self.tileY or not self.info or (self.age or 0) >= REFRESH_TICKS then
        self.tileX, self.tileY = x, y
        self.info = FishingSpotInfo.query(x, y, player)
        self.lines = FishingSpotInfo.lines(self.info)
        self.around = FishingSpotInfo.aroundTiles(x, y, player)
        self.rects = FishingSpotInfo.areaRects(self.info, self.around)
        self.age = 0
        local w = 0
        for _, line in ipairs(self.lines) do
            w = math.max(w, getTextManager():MeasureStringX(FONT, line[1]))
        end
        self:setWidth(w + PAD * 2)
        self:setHeight(#self.lines * (FONT_HGT + 1) + PAD * 2 - 1)
    end
    self.age = self.age + 1
    self:place(player)
end

-- right of the mouse cursor, or of the aimed tile on a gamepad; flipped to stay on screen
function FishingSpotInfoBox:place(player)
    local ax, ay
    if player:getJoypadBind() == -1 then
        ax, ay = getMouseX(), getMouseY()
    else
        ax = isoToScreenX(self.playerNum, self.tileX + 0.5, self.tileY + 0.5, 0)
        ay = isoToScreenY(self.playerNum, self.tileX + 0.5, self.tileY + 0.5, 0)
    end
    local left, top = getPlayerScreenLeft(self.playerNum), getPlayerScreenTop(self.playerNum)
    local right = left + getPlayerScreenWidth(self.playerNum)
    local bottom = top + getPlayerScreenHeight(self.playerNum)
    local x = ax + CURSOR_GAP
    if x + self.width > right then x = ax - CURSOR_GAP - self.width end
    local y = ay - self.height / 2
    y = math.max(top, math.min(y, bottom - self.height))
    self:setX(x)
    self:setY(y)
end

function FishingSpotInfoBox:render()
    if not self.lines then return end
    for _, rc in ipairs(self.rects) do
        addAreaHighlightForPlayer(self.playerNum, rc[1], rc[2], rc[3], rc[4], 0, rc[5], rc[6], rc[7], rc[8])
    end
    self:drawRect(0, 0, self.width, self.height, 0.75, 0, 0, 0)
    self:drawRectBorder(0, 0, self.width, self.height, 0.8, 0.4, 0.4, 0.4)
    local y = PAD
    for _, line in ipairs(self.lines) do
        local rgb = line[2]
        self:drawText(line[1], PAD, y, rgb[1], rgb[2], rgb[3], 1, FONT)
        y = y + FONT_HGT + 1
    end
end

FishingSpotInfo.boxes = FishingSpotInfo.boxes or {}

function FishingSpotInfo.getBox(playerNum)
    local box = FishingSpotInfo.boxes[playerNum]
    if not box then
        box = FishingSpotInfoBox:new(playerNum)
        box:initialise()
        box:addToUIManager()
        box:setVisible(false)
        FishingSpotInfo.boxes[playerNum] = box
    end
    return box
end

-- Tests set this to {x, y} to show the box for a tile without a real aim
FishingSpotInfo.testAim = nil

function FishingSpotInfo.update()
    if not (Fishing and Fishing.Utils) then return end
    for playerNum = 0, getNumActivePlayers() - 1 do
        local player = getSpecificPlayer(playerNum)
        local x, y
        if FishingSpotInfo.testAim and playerNum == 0 then
            x, y = FishingSpotInfo.testAim[1], FishingSpotInfo.testAim[2]
        elseif player then
            x, y = FishingSpotInfo.aimTile(player)
        end
        local box = FishingSpotInfo.boxes[playerNum]
        if x then
            box = FishingSpotInfo.getBox(playerNum)
            box:setTile(x, y)
            if not box:isVisible() then box:setVisible(true) end
        elseif box and box:isVisible() then
            box:setVisible(false)
            box.info, box.lines = nil, nil
        end
    end
end

Events.OnPreUIDraw.Add(FishingSpotInfo.update)
