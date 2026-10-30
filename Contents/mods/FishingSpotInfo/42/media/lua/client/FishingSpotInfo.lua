-- Fishing Spot Info
-- Right-click a water tile -> "Fishing spot info" opens a small window that
-- shows, for that tile and live:
--   - the fish number vanilla uses for the bite chance, and its multiplier
--     (Fishing.Utils.getFishNumParams, shared/Fishing/FishingUtils.lua:255)
--   - how many fish were caught in the fishing area around it
--   - when that area recovers
--   - the time-of-day bite multiplier now, and when it changes next
--     (Fishing.Utils.getTimeParams: x1.2 from 04:00 to 06:59 and 18:00 to 20:59)
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

-- Everything the window shows, as numbers (tests read this too)
function FishingSpotInfo.query(x, y)
    local params = Fishing.Utils.getFishNumParams(x, y)
    local info = { x = x, y = y, fish = params.value, coeff = params.coeff, time = FishingSpotInfo.timeInfo() }
    local zone = FishingSpotInfo.getZone(x, y)
    if zone then
        info.caught = tonumber(zone:getName()) or 0
        info.zoneX, info.zoneY = zone:getX(), zone:getY()
        info.zoneW, info.zoneH = zone:getWidth(), zone:getHeight()
        info.minutesLeft = zone:getLastActionTimestamp() + FishingSpotInfo.RESET_MINUTES - FishingSpotInfo.nowMinutes()
    end
    return info
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

-- Lines of text for one tile
function FishingSpotInfo.lines(info)
    local lines = {}
    table.insert(lines, getText("IGUI_FishingSpotInfo_Fish", info.fish, info.coeff))
    if not info.caught then
        table.insert(lines, getText("IGUI_FishingSpotInfo_NoArea"))
    else
        table.insert(lines, getText("IGUI_FishingSpotInfo_Caught", info.caught,
            info.zoneX, info.zoneY, info.zoneX + info.zoneW - 1, info.zoneY + info.zoneH - 1))
        if info.caught == 0 then
            table.insert(lines, getText("IGUI_FishingSpotInfo_Full"))
        elseif info.minutesLeft > 0 then
            table.insert(lines, getText("IGUI_FishingSpotInfo_RecoverIn", formatMinutes(info.minutesLeft)))
        else
            table.insert(lines, getText("IGUI_FishingSpotInfo_RecoverReady"))
        end
    end
    local time = info.time
    local clock = string.format("%02d:%02d", math.floor(time.minute / 60), time.minute % 60)
    if time.bonus then
        table.insert(lines, getText("IGUI_FishingSpotInfo_TimeBonus", clock, time.coeff, formatMinutes(time.minutesLeft)))
    else
        table.insert(lines, getText("IGUI_FishingSpotInfo_TimeNormal", clock, time.coeff, formatMinutes(time.minutesLeft)))
    end
    table.insert(lines, getText("IGUI_FishingSpotInfo_TimeHours"))
    table.insert(lines, getText("IGUI_FishingSpotInfo_Note"))
    return lines
end

------------------------------------------------------------------------------
-- Window

FishingSpotInfoWindow = ISPanel:derive("FishingSpotInfoWindow")

local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local PAD = 8
local TITLE_HGT = FONT_HGT_SMALL + 6

function FishingSpotInfoWindow:new(x, y, playerNum, tileX, tileY)
    local o = ISPanel.new(self, x, y, 320, 100)
    o.playerNum = playerNum
    o.tileX, o.tileY = tileX, tileY
    o.moveWithMouse = true
    o.backgroundColor = { r = 0, g = 0, b = 0, a = 0.8 }
    o.borderColor = { r = 0.4, g = 0.4, b = 0.4, a = 1 }
    return o
end

function FishingSpotInfoWindow:createChildren()
    ISPanel.createChildren(self)
    local size = TITLE_HGT - 4
    self.closeButton = ISButton:new(self.width - size - 2, 2, size, size, "X", self, FishingSpotInfoWindow.close)
    self.closeButton:initialise()
    self:addChild(self.closeButton)
end

