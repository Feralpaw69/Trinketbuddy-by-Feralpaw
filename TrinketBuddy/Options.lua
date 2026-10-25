-- TrinketBuddy by feralpaw - options (Esc > Interface > AddOns > TrinketBuddy)

local ADDON, ns = ...

local floor, max = floor, max
local cfg
local pages = {}
local uid = 0
local function Name(kind) uid = uid + 1 return "TrinketBuddyOpt" .. kind .. uid end

-- the 3.3.5 options panel is only ~400px wide: one column
local COL1, COLW = 12, 350
local GOLD = {1, 0.82, 0}
local BOX = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 14,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

---------------------------------------------------------------------------
-- Building blocks
---------------------------------------------------------------------------

local function NewPage(name, subtitle, parent)
    local panel = CreateFrame("Frame")
    panel.name, panel.parent = name, parent
    panel.widgets, panel.boxes = {}, {}

    local scroll = CreateFrame("ScrollFrame", Name("Scroll"), panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 4, -4)
    scroll:SetPoint("BOTTOMRIGHT", -26, 4)
    local bar = _G[scroll:GetName() .. "ScrollBar"]
    local c = CreateFrame("Frame", nil, scroll)
    c:SetWidth(375)
    c:SetHeight(400)
    scroll:SetScrollChild(c)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local v = max(0, math.min(self:GetVerticalScrollRange(), self:GetVerticalScroll() - delta * 40))
        bar:SetValue(v)
    end)
    local onRange = scroll:GetScript("OnScrollRangeChanged")
    scroll:SetScript("OnScrollRangeChanged", function(self, x, y)
        if onRange then onRange(self, x, y) end
        if (y or 0) < 1 then bar:Hide() else bar:Show() end
    end)

    -- header: icon, name, subtitle and a gold rule
    local logo = c:CreateTexture(nil, "ARTWORK")
    logo:SetTexture("Interface\\Icons\\INV_Jewelry_Talisman_07")
    logo:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    logo:SetWidth(30)
    logo:SetHeight(30)
    logo:SetPoint("TOPLEFT", 12, -10)
    local title = c:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", logo, "TOPRIGHT", 8, -1)
    title:SetText("|cff33ccffTrinket|r|cffffcc00Buddy|r  |cff808080" .. (GetAddOnMetadata(ADDON, "Version") or "") .. "|r")
    local sub = c:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
    sub:SetText(subtitle)
    local rule = c:CreateTexture(nil, "ARTWORK")
    rule:SetTexture(1, 0.82, 0, 0.6)
    rule:SetHeight(1)
    rule:SetPoint("TOPLEFT", 12, -48)
    rule:SetPoint("TOPRIGHT", -12, -48)
    rule:SetGradientAlpha("HORIZONTAL", 1, 0.82, 0, 0.8, 1, 0.82, 0, 0)

    panel.content = c
    panel:SetScript("OnShow", function(self) self:Refresh() end)
    function panel:Refresh()
        local h = 60
        for _, b in ipairs(self.boxes) do h = max(h, -b.top + b:GetHeight() + 16) end
        c:SetHeight(h)
        for _, w in ipairs(self.widgets) do w:Refresh() end
    end
    InterfaceOptions_AddCategory(panel)
    pages[#pages + 1] = panel
    return panel
end

local function Section(page, title, x, y, w)
    local b = CreateFrame("Frame", nil, page.content)
    b:SetBackdrop(BOX)
    b:SetBackdropColor(0.05, 0.05, 0.08, 0.85)
    b:SetBackdropBorderColor(0.55, 0.47, 0.25, 1)
    b:SetPoint("TOPLEFT", x, y)
    b:SetWidth(w or COLW)
    b:SetHeight(20)
    local t = b:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    t:SetPoint("BOTTOMLEFT", b, "TOPLEFT", 6, 1)
    t:SetText(title)
    b.page, b.top, b.cy, b.w = page, y, -10, w or COLW
    page.boxes[#page.boxes + 1] = b
    return b
end

-- next section under an existing one
local function Below(box, title)
    return Section(box.page, title, select(4, box:GetPoint(1)), box.top - box:GetHeight() - 26, box.w)
end

local function Place(box, w, h, x, keepRow)
    w:SetPoint("TOPLEFT", box, "TOPLEFT", 10 + (x or 0), box.cy)
    if not keepRow then
        box.cy = box.cy - h
        box:SetHeight(-box.cy + 8)
    end
    if w.Refresh then box.page.widgets[#box.page.widgets + 1] = w end
    return w
end

local function Check(box, label, get, set, tip, x, keepRow)
    local name = Name("Check")
    local cb = CreateFrame("CheckButton", name, box, "InterfaceOptionsCheckButtonTemplate")
    _G[name .. "Text"]:SetText(label)
    cb.tooltipText = tip
    cb.Refresh = function(self) self:SetChecked(get() and true or false) end
    cb:SetScript("OnClick", function(self)
        PlaySound(self:GetChecked() and "igMainMenuOptionCheckBoxOn" or "igMainMenuOptionCheckBoxOff")
        set(self:GetChecked() and true or false)
    end)
    return Place(box, cb, 25, x, keepRow)
end

local function Slider(box, label, lo, hi, step, get, set)
    local name = Name("Slider")
    local s = CreateFrame("Slider", name, box, "OptionsSliderTemplate")
    s:SetWidth(box.w - 86)
    s:SetHeight(15)
    s:SetMinMaxValues(lo, hi)
    s:SetValueStep(step)
    _G[name .. "Low"]:SetText("")
    _G[name .. "High"]:SetText("")
    local t = _G[name .. "Text"]
    t:ClearAllPoints()
    t:SetPoint("BOTTOMLEFT", s, "TOPLEFT", 2, 1)
    t:SetFontObject(GameFontHighlightSmall)
    t:SetText(label)

    local eb = CreateFrame("EditBox", name .. "Value", s, "InputBoxTemplate")
    eb:SetWidth(40)
    eb:SetHeight(18)
    eb:SetPoint("LEFT", s, "RIGHT", 12, 0)
    eb:SetAutoFocus(false)
    eb:SetJustifyH("CENTER")
    eb:SetFontObject(GameFontHighlightSmall)
    eb:SetScript("OnShow", function(self) self:SetText(get()) end)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() self:SetText(get()) end)
    eb:SetScript("OnEnterPressed", function(self)
        local v = tonumber(self:GetText())
        if v then s:SetValue(v) end
        self:ClearFocus()
        self:SetText(get())
    end)

    local quiet
    s:SetScript("OnValueChanged", function(self, v)
        v = floor(v / step + 0.5) * step
        eb:SetText(v)
        if not quiet and v ~= get() then set(v) end
    end)
    s.Refresh = function(self)
        quiet = true
        if self.range then self:SetMinMaxValues(self.range()) end
        self:SetValue(get())
        eb:SetText(get())
        quiet = false
    end
    box.cy = box.cy - 12
    return Place(box, s, 32)
end

-- list() returns { {value, text}, ... }; long lists are split into sub menus
local function Dropdown(box, label, width, list, get, set)
    local dd = CreateFrame("Frame", Name("Drop"), box, "UIDropDownMenuTemplate")
    UIDropDownMenu_SetWidth(dd, width)
    local l = box:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    l:SetPoint("BOTTOMLEFT", dd, "TOPLEFT", 18, 1)
    l:SetText(label)

    local function add(e, level)
        local info = UIDropDownMenu_CreateInfo()
        info.text, info.value, info.checked = e[2], e[1], e[1] == get()
        info.func = function(b)
            set(b.value)
            UIDropDownMenu_SetText(dd, e[2])
            CloseDropDownMenus()
        end
        UIDropDownMenu_AddButton(info, level)
    end
    local function init(self, level, menuList)
        local entries = menuList or list()
        if level == 1 and #entries > 24 then
            for i = 1, #entries, 20 do
                local chunk = {}
                for j = i, math.min(i + 19, #entries) do chunk[#chunk + 1] = entries[j] end
                local info = UIDropDownMenu_CreateInfo()
                info.text = chunk[1][2]:sub(1, 1):upper() .. " - " .. chunk[#chunk][2]:sub(1, 1):upper()
                info.hasArrow, info.notCheckable, info.menuList = true, true, chunk
                UIDropDownMenu_AddButton(info, level)
            end
        else
            for _, e in ipairs(entries) do add(e, level) end
        end
    end
    dd.Refresh = function()
        UIDropDownMenu_Initialize(dd, init)
        local cur, text = get(), nil
        for _, e in ipairs(list()) do if e[1] == cur then text = e[2] end end
        UIDropDownMenu_SetText(dd, text or "-")
    end
    box.cy = box.cy - 14
    return Place(box, dd, 34, -16)
end

local function Note(box, text, x)
    local fs = box:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    fs:SetWidth(box.w - 24 - (x or 0))
    fs:SetJustifyH("LEFT")
    fs:SetText(text)
    return Place(box, fs, fs:GetStringHeight() + 8, (x or 0) + 4)
end

local function Button(box, text, w, onClick, x, keepRow)
    local b = CreateFrame("Button", Name("Button"), box, "UIPanelButtonTemplate")
    b:SetWidth(w)
    b:SetHeight(22)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return Place(box, b, 28, x, keepRow)
end

local function Color(box, label, get, set, x, keepRow)
    local b = CreateFrame("Button", nil, box)
    b:SetWidth(18)
    b:SetHeight(18)
    local edge = b:CreateTexture(nil, "BACKGROUND")
    edge:SetTexture(0.8, 0.8, 0.8)
    edge:SetAllPoints()
    local sw = b:CreateTexture(nil, "ARTWORK")
    sw:SetPoint("TOPLEFT", 1, -1)
    sw:SetPoint("BOTTOMRIGHT", -1, 1)
    sw:SetTexture(1, 1, 1)
    local l = b:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    l:SetPoint("LEFT", b, "RIGHT", 6, 0)
    l:SetText(label)
    b.Refresh = function() local c = get() sw:SetVertexColor(c[1], c[2], c[3]) end
    b:SetScript("OnClick", function()
        local c = get()
        local old = { c[1], c[2], c[3] }
        ColorPickerFrame.hasOpacity = false
        ColorPickerFrame.opacityFunc = nil
        ColorPickerFrame.previousValues = old
        ColorPickerFrame.func = function()
            local r, g, bl = ColorPickerFrame:GetColorRGB()
            set(r, g, bl)
            b:Refresh()
        end
        ColorPickerFrame.cancelFunc = function()
            set(old[1], old[2], old[3])
            b:Refresh()
        end
        ColorPickerFrame:SetColorRGB(old[1], old[2], old[3])
        ColorPickerFrame:Hide()
        ColorPickerFrame:Show()
    end)
    return Place(box, b, 26, (x or 0) + 4, keepRow)
end

local function RefreshAllPages()
    for _, p in ipairs(pages) do if p:IsVisible() then p:Refresh() end end
end

---------------------------------------------------------------------------
-- Pages
---------------------------------------------------------------------------

local function Redraw() ns.ApplyAll() end

local function GeneralPage()
    local p = NewPage(ADDON, "Proc and cooldown tracker for trinkets, rings and enchants.")

    local vis = Section(p, "Visibility", COL1, -72)
    Check(vis, "Hide out of combat", function() return cfg.combatOnly end, function(v) cfg.combatOnly = v Redraw() end)
    Check(vis, "Hide icons that are ready", function() return cfg.hideReady end, function(v) cfg.hideReady = v Redraw() end,
        "Only show an icon while its buff is up or it is on cooldown.\nTurns off click-to-use.")
    Check(vis, "Show the proc's spell icon while active", function() return cfg.procIcon end,
        function(v) cfg.procIcon = v Redraw() end)
    Check(vis, "Border around each icon", function() return cfg.iconBorder end,
        function(v) cfg.iconBorder = v Redraw() end, "Thin black frame around every single icon.\nThe thickness is set per icon on the Icons page.")
    Check(vis, "Stack count at the bottom", function() return cfg.stacksBottom end, function(v) cfg.stacksBottom = v Redraw() end)
    Check(vis, "Tenths of a second below 10s", function() return cfg.decimals end, function(v) cfg.decimals = v end)

    local mv = Below(vis, "Moving")
    Check(mv, "Unlock icons (move with the mouse)", function() return ns.IsUnlocked() end,
        function(v) ns.SetUnlocked(v) RefreshAllPages() end, "Also: /tb unlock, /tb lock")
    Check(mv, "Snap icons into line", function() return cfg.snap end, function(v) cfg.snap = v end,
        "Dropped icons line up with other icons' rows and columns or dock right next to them.\nHold Shift while dropping to place freely.")
    Note(mv, "While unlocked, the checkmark on each icon turns it on or off. Dragged icons never overlap - the X/Y sliders on the Icons page can.")
    Button(mv, "Reset positions", 120, function() ns.ResetPositions() end, 0, true)
    Button(mv, "Reset everything", 120, function() StaticPopup_Show("TRINKETBUDDY_RESET") end, 128)

    local on = Below(mv, "Tracked icons")
    for i, slot in ipairs(ns.ORDER) do
        local col = (i - 1) % 2
        Check(on, ns.LABEL[slot], function() return cfg.icons[slot].show end, function(v)
            cfg.icons[slot].show = v
            ns.ApplyLayout(ns.icons[slot])
            ns.UpdateGroupBox()
        end, nil, col * 150, col == 0)
    end

    local clk = Below(on, "Clicking")
    Check(clk, "Click an icon to use the item", function() return cfg.clickUse end, function(v)
        cfg.clickUse = v
        ns.Print("Click-to-use changes after |cffffff00/reload|r.")
    end, "Needs a /reload. Not available together with \"Hide icons that are ready\".")
    Check(clk, "Swapped trinkets start at 30s cooldown", function() return cfg.force30 end, function(v) cfg.force30 = v end,
        "Equipping a proc trinket normally starts its full internal cooldown.\nCheck this if your server uses 30 seconds instead.")

    local swapLabel = clk:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    swapLabel:SetText("Swap trinket (Ctrl + Right-click):")
    clk.cy = clk.cy - 4
    Place(clk, swapLabel, 16, 4)
    local eb = CreateFrame("EditBox", Name("Swap"), clk, "InputBoxTemplate")
    eb:SetWidth(clk.w - 36)
    eb:SetHeight(20)
    eb:SetAutoFocus(false)
    eb.Refresh = function(self)
        self:SetText(TrinketBuddyChar.swapLink or "[Gnomish Battle Chicken]")
        self:SetCursorPosition(0)
    end
    eb:SetScript("OnEditFocusGained", function(self) self:RegisterEvent("CURSOR_UPDATE") self:RegisterEvent("ITEM_LOCKED") end)
    eb:SetScript("OnEditFocusLost", function(self) self:UnregisterEvent("CURSOR_UPDATE") self:UnregisterEvent("ITEM_LOCKED") self:Refresh() end)
    eb:SetScript("OnEscapePressed", eb.ClearFocus)
    eb:SetScript("OnEvent", function(self, event)
        local kind, id, link = GetCursorInfo()
        if event == "ITEM_LOCKED" then ClearCursor() end
        if kind ~= "item" then return end
        if select(9, GetItemInfo(id)) ~= "INVTYPE_TRINKET" then
            ns.Print("Not a trinket: " .. (link or id))
        else
            TrinketBuddyChar.swapItem, TrinketBuddyChar.swapLink = id, link
        end
        self:ClearFocus()
    end)
    Place(clk, eb, 24, 6)
    Note(clk, "Click the box, then click a trinket in your bags.\n\n"
        .. "|cffffcc00Ctrl+Click|r take off & put back on   |cffffcc00Shift+Click|r switch trinket slots\n"
        .. "|cffffcc00Alt+Click|r equip a copy   |cffffcc00Ctrl+Right-click|r swap trinket")
    return p
end

local selected = ns.ORDER and ns.ORDER[1] or 13
local function S() return cfg.icons[selected] end
local function ApplySelected()
    ns.ApplyLayout(ns.icons[selected])
    ns.UpdateGroupBox()
end

local function IconsPage(parent)
    local p = NewPage("Icons", "Size, position and text of each icon.", parent)

    local pick = Section(p, "Icon", COL1, -72)
    local list = {}
    for _, slot in ipairs(ns.ORDER) do list[#list + 1] = { slot, ns.LABEL[slot] } end
    Dropdown(pick, "Edit icon:", 140, function() return list end, function() return selected end,
        function(v) selected = v p:Refresh() end)
    Check(pick, "Shown", function() return S().show end, function(v) S().show = v ApplySelected() end, nil, 0, true)
    Check(pick, "Item level", function() return S().ilvl end, function(v) S().ilvl = v ApplySelected() end, nil, 110, true)
    Check(pick, "Glow", function() return S().glow end, function(v) S().glow = v ns.RefreshGlows() end, nil, 240)
    pick.cy = pick.cy - 4
    pick:SetHeight(-pick.cy + 8)

    local pos = Below(pick, "Size & position")
    Slider(pos, "Size", 16, 80, 1, function() return S().size end, function(v) S().size = v ApplySelected() end)
    local sx = Slider(pos, "X (from screen center)", -1000, 1000, 1, function() return S().x end, function(v) S().x = v ApplySelected() end)
    sx.range = function() local w = floor(UIParent:GetWidth() / 2) return -w, w end
    local sy = Slider(pos, "Y (from screen center)", -800, 800, 1, function() return S().y end, function(v) S().y = v ApplySelected() end)
    sy.range = function() local h = floor(UIParent:GetHeight() / 2) return -h, h end
    Slider(pos, "Zoom %", 0, 30, 1, function() return S().zoom end, function(v) S().zoom = v ApplySelected() end)
    Slider(pos, "Border", 0, 8, 1, function() return S().border end, function(v) S().border = v ApplySelected() end)

    local txt = Below(pos, "Text size (% of icon)")
    Slider(txt, "Cooldown", 0, 100, 5, function() return S().cdSize end, function(v) S().cdSize = v ApplySelected() end)
    Slider(txt, "Stacks", 0, 100, 5, function() return S().stackSize end, function(v) S().stackSize = v ApplySelected() end)
    Slider(txt, "Item level", 0, 100, 5, function() return S().ilvlSize end, function(v) S().ilvlSize = v ApplySelected() end)
    Note(txt, "Copy size, zoom, border and text sizes of this icon to all others (positions stay):")
    Button(txt, "Apply to all icons", 150, function()
        local src = S()
        for _, s in pairs(cfg.icons) do
            s.size, s.zoom, s.border, s.cdSize, s.stackSize, s.ilvlSize =
                src.size, src.zoom, src.border, src.cdSize, src.stackSize, src.ilvlSize
        end
        ns.ApplyAll()
        ns.Print("Copied to all icons. Unlock and drag them if they overlap now.")
    end)
    return p
end

local GLOW_STYLES = { {1, "Soft glow"}, {2, "Frame"}, {3, "Sparks"} }
local FONTS = {
    {"Fonts\\ARIALN.TTF", "Arial Narrow"}, {"Fonts\\FRIZQT__.TTF", "Friz Quadrata"},
    {"Fonts\\MORPHEUS.TTF", "Morpheus"}, {"Fonts\\skurri.ttf", "Skurri"},
}
local function FontList()
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    if not LSM then return FONTS end
    local list, seen = {}, {}
    for _, f in ipairs(FONTS) do list[#list + 1] = f seen[f[1]:lower()] = true end
    local names = LSM:List("font")
    for _, n in ipairs(names) do
        local path = LSM:Fetch("font", n)
        if path and not seen[path:lower()] then list[#list + 1] = { path, n } seen[path:lower()] = true end
    end
    return list
end

local function LookPage(parent)
    local p = NewPage("Look", "Proc glow, font and the frame around your icons.", parent)

    local gl = Section(p, "Proc glow", COL1, -72)
    Check(gl, "Glow while a proc is active", function() return cfg.glow end, function(v) cfg.glow = v ns.RefreshGlows() end)
    Dropdown(gl, "Style", 150, function() return GLOW_STYLES end, function() return cfg.glowStyle end,
        function(v) cfg.glowStyle = v ns.RefreshGlows() end)
    Color(gl, "Proc glow color", function() return cfg.glowColor end, function(r, g, b)
        cfg.glowColor[1], cfg.glowColor[2], cfg.glowColor[3] = r, g, b
        ns.RefreshGlows()
    end)
    Check(gl, "Glow when an on-use trinket is ready", function() return cfg.readyGlow end,
        function(v) cfg.readyGlow = v ns.RefreshGlows() end,
        "Trinkets with a \"Use:\" effect glow while they are off cooldown,\nso you see at a glance when to press them.")
    Check(gl, "Only in combat", function() return cfg.readyCombatOnly end,
        function(v) cfg.readyCombatOnly = v ns.RefreshGlows() end, nil, 20)
    Color(gl, "Ready glow color", function() return cfg.readyColor end, function(r, g, b)
        cfg.readyColor[1], cfg.readyColor[2], cfg.readyColor[3] = r, g, b
        ns.RefreshGlows()
    end)
    Note(gl, "Turn the glow off for single icons on the Icons page.")

    local ft = Below(gl, "Font")
    Dropdown(ft, "Font for all icon text", 180, FontList, function() return cfg.font end, function(v) cfg.font = v Redraw() end)
    local prev = ft:CreateFontString(nil, "ARTWORK")
    prev.Refresh = function(self)
        if not self:SetFont(cfg.font, 15, "OUTLINE") then self:SetFont(ns.DEFAULT_FONT, 15, "OUTLINE") end
        self:SetText("12  4.5  3m  |cffa335ee264|r")
    end
    Place(ft, prev, 24, 6)

    local fr = Below(ft, "Group frame")
    local F = cfg.frame
    local function Restyle() ns.StyleGroupBox() end
    Check(fr, "Draw a frame around all icons", function() return F.enabled end, function(v) F.enabled = v Restyle() end,
        "A box behind all active icons. It follows the icons when you move them.")
    Slider(fr, "Padding", 0, 20, 1, function() return F.padding end, function(v) F.padding = v Restyle() end)
    Slider(fr, "Border thickness", 0, 8, 1, function() return F.edge end, function(v) F.edge = v Restyle() end)
    Color(fr, "Border color", function() return F.edgeColor end, function(r, g, b)
        F.edgeColor[1], F.edgeColor[2], F.edgeColor[3] = r, g, b
        Restyle()
    end)
    Color(fr, "Background color", function() return F.bgColor end, function(r, g, b)
        F.bgColor[1], F.bgColor[2], F.bgColor[3] = r, g, b
        Restyle()
    end)
    Slider(fr, "Background opacity %", 0, 100, 5, function() return floor(F.bgAlpha * 100 + 0.5) end,
        function(v) F.bgAlpha = v / 100 Restyle() end)
    return p
end

local function ProfilesPage(parent)
    local p = NewPage("Profiles", "Save your setup and load it on other characters.", parent)
    local pr = Section(p, "Profiles", COL1, -72)
    local name = ""
    local eb
    Dropdown(pr, "Saved profiles", 180, function()
        local l = {}
        for _, n in ipairs(ns.ProfileList()) do l[#l + 1] = { n, n } end
        if #l == 0 then l[1] = { "", "(none yet)" } end
        return l
    end, function() return name end, function(v) name = v eb:SetText(v) end)

    local lbl = pr:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    lbl:SetText("Name:")
    Place(pr, lbl, 0, 4, true)
    eb = CreateFrame("EditBox", Name("Profile"), pr, "InputBoxTemplate")
    eb:SetWidth(180)
    eb:SetHeight(20)
    eb:SetAutoFocus(false)
    eb:SetScript("OnTextChanged", function(self) name = strtrim(self:GetText()) end)
    eb:SetScript("OnEnterPressed", eb.ClearFocus)
    eb:SetScript("OnEscapePressed", eb.ClearFocus)
    pr.cy = pr.cy + 3
    Place(pr, eb, 30, 46)

    local function need(f)
        return function()
            if name == "" then ns.Print("Enter or pick a profile name first.") return end
            f(name)
            p:Refresh()
        end
    end
    Button(pr, "Save", 90, need(ns.SaveProfile), 0, true)
    Button(pr, "Load", 90, need(ns.LoadProfile), 96, true)
    Button(pr, "Delete", 90, need(ns.DeleteProfile), 192)

    local cmd = Below(pr, "Chat commands")
    Note(cmd, "|cffffff00/tb|r  open these options\n"
        .. "|cffffff00/tb unlock|r  |cffffff00/tb lock|r  |cffffff00/tb move|r  move icons with the mouse\n"
        .. "|cffffff00/tb save <name>|r  |cffffff00/tb load <name>|r  |cffffff00/tb delete <name>|r  |cffffff00/tb profiles|r\n"
        .. "|cffffff00/tb reset|r  back to defaults (reloads the UI, profiles are kept)")
    return p
end

---------------------------------------------------------------------------

StaticPopupDialogs.TRINKETBUDDY_RESET = {
    text = "Reset all TrinketBuddy settings for this character?\nYour UI will reload. Saved profiles are kept.",
    button1 = YES, button2 = NO,
    OnAccept = function() ns.ResetAll() end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

local main
function ns.BuildOptions()
    cfg = ns.cfg
    main = GeneralPage()
    IconsPage(ADDON)
    LookPage(ADDON)
    ProfilesPage(ADDON)
    ns.OnIconMoved = function(slot)
        if slot then selected = slot end
        RefreshAllPages()
    end
    ns.OnUnlockChanged = RefreshAllPages
end

function ns.OpenOptions()
    -- called twice: the first call only expands the list on 3.3.5
    InterfaceOptionsFrame_OpenToCategory(main)
    InterfaceOptionsFrame_OpenToCategory(main)
end
