-- TrinketBuddy by feralpaw
-- Proc and cooldown icons for trinkets, rings and enchants (WoW 3.3.5a).
-- One event frame and one shared timer drive all icons; auras are scanned once per change.

local ADDON, ns = ...
local D = ns.data

local GetTime, UnitBuff, InCombatLockdown = GetTime, UnitBuff, InCombatLockdown
local GetInventoryItemID, GetInventoryItemCooldown = GetInventoryItemID, GetInventoryItemCooldown
local pairs, ipairs, type, tonumber, wipe = pairs, ipairs, type, tonumber, wipe
local floor, ceil, abs, min, max, format = floor, ceil, abs, min, max, format

local W8 = "Interface\\Buttons\\WHITE8X8"
ns.DEFAULT_FONT = "Fonts\\ARIALN.TTF"

function ns.Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ccffTrinket|r|cffffcc00Buddy|r: " .. msg)
end
local Print = ns.Print

---------------------------------------------------------------------------
-- Icons and settings
---------------------------------------------------------------------------

-- slot, kind, label, default x, default y, on by default
local LAYOUT = {
    {13, "trinket", "Trinket 1", 100, -172, true},
    {14, "trinket", "Trinket 2", 132, -172, true},
    {10, "enchant", "Hands",     164, -172, true},
    { 8, "enchant", "Boots",     196, -172, true},
    { 6, "enchant", "Belt",      100, -140, false},
    {11, "ring",    "Ring",      132, -140, false},
    {15, "enchant", "Cloak",     164, -140, false},
    {16, "enchant", "Weapon",    196, -140, false},
}
ns.ORDER, ns.LABEL = {}, {}