function FishingSpotInfoWindow:setTile(tileX, tileY)
    self.tileX, self.tileY = tileX, tileY
end

function FishingSpotInfoWindow:close()
    self:setVisible(false)
    self:removeFromUIManager()
    if FishingSpotInfo.window == self then
        FishingSpotInfo.window = nil
    end
end

-- Ground highlights for one tile, as {x1, y1, x2, y2, r, g, b, a} (x2/y2 exclusive, like
-- addAreaHighlightForPlayer): the tile itself, and the area's 1-tile border, green when the
-- area is full, orange while it is depleted
function FishingSpotInfo.areaRects(info)
    local rects = { { info.x, info.y, info.x + 1, info.y + 1, 0.3, 0.7, 1.0, 0.6 } }
    if info.caught then
        local r, g, b = 1.0, 0.55, 0.1
        if info.caught == 0 then r, g, b = 0.3, 1.0, 0.3 end
        local x1, y1 = info.zoneX, info.zoneY
        local x2, y2 = x1 + info.zoneW, y1 + info.zoneH
        table.insert(rects, { x1, y1, x2, y1 + 1, r, g, b, 0.45 })
        table.insert(rects, { x1, y2 - 1, x2, y2, r, g, b, 0.45 })
        table.insert(rects, { x1, y1 + 1, x1 + 1, y2 - 1, r, g, b, 0.45 })
        table.insert(rects, { x2 - 1, y1 + 1, x2, y2 - 1, r, g, b, 0.45 })
    end
    return rects
end

function FishingSpotInfoWindow:render()
    ISPanel.render(self)
    local info = FishingSpotInfo.query(self.tileX, self.tileY)
    -- per-frame highlight, the way vanilla tools draw areas (FireBrushUI:render)
    for _, rc in ipairs(FishingSpotInfo.areaRects(info)) do
        addAreaHighlightForPlayer(self.playerNum, rc[1], rc[2], rc[3], rc[4], 0, rc[5], rc[6], rc[7], rc[8])
    end
    self:drawText(getText("IGUI_FishingSpotInfo_Title", self.tileX, self.tileY), PAD, 3, 1, 1, 1, 1, UIFont.Small)
    local y = TITLE_HGT + 4
    local width = 0
    for _, line in ipairs(FishingSpotInfo.lines(info)) do
        self:drawText(line, PAD, y, 1, 1, 1, 1, UIFont.Small)
        width = math.max(width, getTextManager():MeasureStringX(UIFont.Small, line))
        y = y + FONT_HGT_SMALL + 2
    end
    local w = math.max(240, width + PAD * 2)
    if self.width ~= w or self.height ~= y + PAD then
        self:setWidth(w)
        self:setHeight(y + PAD)
        self.closeButton:setX(w - self.closeButton.width - 2)
    end
end

function FishingSpotInfo.open(playerNum, tileX, tileY)
    if FishingSpotInfo.window then
        FishingSpotInfo.window:setTile(tileX, tileY)
        FishingSpotInfo.window:setVisible(true)
        FishingSpotInfo.window:bringToTop()
        return FishingSpotInfo.window
    end
    local x = getPlayerScreenLeft(playerNum) + 100
    local y = getPlayerScreenTop(playerNum) + 100
    local window = FishingSpotInfoWindow:new(x, y, playerNum, tileX, tileY)
    window:initialise()
    window:addToUIManager()
    FishingSpotInfo.window = window
    return window
end

------------------------------------------------------------------------------
-- Context menu

local function findWaterSquare(worldobjects)
    for _, obj in ipairs(worldobjects) do
        local square = obj:getSquare()
        if FishingSpotInfo.isWater(square) then
            return square
        end
    end
    return nil
end

function FishingSpotInfo.onFillWorldObjectContextMenu(playerNum, context, worldobjects, test)
    if test then return end
    local square = findWaterSquare(worldobjects)
    if not square then return end
    context:addOption(getText("IGUI_FishingSpotInfo_Menu"), playerNum,
        FishingSpotInfo.open, square:getX(), square:getY())
end

Events.OnFillWorldObjectContextMenu.Add(FishingSpotInfo.onFillWorldObjectContextMenu)