local DEFAULTS = {
    iconBorder = true,
    combatOnly = false, hideReady = false, procIcon = true, stacksBottom = false, decimals = false,
    clickUse = false, force30 = false, snap = true,
    glow = true, glowStyle = 1, glowColor = {1, 0.82, 0.25},
    readyGlow = true, readyCombatOnly = true, readyColor = {0.25, 1, 0.35},
    font = ns.DEFAULT_FONT,
    frame = { enabled = false, padding = 4, edge = 1, edgeColor = {0.55, 0.47, 0.25}, bgColor = {0, 0, 0}, bgAlpha = 0.45 },
    icons = {},
}
for _, l in ipairs(LAYOUT) do
    local slot = l[1]
    ns.ORDER[#ns.ORDER + 1] = slot
    ns.LABEL[slot] = l[3]
    DEFAULTS.icons[slot] = {
        show = l[6], x = l[4], y = l[5], size = 32, zoom = 8, border = 1,
        ilvl = l[2] == "trinket", ilvlSize = 28, stackSize = 45, cdSize = 42, glow = true,
    }
end
ns.DEFAULTS = DEFAULTS

local function copy(t)
    if type(t) ~= "table" then return t end
    local c = {}
    for k, v in pairs(t) do c[k] = copy(v) end
    return c
end
ns.copy = copy

-- write known keys from src into dst (keeps dst's tables, ignores unknown or mistyped values)
local function merge(dst, src)
    if type(src) ~= "table" then return end
    for k, v in pairs(dst) do
        local s = src[k]
        if type(v) == "table" then
            merge(v, s)
        elseif s ~= nil and type(s) == type(v) then
            dst[k] = s
        end
    end
end
ns.merge = merge

local cfg            -- live settings (saved per character)
local icons = {}     -- slot -> icon frame
local bySlot = {}    -- inventory slot -> icon (both ring slots map to the ring icon)
ns.icons = icons
local moveMode = false
local inCombat = false
local items = {}     -- cached item state, keeps cooldowns when swapping items back and forth

---------------------------------------------------------------------------
-- Shared timer (only runs while something counts down)
---------------------------------------------------------------------------

local ticker = CreateFrame("Frame")
ticker:Hide()
local acc, pendingRefresh = 0, nil
local Ready, RefreshAll

local function FormatTime(left)
    if left >= 100 then return format("%dm", ceil(left / 60)) end
    if cfg.decimals and left < 10 then return format("%.1f", left) end
    return format("%d", ceil(left))
end

ticker:SetScript("OnUpdate", function(self, elapsed)
    acc = acc + elapsed
    if acc < 0.1 then return end
    acc = 0
    local now, busy = GetTime(), false
    for _, icon in pairs(icons) do
        local t = icon.timerEnd
        if t then
            local left = t - now
            if left <= 0 then
                icon.timerEnd = nil
                if icon.cdText then icon.cdText:SetText("") end
                if icon.item and not icon.item.active then Ready(icon) end
            else
                busy = true
                if icon.cdText and icon:IsVisible() then icon.cdText:SetText(FormatTime(left)) end
            end
        end
    end
    if pendingRefresh and now >= pendingRefresh then
        pendingRefresh = nil
        RefreshAll()
    end
    if not busy and not pendingRefresh then self:Hide() end
end)

local function Wake() ticker:Show() end

---------------------------------------------------------------------------
-- Glow (own styles: soft glow, frame, sparks)
---------------------------------------------------------------------------

local SPARKS = 4
local function Sparks_OnUpdate(g, elapsed)
    g.pos = (g.pos + elapsed * 0.9) % 4
    local s = g:GetWidth()
    local h = s / 2
    for i = 1, SPARKS do
        local p = (g.pos + (i - 1) * 4 / SPARKS) % 4
        local side, f = floor(p), p % 1
        local x, y
        if side == 0 then x, y = -h + f * s, h
        elseif side == 1 then x, y = h, h - f * s
        elseif side == 2 then x, y = h - f * s, -h
        else x, y = -h, -h + f * s end
        g[i]:SetPoint("CENTER", g, "CENTER", x, y)
    end
end

local function GlowFrame(icon)
    local g = icon.glow
    if g then return g end
    g = CreateFrame("Frame", nil, icon)
    g:SetAllPoints()
    g:SetFrameLevel(icon:GetFrameLevel() + 3)
    g:Hide()

    g.soft = g:CreateTexture(nil, "OVERLAY")
    g.soft:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    g.soft:SetBlendMode("ADD")
    g.soft:SetPoint("CENTER")

    g.edge = CreateFrame("Frame", nil, g)
    g.edge:SetAllPoints()

    g.sparks = CreateFrame("Frame", nil, g)
    g.sparks:SetAllPoints()
    g.sparks.pos = 0
    for i = 1, SPARKS do
        local t = g.sparks:CreateTexture(nil, "OVERLAY")
        t:SetTexture(W8)
        t:SetBlendMode("ADD")
        t:SetWidth(4)
        t:SetHeight(4)
        g.sparks[i] = t
    end
    g.sparks:SetScript("OnUpdate", Sparks_OnUpdate)

    local ag = g:CreateAnimationGroup()
    local a = ag:CreateAnimation("Alpha")
    a:SetChange(-0.6)
    a:SetDuration(0.55)
    ag:SetLooping("BOUNCE")
    g.pulse = ag

    icon.glow = g
    return g
end

-- "proc" while a proc buff is up, "ready" when an on-use trinket can be used, nil otherwise
local function GlowMode(icon)
    local it = icon.item
    if not (it and icon.s.glow) then return end
    if it.active then return cfg.glow and "proc" or nil end
    if cfg.readyGlow and it.usable and icon.kind == "trinket" and not icon.timerEnd and not moveMode
        and (inCombat or not cfg.readyCombatOnly) then
        return "ready"
    end
end

local function UpdateGlow(icon, force)
    local mode = GlowMode(icon)
    local g = icon.glow
    if not mode then
        if g and g:IsShown() then g.pulse:Stop(); g:Hide() end
        return
    end
    g = GlowFrame(icon)
    if g.mode == mode and g:IsShown() and not force then return end
    g.mode = mode
    local style, size = cfg.glowStyle, icon.s.size
    local c = mode == "ready" and cfg.readyColor or cfg.glowColor
    g.soft:SetWidth(size * 1.9)
    g.soft:SetHeight(size * 1.9)
    g.soft:SetVertexColor(c[1], c[2], c[3])
    g.edge:SetBackdrop({ edgeFile = W8, edgeSize = 2 })
    g.edge:SetBackdropBorderColor(c[1], c[2], c[3], 1)
    for i = 1, SPARKS do g.sparks[i]:SetVertexColor(c[1], c[2], c[3]) end
    if style == 2 then g.soft:Hide(); g.edge:Show(); g.sparks:Hide()
    elseif style == 3 then g.soft:Hide(); g.edge:Hide(); g.sparks:Show()
    else g.soft:Show(); g.edge:Hide(); g.sparks:Hide() end
    g:Show()
    if style == 3 then g.pulse:Stop() elseif not g.pulse:IsPlaying() then g.pulse:Play() end
end

function ns.RefreshGlows()
    for _, icon in pairs(icons) do UpdateGlow(icon, true) end
end

---------------------------------------------------------------------------
-- Group frame (optional border around all icons)
---------------------------------------------------------------------------

local box = CreateFrame("Frame", nil, UIParent)
box:SetFrameStrata("MEDIUM")
box:SetFrameLevel(2)
box:Hide()

function ns.StyleGroupBox()
    local f = cfg.frame
    local e = f.edge
    box:SetBackdrop({ bgFile = W8, edgeFile = e > 0 and W8 or nil, edgeSize = e, insets = { left = e, right = e, top = e, bottom = e } })
    box:SetBackdropColor(f.bgColor[1], f.bgColor[2], f.bgColor[3], f.bgAlpha)
    box:SetBackdropBorderColor(f.edgeColor[1], f.edgeColor[2], f.edgeColor[3], 1)
    ns.UpdateGroupBox()
end

function ns.UpdateGroupBox()
    local f = cfg.frame
    if not f.enabled then box:Hide() return end
    local l, r, t, b, visible
    for _, icon in pairs(icons) do
        local s = icon.s
        if s.show and (icon.item or moveMode) then
            local h = s.size / 2
            l, r = min(l or 1e6, s.x - h), max(r or -1e6, s.x + h)
            b, t = min(b or 1e6, s.y - h), max(t or -1e6, s.y + h)
            visible = visible or icon:IsShown()
        end
    end
    if not visible then box:Hide() return end
    local p = f.padding + f.edge
    box:ClearAllPoints()
    box:SetPoint("BOTTOMLEFT", UIParent, "CENTER", l - p, b - p)
    box:SetPoint("TOPRIGHT", UIParent, "CENTER", r + p, t + p)
    box:Show()
end

---------------------------------------------------------------------------
-- Icon visuals
---------------------------------------------------------------------------

local function SetFont(fs, size, pct)
    if not fs then return end
    local px = floor(size * pct / 100 + 1)
    if not fs:SetFont(cfg.font, px, "OUTLINE") then
        cfg.font = ns.DEFAULT_FONT
        fs:SetFont(ns.DEFAULT_FONT, px, "OUTLINE")
    end
end

local function ShouldShow(icon)
    if moveMode then return true end
    if not (icon.s.show and icon.item) then return false end
    if cfg.combatOnly and not inCombat then return false end
    if cfg.hideReady and not (icon.timerEnd or icon.item.active) then return false end
    return true
end

local UpdateOverlay -- move mode, defined below

local function UpdateVisibility(icon)
    if moveMode then UpdateOverlay(icon) end
    if icon.button and InCombatLockdown() then return end
    local want = ShouldShow(icon)
    if want ~= (icon:IsShown() and true or false) then
        if want then icon:Show() else icon:Hide() end
        ns.UpdateGroupBox()
    end
end

local function UpdateButton(icon)
    local b = icon.button
    if not b or InCombatLockdown() then return end
    local it = icon.item
    if not moveMode and it and (it.usable or it.id == ns.SwapID()) then b:Show() else b:Hide() end
end

local function ShowIconTexture(icon, spell)
    local tex = icon.item and icon.item.tex
    if spell and cfg.procIcon then
        tex = select(3, GetSpellInfo(spell)) or tex
    end
    icon.tex:SetTexture(tex or "Interface\\Icons\\INV_Misc_QuestionMark")
end

function Ready(icon)
    icon.timerEnd = nil
    icon.tex:SetDesaturated(false)
    if icon.cdText then icon.cdText:SetText("") end
    if cfg.hideReady then UpdateVisibility(icon) end
    UpdateGlow(icon)
end

local function ShowCooldown(icon, start, dur)
    icon.cd:SetReverse(false)
    icon.cd:SetCooldown(start, dur)
    icon.tex:SetDesaturated(true)
    icon.timerEnd = start + dur
    UpdateGlow(icon)
    UpdateVisibility(icon)
    Wake()
end

local function ShowActive(icon, start, dur)
    icon.cd:SetReverse(true)
    icon.cd:SetCooldown(start, dur)
    icon.tex:SetDesaturated(false)
    icon.timerEnd = start + dur
    UpdateVisibility(icon)
    Wake()
end

local function ClearVisuals(icon)
    icon.timerEnd = nil
    icon.stacks:SetText("")
    icon.tex:SetDesaturated(false)
    icon.cd:SetCooldown(0, 0)
    if icon.cdText then icon.cdText:SetText("") end
end

function ns.ApplyLayout(icon)
    local s = icon.s
    local size, bd = s.size, cfg.iconBorder and s.border or 0
    local z = s.zoom / 100
    icon.tex:SetTexCoord(z, 1 - z, z, 1 - z)
    icon.tex:ClearAllPoints()
    icon.tex:SetPoint("TOPLEFT", bd, -bd)
    icon.tex:SetPoint("BOTTOMRIGHT", -bd, bd)
    if bd > 0 then
        icon:SetBackdrop({ edgeFile = W8, edgeSize = bd })
        icon:SetBackdropBorderColor(0, 0, 0, 1)
    else
        icon:SetBackdrop(nil)
    end

    icon.stacks:ClearAllPoints()
    icon.stacks:SetPoint(cfg.stacksBottom and "BOTTOM" or "TOP", 0, cfg.stacksBottom and 2 or -2)
    SetFont(icon.stacks, size, s.stackSize)
    SetFont(icon.ilvl, size, s.ilvlSize)
    SetFont(icon.cdText, size, s.cdSize)
    if s.ilvl then icon.ilvl:Show() else icon.ilvl:Hide() end

    if icon.glow and icon.glow:IsShown() then UpdateGlow(icon, true) end

    if not InCombatLockdown() then
        icon:SetWidth(size)
        icon:SetHeight(size)
        icon:ClearAllPoints()
        icon:SetPoint("CENTER", UIParent, "CENTER", s.x, s.y)
    end
    UpdateVisibility(icon)
end

function ns.ApplyAll()
    for _, icon in pairs(icons) do
        ns.ApplyLayout(icon)
        UpdateButton(icon)
    end
    ns.StyleGroupBox()
    ns.RefreshGlows()
end

---------------------------------------------------------------------------
-- Tracking
---------------------------------------------------------------------------

local auraCount, auraDur, auraExp = {}, {}, {}

local function ScanAuras()
    wipe(auraCount); wipe(auraDur); wipe(auraExp)
    for i = 1, 40 do
        local name, _, _, count, _, dur, exp, _, _, _, id = UnitBuff("player", i)
        if not name then break end
        if id then
            auraCount[id], auraDur[id], auraExp[id] = count or 0, dur or 0, exp or 0
        end
    end
end

local function CheckUse(icon)
    local it = icon.item
    if not (it and it.usable) then return end
    local start, dur = GetInventoryItemCooldown("player", icon.useSlot)
    if not dur or dur <= 2 then return end
    if it.cdEnd == start + dur and icon.timerEnd then return end -- nothing new
    -- swap trinket (e.g. Gnomish Battle Chicken) used: put the previous trinket back
    if dur > 30 and it.id == ns.SwapID() and icon.prevItem and GetTime() - start < 5 then
        EquipItemByName(icon.prevItem, icon.useSlot)
    end
    it.procStart, it.cdEnd = start, start + dur
    if not it.active then ShowCooldown(icon, start, dur) end
end

local function CheckAura(icon, force)
    local it = icon.item
    if not (it and (it.buff or it.buffs)) then return end
    local id = it.buff
    if not (id and auraExp[id]) then
        id = nil
        if it.buffs then
            for b in pairs(it.buffs) do
                if auraExp[b] then id = b break end
            end
        end
    end

    if id then
        local was = it.active
        local dur, exp = auraDur[id], auraExp[id]
        local stacks = it.stack and auraCount[it.stack] or auraCount[id]
        icon.stacks:SetText(stacks and stacks > 0 and stacks or "")
        it.active = true
        if dur > 0 and (force or exp ~= it.buffEnd) then
            it.buffEnd = exp
            local start = exp - dur
            if not it.procStart or start > it.procStart then
                it.procStart = start
                it.cdEnd = it.icd > 0 and start + it.icd or exp
            end
            ShowActive(icon, start, dur)
        end
        if icon.procSpell ~= id or force then
            icon.procSpell = id
            ShowIconTexture(icon, id)
        end
        UpdateGlow(icon)
        if not was then UpdateVisibility(icon) end
    elseif it.active then
        it.active = false
        icon.procSpell = nil
        UpdateGlow(icon)
        icon.stacks:SetText("")
        ShowIconTexture(icon)
        if it.usable then
            CheckUse(icon)
        elseif it.icd > 0 and it.cdEnd and it.cdEnd > GetTime() then
            ShowCooldown(icon, it.procStart, it.cdEnd - it.procStart)
        else
            icon.cd:SetCooldown(0, 0)
            Ready(icon)
        end
    end
end

-- which item (and buff) an icon tracks right now
local function Resolve(icon)
    if icon.kind == "ring" then
        for slot = 11, 12 do
            local id = GetInventoryItemID("player", slot)
            if id and D.RING[id] then return id, slot, D.RING[id], nil, D.ICD[id] or 60, id end
        end
        return
    end
    local slot = icon.slot
    local id = GetInventoryItemID("player", slot)
    if not id then return end
    if icon.kind == "trinket" then
        local buff, multi = D.PROC[id], D.MULTI[id]
        return id, slot, buff, multi, (buff or multi) and (D.ICD[id] or 45) or 0, id
    end
    local link = GetInventoryItemLink("player", slot)
    local ench = link and tonumber(link:match("item:%d+:(%d+)"))
    local buff = ench and D.ENCHANT[ench]
    if buff then return id, slot, buff, nil, D.ENCHANT_ICD[buff] or 60, id .. ":" .. ench end
    local _, _, enable = GetInventoryItemCooldown("player", slot)
    if enable == 1 then return id, slot, nil, nil, 0, id end -- on-use effect (e.g. engineering tinker)
end

-- returns true if the tracked item changed
local function SetItem(icon)
    local id, slot, buff, multi, icd, key = Resolve(icon)
    local old = icon.item
    if old and key == old.key then return false end
    if old and old.id ~= ns.SwapID() then icon.prevItem = old.id end

    local it
    if id then
        it = items[key]
        if not it then
            local _, _, quality, ilvl, _, _, _, _, _, tex = GetItemInfo(id)
            if not tex then -- not in the item cache yet, try again shortly
                pendingRefresh = GetTime() + 1
                Wake()
                return false
            end
            it = { id = id, key = key, tex = tex, ilvl = ilvl, quality = quality,
                   buff = buff, buffs = multi, stack = buff and D.STACKS[buff], icd = icd }
            items[key] = it
        end
        local _, _, enable = GetInventoryItemCooldown("player", slot)
        it.usable = enable == 1
        it.active = false
    end

    icon.item, icon.useSlot = it, slot or icon.slot
    ClearVisuals(icon)
    if it then
        ShowIconTexture(icon)
        icon.ilvl:SetText(it.ilvl or "")
        local r, g, b = GetItemQualityColor(it.quality or 1)
        icon.ilvl:SetTextColor(r, g, b)
        CheckAura(icon, true)
        if not it.active then
            if it.usable then CheckUse(icon)
            elseif it.cdEnd and it.cdEnd > GetTime() then ShowCooldown(icon, it.procStart, it.cdEnd - it.procStart) end
        end
    end
    UpdateGlow(icon)
    UpdateButton(icon)
    UpdateVisibility(icon)
    return true
end

-- equipping a proc item starts its internal cooldown
local function OnSwapped(icon)
    local it = icon.item
    if not it or it.usable or not (it.buff or it.buffs) or it.icd == 0 or it.active then return end
    local now = GetTime()
    if not cfg.force30 then
        it.procStart, it.cdEnd = now, now + it.icd
    elseif not (it.cdEnd and it.cdEnd - now > 30) then
        it.procStart, it.cdEnd = now, now + 30
    end
    ShowCooldown(icon, it.procStart, it.cdEnd - it.procStart)
end

function RefreshAll()
    ScanAuras()
    for _, icon in pairs(icons) do SetItem(icon) end
    ns.UpdateGroupBox()
end

---------------------------------------------------------------------------
-- Clicks (swap helpers)
---------------------------------------------------------------------------

function ns.SwapID()
    return TrinketBuddyChar and TrinketBuddyChar.swapItem or 10725
end

local function ClickAction(icon, button)
    icon = icon.parent or icon
    local it = icon.item
    if moveMode or not it then return end
    if InCombatLockdown() then
        if IsModifierKeyDown() then Print("Leave combat to swap items.") end
        return
    end
    local slot = icon.useSlot
    if button == "LeftButton" then
        if IsControlKeyDown() then -- take off and put back on
            for bag = 0, 4 do
                local free, family = GetContainerNumFreeSlots(bag)
                if family == 0 and free > 0 then
                    icon.swapBack = it.id
                    PickupInventoryItem(slot)
                    if bag == 0 then PutItemInBackpack() else PutItemInBag(ContainerIDToInventoryID(bag)) end
                    return
                end
            end
            Print("No free bag space.")
        elseif IsShiftKeyDown() and (slot == 13 or slot == 14) then
            EquipItemByName(it.id, slot == 13 and 14 or 13)
        elseif IsAltKeyDown() then
            EquipItemByName((GetItemInfo(it.id)), slot)
        end
    elseif button == "RightButton" and IsControlKeyDown() and icon.kind == "trinket" then
        if it.id == ns.SwapID() then
            if icon.prevItem then EquipItemByName(icon.prevItem, slot) end
        else
            EquipItemByName(ns.SwapID(), slot)
        end
    end
end

---------------------------------------------------------------------------
-- Move mode: drag, per-icon checkmark, overlap protection, snapping
---------------------------------------------------------------------------

local TINT = { ok = {0, 1, 0, 0.25}, bad = {1, 0, 0, 0.55}, off = {0, 0, 0, 0.65} }
local SNAP = 10

local function Round(v) return floor(v + 0.5) end

local function FramePos(icon)
    local cx, cy = icon:GetCenter()
    local ux, uy = UIParent:GetCenter()
    if not cx then return icon.s.x, icon.s.y end
    local k = icon:GetEffectiveScale() / UIParent:GetEffectiveScale()
    return cx * k - ux, cy * k - uy
end

local function Blocks(other, moving) return other ~= moving and other.s.show end

local function Overlaps(moving, x, y, size)
    for _, o in pairs(icons) do
        if Blocks(o, moving) then
            local h = (size + o.s.size) / 2
            if abs(x - o.s.x) < h and abs(y - o.s.y) < h then return o end
        end
    end
end

-- nearest spot to (x, y) that overlaps nothing; nil if nothing fits on screen
local function FreeSpot(moving, x, y, size)
    x, y = Round(x), Round(y)
    if not Overlaps(moving, x, y, size) then return x, y end
    local xs, ys = {x}, {y}
    for _, o in pairs(icons) do
        if Blocks(o, moving) then
            local h = ceil((size + o.s.size) / 2)
            xs[#xs + 1], xs[#xs + 2] = o.s.x - h, o.s.x + h
            ys[#ys + 1], ys[#ys + 2] = o.s.y - h, o.s.y + h
        end
    end
    local mx, my = UIParent:GetWidth() / 2 - size / 2, UIParent:GetHeight() / 2 - size / 2
    local best, bx, by
    for _, cx in ipairs(xs) do
        for _, cy in ipairs(ys) do
            if abs(cx) <= mx and abs(cy) <= my then
                local d = (cx - x) ^ 2 + (cy - y) ^ 2
                if (not best or d < best) and not Overlaps(moving, cx, cy, size) then best, bx, by = d, cx, cy end
            end
        end
    end
    return bx, by
end
ns.FreeSpot = FreeSpot

-- line up with other icons' rows/columns or dock flush beside them
local function Snap(moving, x, y, size)
    local h = size / 2
    local bdx, sx, bdy, sy
    local function tx(v) local d = abs(v - x) if d <= SNAP and (not bdx or d < bdx) then bdx, sx = d, v end end
    local function ty(v) local d = abs(v - y) if d <= SNAP and (not bdy or d < bdy) then bdy, sy = d, v end end
    for _, o in pairs(icons) do
        if Blocks(o, moving) then
            local ox, oy, oh = o.s.x, o.s.y, o.s.size / 2
            local flush = ceil(oh + h)
            ty(oy); ty(Round(oy + oh - h)); ty(Round(oy - oh + h))
            tx(ox); tx(Round(ox - oh + h)); tx(Round(ox + oh - h))
            if abs(y - oy) < oh + h then tx(ox - flush); tx(ox + flush) end
            if abs(x - ox) < oh + h then ty(oy - flush); ty(oy + flush) end
        end
    end
    return sx or x, sy or y, sx ~= nil, sy ~= nil
end

local guides
local function ShowGuides(x, y, gx, gy)
    if not guides then
        guides = CreateFrame("Frame", nil, UIParent)
        guides:SetFrameStrata("FULLSCREEN_DIALOG")
        guides.h = guides:CreateTexture(nil, "OVERLAY")
        guides.v = guides:CreateTexture(nil, "OVERLAY")
        guides.h:SetTexture(0.2, 0.8, 1, 0.8)
        guides.v:SetTexture(0.2, 0.8, 1, 0.8)
        guides.h:SetHeight(1)
        guides.v:SetWidth(1)
    end
    local w, hh = UIParent:GetWidth() / 2, UIParent:GetHeight() / 2
    guides.h:ClearAllPoints()
    guides.h:SetPoint("LEFT", UIParent, "CENTER", -w, y)
    guides.h:SetPoint("RIGHT", UIParent, "CENTER", w, y)
    guides.v:ClearAllPoints()
    guides.v:SetPoint("TOP", UIParent, "CENTER", x, hh)
    guides.v:SetPoint("BOTTOM", UIParent, "CENTER", x, -hh)
    if gy then guides.h:Show() else guides.h:Hide() end
    if gx then guides.v:Show() else guides.v:Hide() end
    guides:Show()
end
local function HideGuides() if guides then guides:Hide() end end

local function SnapOn() return cfg.snap and not IsShiftKeyDown() end

local function Tint(ov, state)
    if ov.state ~= state then
        ov.state = state
        ov.tint:SetTexture(unpack(TINT[state]))
    end
end

local function Overlay_OnUpdate(ov)
    local icon = ov.icon
    if not icon.moving then return end
    local size = icon.s.size
    local x, y = FramePos(icon)
    if SnapOn() then
        local gx, gy
        x, y, gx, gy = Snap(icon, x, y, size)
        ShowGuides(x, y, gx, gy)
    else
        HideGuides()
    end
    Tint(ov, Overlaps(icon, x, y, size) and "bad" or "ok")
end

local function Moved(icon)
    icon:ClearAllPoints()
    icon:SetPoint("CENTER", UIParent, "CENTER", icon.s.x, icon.s.y)
    ns.UpdateGroupBox()
    if ns.OnIconMoved then ns.OnIconMoved(icon.slot) end
end

local function Check_OnClick(cb)
    local icon = cb.icon
    local s = icon.s
    s.show = cb:GetChecked() and true or false
    if s.show then
        local x, y = FreeSpot(icon, s.x, s.y, s.size)
        if not x then
            Print(icon.label .. " overlaps another icon and there is no free spot nearby.")
        elseif x ~= s.x or y ~= s.y then
            s.x, s.y = x, y
            Moved(icon)
            Print(icon.label .. " was moved a little so it doesn't overlap another icon.")
        end
    end
    UpdateOverlay(icon)
    ns.UpdateGroupBox()
    if ns.OnIconMoved then ns.OnIconMoved(icon.slot) end
end

local function Check_OnEnter(cb)
    GameTooltip:SetOwner(cb, "ANCHOR_RIGHT")
    GameTooltip:SetText(cb.icon.label)
    GameTooltip:AddLine("Checked: icon is active.", 1, 1, 1)
    GameTooltip:AddLine("Unchecked: icon is turned off completely.", 1, 1, 1)
    GameTooltip:AddLine("Drag the icon to move it. Hold Shift to place it freely.", 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

function UpdateOverlay(icon)
    local ov = icon.overlay
    if not ov then
        ov = CreateFrame("Frame", nil, icon)
        ov.icon = icon
        ov:SetAllPoints()
        ov.tint = ov:CreateTexture(nil, "OVERLAY")
        ov.tint:SetAllPoints()
        ov.label = ov:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        ov.label:SetPoint("BOTTOM", ov, "TOP", 0, 3)
        local cb = CreateFrame("CheckButton", "TrinketBuddyMoveCheck" .. icon.slot, ov, "UICheckButtonTemplate")
        cb.icon = icon
        cb:SetWidth(20)
        cb:SetHeight(20)
        cb:SetPoint("CENTER", ov, "TOPRIGHT", -2, -2)
        cb:SetScript("OnClick", Check_OnClick)
        cb:SetScript("OnEnter", Check_OnEnter)
        cb:SetScript("OnLeave", GameTooltip_Hide)
        ov.check = cb
        ov:SetScript("OnUpdate", Overlay_OnUpdate)
        icon.overlay = ov
    end
    ov:SetFrameLevel(icon:GetFrameLevel() + 8)
    ov.check:SetFrameLevel(ov:GetFrameLevel() + 2)
    local on = icon.s.show
    ov.check:SetChecked(on)
    ov.label:SetText(icon.item and icon.label or icon.label .. " |cff888888(empty)|r")
    ov.label:SetTextColor(on and 1 or 0.5, on and 0.82 or 0.5, on and 0 or 0.5)
    if not icon.item then icon.tex:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark") end
    ov.state = nil
    Tint(ov, on and "ok" or "off")
    ov:Show()
end

local function DragStart(icon)
    if not moveMode or InCombatLockdown() then return end
    icon.startX, icon.startY = icon.s.x, icon.s.y
    icon:StartMoving()
    icon.moving = true
end

local function DragStop(icon)
    if not icon.moving then return end
    icon:StopMovingOrSizing()
    if icon.SetUserPlaced then icon:SetUserPlaced(false) end
    icon.moving = false
    HideGuides()
    local s = icon.s
    local x, y = FramePos(icon)
    if SnapOn() then x, y = Snap(icon, x, y, s.size) end
    x, y = FreeSpot(icon, x, y, s.size)
    if x then
        s.x, s.y = x, y
    else
        s.x, s.y = icon.startX, icon.startY
        Print("No free spot there - moved back. Use the X/Y sliders to overlap icons on purpose.")
    end
    Moved(icon)
    if moveMode then UpdateOverlay(icon) end
end

function ns.IsUnlocked() return moveMode end

function ns.SetUnlocked(on, quiet)
    on = on and true or false
    if on == moveMode then return true end
    if InCombatLockdown() then Print("Can't move icons in combat.") return false end
    moveMode = on
    local strata = on and "FULLSCREEN_DIALOG" or "MEDIUM"
    box:SetFrameStrata(strata)
    for _, icon in pairs(icons) do
        if not on and icon.moving then DragStop(icon) end
        icon:SetFrameStrata(strata)
        icon:EnableMouse(on)
        if not on then
            if icon.overlay then icon.overlay:Hide() end
            ShowIconTexture(icon, icon.procSpell)
        end
        UpdateButton(icon)
        UpdateVisibility(icon)
    end
    ns.UpdateGroupBox()
    ns.RefreshGlows()
    if ns.OnUnlockChanged then ns.OnUnlockChanged() end
    if not quiet then
        Print(on and "|cff00ff00Icons unlocked|r - drag to move, use the checkmark to turn an icon on/off. |cffffff00/tb lock|r when done."
            or "|cffff4444Icons locked.|r")
    end
    return true
end

---------------------------------------------------------------------------
-- Frames
---------------------------------------------------------------------------

local function CreateIcon(slot, kind, label)
    local f = CreateFrame("Frame", "TrinketBuddyIcon" .. slot, UIParent)
    f:Hide()
    f.slot, f.useSlot, f.kind, f.label = slot, slot, kind, label
    f.s = cfg.icons[slot]
    f:SetFrameStrata("MEDIUM")
    f:SetFrameLevel(5)

    f.tex = f:CreateTexture(nil, "ARTWORK")
    f.cd = CreateFrame("Cooldown", nil, f)
    f.cd:SetAllPoints(f.tex)

    local o = CreateFrame("Frame", nil, f)
    o:SetAllPoints()
    o:SetFrameLevel(f:GetFrameLevel() + 6)
    f.stacks = o:CreateFontString(nil, "OVERLAY")
    f.ilvl = o:CreateFontString(nil, "OVERLAY")
    f.ilvl:SetPoint("BOTTOMRIGHT", -1, 2)
    if not IsAddOnLoaded("OmniCC") then
        f.cdText = o:CreateFontString(nil, "OVERLAY")
        f.cdText:SetPoint("CENTER", 0, 0)
    end
    for _, fs in ipairs({ f.stacks, f.ilvl, f.cdText }) do
        fs:SetFont(ns.DEFAULT_FONT, 12, "OUTLINE")
        fs:SetShadowOffset(1, -1)
        fs:SetShadowColor(0, 0, 0, 1)
    end

    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", DragStart)
    f:SetScript("OnDragStop", DragStop)
    f:SetScript("OnMouseDown", ClickAction)

    if cfg.clickUse and not cfg.hideReady then
        local b = CreateFrame("Button", "TrinketBuddyUse" .. slot, f, "SecureActionButtonTemplate")
        b:SetAllPoints()
        b:RegisterForClicks("AnyUp")
        b:SetAttribute("type1", "item")
        b:SetAttribute("item", slot)
        for _, mod in ipairs({ "shift-", "ctrl-", "alt-" }) do b:SetAttribute(mod .. "type1", "") end
        b:SetScript("OnMouseDown", ClickAction)
        b.parent = f
        b:Hide()
        f.button = b
    end

    icons[slot] = f
    bySlot[slot] = f
    if kind == "ring" then bySlot[12] = f end
    ns.ApplyLayout(f)
    return f
end

---------------------------------------------------------------------------
-- Profiles & reset
---------------------------------------------------------------------------

function ns.ProfileList()
    local list = {}
    for name in pairs(TrinketBuddyDB.profiles) do list[#list + 1] = name end
    sort(list)
    return list
end

function ns.SaveProfile(name)
    TrinketBuddyDB.profiles[name] = copy(cfg)
    Print(format("Profile '%s' saved.", name))
end

function ns.LoadProfile(name)
    local p = TrinketBuddyDB.profiles[name]
    if not p then Print(format("Profile '%s' not found.", name)) return end
    merge(cfg, p)
    ns.ApplyAll()
    RefreshAll()
    if ns.OnIconMoved then ns.OnIconMoved() end
    Print(format("Profile '%s' loaded.", name))
end

function ns.DeleteProfile(name)
    if not TrinketBuddyDB.profiles[name] then Print(format("Profile '%s' not found.", name)) return end
    TrinketBuddyDB.profiles[name] = nil
    Print(format("Profile '%s' deleted.", name))
end

function ns.ResetPositions()
    for slot, icon in pairs(icons) do
        local d = DEFAULTS.icons[slot]
        icon.s.x, icon.s.y = d.x, d.y
        ns.ApplyLayout(icon)
    end
    ns.UpdateGroupBox()
    if ns.OnIconMoved then ns.OnIconMoved() end
end

function ns.ResetAll()
    TrinketBuddyChar.cfg = nil
    ReloadUI()
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local ev = CreateFrame("Frame")
local firstRun

local handlers = {}

function handlers.ADDON_LOADED(name)
    if name ~= ADDON then return end
    ev:UnregisterEvent("ADDON_LOADED")
    TrinketBuddyDB = TrinketBuddyDB or {}
    TrinketBuddyDB.profiles = TrinketBuddyDB.profiles or {}
    TrinketBuddyChar = TrinketBuddyChar or {}
    firstRun = not TrinketBuddyChar.cfg
    cfg = copy(DEFAULTS)
    merge(cfg, TrinketBuddyChar.cfg)
    TrinketBuddyChar.cfg = cfg
    ns.cfg = cfg
    for _, l in ipairs(LAYOUT) do CreateIcon(l[1], l[2], l[3]) end
    ns.StyleGroupBox()
    if ns.BuildOptions then ns.BuildOptions() end
end

function handlers.PLAYER_ENTERING_WORLD()
    inCombat = UnitAffectingCombat("player") and true or false
    RefreshAll()
    if firstRun then
        firstRun = nil
        ns.SetUnlocked(true, true)
        Print("Welcome! Drag the icons where you want them and use the checkmark to turn icons on/off. "
            .. "Type |cffffff00/tb lock|r when you're done, |cffffff00/tb|r for options.")
    end
end

function handlers.UNIT_AURA(unit)
    if unit ~= "player" then return end
    ScanAuras()
    for _, icon in pairs(icons) do CheckAura(icon) end
end

function handlers.BAG_UPDATE_COOLDOWN()
    for _, icon in pairs(icons) do CheckUse(icon) end
end

function handlers.PLAYER_EQUIPMENT_CHANGED(slot)
    local icon = bySlot[slot]
    if not icon then return end
    if icon.swapBack and GetInventoryItemID("player", slot) == icon.swapBack then icon.swapBack = nil end
    ScanAuras()
    if SetItem(icon) then OnSwapped(icon) end
    ns.UpdateGroupBox()
end

function handlers.ITEM_UNLOCKED()
    for _, icon in pairs(icons) do
        if icon.swapBack and not InCombatLockdown() then EquipItemByName(icon.swapBack, icon.useSlot) end
    end
end

function handlers.PLAYER_REGEN_DISABLED()
    inCombat = true
    -- still allowed to touch secure frames during this event
    if moveMode then
        ns.SetUnlocked(false, true)
        Print("Entered combat - icons locked.")
    end
    for _, icon in pairs(icons) do
        if not icon.button then icon:EnableMouse(false) end
        UpdateVisibility(icon)
        UpdateGlow(icon)
    end
end

function handlers.PLAYER_REGEN_ENABLED()
    inCombat = false
    for _, icon in pairs(icons) do UpdateButton(icon); UpdateVisibility(icon); UpdateGlow(icon) end
end

function handlers.MODIFIER_STATE_CHANGED()
    if moveMode or InCombatLockdown() then return end
    local down = IsModifierKeyDown() and true or false
    for _, icon in pairs(icons) do icon:EnableMouse(down) end
end

ev:SetScript("OnEvent", function(_, event, ...) handlers[event](...) end)
for event in pairs(handlers) do ev:RegisterEvent(event) end

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------

SLASH_TRINKETBUDDY1 = "/tb"
SLASH_TRINKETBUDDY2 = "/trinketbuddy"
SlashCmdList.TRINKETBUDDY = function(msg)
    local cmd, arg = strtrim(msg or ""):match("^(%S*)%s*(.-)$")
    cmd = cmd:lower()
    if cmd == "" or cmd == "options" or cmd == "config" then
        if ns.OpenOptions then ns.OpenOptions() end
    elseif cmd == "unlock" then ns.SetUnlocked(true)
    elseif cmd == "lock" then ns.SetUnlocked(false)
    elseif cmd == "move" or cmd == "drag" then ns.SetUnlocked(not moveMode)
    elseif cmd == "reset" then ns.ResetAll()
    elseif cmd == "save" and arg ~= "" then ns.SaveProfile(arg)
    elseif cmd == "load" and arg ~= "" then ns.LoadProfile(arg)
    elseif cmd == "delete" and arg ~= "" then ns.DeleteProfile(arg)
    elseif cmd == "profiles" then
        local list = ns.ProfileList()
        Print(#list > 0 and ("Profiles: " .. table.concat(list, ", ")) or "No saved profiles.")
    else
        Print("commands:")
        print("  |cffffff00/tb|r - options")
        print("  |cffffff00/tb unlock|r, |cffffff00lock|r, |cffffff00move|r - move icons with the mouse")
        print("  |cffffff00/tb save / load / delete <name>|r, |cffffff00/tb profiles|r - profiles")
        print("  |cffffff00/tb reset|r - back to defaults (reloads UI, profiles are kept)")
    end
end
