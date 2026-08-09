--!nocheck

local environment = getfenv and getfenv() or {}

local getgenv = environment.getgenv or function()
    return environment
end
local cloneref = environment.cloneref or function(value)
    return value
end
local setthreadidentity = environment.setthreadidentity
local readfile = environment.readfile or function()
    return ""
end
local writefile = environment.writefile or function()
end
local isfolder = environment.isfolder or function()
    return false
end
local makefolder = environment.makefolder or function()
end
local listfiles = environment.listfiles or function()
    return {}
end
local getcustomasset = environment.getcustomasset or function()
    return ""
end

local function tryGetCustomAsset(path)
    if type(getcustomasset) ~= "function" then
        return ""
    end
    local ok, res = pcall(getcustomasset, path)
    if ok and res and res ~= "" then
        return res
    end
    -- try without leading Phantom/ prefix as a fallback
    local alt = tostring(path):gsub("^Phantom/", "")
    local ok2, res2 = pcall(getcustomasset, alt)
    if ok2 and res2 and res2 ~= "" then
        return res2
    end
    return ""
end

local sharedExecutorContext = getgenv()
local isBad = false
if type(sharedExecutorContext) == "table" then
    local executorInfo = type(sharedExecutorContext.phantomExecutor) == "table" and sharedExecutorContext.phantomExecutor or nil
    isBad = (executorInfo and executorInfo.isBad == true) or sharedExecutorContext.phantomIsBadExecutor == true
end

local function safeVisible(obj, state)
    if typeof(obj) == "Instance" and obj.Parent then
        pcall(function()
            obj.Visible = state == true
        end)
    end
end

local P = {
    BASE0      = Color3.fromRGB(3,   3,   4),
    BASE1      = Color3.fromRGB(5,   5,   6),
    BASE2      = Color3.fromRGB(9,   9,   10),
    BASE3      = Color3.fromRGB(12,  12,  14),
    BASE_HOV   = Color3.fromRGB(16,  14,  20),
    BASE_LIT   = Color3.fromRGB(32,  10,  56),
    HUE        = Color3.fromRGB(86,  34, 150),
    HUE_FADE   = Color3.fromRGB(30,   8,  52),
    EDGE       = Color3.fromRGB(19,  19,  22),
    EDGE_HI    = Color3.fromRGB(102, 46, 182),
    INK_HI     = Color3.fromRGB(238, 238, 243),
    INK_MID    = Color3.fromRGB(166, 166, 176),
    INK_LOW    = Color3.fromRGB(102, 102, 114),
    INK_BETA    = Color3.fromRGB(86,  198, 238),
    INK_NEW     = Color3.fromRGB(198, 122, 255),
    INK_PRIVATE = Color3.fromRGB(255, 160, 60),
    STATE_ON   = Color3.fromRGB(68, 192, 82),
    STATE_OFF  = Color3.fromRGB(212, 60, 65),
    CAUTION    = Color3.fromRGB(212, 168, 27),
}

local R_SM = UDim.new(0, 0)
local R_MD = UDim.new(0, 0)
local R_LG = UDim.new(0, 0)

local FONT_HDR = Enum.Font.GothamBold
local FONT_ROW = Enum.Font.Gotham
local FONT_VALUE = Enum.Font.GothamBold

local COL_W    = 128
local ROW_W    = 122
local SUB_W    = 116
local ROW_H    = 18
local HDR_H    = 19
local PANEL_TOP_MARGIN = 12
local PRESET_BAR_GAP = 9
local PANEL_GAP = 5
local Scaler

local DEFAULT_PALETTE = { H = 0.73, S = 0.77, V = 0.59 }
local DEFAULT_SECONDARY = P.HUE_FADE
local DEFAULT_FONT_COLOR = P.INK_HI

local function mixColor(a, b, alpha)
    return a:Lerp(b, math.clamp(alpha or 0, 0, 1))
end

local function darken(color, amount)
    return mixColor(color, Color3.new(0, 0, 0), amount or 0.5)
end

local function lighten(color, amount)
    return mixColor(color, Color3.new(1, 1, 1), amount or 0.5)
end

local function packColor(color)
    return {
        R = math.floor((color.R * 255) + 0.5),
        G = math.floor((color.G * 255) + 0.5),
        B = math.floor((color.B * 255) + 0.5),
    }
end

local function normalizeColor(color, fallback)
    if typeof(color) == "Color3" then
        return color
    end
    if type(color) == "table" then
        return Color3.fromRGB(
            math.clamp(math.floor((tonumber(color.R) or 0) + 0.5), 0, 255),
            math.clamp(math.floor((tonumber(color.G) or 0) + 0.5), 0, 255),
            math.clamp(math.floor((tonumber(color.B) or 0) + 0.5), 0, 255)
        )
    end
    return fallback
end

local function applyAccentPalette(palette, secondary)
    local accent = Color3.fromHSV(
        palette.H or DEFAULT_PALETTE.H,
        palette.S or DEFAULT_PALETTE.S,
        palette.V or DEFAULT_PALETTE.V
    )
    local fade = normalizeColor(secondary, DEFAULT_SECONDARY)

    P.HUE = accent
    P.HUE_FADE = fade
    P.BASE_LIT = mixColor(darken(accent, 0.46), fade, 0.58)
    P.EDGE_HI = mixColor(accent, Color3.new(1, 1, 1), 0.14)
end

local function applyFontPalette(fontColor)
    local color = normalizeColor(fontColor, DEFAULT_FONT_COLOR)
    P.INK_HI = color
    P.INK_MID = darken(color, 0.30)
    P.INK_LOW = darken(color, 0.58)
end

local function mkCorner(p, r)
    local c = Instance.new("UICorner"); c.CornerRadius = r or R_SM; c.Parent = p; return c
end
local function mkBorder(p, col, thick, trans)
    local s = Instance.new("UIStroke")
    s.Color           = col or P.EDGE
    s.Thickness       = thick or 1
    s.Transparency    = trans or 0
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    s.Parent = p; return s
end
local function mkPad(p, t, b, l, r)
    local u = Instance.new("UIPadding")
    u.PaddingTop    = UDim.new(0, t or 0)
    u.PaddingBottom = UDim.new(0, b or 0)
    u.PaddingLeft   = UDim.new(0, l or 0)
    u.PaddingRight  = UDim.new(0, r or 0)
    u.Parent = p; return u
end
local function mkChevron(parent, xPos, _, sz)
    local a = Instance.new("ImageLabel")
    a.Parent              = parent
    a.BackgroundTransparency = 1
    a.BorderSizePixel     = 0
    a.Position            = UDim2.new(0, xPos, 0.5, -math.floor(sz / 2))
    a.Size                = UDim2.new(0, sz, 0, sz)
    a.Image               = "http://www.roblox.com/asset/?id=6031094679"
    a.ImageColor3         = P.INK_LOW
    a.ScaleType           = Enum.ScaleType.Fit
    a.Rotation            = 180
    a.ZIndex              = 3; return a
end

local Hook = {}; Hook.__index = Hook

function Hook.new()
    return setmetatable({ _slots = {}, _seq = 0 }, Hook)
end

function Hook:Bind(fn)
    self._seq = self._seq + 1
    local id   = self._seq
    local slots = self._slots
    slots[id] = fn

    pcall(fn)

    return {
        Active     = true,
        Unbind = function(self)
            slots[id]  = nil
            self.Active = false
        end,

        Connected  = true,
        Disconnect = function(self)
            slots[id]  = nil
            self.Active    = false
            self.Connected = false
        end,
    }
end

function Hook:Emit(...)
    for _, fn in next, self._slots do fn(...) end
end

Hook.Connect = Hook.Bind
Hook.Fire    = Hook.Emit


local UIS          = cloneref(game:GetService("UserInputService"))
local Tween        = cloneref(game:GetService("TweenService"))
local Runner       = cloneref(game:GetService("RunService"))
local HttpService  = cloneref(game:GetService("HttpService"))
local GuiService   = cloneref(game:GetService("GuiService"))
local TextService  = cloneref(game:GetService("TextService"))

local IS_MOBILE =  UIS.TouchEnabled and not UIS.MouseEnabled

local TEXT_SIZE_SM = 10
local TEXT_SIZE_MD = 11
local TOGGLE_H = 16
local SLIDER_H = 24
local TEXTBOX_H = 18
local PADDING_SM = 1
local PADDING_MD = 2

if IS_MOBILE then
    COL_W = 165
    ROW_W = 156
    SUB_W = 148
    ROW_H = 24
    HDR_H = 28
    TEXT_SIZE_SM = 13
    TEXT_SIZE_MD = 15
    TOGGLE_H = 26
    SLIDER_H = 42
    TEXTBOX_H = 30
    PADDING_SM = 5
    PADDING_MD = 8
end

local function isPrimaryPress(inputType)
    return inputType == Enum.UserInputType.MouseButton1 or inputType == Enum.UserInputType.Touch
end

local function isPointerMove(inputType)
    return inputType == Enum.UserInputType.MouseMovement or inputType == Enum.UserInputType.Touch
end

local MOBILE_UI_FILE = "Phantom/storage/config/mobile.ui.json"

local function readStoredJson(path, fallback)
    local ok, data = pcall(function()
        return HttpService:JSONDecode(readfile(path))
    end)
    if ok and type(data) == "table" then
        return data
    end
    return fallback or {}
end

local function writeStoredJson(path, data)
    pcall(function()
        if not isfolder("Phantom/storage/config") then makefolder("Phantom/storage/config") end
        writefile(path, HttpService:JSONEncode(data))
    end)
end

local MobileUIState = readStoredJson(MOBILE_UI_FILE, {})
MobileUIState.Buttons = type(MobileUIState.Buttons) == "table" and MobileUIState.Buttons or {}
MobileUIState.Open = type(MobileUIState.Open) == "table" and MobileUIState.Open or {}
MobileUIState.PresetBar = type(MobileUIState.PresetBar) == "table" and MobileUIState.PresetBar or {}
MobileUIState.Style = type(MobileUIState.Style) == "table" and MobileUIState.Style or {}

local function readMobileButtonStyle()
    local style = MobileUIState.Style
    if type(style) ~= "table" then
        style = {}
        MobileUIState.Style = style
    end
    if style.Circle == nil then
        style.Circle = false
    end
    if style.Outline == nil then
        style.Outline = true
    end
    return style
end

local function saveMobileUIState()
    writeStoredJson(MOBILE_UI_FILE, MobileUIState)
end

local function getViewportSize()
    local camera = workspace.CurrentCamera
    if camera then
        return camera.ViewportSize
    end
    return Vector2.new(1280, 720)
end

local function getTopInsetPixels()
    local ok, topLeftInset = pcall(function()
        return select(1, GuiService:GetGuiInset())
    end)
    if ok and typeof(topLeftInset) == "Vector2" then
        return topLeftInset.Y
    end
    return 0
end

local function pixelsToUiOffset(pixels)
    local s = (Scaler and Scaler.Scale and Scaler.Scale > 0) and Scaler.Scale or 1
    return math.floor((pixels / s) + 0.5)
end

local function getPanelTopOffset()
    return pixelsToUiOffset(getTopInsetPixels() + PANEL_TOP_MARGIN)
end

local function getPresetBarTopOffset(barHeight)
    local heightOffset = pixelsToUiOffset((barHeight or 18) + PRESET_BAR_GAP)
    return math.max(0, getPanelTopOffset() - heightOffset)
end

local PanelManualState = setmetatable({}, { __mode = "k" })

local function getPanelManual(bar)
    return PanelManualState[bar] == true
end

local function setPanelManual(bar, value)
    if not bar then return false end
    if value == true then
        PanelManualState[bar] = true
        return true
    end
    PanelManualState[bar] = nil
    return false
end

local function clampPanelOffset(bar, x, y, scale)
    local vp = getViewportSize()
    local s = scale or ((Scaler and Scaler.Scale and Scaler.Scale > 0) and Scaler.Scale or 1)
    local minX = 6
    local minY = getPanelTopOffset()
    local width = (bar and bar.AbsoluteSize and bar.AbsoluteSize.X) or COL_W
    local height = (bar and bar.AbsoluteSize and bar.AbsoluteSize.Y) or HDR_H
    
    local maxX = math.max(minX, math.floor(vp.X / s - width - 6))
    local maxY = math.max(minY, math.floor(vp.Y / s - height - 20))
    
    return math.clamp(math.floor((x or minX) + 0.5), minX, maxX),
           math.clamp(math.floor((y or minY) + 0.5), minY, maxY)
end

local function applyPanelOffset(bar, x, y, scale)
    local clampedX, clampedY = clampPanelOffset(bar, x, y, scale)
    bar.Position = UDim2.new(0, clampedX, 0, clampedY)
    return clampedX, clampedY
end

local function clampAnchorPosition(button, x, y)
    local vp = getViewportSize()
    local absSize = button.AbsoluteSize
    local halfX = math.max((absSize.X or 0) / 2, 18)
    local halfY = math.max((absSize.Y or 0) / 2, 18)
    local px = math.clamp(x * vp.X, halfX + 6, vp.X - halfX - 6)
    local py = math.clamp(y * vp.Y, halfY + 6, vp.Y - halfY - 6)
    return px / vp.X, py / vp.Y
end

local function getAnchorPixelPosition(gui)
    local absPos = gui.AbsolutePosition
    local absSize = gui.AbsoluteSize
    local anchor = gui.AnchorPoint
    return Vector2.new(
        absPos.X + (absSize.X * anchor.X),
        absPos.Y + (absSize.Y * anchor.Y)
    )
end

local function clampFloatingAnchorPixels(gui, x, y)
    local parent = gui and gui.Parent
    local parentSize = parent and parent.AbsoluteSize or getViewportSize()
    local absSize = gui and gui.AbsoluteSize or Vector2.new(0, 0)
    local anchor = gui and gui.AnchorPoint or Vector2.zero
    local minX = 6 + (absSize.X * anchor.X)
    local minY = math.max(6 + (absSize.Y * anchor.Y), getPanelTopOffset())
    local maxX = math.max(minX, parentSize.X - 6 - (absSize.X * (1 - anchor.X)))
    local maxY = math.max(minY, parentSize.Y - (HDR_H + 8) + (absSize.Y * anchor.Y))
    return math.clamp(math.floor((x or minX) + 0.5), minX, maxX),
           math.clamp(math.floor((y or minY) + 0.5), minY, maxY)
end

local function applyFloatingAnchorPixels(gui, x, y)
    local scale = (Scaler and Scaler.Scale and Scaler.Scale > 0) and Scaler.Scale or 1
    local clampedX, clampedY = clampFloatingAnchorPixels(gui, x, y)
    gui.Position = UDim2.new(
        0, math.floor((clampedX / scale) + 0.5),
        0, math.floor((clampedY / scale) + 0.5)
    )
    return gui.Position.X.Offset, gui.Position.Y.Offset
end

local function applyFloatingOffset(gui, x, y)
    local scale = (Scaler and Scaler.Scale and Scaler.Scale > 0) and Scaler.Scale or 1
    return applyFloatingAnchorPixels(gui, (x or 0) * scale, (y or 0) * scale)
end

local function clampFloatingOffset(gui, x, y)
    local scale = (Scaler and Scaler.Scale and Scaler.Scale > 0) and Scaler.Scale or 1
    local px, py = clampFloatingAnchorPixels(gui, (x or 0) * scale, (y or 0) * scale)
    return math.floor((px / scale) + 0.5), math.floor((py / scale) + 0.5)
end

local function readStoredAnchorPoint(info)
    if type(info) ~= "table" then
        return nil
    end
    local anchorX = tonumber(info.AnchorX)
    local anchorY = tonumber(info.AnchorY)
    if not anchorX or not anchorY then
        return nil
    end
    return anchorX, anchorY
end

local function captureRelativeAnchorPoint(gui)
    local parent = gui and gui.Parent
    local parentSize = parent and parent.AbsoluteSize or getViewportSize()
    local anchorPoint = getAnchorPixelPosition(gui)
    return {
        AnchorX = parentSize.X > 0 and math.clamp(anchorPoint.X / parentSize.X, 0, 1) or 0.5,
        AnchorY = parentSize.Y > 0 and math.clamp(anchorPoint.Y / parentSize.Y, 0, 1) or 0.5,
    }
end

local function applyRelativeAnchorPoint(gui, info)
    local anchorX, anchorY = readStoredAnchorPoint(info)
    if not anchorX or not anchorY then
        return false
    end
    local parent = gui and gui.Parent
    local parentSize = parent and parent.AbsoluteSize or getViewportSize()
    if parentSize.X <= 0 or parentSize.Y <= 0 then
        return false
    end
    local offsetX = anchorX * parentSize.X
    local offsetY = anchorY * parentSize.Y
    applyFloatingAnchorPixels(gui, offsetX, offsetY)
    return true
end

local function captureResponsiveFloatingLayout(gui)
    local parent = gui and gui.Parent
    local parentSize = parent and parent.AbsoluteSize or getViewportSize()
    local absPos = gui and gui.AbsolutePosition or Vector2.zero
    local absSize = gui and gui.AbsoluteSize or Vector2.zero
    local centerX = absPos.X + absSize.X * 0.5
    local centerY = absPos.Y + absSize.Y * 0.5

    if parentSize.X <= 0 or parentSize.Y <= 0 then
        return { AnchorX = 0.5, AnchorY = 0.5 }
    end

    return {
        AnchorX = math.clamp(centerX / parentSize.X, 0, 1),
        AnchorY = math.clamp(centerY / parentSize.Y, 0, 1),
    }
end

local function applyResponsiveFloatingLayout(gui, info)
    if type(info) ~= "table" then return false end

    local xScale = info.AnchorX or 0.5
    local yScale = info.AnchorY or 0.5
    if xScale < 0.02 and yScale < 0.02 then return false end

    local parentSize = gui.Parent and gui.Parent.AbsoluteSize or getViewportSize()
    local absSize = gui.AbsoluteSize or Vector2.zero
    local anchor = Vector2.new(0.5, 0.5)
    gui.AnchorPoint = anchor

    local minX = (6 + absSize.X * 0.5) / parentSize.X
    local maxX = (parentSize.X - 6 - absSize.X * 0.5) / parentSize.X
    local minY = (6 + absSize.Y * 0.5) / parentSize.Y
    local maxY = (parentSize.Y - 6 - absSize.Y * 0.5) / parentSize.Y

    if maxX < minX then maxX = minX end
    if maxY < minY then maxY = minY end

    xScale = math.clamp(xScale, minX, maxX)
    yScale = math.clamp(yScale, minY, maxY)

    gui.Position = UDim2.fromScale(xScale, yScale)
    return true
end

local function formatBindDisplay(bind)
    if bind == nil or bind == "" then
        return nil
    end

    local text = tostring(bind)
    local aliases = {
        RightShift = "RightShift",
        LeftShift = "LeftShift",
        LeftControl = "LCtrl",
        RightControl = "RCtrl",
        LeftAlt = "LAlt",
        RightAlt = "RAlt",
        MouseButton1 = "Mouse1",
        MouseButton2 = "Mouse2",
        MouseButton3 = "Mouse3",
    }

    return aliases[text] or text
end

local function measureTextWidth(text, font, textSize)
    if not text or text == "" then
        return 0
    end

    local ok, result = pcall(function()
        return TextService:GetTextSize(tostring(text), textSize or TEXT_SIZE_SM, font or FONT_VALUE, Vector2.new(4096, 32))
    end)
    return ok and result.X or 0
end

local function readMobilePoint(store, defaultX, defaultY)
    if type(store) ~= "table" then
        return defaultX, defaultY
    end
    return math.clamp(tonumber(store.X) or defaultX, 0.06, 0.94),
        math.clamp(tonumber(store.Y) or defaultY, 0.06, 0.94)
end

local function nextMobileButtonSlot()
    local used = 0
    for _, info in next, MobileUIState.Buttons do
        if type(info) == "table" and info.Enabled == true then
            used = used + 1
        end
    end
    local y = 0.84 - math.min(used, 5) * 0.09
    if used > 5 then
        y = 0.30 + ((used - 6) * 0.06)
    end
    return 0.86, math.clamp(y, 0.18, 0.84)
end

local function ensureMobileButtonState(id, defaultX, defaultY)
    local entry = MobileUIState.Buttons[id]
    if type(entry) ~= "table" then
        entry = { Enabled = false, Manual = false, X = defaultX, Y = defaultY }
        MobileUIState.Buttons[id] = entry
    end
    entry.X, entry.Y = readMobilePoint(entry, defaultX, defaultY)
    entry.Enabled = entry.Enabled == true
    entry.Manual = entry.Manual == true
    return entry
end


local Spectrum = {
    RainbowMode = false,
    RainbowSpeed = 1750,
    AnimationSpeed = 1,
    GlowSpeed = 1.5,
    SecondaryColor = DEFAULT_SECONDARY,
    FontColor = DEFAULT_FONT_COLOR,
    UserScale = 1,
    ActiveLayoutPreset = "default",
}
local kit      = {}; Spectrum.kit = kit
local refreshTweenInfo

local PANEL_LAYOUT_PRESETS = {
    default = {
        Id = "default",
        ScaleMultiplier = 1,
        HorizontalGap = PANEL_GAP,
        VerticalGap = 8,
        MaxColumns = nil,
        Align = "center",
    },
    compact = {
        Id = "compact",
        ScaleMultiplier = 0.92,
        HorizontalGap = 4,
        VerticalGap = 6,
        MaxColumns = nil,
        Align = "center",
    },
    vertical = {
        Id = "vertical",
        ScaleMultiplier = 0.9,
        HorizontalGap = 4,
        VerticalGap = 6,
        MaxColumns = 1,
        Align = "left",
        LeftPadding = 10,
    },
    hud = {
        Id = "hud",
        ScaleMultiplier = 0.88,
        HorizontalGap = 6,
        VerticalGap = 6,
        MaxColumns = 3,
        Align = "center",
    },
}

applyAccentPalette(DEFAULT_PALETTE, Spectrum.SecondaryColor)
applyFontPalette(Spectrum.FontColor)

local hoverTI

local function playTween(instance, info, props)
    local tween = Tween:Create(instance, info, props)
    tween:Play()
    return tween
end

local function getLayoutPresetConfig()
    local key = string.lower(tostring(Spectrum.ActiveLayoutPreset or "default"))
    return PANEL_LAYOUT_PRESETS[key] or PANEL_LAYOUT_PRESETS.default
end
local FloatingLayoutRecords = {}

do 
    function kit:activeColor()
        if kit:rainbowActive() then return kit:rainbowColor() end
        return P.HUE
    end

    function kit:objectColor(obj)
        if not kit:rainbowActive() then return P.HUE end
        local y = 0
        pcall(function() y = obj.AbsolutePosition.Y end)
        return kit:rainbowColor(y)
    end

    function kit:readPalette(asTable)
        local t = Spectrum.Palette or DEFAULT_PALETTE
        return asTable and t or Color3.fromHSV(t.H, t.S, t.V)
    end

    function kit:writePalette(color)
        local t = typeof(color)
        Spectrum.Palette = Spectrum.Palette or {}
        if t == "table" then
            Spectrum.Palette = color
        else
            local h, s, v = color:ToHSV()
            Spectrum.Palette.H = h
            Spectrum.Palette.S = s
            Spectrum.Palette.V = v
        end
        applyAccentPalette(Spectrum.Palette, Spectrum.SecondaryColor)
        if Spectrum.PaletteSync then Spectrum.PaletteSync:Emit() end
    end

    function kit:rainbowActive() return Spectrum.RainbowMode or false end

    function kit:rainbowColor(y)
        if not kit:rainbowActive() then return P.HUE end
        y = math.abs(y or 0)
        local pal  = kit:readPalette(true)
        local h    = pal.H + y / (Spectrum.RainbowSpeed or 1750)
        while h > 1 do h = h - 1 end
        return Color3.fromHSV(h, pal.S, pal.V)
    end

    function kit:track(conn)
        if not Spectrum.Tracked then Spectrum.Tracked = {} end
        Spectrum.Tracked[#Spectrum.Tracked + 1] = conn
    end

    function kit:register(name, obj)
        if not Spectrum.Registry then Spectrum.Registry = {} end
        Spectrum.Registry[name] = obj
    end

    function kit:deregister(name)
        local function purge(t)
            for _, v in next, t do
                local k = typeof(v)
                if k == "Instance" then
                    v:Destroy()
                elseif k == "RBXScriptConnection" then
                    if v.Connected then v:Disconnect() end
                elseif k == "table" and v.Unbind then
                    v:Unbind()
                elseif k == "table" then
                    purge(v)
                end
            end
        end
        if Spectrum.Registry and Spectrum.Registry[name] then
            purge(Spectrum.Registry[name])
            Spectrum.Registry[name] = nil
        end
    end

    function kit:nextSlot()
        Spectrum.SlotIndex = (Spectrum.SlotIndex or 0) + 1
        return Spectrum.SlotIndex
    end

    local function getPanelWindowHeight(bar)
        local body = bar and bar:FindFirstChild("Body")
        local height = (bar and bar.Size and bar.Size.Y.Offset) or HDR_H
        if body and body.Visible then
            height = height + body.AbsoluteSize.Y + 2
        end
        return height
    end

    local function getGuiRect(gui)
        if not gui or not gui.Parent then
            return nil
        end

        local pos = gui.AbsolutePosition
        local size = gui.AbsoluteSize
        local body = gui:FindFirstChild("Body")
        if body and body.Visible then
            size = Vector2.new(size.X, size.Y + body.AbsoluteSize.Y + 2)
        end

        return {
            Left = pos.X,
            Top = pos.Y,
            Right = pos.X + size.X,
            Bottom = pos.Y + size.Y,
        }
    end

    local function rectsOverlap(a, b, padding)
        if not a or not b then
            return false
        end

        local pad = padding or 6
        return not (
            a.Right <= (b.Left + pad)
            or a.Left >= (b.Right - pad)
            or a.Bottom <= (b.Top + pad)
            or a.Top >= (b.Bottom - pad)
        )
    end

    local function resolveGuiOverlap(gui, mode)
        local current = getGuiRect(gui)
        if not current then
            return false
        end

        local others = {}
        for _, bar in ipairs(Spectrum.PanelBars or {}) do
            if bar ~= gui and bar.Parent and bar.Visible ~= false then
                others[#others + 1] = bar
            end
        end
        for _, record in next, FloatingLayoutRecords do
            if record and record.Frame and record.Frame ~= gui and record.Frame.Parent and record.Frame.Visible ~= false then
                others[#others + 1] = record.Frame
            end
        end

        local overlaps = false
        for _, other in ipairs(others) do
            if rectsOverlap(current, getGuiRect(other), 8) then
                overlaps = true
                break
            end
        end
        if not overlaps then
            return false
        end

        local scale = (Scaler and Scaler.Scale and Scaler.Scale > 0) and Scaler.Scale or 1
        local originX = gui.Position.X.Offset
        local originY = gui.Position.Y.Offset
        local step = math.max(8, math.floor((18 / scale) + 0.5))
        local maxRadius = math.max(120, math.floor((getViewportSize().X / scale) * 0.4))

        local function applyPosition(x, y)
            if mode == "panel" then
                applyPanelOffset(gui, x, y, scale)
            else
                applyFloatingOffset(gui, x, y)
            end
        end

        for radius = step, maxRadius, step do
            local candidates = {
                Vector2.new(originX + radius, originY),
                Vector2.new(originX - radius, originY),
                Vector2.new(originX, originY + radius),
                Vector2.new(originX, originY - radius),
                Vector2.new(originX + radius, originY + radius),
                Vector2.new(originX - radius, originY + radius),
                Vector2.new(originX + radius, originY - radius),
                Vector2.new(originX - radius, originY - radius),
            }

            for _, candidate in ipairs(candidates) do
                applyPosition(candidate.X, candidate.Y)
                local candidateRect = getGuiRect(gui)
                local blocked = false
                for _, other in ipairs(others) do
                    if rectsOverlap(candidateRect, getGuiRect(other), 8) then
                        blocked = true
                        break
                    end
                end
                if not blocked then
                    return true
                end
            end
        end

        applyPosition(originX, originY)
        return false
    end

    kit.resolveGuiOverlap = resolveGuiOverlap

    function kit:repositionPanels(scale)
        local bars = Spectrum.PanelBars
        if not bars or #bars == 0 then return end
        local s = scale or 1
        local vp = workspace.CurrentCamera.ViewportSize
        if vp.X < 1 or vp.Y < 1 then return end

        local preset = getLayoutPresetConfig()
        local topOffset = getPanelTopOffset()
        local availableWidth = math.max(COL_W + 12, math.floor(vp.X / s) - 12)
        local horizontalGap = preset.HorizontalGap or PANEL_GAP
        local verticalGap = preset.VerticalGap or 8
        local defaultMaxCols = math.max(1, math.floor((availableWidth + horizontalGap) / (COL_W + horizontalGap)))
        local maxColumns = math.max(1, math.min(#bars, preset.MaxColumns or defaultMaxCols))

        local autoBars = {}
        for _, bar in ipairs(bars) do
            if not getPanelManual(bar) then
                autoBars[#autoBars + 1] = bar
            end
        end

        local rowIndex = 1
        local columnIndex = 1
        local rowBars = {}
        local rowHeights = {}

        for _, bar in ipairs(autoBars) do
            rowBars[rowIndex] = rowBars[rowIndex] or {}
            rowBars[rowIndex][#rowBars[rowIndex] + 1] = bar
            rowHeights[rowIndex] = math.max(rowHeights[rowIndex] or 0, getPanelWindowHeight(bar))

            columnIndex = columnIndex + 1
            if columnIndex > maxColumns then
                columnIndex = 1
                rowIndex = rowIndex + 1
            end
        end

        local currentY = topOffset
        for row = 1, #rowBars do
            local barsInRow = rowBars[row]
            local rowWidth = (#barsInRow * COL_W) + math.max(#barsInRow - 1, 0) * horizontalGap
            local startX
            if preset.Align == "left" then
                startX = preset.LeftPadding or 8
            else
                startX = math.max(6, math.floor((availableWidth - rowWidth) * 0.5))
            end

            for index, bar in ipairs(barsInRow) do
                local x = startX + ((index - 1) * (COL_W + horizontalGap))
                bar.Position = UDim2.new(0, x, 0, currentY)
            end

            currentY = currentY + (rowHeights[row] or HDR_H) + verticalGap
        end

        for _, bar in ipairs(bars) do
            if getPanelManual(bar) then
                local x, y = clampPanelOffset(bar, bar.Position.X.Offset, bar.Position.Y.Offset, s)
                bar.Position = UDim2.new(0, x, 0, y)
                resolveGuiOverlap(bar, "panel")
            end
        end
    end

    function kit:drag(gui, handle, options)
        options = options or {}
        local dragging = false
        local activeType
        local origin
        local startPos
        local moved = false

        handle.InputBegan:Connect(function(input)
            if not isPrimaryPress(input.UserInputType) then return end
            if Spectrum.DraggingLocked and options.IgnoreLock ~= true then
                return
            end
            dragging   = true
            activeType = input.UserInputType
            origin     = Vector2.new(input.Position.X, input.Position.Y)
            if gui.Position.X.Scale ~= 0 or gui.Position.Y.Scale ~= 0 then
                local _p = getAnchorPixelPosition(gui)
                applyFloatingAnchorPixels(gui, _p.X, _p.Y)
            end
            startPos = gui.Position
            moved = false
            if options.OnStart then
                task.spawn(options.OnStart, gui)
            end
        end)
        UIS.InputEnded:Connect(function(input)
            if not dragging then return end
            if activeType == Enum.UserInputType.Touch then
                if input.UserInputType ~= Enum.UserInputType.Touch then return end
            elseif input.UserInputType ~= Enum.UserInputType.MouseButton1 then
                return
            end
            dragging = false
            if moved and options.ResolveOverlap ~= false then
                resolveGuiOverlap(gui, options.Mode == "panel" and "panel" or "floating")
            end
            if options.OnReleased then
                task.spawn(options.OnReleased, gui, moved)
            end
        end)
        UIS.InputChanged:Connect(function(input)
            if not dragging then return end
            if activeType == Enum.UserInputType.Touch then
                if input.UserInputType ~= Enum.UserInputType.Touch then return end
            elseif input.UserInputType ~= Enum.UserInputType.MouseMovement then
                return
            end
            local s     = Scaler.Scale > 0 and Scaler.Scale or 1
            local delta = Vector2.new(input.Position.X, input.Position.Y) - origin
            local nextX = startPos.X.Offset + delta.X / s
            local nextY = startPos.Y.Offset + delta.Y / s
            moved = moved or delta.Magnitude >= 4

            if options.Mode == "panel" then
                applyPanelOffset(gui, nextX, nextY, s)
            else
                applyFloatingOffset(gui, nextX, nextY)
            end
        end)
    end

    function kit:rescale(scaler)
        local vp      = workspace.CurrentCamera.ViewportSize
        if vp.X < 1 or vp.Y < 1 then return end
        local preset = getLayoutPresetConfig()
        local total   = math.max(Spectrum.PanelCount or 1, 1)
        local columns = math.max(1, math.min(total, preset.MaxColumns or total))
        local needed  = columns * COL_W + math.max(columns - 1, 0) * (preset.HorizontalGap or PANEL_GAP) + 24
        local minScale = IS_MOBILE and 0.45 or 0.25
        local maxScale = IS_MOBILE and 1.0 or 1.6
        local widthScale = vp.X / needed
        local heightScale = (vp.Y - getTopInsetPixels() - 24) / (HDR_H + 300)
        local natural = math.clamp(math.min(widthScale, heightScale), minScale, maxScale)
        local userScale = math.clamp(tonumber(Spectrum.UserScale) or 1, 0.7, 1.4)
        local presetScale = preset.ScaleMultiplier or 1
        local s = Spectrum.canScale == false and 1 or math.clamp(natural * userScale * presetScale, minScale, maxScale)
        scaler.Scale  = s
        kit:repositionPanels(s)
    end

    function kit:refreshPanelBodies()
        for _, updater in ipairs(Spectrum.PanelUpdaters or {}) do
            updater(false)
        end
    end
end

function Spectrum.GetThemeState()
    local palette = kit:readPalette(true)
    return {
        Palette = {
            H = palette.H or DEFAULT_PALETTE.H,
            S = palette.S or DEFAULT_PALETTE.S,
            V = palette.V or DEFAULT_PALETTE.V,
        },
        RainbowMode = Spectrum.RainbowMode == true,
        RainbowSpeed = Spectrum.RainbowSpeed or 1750,
        AnimationSpeed = Spectrum.AnimationSpeed or 1,
        GlowSpeed = Spectrum.GlowSpeed or 1.5,
        SecondaryColor = packColor(Spectrum.SecondaryColor or DEFAULT_SECONDARY),
        FontColor = packColor(Spectrum.FontColor or DEFAULT_FONT_COLOR),
    }
end

function Spectrum.SetPalette(color)
    local current = kit:readPalette(true)
    if typeof(color) == "table" then
        kit:writePalette({
            H = color.H or current.H,
            S = color.S or current.S,
            V = color.V or current.V,
        })
        return
    end

    kit:writePalette(color)
end

function Spectrum.SetRainbowMode(enabled)
    Spectrum.RainbowMode = enabled == true
    if Spectrum.PaletteSync then
        Spectrum.PaletteSync:Emit()
    end
end

function Spectrum.SetRainbowSpeed(speed)
    Spectrum.RainbowSpeed = math.max(250, math.floor(tonumber(speed) or 1750))
    if Spectrum.PaletteSync then
        Spectrum.PaletteSync:Emit()
    end
end

function Spectrum.SetSecondaryColor(color)
    Spectrum.SecondaryColor = normalizeColor(color, DEFAULT_SECONDARY)
    applyAccentPalette(kit:readPalette(true), Spectrum.SecondaryColor)
    if Spectrum.PaletteSync then
        Spectrum.PaletteSync:Emit()
    end
    return Spectrum.SecondaryColor
end

function Spectrum.SetFontColor(color)
    Spectrum.FontColor = normalizeColor(color, DEFAULT_FONT_COLOR)
    applyFontPalette(Spectrum.FontColor)
    if Spectrum.PaletteSync then
        Spectrum.PaletteSync:Emit()
    end
    return Spectrum.FontColor
end

function Spectrum.SetAnimationSpeed(speed)
    Spectrum.AnimationSpeed = math.clamp(tonumber(speed) or 1, 0.5, 2)
    refreshTweenInfo()
    return Spectrum.AnimationSpeed
end

function Spectrum.SetGlowSpeed(speed)
    Spectrum.GlowSpeed = math.clamp(tonumber(speed) or 1.5, 0.5, 3)
    return Spectrum.GlowSpeed
end

local PaletteSync  = Hook.new()
local ModuleSync   = Hook.new()
local BindSync     = Hook.new()
Spectrum.PaletteSync = PaletteSync
Spectrum.ModuleSync  = ModuleSync
Spectrum.BindSync    = BindSync

Spectrum.ColorUpdate  = PaletteSync
Spectrum.ButtonUpdate = ModuleSync

local Screen  = Instance.new("ScreenGui")
local Root    = Instance.new("Frame")
Scaler  = Instance.new("UIScale")
local showTooltip = function() end
local hideTooltip = function() end

Screen.Name            = "Spectrum"
Screen.ZIndexBehavior  = Enum.ZIndexBehavior.Sibling
Screen.IgnoreGuiInset  = true
Screen.DisplayOrder    = 9e9

Screen.ResetOnSpawn    = false

Root.Name                   = "Root"
Root.Parent                 = Screen
Root.BackgroundTransparency = 1
Root.Size                   = UDim2.new(1, 0, 1, 0)
Scaler.Parent = Screen

local easing    = { Enum.EasingStyle.Circular, Enum.EasingDirection.Out }
local panelTI
local accentTI

refreshTweenInfo = function()
    local speed = math.clamp(tonumber(Spectrum.AnimationSpeed) or 1, 0.4, 2.5)
    panelTI = TweenInfo.new(0.2 / speed, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
    hoverTI = TweenInfo.new(0.1 / speed, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    accentTI = TweenInfo.new(0.14 / speed, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
end

refreshTweenInfo()

local function playStoredTween(bucket, key, instance, info, props, onComplete)
    local current = bucket[key]
    if current then
        pcall(function()
            current:Cancel()
        end)
        bucket[key] = nil
    end

    local tween = Tween:Create(instance, info, props)
    bucket[key] = tween
    tween.Completed:Connect(function(state)
        if bucket[key] == tween then
            bucket[key] = nil
        end
        if onComplete then
            onComplete(state)
        end
    end)
    tween:Play()
    return tween
end

Spectrum.toggle = function()
    Root.Position = UDim2.new()
    hideTooltip()
    Root.Visible  = not Root.Visible
    if Root.Visible then
        if Spectrum.ResetPanelScrolls then
            Spectrum.ResetPanelScrolls()
        end
        task.defer(function()
            if Spectrum.ResetPanelScrolls then
                Spectrum.ResetPanelScrolls()
            end
            if kit and kit.refreshPanelBodies then
                kit:refreshPanelBodies()
            end
        end)
    end
end

function Spectrum.ResetPanelScrolls()
    local scrolls = Spectrum.PanelScrolls or {}
    for index = #scrolls, 1, -1 do
        local scroll = scrolls[index]
        if not scroll or not scroll.Parent then
            table.remove(scrolls, index)
        else
            scroll.CanvasPosition = Vector2.new(0, 0)
        end
    end
end

local function randomString()
    local length = math.random(10, 20)
    local array = {}
    for i = 1, length do
        array[i] = string.char(math.random(32, 126))
    end
    return table.concat(array)
end

local function isPhantomScreenGui(gui)
    if not gui or not gui:IsA("ScreenGui") then return false end

    local ok, tagged = pcall(function()
        return gui:GetAttribute("PhantomUI") == true
    end)
    if ok and tagged then
        return true
    end

    return gui.DisplayOrder == 2147483647
        and gui.IgnoreGuiInset == true
        and gui.ResetOnSpawn == false
        and gui:FindFirstChild("Root") ~= nil
        and gui:FindFirstChildWhichIsA("UIScale") ~= nil
end

local function cleanupPhantomScreens(parent)
    if not parent then return end

    for _, child in ipairs(parent:GetChildren()) do
        if child ~= Screen and isPhantomScreenGui(child) then
            pcall(function()
                child:Destroy()
            end)
        end
    end
end

Screen.Name = randomString()
Screen.DisplayOrder = 2147483647
Screen.ResetOnSpawn = false
pcall(function()
    Screen:SetAttribute("PhantomUI", true)
end)

local coreGui
pcall(function()
    coreGui = cloneref(game:GetService("CoreGui"))
end)

local playerGui
pcall(function()
    playerGui = cloneref(game:GetService("Players")).LocalPlayer.PlayerGui
end)

cleanupPhantomScreens(coreGui)
cleanupPhantomScreens(playerGui)

if setthreadidentity then
    setthreadidentity(8)
    Screen.Parent = cloneref(game:GetService("CoreGui"))
else
    Screen.Parent = cloneref(game:GetService("Players")).LocalPlayer.PlayerGui
end

local GlowRegistry = setmetatable({}, { __mode = "k" })
local TooltipState = {
    Target = nil,
    Pointer = nil,
}

local function registerGlow(frame, resolver)
    if not frame then
        return nil
    end
    GlowRegistry[frame] = resolver or function()
        return true
    end
    return frame
end

local function updateTooltipPosition(point)
    local tooltip = Spectrum.Tooltip
    if not tooltip then
        return
    end
    TooltipState.Pointer = point or UIS:GetMouseLocation()
    local viewport = getViewportSize()
    local width = tooltip.AbsoluteSize.X > 0 and tooltip.AbsoluteSize.X or 170
    local height = tooltip.AbsoluteSize.Y > 0 and tooltip.AbsoluteSize.Y or 26
    local pointer = TooltipState.Pointer
    local x = (pointer.X or 0) + 16
    local y = (pointer.Y or 0) + 12

    x = math.clamp(x, 6, math.max(6, viewport.X - width - 6))
    y = math.clamp(y, 6, math.max(6, viewport.Y - height - 6))
    local _tscale = (Scaler and Scaler.Scale and Scaler.Scale > 0) and Scaler.Scale or 1
    tooltip.Position = UDim2.new(0, math.floor(x / _tscale + 0.5), 0, math.floor(y / _tscale + 0.5))
end

do
    local tooltipFrame = Instance.new("Frame")
    tooltipFrame.Name = "Tooltip"
    tooltipFrame.Parent = Root
    tooltipFrame.Visible = false
    tooltipFrame.BackgroundColor3 = P.BASE2
    tooltipFrame.BorderSizePixel = 0
    tooltipFrame.ZIndex = 60
    tooltipFrame.AutomaticSize = Enum.AutomaticSize.Y
    tooltipFrame.Size = UDim2.new(0, 170, 0, 0)
    mkCorner(tooltipFrame, UDim.new(0, 3))
    mkBorder(tooltipFrame, P.EDGE_HI, 1, 0.12)
    mkPad(tooltipFrame, 4, 4, 7, 7)

    local tooltipGlow = Instance.new("Frame")
    tooltipGlow.Name = "Glow"
    tooltipGlow.Parent = tooltipFrame
    tooltipGlow.BackgroundColor3 = P.HUE
    tooltipGlow.BackgroundTransparency = 0.84
    tooltipGlow.BorderSizePixel = 0
    tooltipGlow.Size = UDim2.new(1, 0, 0.45, 0)
    tooltipGlow.ZIndex = 60
    local tooltipGlowFade = Instance.new("UIGradient")
    tooltipGlowFade.Rotation = 90
    tooltipGlowFade.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.1),
        NumberSequenceKeypoint.new(1, 1),
    })
    tooltipGlowFade.Parent = tooltipGlow

    local tooltipLabel = Instance.new("TextLabel")
    tooltipLabel.Name = "Text"
    tooltipLabel.Parent = tooltipFrame
    tooltipLabel.BackgroundTransparency = 1
    tooltipLabel.AutomaticSize = Enum.AutomaticSize.Y
    tooltipLabel.Size = UDim2.new(1, 0, 0, 0)
    tooltipLabel.Font = Enum.Font.GothamSemibold
    tooltipLabel.Text = ""
    tooltipLabel.TextColor3 = P.INK_HI
    tooltipLabel.TextSize = 9
    tooltipLabel.TextWrapped = true
    tooltipLabel.TextXAlignment = Enum.TextXAlignment.Left
    tooltipLabel.TextYAlignment = Enum.TextYAlignment.Top
    tooltipLabel.ZIndex = 61

    showTooltip = function(text, target)
        if not text or not target or not target.Parent then return end
        TooltipState.Target = target
        tooltipLabel.Text = tostring(text)
        tooltipFrame.Visible = true
        updateTooltipPosition(UIS:GetMouseLocation())
    end

    hideTooltip = function()
        TooltipState.Target = nil
        tooltipFrame.Visible = false
        tooltipLabel.Text = ""
    end

    Spectrum.Tooltip = tooltipFrame
    Spectrum.TooltipLabel = tooltipLabel

    kit:track(PaletteSync:Bind(function()
        tooltipFrame.BackgroundColor3 = P.BASE2
        tooltipGlow.BackgroundColor3 = P.HUE
        tooltipLabel.TextColor3 = P.INK_HI
    end))
end

kit:track(UIS.InputChanged:Connect(function(input)
    if Spectrum.Tooltip and Spectrum.Tooltip.Visible and isPointerMove(input.UserInputType) then
        updateTooltipPosition(input.Position)
    end
end))

kit:track(Root:GetPropertyChangedSignal("Visible"):Connect(function()
    if not Root.Visible then
        return
    end
    task.defer(function()
        if Spectrum.ResetPanelScrolls then
            Spectrum.ResetPanelScrolls()
        end
        if kit and kit.refreshPanelBodies then
            kit:refreshPanelBodies()
        end
    end)
end))

kit:track(Runner.RenderStepped:Connect(function()
    local pulse = os.clock() * math.max(0.25, tonumber(Spectrum.GlowSpeed) or 1.5)
    for frame, resolver in next, GlowRegistry do
        if not frame or not frame.Parent then
            GlowRegistry[frame] = nil
        else
            local active = resolver == nil or resolver() == true
            if active then
                local phase = 0
                pcall(function()
                    phase = frame.AbsolutePosition.Y * 0.015
                end)
                local alpha = 0.72 + (((math.sin(pulse + phase) + 1) * 0.5) * 0.12)
                frame.BackgroundTransparency = alpha
            else
                frame.BackgroundTransparency = 0.92
            end
        end
    end
end))

local function bindHoverTooltip(guiObject, text)
    if not guiObject or not text or text == "" then
        return
    end
    kit:track(guiObject.MouseEnter:Connect(function()
        showTooltip(text, guiObject)
    end))
    kit:track(guiObject.MouseLeave:Connect(function()
        hideTooltip()
    end))
end

kit:rescale(Scaler)
do
    local _vpDebounce = 0
    kit:track(workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
        kit:rescale(Scaler)
        kit:refreshPanelBodies()
        _vpDebounce = _vpDebounce + 1
        local tag = _vpDebounce
        task.delay(0.15, function()
            if tag == _vpDebounce then
                kit:rescale(Scaler)
                kit:refreshPanelBodies()
            end
        end)
    end))
end

Spectrum.rescale  = function() kit:rescale(Scaler) end
Spectrum.Scaler   = Scaler
Spectrum.Root     = Root
Spectrum.Screen   = Screen

Spectrum.UIScale   = Scaler
Spectrum.ClickGUI  = Root
Spectrum.ScreenGui = Screen
Spectrum.toggleGui = Spectrum.toggle
Spectrum.IsMobile  = IS_MOBILE

local MobileButtonStyleSync = Hook.new()

function Spectrum.GetMobileButtonStyle()
    local style = readMobileButtonStyle()
    return {
        Circle = style.Circle == true,
        Outline = style.Outline ~= false,
    }
end

function Spectrum.SetMobileButtonStyle(style)
    if type(style) ~= "table" then
        return Spectrum.GetMobileButtonStyle()
    end

    local current = readMobileButtonStyle()
    if style.Circle ~= nil then
        current.Circle = style.Circle == true
    end
    if style.Outline ~= nil then
        current.Outline = style.Outline == true
    end

    saveMobileUIState()
    MobileButtonStyleSync:Emit()
    if Spectrum.PaletteSync then
        Spectrum.PaletteSync:Emit()
    end
    return Spectrum.GetMobileButtonStyle()
end

local function updateMobileGradient(button, gradient, stroke, accent)
    local y = 0
    pcall(function()
        y = button.AbsolutePosition.Y
    end)

    local c0, c1, c2
    if kit:rainbowActive() then
        c0 = kit:rainbowColor(y)
        c1 = kit:rainbowColor(y + 180)
        c2 = kit:rainbowColor(y + 360)
    else
        accent = accent or kit:activeColor()
        c0 = accent
        c1 = accent:Lerp(Color3.new(1, 1, 1), 0.18)
        c2 = accent:Lerp(Color3.new(0, 0, 0), 0.18)
    end

    gradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, c0),
        ColorSequenceKeypoint.new(0.5, c1),
        ColorSequenceKeypoint.new(1, c2),
    })
    gradient.Rotation = 18
    if stroke then
        stroke.Color = accent or c0
    end
end

local function getMobileButtonSize(text, primary)
    text = tostring(text or "")
    local style = readMobileButtonStyle()
    local vp = getViewportSize()
    local height = math.clamp(math.floor(vp.Y * 0.065), primary and 42 or 48, primary and 52 or 62)
    if style.Circle then
        local diameter = math.clamp(math.floor(height + (#text * (primary and 1.8 or 2.2))), primary and 54 or 58, primary and 108 or 124)
        return UDim2.new(0, diameter, 0, diameter)
    end
    local width = math.clamp(math.floor(#text * (height * 0.45) + (primary and 48 or 60)), primary and 96 or 120, primary and 150 or 185)
    return UDim2.new(0, width, 0, height)
end

local function setFloatingButtonPosition(button, x, y)
    local clampedX, clampedY = clampAnchorPosition(button, x, y)
    button.Position = UDim2.fromScale(clampedX, clampedY)
    return clampedX, clampedY
end

local function styleFloatingButton(button, stateResolver)
    button.BackgroundColor3 = P.BASE1
    button.TextStrokeTransparency = 0.85

    local stroke = mkBorder(button, P.EDGE, 1, 0.08)
    local corner = button:FindFirstChildWhichIsA("UICorner") or mkCorner(button, UDim.new(0, 10))
    local gradient = Instance.new("UIGradient")
    gradient.Parent = button

    local function apply()
        local enabled, accent = true, nil
        local style = readMobileButtonStyle()
        if stateResolver then
            enabled, accent = stateResolver()
        end
        corner.CornerRadius = style.Circle and UDim.new(1, 0) or UDim.new(0, 10)
        button.BackgroundTransparency = enabled == false and 0.28 or 0.08
        button.TextColor3 = enabled == false and P.INK_MID or P.INK_HI
        updateMobileGradient(button, gradient, stroke, accent or kit:activeColor())
        stroke.Transparency = style.Outline == false and 1 or (enabled == false and 0.18 or 0.04)
    end

    apply()
    return {
        Stroke = stroke,
        Gradient = gradient,
        ThemeBinding = PaletteSync:Bind(apply),
        Refresh = apply,
    }
end

local function attachFloatingButton(button, options)
    local connections = {}
    local dragging = false
    local activeType
    local origin
    local startScale
    local moved = false
    local defaultTextSize = button.TextSize
    local defaultTextScaled = button.TextScaled
    local defaultTextWrapped = button.TextWrapped
    local defaultTextTruncate = button.TextTruncate

    local function connect(signal, callback)
        local conn = signal:Connect(callback)
        table.insert(connections, conn)
        return conn
    end

    local function getStore()
        return options and options.getStore and options.getStore() or nil
    end

    local function savePosition()
        local store = getStore()
        if type(store) == "table" then
            store.X = button.Position.X.Scale
            store.Y = button.Position.Y.Scale
            saveMobileUIState()
        end
    end

    local function refreshSize()
        local label = tostring((options and options.text) or button.Text or "")
        local style = readMobileButtonStyle()

        button.Text = label
        if style.Circle then
            button.TextScaled = true
            button.TextWrapped = true
            button.TextTruncate = Enum.TextTruncate.None
        else
            button.TextSize = defaultTextSize
            button.TextScaled = defaultTextScaled
            button.TextWrapped = defaultTextWrapped
            button.TextTruncate = defaultTextTruncate
        end

        button.Size = getMobileButtonSize(label, options and options.primary == true)
        setFloatingButtonPosition(button, button.Position.X.Scale, button.Position.Y.Scale)
    end

    local startX = options and options.defaultX or 0.5
    local startY = options and options.defaultY or 0.5
    local store = getStore()
    if store then
        startX, startY = readMobilePoint(store, startX, startY)
        store.X, store.Y = startX, startY
    end

    refreshSize()
    setFloatingButtonPosition(button, startX, startY)

    connect(button.InputBegan, function(input)
        if not isPrimaryPress(input.UserInputType) then return end
        dragging = true
        activeType = input.UserInputType
        origin = Vector2.new(input.Position.X, input.Position.Y)
        startScale = Vector2.new(button.Position.X.Scale, button.Position.Y.Scale)
        moved = false
    end)

    connect(UIS.InputChanged, function(input)
        if not dragging then return end
        if activeType == Enum.UserInputType.Touch then
            if input.UserInputType ~= Enum.UserInputType.Touch then return end
        elseif input.UserInputType ~= Enum.UserInputType.MouseMovement then
            return
        end

        local vp = getViewportSize()
        local delta = Vector2.new(input.Position.X, input.Position.Y) - origin
        if delta.Magnitude >= 8 then
            moved = true
        end

        local posPx = Vector2.new(startScale.X * vp.X, startScale.Y * vp.Y) + delta
        local x, y = clampAnchorPosition(button, posPx.X / vp.X, posPx.Y / vp.Y)
        button.Position = UDim2.fromScale(x, y)
    end)

    connect(UIS.InputEnded, function(input)
        if not dragging then return end
        if activeType == Enum.UserInputType.Touch then
            if input.UserInputType ~= Enum.UserInputType.Touch then return end
        elseif input.UserInputType ~= Enum.UserInputType.MouseButton1 then
            return
        end

        dragging = false
        savePosition()
        if not moved and options and options.onTap then
            options.onTap()
        end
    end)

    local camera = workspace.CurrentCamera
    if camera then
        connect(camera:GetPropertyChangedSignal("ViewportSize"), refreshSize)
    end
    table.insert(connections, MobileButtonStyleSync:Bind(refreshSize))

    return {
        RefreshSize = refreshSize,
        SavePosition = savePosition,
        Destroy = function()
            for _, conn in ipairs(connections) do
                if conn and conn.Disconnect then
                    conn:Disconnect()
                end
            end
        end,
    }
end

local MobileOpenButton
local function ensureMobileOpenButton()
    if not IS_MOBILE or MobileOpenButton then return end

    local openStore = MobileUIState.Open
    openStore.X, openStore.Y = readMobilePoint(openStore, 0.14, 0.82)

    local button = Instance.new("TextButton")
    button.Name = "MobileOpen"
    button.Parent = Screen
    button.AnchorPoint = Vector2.new(0.5, 0.5)
    button.AutoButtonColor = false
    button.BorderSizePixel = 0
    button.BackgroundColor3 = P.BASE1
    button.Font = Enum.Font.GothamBold
    button.Text = "open"
    button.TextSize = 13
    button.ZIndex = 30
    mkCorner(button, UDim.new(0, 10))

    local theme = styleFloatingButton(button, function()
        return not Root.Visible, kit:activeColor()
    end)
    local handle = attachFloatingButton(button, {
        text = "open",
        primary = true,
        defaultX = openStore.X,
        defaultY = openStore.Y,
        getStore = function() return MobileUIState.Open end,
        onTap = function()
            Spectrum.toggle()
            theme.Refresh()
        end,
    })
    local visibleSync = Root:GetPropertyChangedSignal("Visible"):Connect(theme.Refresh)

    MobileOpenButton = {
        Instance = button,
        Theme = theme,
        Handle = handle,
        VisibleSync = visibleSync,
    }
end

if IS_MOBILE then
    ensureMobileOpenButton()
end

kit:track(PaletteSync:Bind(function()
    local col      = kit:readPalette()
    P.HUE          = col
    P.HUE_FADE     = col:Lerp(Color3.new(0, 0, 0),   0.45)
    P.EDGE_HI      = col:Lerp(Color3.new(0, 0, 0.5), 0.30)
    P.BASE_LIT     = col:Lerp(Color3.new(0, 0, 0),   0.55)

    if Spectrum.Registry then
        for _, v in next, Spectrum.Registry do
            if v.Type == "OptionsButton" and v.API.Enabled then
                v.Instance.BackgroundColor3 = P.BASE_LIT
            end
        end
    end
end))

kit:track(Runner.PreRender:Connect(function()
    if not Spectrum.RainbowMode then return end
    local old = Spectrum.Palette or {}
    local h   = (old.H or 0) + 0.001
    if h >= 1 then h = h - 1 end
    kit:writePalette({ H = h, S = old.S or 1, V = old.V or 1 })
end))

local stateColors   = { on = {68,192,82}, off = {212,60,65}, warn = {212,168,27} }
local toastQueue    = {}
local slideTime     = 0.16
local toastGap      = 0.002

Spectrum.toast = function(titleStr, bodyStr, duration, hlWord)
    if not getgenv().configloaded then return end
    coroutine.wrap(function()
        local card = Instance.new("ImageLabel")
        card.Parent               = Screen
        card.BorderSizePixel      = 0
        card.Size                 = UDim2.new(0.13, 0, 0.082, 0)
        card.Position             = UDim2.new(1, 0, 0, 0)
        card.BackgroundTransparency = 1
        card.Image               = tryGetCustomAsset("Phantom/storage/assets/background.png")
        card.ImageColor3         = P.BASE1
        card.ScaleType           = Enum.ScaleType.Slice
        card.SliceCenter         = Rect.new(8, 8, 92, 100)
        mkCorner(card, R_MD); mkBorder(card, P.EDGE, 1)

        local progBack = Instance.new("Frame")
        progBack.Parent             = card
        progBack.BackgroundColor3   = P.BASE2
        progBack.BorderSizePixel    = 0
        progBack.Position           = UDim2.new(0, 0, 0.92, 0)
        progBack.Size               = UDim2.new(1, 0, 0.08, 0)
        mkCorner(progBack, UDim.new(0, 2))

        local progFill = Instance.new("Frame")
        progFill.Parent           = progBack
        progFill.BackgroundColor3 = P.HUE
        progFill.BackgroundTransparency = 0.15
        progFill.BorderSizePixel  = 0
        progFill.Size             = UDim2.new(1, 0, 1, 0)
        mkCorner(progFill, UDim.new(0, 2))

        local titleLbl = Instance.new("TextLabel")
        titleLbl.Parent               = card
        titleLbl.BackgroundTransparency = 1
        titleLbl.BorderSizePixel      = 0
        titleLbl.Position             = UDim2.new(0.06, 0, 0.1, 0)
        titleLbl.Size                 = UDim2.new(0.88, 0, 0.32, 0)
        titleLbl.Font                 = Enum.Font.GothamBold
        titleLbl.TextColor3           = P.INK_HI
        titleLbl.TextScaled           = true
        titleLbl.TextWrapped          = true
        titleLbl.TextXAlignment       = Enum.TextXAlignment.Left
        titleLbl.RichText             = true

        local bodyLbl = Instance.new("TextLabel")
        bodyLbl.Parent              = card
        bodyLbl.BackgroundTransparency = 1
        bodyLbl.BorderSizePixel     = 0
        bodyLbl.Position            = UDim2.new(0.06, 0, 0.46, 0)
        bodyLbl.Size                = UDim2.new(0.88, 0, 0.30, 0)
        bodyLbl.Font                = Enum.Font.GothamSemibold
        bodyLbl.TextColor3          = P.INK_MID
        bodyLbl.TextScaled          = true
        bodyLbl.TextWrapped         = true
        bodyLbl.TextXAlignment      = Enum.TextXAlignment.Left
        bodyLbl.RichText            = true

        local aspect = Instance.new("UIAspectRatioConstraint")
        aspect.Parent      = card
        aspect.AspectRatio = 3.4

        titleLbl.Text = titleStr
        if hlWord then
            local nc = stateColors.warn
            bodyLbl.Text = bodyStr:gsub(hlWord,
                ('<font color="rgb(%d,%d,%d)">%s</font>'):format(nc[1], nc[2], nc[3], hlWord))
        elseif type(bodyStr) == "boolean" then
            local nc  = bodyStr and stateColors.on or stateColors.off
            local tag = bodyStr and "Enabled!" or "Disabled!"
            bodyLbl.Text = ('%s has been <font color="rgb(%d,%d,%d)">%s</font>'):format(
                titleStr, nc[1], nc[2], nc[3], tag)
        else
            bodyLbl.Text = bodyStr or titleStr
        end

        local delay = duration or 3
        table.insert(toastQueue, { card = card, bar = progBack, duration = delay })

        for i, item in ipairs(toastQueue) do
            local tY = 0.9 - (card.Size.Y.Scale + toastGap - 0.004) * (i - 1)
            item.card.Position = UDim2.new(0.87, 0, tY, 0)
        end

        card.Position = UDim2.new(1, 0, card.Position.Y.Scale, 0)
        Tween:Create(card, TweenInfo.new(slideTime, unpack(easing)),
            { Position = UDim2.new(0.87, 0, card.Position.Y.Scale, 0) }):Play()
        Tween:Create(progFill, TweenInfo.new(delay - 0.2, unpack(easing)),
            { Size = UDim2.new(0, 0, 1, 0) }):Play()

        task.delay(delay + slideTime / 2, function()
            Tween:Create(card, TweenInfo.new(slideTime, unpack(easing)),
                { Position = UDim2.new(1, 0, card.Position.Y.Scale, 0) }):Play()
            task.delay(slideTime, function()
                for i, item in ipairs(toastQueue) do
                    if item.card == card then table.remove(toastQueue, i); break end
                end
                for i, item in ipairs(toastQueue) do
                    local tY = 0.9 - (card.Size.Y.Scale - toastGap) * (i - 1)
                    Tween:Create(item.card, TweenInfo.new(slideTime, unpack(easing)),
                        { Position = UDim2.new(0.87, 0, tY, 0) }):Play()
                end
                card:Destroy()
            end)
        end)
    end)()
end


Spectrum.createNotification = Spectrum.toast

local LAYOUT_FILE = IS_MOBILE and "Phantom/storage/config/layout.mobile.json" or "Phantom/storage/config/layout.json"

local function normalizePanelLayoutMap(data)
    local normalized = {}
    for name, info in next, data or {} do
        if type(info) == "table" then
            local x = tonumber(info.X)
            local y = tonumber(info.Y)
            if x and y then
                normalized[name] = {
                    X = math.floor(x + 0.5),
                    Y = math.floor(y + 0.5),
                    Manual = info.Manual ~= false,
                }
            end
        end
    end
    return normalized
end

local function normalizeFloatingLayoutMap(data)
    local normalized = {}
    for name, info in next, data or {} do
        if type(info) == "table" then
            local anchorX, anchorY = readStoredAnchorPoint(info)
            if anchorX and anchorY or info.Left ~= nil or info.Right ~= nil or info.CenterX ~= nil then
                normalized[name] = {
                    AnchorX = math.clamp(anchorX or tonumber(info.AnchorX) or 0.5, 0, 1),
                    AnchorY = math.clamp(anchorY or tonumber(info.AnchorY) or 0.5, 0, 1),
                    Left = tonumber(info.Left),
                    Right = tonumber(info.Right),
                    Top = tonumber(info.Top),
                    Bottom = tonumber(info.Bottom),
                    CenterX = tonumber(info.CenterX),
                    CenterY = tonumber(info.CenterY),
                    ModeX = tostring(info.ModeX or "center"),
                    ModeY = tostring(info.ModeY or "center"),
                    ViewportX = tonumber(info.ViewportX),
                    ViewportY = tonumber(info.ViewportY),
                }
            end
        end
    end
    return normalized
end

local function readLayout()
    local ok, data = pcall(function()
        return HttpService:JSONDecode(readfile(LAYOUT_FILE))
    end)
    if not ok or type(data) ~= "table" then
        return {
            Panels = {},
            Floaters = {},
            DragLocked = false,
            Preset = "default",
            Scale = 1,
        }
    end

    if data.Panels or data.Floaters or data.DragLocked ~= nil then
        return {
            Panels = normalizePanelLayoutMap(data.Panels or {}),
            Floaters = normalizeFloatingLayoutMap(data.Floaters or {}),
            DragLocked = data.DragLocked == true,
            Preset = string.lower(tostring(data.Preset or "default")),
            Scale = math.clamp(tonumber(data.Scale) or 1, 0.7, 1.4),
        }
    end

    return {
        Panels = normalizePanelLayoutMap(data),
        Floaters = {},
        DragLocked = false,
        Preset = "default",
        Scale = 1,
    }
end

local function writeLayout()
    local positions = {
        Version = 3,
        Panels = {},
        Floaters = {},
        DragLocked = Spectrum.DraggingLocked == true,
        Preset = Spectrum.ActiveLayoutPreset or "default",
        Scale = Spectrum.UserScale or 1,
    }
    for _, bar in ipairs(Spectrum.PanelBars or {}) do
        positions.Panels[bar.Name] = {
            X = bar.Position.X.Offset,
            Y = bar.Position.Y.Offset,
            Manual = getPanelManual(bar),
        }
    end
    for name, record in next, FloatingLayoutRecords do
        if record and record.Frame and record.Frame.Parent and record.Persist ~= false then
            positions.Floaters[name] = captureResponsiveFloatingLayout(record.Frame)
        end
    end
    pcall(function()
        if not isfolder("Phantom/storage/config") then makefolder("Phantom/storage/config") end
        writefile(LAYOUT_FILE, HttpService:JSONEncode(positions))
    end)
    Spectrum.LayoutState = positions
    Spectrum.Layout = positions.Panels
    Spectrum.FloatingLayout = positions.Floaters
end

Spectrum.LayoutState        = readLayout()
Spectrum.Layout             = Spectrum.LayoutState.Panels
Spectrum.FloatingLayout     = Spectrum.LayoutState.Floaters
Spectrum.DraggingLocked     = Spectrum.LayoutState.DragLocked == true
Spectrum.ActiveLayoutPreset = PANEL_LAYOUT_PRESETS[Spectrum.LayoutState.Preset] and Spectrum.LayoutState.Preset or "default"
Spectrum.UserScale          = math.clamp(tonumber(Spectrum.LayoutState.Scale) or 1, 0.7, 1.4)
Spectrum.saveTabPositions   = writeLayout
Spectrum.SaveLayout         = writeLayout
Spectrum.TabPositions       = Spectrum.Layout

local function registerFloatingLayout(name, frame, options)
    if not name or not frame then
        return nil
    end
    local record = {
        Name = name,
        Frame = frame,
        Persist = not (options and options.Persist == false),
        DefaultPosition = options and options.DefaultPosition or frame.Position,
        OnRestore = options and options.OnRestore or nil,
    }
    record.DefaultLayout = captureResponsiveFloatingLayout(frame)
    FloatingLayoutRecords[name] = record
    return record
end

local function restoreFloatingLayout(name)
    local record = FloatingLayoutRecords[name]
    if not record or not record.Frame then
        return false
    end
    if record.DefaultLayout and applyResponsiveFloatingLayout(record.Frame, record.DefaultLayout) then
        if record.OnRestore then
            record.OnRestore(record.Frame)
        end
        return true
    end
    if typeof(record.DefaultPosition) == "UDim2" then
        local parent = record.Frame.Parent
        local parentSize = parent and parent.AbsoluteSize or getViewportSize()
        local position = record.DefaultPosition
        local scale = (Scaler and Scaler.Scale and Scaler.Scale > 0) and Scaler.Scale or 1
        applyFloatingAnchorPixels(
            record.Frame,
            (position.X.Scale * parentSize.X) + (position.X.Offset * scale),
            (position.Y.Scale * parentSize.Y) + (position.Y.Offset * scale)
        )
        if record.OnRestore then
            record.OnRestore(record.Frame)
        end
        return true
    end
    return false
end

local function makeBarDraggable(bar)
    local dragging, moved = false, false
    local activeType
    local origin
    local startPos
    local wasManual = false

    bar.InputBegan:Connect(function(input)
        if not isPrimaryPress(input.UserInputType) then return end
        if Spectrum.DraggingLocked then return end

        dragging = true
        moved = false
        activeType = input.UserInputType
        wasManual = getPanelManual(bar)
        origin = Vector2.new(input.Position.X, input.Position.Y)
        startPos = bar.Position

        playTween(bar, hoverTI, { BackgroundColor3 = P.BASE_HOV })
    end)

    UIS.InputEnded:Connect(function(input)
        if not dragging then return end

        if activeType == Enum.UserInputType.Touch then
            if input.UserInputType ~= Enum.UserInputType.Touch then return end
        elseif input.UserInputType ~= Enum.UserInputType.MouseButton1 then
            return
        end

        dragging = false
        playTween(bar, hoverTI, { BackgroundColor3 = P.BASE2 })

        if moved then
            applyPanelOffset(bar, bar.Position.X.Offset, bar.Position.Y.Offset)
            if kit and kit.resolveGuiOverlap then
                kit.resolveGuiOverlap(bar, "panel")
            end
            writeLayout()
        else
            setPanelManual(bar, wasManual)
        end
    end)

    UIS.InputChanged:Connect(function(input)
        if not dragging then return end

        if activeType == Enum.UserInputType.Touch then
            if input.UserInputType ~= Enum.UserInputType.Touch then return end
        elseif input.UserInputType ~= Enum.UserInputType.MouseMovement then
            return
        end

        local s = Scaler.Scale > 0 and Scaler.Scale or 1
        local delta = Vector2.new(input.Position.X, input.Position.Y) - origin
        local newX = startPos.X.Offset + (delta.X / s)
        local newY = startPos.Y.Offset + (delta.Y / s)

        if not moved then
            moved = true
            setPanelManual(bar, true)
        end

        applyPanelOffset(bar, newX, newY, s)
    end)
end

function Spectrum.GetDraggingLocked()
    return Spectrum.DraggingLocked == true
end

function Spectrum.SetDraggingLocked(locked)
    Spectrum.DraggingLocked = locked == true
    if Spectrum.SaveLayout then
        Spectrum.SaveLayout()
    end
    return Spectrum.DraggingLocked
end

function Spectrum.ResetLayout()
    Spectrum.ActiveLayoutPreset = "default"
    Spectrum.UserScale = 1
    for _, bar in ipairs(Spectrum.PanelBars or {}) do
        setPanelManual(bar, false)
    end
    kit:rescale(Scaler)
    for name in next, FloatingLayoutRecords do
        restoreFloatingLayout(name)
    end
    if Spectrum.SaveLayout then
        Spectrum.SaveLayout()
    end
end

function Spectrum.ResetPositions()
    for _, bar in ipairs(Spectrum.PanelBars or {}) do
        setPanelManual(bar, false)
    end
    kit:repositionPanels((Scaler and Scaler.Scale and Scaler.Scale > 0) and Scaler.Scale or 1)
    for name in next, FloatingLayoutRecords do
        restoreFloatingLayout(name)
    end
    if Spectrum.SaveLayout then
        Spectrum.SaveLayout()
    end
end

function Spectrum.ResetScale()
    Spectrum.UserScale = 1
    kit:rescale(Scaler)
    if Spectrum.SaveLayout then
        Spectrum.SaveLayout()
    end
    return Spectrum.UserScale
end

function Spectrum.SetScaleMultiplier(value)
    Spectrum.UserScale = math.clamp(tonumber(value) or 1, 0.7, 1.4)
    kit:rescale(Scaler)
    if Spectrum.SaveLayout then
        Spectrum.SaveLayout()
    end
    return Spectrum.UserScale
end

function Spectrum.GetScaleMultiplier()
    return Spectrum.UserScale or 1
end

function Spectrum.GetLayoutPreset()
    return Spectrum.ActiveLayoutPreset or "default"
end

function Spectrum.ApplyLayoutPreset(name)
    local normalized = string.lower(tostring(name or "default"))
    if not PANEL_LAYOUT_PRESETS[normalized] then
        normalized = "default"
    end

    Spectrum.ActiveLayoutPreset = normalized
    for _, bar in ipairs(Spectrum.PanelBars or {}) do
        setPanelManual(bar, false)
    end
    kit:rescale(Scaler)
    for floaterName in next, FloatingLayoutRecords do
        restoreFloatingLayout(floaterName)
    end
    if Spectrum.SaveLayout then
        Spectrum.SaveLayout()
    end
    return normalized
end

function Spectrum.GetLayoutPresets()
    local list = {}
    for key in pairs(PANEL_LAYOUT_PRESETS) do
        list[#list + 1] = key
    end
    table.sort(list)
    return list
end

function Spectrum.FactoryResetUI()
    Spectrum.ActiveLayoutPreset = "default"
    Spectrum.UserScale = 1
    Spectrum.RainbowMode = false
    Spectrum.RainbowSpeed = 1750
    Spectrum.AnimationSpeed = 1
    Spectrum.GlowSpeed = 1.5
    Spectrum.SecondaryColor = DEFAULT_SECONDARY
    Spectrum.FontColor = DEFAULT_FONT_COLOR
    kit:writePalette(DEFAULT_PALETTE)
    Spectrum.SetSecondaryColor(DEFAULT_SECONDARY)
    Spectrum.SetFontColor(DEFAULT_FONT_COLOR)
    Spectrum.ResetLayout()
end

function Spectrum.window(cfg)
    local panel  = { Open = true }
    local panelId = cfg.Name .. "Panel"
    local displayName = cfg.Title or cfg.Name

    Spectrum.PanelCount    = (Spectrum.PanelCount or 0) + 1
    Spectrum.PanelBars     = Spectrum.PanelBars or {}
    Spectrum.PanelUpdaters = Spectrum.PanelUpdaters or {}
    Spectrum.PanelScrolls  = Spectrum.PanelScrolls or {}
    kit:nextSlot()

    local Header = Instance.new("TextButton", Root)
    Header.Name             = cfg.Name .. "Header"
    Header.BackgroundColor3 = P.BASE2
    Header.BorderSizePixel  = 0
    Header.Position         = UDim2.new(0, 0, 0, getPanelTopOffset())
    Header.Size             = UDim2.new(0, COL_W, 0, HDR_H)
    Header.AutoButtonColor  = false
    Header.Font             = FONT_HDR
    Header.Text             = ""
    Header.TextColor3       = P.INK_HI
    Header.TextSize         = 10
    Header.Modal            = true
    mkCorner(Header, R_SM)
    local headerEdge = mkBorder(Header, P.EDGE, 1, 0.12)

    local HeaderGlow = Instance.new("Frame")
    HeaderGlow.Name = "Glow"
    HeaderGlow.Parent = Header
    HeaderGlow.BackgroundColor3 = P.HUE
    HeaderGlow.BackgroundTransparency = 0.92
    HeaderGlow.BorderSizePixel = 0
    HeaderGlow.Size = UDim2.new(1, 0, 0.55, 0)
    HeaderGlow.ZIndex = 1
    local headerGlowFade = Instance.new("UIGradient")
    headerGlowFade.Rotation = 90
    headerGlowFade.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.12),
        NumberSequenceKeypoint.new(1, 1),
    })
    headerGlowFade.Parent = HeaderGlow

    table.insert(Spectrum.PanelBars, Header)
    local saved = Spectrum.Layout[cfg.Name .. "Header"]
    setPanelManual(Header, saved and saved.Manual == true)
    if saved and getPanelManual(Header) then
        applyPanelOffset(Header, saved.X, getPanelTopOffset(), (Scaler.Scale > 0 and Scaler.Scale or 1))
    else
        setPanelManual(Header, false)
        kit:rescale(Scaler)
    end
    makeBarDraggable(Header)

    local showHeaderIcon = cfg.ShowIcon == true and cfg.Icon ~= nil
    local headerTextLeft = 0
    local headerTextRight = -14

    if showHeaderIcon then
        local HdrIcon = Instance.new("ImageLabel")
        HdrIcon.Parent             = Header
        HdrIcon.BackgroundTransparency = 1
        HdrIcon.BorderSizePixel    = 0
        HdrIcon.Position           = UDim2.new(0, 6, 0.5, -5)
        HdrIcon.Size               = UDim2.new(0, 10, 0, 10)
        HdrIcon.Image              = cfg.Icon
        HdrIcon.ImageColor3        = P.INK_HI
        HdrIcon.ImageRectOffset    = cfg.IconOffset or Vector2.new(4, 4)
        HdrIcon.ImageRectSize      = cfg.IconSize or Vector2.new(36, 36)
        HdrIcon.ScaleType          = Enum.ScaleType.Fit
        HdrIcon.ZIndex             = 2
        headerTextLeft = 18
        headerTextRight = -22
    end

    local HdrTitle = Instance.new("TextLabel")
    HdrTitle.Name               = "Name"; HdrTitle.Parent = Header
    HdrTitle.BackgroundTransparency = 1; HdrTitle.Position = UDim2.new(0, headerTextLeft, 0, 0)
    HdrTitle.Size               = UDim2.new(1, headerTextRight - headerTextLeft, 1, 0); HdrTitle.ZIndex = 2
    HdrTitle.Font               = FONT_HDR; HdrTitle.Text = displayName
    HdrTitle.TextColor3         = P.INK_HI; HdrTitle.TextSize = TEXT_SIZE_SM
    HdrTitle.TextXAlignment     = showHeaderIcon and Enum.TextXAlignment.Left or Enum.TextXAlignment.Center

    local CollapseBtn = Instance.new("ImageButton")
    CollapseBtn.Name               = "Collapse"; CollapseBtn.Parent = Header
    CollapseBtn.BackgroundTransparency = 1; CollapseBtn.BorderSizePixel = 0
    CollapseBtn.Position           = UDim2.new(1, -12, 0.5, -4)
    CollapseBtn.Rotation           = 180; CollapseBtn.Size = UDim2.new(0, 8, 0, 8)
    CollapseBtn.ZIndex             = 2
    CollapseBtn.Image              = "http://www.roblox.com/asset/?id=6031094679"
    CollapseBtn.ImageColor3        = P.INK_MID; CollapseBtn.ScaleType = Enum.ScaleType.Fit

    local Body = Instance.new("Frame")
    Body.Name                   = "Body"; Body.Parent = Header
    Body.BackgroundColor3       = P.BASE1
    Body.BackgroundTransparency = 0
    Body.BorderSizePixel        = 0
    Body.ClipsDescendants       = true
    Body.Position               = UDim2.new(0, 0, 1, 1)
    Body.Size                   = UDim2.new(0, COL_W, 0, 0)
    mkCorner(Body, R_SM)
    local bodyEdge = mkBorder(Body, P.EDGE, 1, 0.14)

    local BodyGlow = Instance.new("Frame")
    BodyGlow.Name = "Glow"
    BodyGlow.Parent = Body
    BodyGlow.BackgroundColor3 = P.HUE_FADE
    BodyGlow.BackgroundTransparency = 0.95
    BodyGlow.BorderSizePixel = 0
    BodyGlow.Size = UDim2.new(1, 0, 0.6, 0)
    BodyGlow.ZIndex = 0
    local bodyGlowFade = Instance.new("UIGradient")
    bodyGlowFade.Rotation = 90
    bodyGlowFade.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.18),
        NumberSequenceKeypoint.new(1, 1),
    })
    bodyGlowFade.Parent = BodyGlow

    local BodyScroll = Instance.new("ScrollingFrame")
    BodyScroll.Name                  = "BodyScroll"; BodyScroll.Parent = Body
    BodyScroll.BackgroundTransparency = 1; BodyScroll.BorderSizePixel = 0
    BodyScroll.Size                  = UDim2.new(1, 0, 1, 0)
    BodyScroll.CanvasSize            = UDim2.new(0, 0, 0, 0)
    BodyScroll.ScrollBarThickness    = 1
    BodyScroll.ScrollBarImageColor3  = P.INK_LOW
    BodyScroll.ScrollingDirection    = Enum.ScrollingDirection.Y
    table.insert(Spectrum.PanelScrolls, BodyScroll)

    local EntryHolder = Instance.new("Frame")
    EntryHolder.Name                   = "EntryHolder"; EntryHolder.Parent = BodyScroll
    EntryHolder.BackgroundTransparency = 1; EntryHolder.BorderSizePixel = 0
    EntryHolder.Size                   = UDim2.new(0, COL_W, 0, 0)

    local Flow = Instance.new("UIListLayout")
    Flow.Padding             = UDim.new(0, 1)
    Flow.Parent              = EntryHolder
    Flow.HorizontalAlignment = Enum.HorizontalAlignment.Center
    Flow.VerticalAlignment   = Enum.VerticalAlignment.Top
    Flow.SortOrder           = Enum.SortOrder.LayoutOrder
    mkPad(EntryHolder, 3, 3, 0, 0)

    local function applyPanelSkin()
        Header.BackgroundColor3 = P.BASE2
        headerEdge.Color = P.EDGE
        Body.BackgroundColor3 = P.BASE1
        bodyEdge.Color = P.EDGE
        HeaderGlow.BackgroundColor3 = P.HUE
        BodyGlow.BackgroundColor3 = P.HUE_FADE
        HdrTitle.TextColor3 = P.INK_HI
    end

    applyPanelSkin()
    kit:track(PaletteSync:Bind(applyPanelSkin))

    function panel.Update(instant)
        local scale = (Scaler.Scale > 0 and Scaler.Scale or 1)
        local sz = Flow.AbsoluteContentSize
        local fullH = math.max(0, (sz.Y + 10) / scale)
        local vp = getViewportSize()
        local maxH = math.max(72, vp.Y / scale - (getPanelTopOffset() + HDR_H + 18))
        local cappedH = math.min(fullH, maxH)
        local targetHeight = panel.Open and cappedH or 0

        EntryHolder.Size = UDim2.new(0, COL_W, 0, sz.Y / scale)
        BodyScroll.CanvasSize = UDim2.new(0, 0, 0, fullH)
        BodyScroll.Active = panel.Open
        BodyScroll.ScrollingEnabled = panel.Open

        local maxCanvasY = math.max(0, fullH - targetHeight)
        if BodyScroll.CanvasPosition.Y > maxCanvasY then
            BodyScroll.CanvasPosition = Vector2.new(BodyScroll.CanvasPosition.X, maxCanvasY)
        end

        if instant then
            Body.Size = UDim2.new(0, COL_W, 0, targetHeight)
        else
            playStoredTween(panel, "_bodyTween", Body, panelTI, {
                Size = UDim2.new(0, COL_W, 0, targetHeight),
            })
        end
    end

    kit:track(Flow:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        panel.Update(false)
    end))
    table.insert(Spectrum.PanelUpdaters, panel.Update)

    function panel.SetOpen(open, instant)
        panel.Open = open == true
        if panel.Open then
            BodyScroll.CanvasPosition = Vector2.new(0, 0)
        end

        if instant then
            CollapseBtn.Rotation = panel.Open and 180 or 0
            CollapseBtn.ImageColor3 = panel.Open and P.INK_MID or P.INK_LOW
        else
            playStoredTween(panel, "_collapseTween", CollapseBtn, accentTI, {
                Rotation = panel.Open and 180 or 0,
                ImageColor3 = panel.Open and P.INK_MID or P.INK_LOW,
            })
        end

        panel.Update(instant == true)
    end

    function panel.SetSearchVisible(visible)
        local isVisible = visible ~= false
        Header.Visible = isVisible
        if isVisible then
            panel.Update(true)
        end
    end

    function panel.Collapse()
        panel.SetOpen(not panel.Open, false)
    end

    CollapseBtn.MouseButton1Click:Connect(panel.Collapse)
    panel.SetOpen(panel.Open, true)
    
    panel.Expand = panel.Collapse

    local function shouldHideForBadExecutor(cfg2)
        if type(cfg2) ~= "table" then
            return false
        end

        if cfg2.HideInUI == true then
            return true
        end

        local shared = getgenv()
        if type(shared) ~= "table" then
            return false
        end

        local executorInfo = type(shared.phantomExecutor) == "table" and shared.phantomExecutor or {}
        local hideUnsupported = executorInfo.hideUnsupportedModules == true or shared.phantomHideBadExecutorModules == true
        local badExecutor = executorInfo.isBad == true or shared.phantomIsBadExecutor == true
        if not (hideUnsupported and badExecutor) then
            return false
        end

        if cfg2.AllowBadExecutor == true or cfg2.AllowLowExecutor == true or cfg2.AllowBadExecutorFallback == true or cfg2.Bad == false then
            return false
        end

        if cfg2.AllowBadExecutor == false or cfg2.AllowLowExecutor == false then
            return true
        end

        if cfg2.Bad == true or cfg2.HideOnBadExecutor == true then
            return true
        end

        local required = cfg2.RequireMainFunctions
        if type(required) ~= "table" then
            return false
        end

        local missingLookup = type(executorInfo.missingMainLookup) == "table" and executorInfo.missingMainLookup
        if type(missingLookup) ~= "table" then
            missingLookup = shared.phantomMissingMainFunctions
        end
        if type(missingLookup) ~= "table" then
            return false
        end

        for _, fnName in ipairs(required) do
            if missingLookup[fnName] == true then
                return true
            end
        end

        return false
    end

    function panel.CreateOptionsButton(cfg2)
        local entry     = { Expanded = false, Enabled = false, Recording = false, Value = false }
        local hiddenInUi = shouldHideForBadExecutor(cfg2)
        if hiddenInUi then
            cfg2.NoSave = true
        end
        entry.Hidden = hiddenInUi
        panel._entrySequence = (panel._entrySequence or 0) + 1
        local entryOrder = panel._entrySequence * 2
        local entryId   = cfg2.Name .. "Module"
        local allowMobileButton = IS_MOBILE and cfg2.NoMobileButton ~= true and not hiddenInUi
        local defaultTouchX, defaultTouchY = nextMobileButtonSlot()
        local rowHovered = false
        if IS_MOBILE and not allowMobileButton then
            local storedButtonState = MobileUIState.Buttons[entryId]
            if type(storedButtonState) == "table" and (storedButtonState.Enabled == true or storedButtonState.Manual == true) then
                storedButtonState.Enabled = false
                storedButtonState.Manual = false
                saveMobileUIState()
            end
        end
        entry.MobileBindState = allowMobileButton and ensureMobileButtonState(entryId, defaultTouchX, defaultTouchY) or nil
        entry.MobileButtonEnabled = entry.MobileBindState and entry.MobileBindState.Enabled or false

        local Row = Instance.new("TextButton")
        Row.Name                   = entryId .. "Row"
        Row.Parent                 = EntryHolder
        Row.BackgroundColor3       = P.BASE2
        Row.BackgroundTransparency = 0
        Row.BorderSizePixel        = 0
        Row.Size                   = UDim2.new(0, ROW_W, 0, ROW_H)
        Row.Font                   = FONT_ROW
        Row.Text                   = ""
        Row.TextColor3             = P.INK_MID
        Row.TextSize               = 10
        Row.AutoButtonColor        = false
        Row.LayoutOrder            = entryOrder - 1
        entry.Instance             = Row
        mkCorner(Row, R_SM)
        local RowEdge = mkBorder(Row, P.EDGE, 1, 0.28)

        local RowGlow = Instance.new("Frame")
        RowGlow.Name = "Glow"
        RowGlow.Parent = Row
        RowGlow.BackgroundColor3 = P.HUE
        RowGlow.BackgroundTransparency = 0.92
        RowGlow.BorderSizePixel = 0
        RowGlow.Size = UDim2.new(1, 0, 0.55, 0)
        RowGlow.ZIndex = 0
        mkCorner(RowGlow, R_SM)
        local rowGlowFade = Instance.new("UIGradient")
        rowGlowFade.Rotation = 90
        rowGlowFade.Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0.12),
            NumberSequenceKeypoint.new(1, 1),
        })
        rowGlowFade.Parent = RowGlow
        registerGlow(RowGlow, function()
            return entry.Enabled or rowHovered
        end)

        local RowArrow = mkChevron(Row, 4, nil, 6)

        local ExpandHitbox
        if IS_MOBILE then
            ExpandHitbox = Instance.new("TextButton")
            ExpandHitbox.Name = "ExpandHitbox"
            ExpandHitbox.Parent = Row
            ExpandHitbox.BackgroundTransparency = 1
            ExpandHitbox.BorderSizePixel = 0
            ExpandHitbox.Position = UDim2.new(0, 0, 0, 0)
            ExpandHitbox.Size = UDim2.new(0, 18, 1, 0)
            ExpandHitbox.Text = ""
            ExpandHitbox.AutoButtonColor = false
            ExpandHitbox.ZIndex = 3
        end

        local function readEntryExtraText()
            local extra = type(cfg2.ExtraText) == "function" and cfg2.ExtraText() or cfg2.ExtraText
            if extra == nil then
                return nil
            end
            extra = tostring(extra)
            if extra == "" then
                return nil
            end
            return extra
        end

        local function readEntryStatusText()
            local segments = {}
            local bindText = formatBindDisplay(entry.Bind)
            if bindText then
                segments[#segments + 1] = "[" .. bindText .. "]"
            end

            local extra = readEntryExtraText()
            if extra then
                segments[#segments + 1] = tostring(extra)
            end

            if #segments == 0 then
                return nil
            end

            return table.concat(segments, " ")
        end

        local badgeInset = cfg2.Private and 44 or ((cfg2.Beta or cfg2.New) and 34 or 8)

        local RowLabel = Instance.new("TextLabel")
        RowLabel.Name               = "Name"; RowLabel.Parent = Row
        RowLabel.BackgroundTransparency = 1; RowLabel.BorderSizePixel = 0
        RowLabel.Position           = UDim2.new(0, 14, 0, 0)
        RowLabel.Size               = UDim2.new(1, -28, 1, 0)
        RowLabel.Font               = FONT_ROW; RowLabel.Text = cfg2.Name
        RowLabel.TextColor3         = P.INK_MID; RowLabel.TextSize = TEXT_SIZE_SM
        RowLabel.TextScaled         = false; RowLabel.TextTruncate = Enum.TextTruncate.AtEnd
        RowLabel.TextXAlignment     = Enum.TextXAlignment.Left

        local RowExtra = Instance.new("TextLabel")
        RowExtra.Name               = "Extra"; RowExtra.Parent = Row
        RowExtra.BackgroundTransparency = 1; RowExtra.BorderSizePixel = 0
        RowExtra.AnchorPoint        = Vector2.new(1, 0.5)
        RowExtra.Position           = UDim2.new(1, -badgeInset, 0.5, 0)
        RowExtra.Size               = UDim2.new(0, 46, 0, ROW_H)
        RowExtra.Font               = FONT_VALUE
        RowExtra.Text               = ""
        RowExtra.TextColor3         = P.HUE
        RowExtra.TextSize           = 8
        RowExtra.TextTruncate       = Enum.TextTruncate.AtEnd
        RowExtra.TextXAlignment     = Enum.TextXAlignment.Right
        RowExtra.Visible            = false

        if cfg2.Beta then
            local Badge = Instance.new("TextLabel")
            Badge.Name               = "Beta"; Badge.Parent = Row
            Badge.BackgroundTransparency = 1; Badge.BorderSizePixel = 0
            Badge.AnchorPoint        = Vector2.new(1, 0.5)
            Badge.Position           = UDim2.new(1, -6, 0.5, 0)
            Badge.Size               = UDim2.new(0, 28, 0, 14)
            Badge.Font               = FONT_VALUE; Badge.Text = "Beta"
            Badge.TextColor3         = P.INK_BETA; Badge.TextSize = 8
            Badge.TextXAlignment     = Enum.TextXAlignment.Right; Badge.ZIndex = 3
        end

        if cfg2.New then
            local Badge = Instance.new("TextLabel")
            Badge.Name               = "New"; Badge.Parent = Row
            Badge.BackgroundTransparency = 1; Badge.BorderSizePixel = 0
            Badge.AnchorPoint        = Vector2.new(1, 0.5)
            Badge.Position           = UDim2.new(1, -6, 0.5, 0)
            Badge.Size               = UDim2.new(0, 28, 0, 14)
            Badge.Font               = FONT_VALUE; Badge.Text = "New"
            Badge.TextColor3         = P.INK_NEW; Badge.TextSize = 8
            Badge.TextXAlignment     = Enum.TextXAlignment.Right; Badge.ZIndex = 3
        end

        if cfg2.Private then
            local Badge = Instance.new("TextLabel")
            Badge.Name               = "Private"; Badge.Parent = Row
            Badge.BackgroundTransparency = 1; Badge.BorderSizePixel = 0
            Badge.AnchorPoint        = Vector2.new(1, 0.5)
            Badge.Position           = UDim2.new(1, -6, 0.5, 0)
            Badge.Size               = UDim2.new(0, 36, 0, 14)
            Badge.Font               = FONT_VALUE; Badge.Text = "Private"
            Badge.TextColor3         = P.INK_PRIVATE; Badge.TextSize = 8
            Badge.TextXAlignment     = Enum.TextXAlignment.Right; Badge.ZIndex = 3
        end

        local SubHolder = Instance.new("Frame")
        SubHolder.Name                   = "SubHolder"
        SubHolder.Parent                 = EntryHolder
        SubHolder.BackgroundColor3       = P.BASE1
        SubHolder.BackgroundTransparency = 1
        SubHolder.BorderSizePixel        = 0
        SubHolder.ClipsDescendants       = true
        SubHolder.LayoutOrder            = entryOrder
        SubHolder.Size                   = UDim2.new(0, ROW_W, 0, 0)
        SubHolder.Visible                = false
        mkCorner(SubHolder, R_SM)
        local SubEdge = mkBorder(SubHolder, P.EDGE, 1, 0.8)

        local SubGlow = Instance.new("Frame")
        SubGlow.Name = "Glow"
        SubGlow.Parent = SubHolder
        SubGlow.BackgroundColor3 = P.HUE_FADE
        SubGlow.BackgroundTransparency = 0.96
        SubGlow.BorderSizePixel = 0
        SubGlow.Size = UDim2.new(1, 0, 0.6, 0)
        SubGlow.ZIndex = 0
        mkCorner(SubGlow, R_SM)
        local subGlowFade = Instance.new("UIGradient")
        subGlowFade.Rotation = 90
        subGlowFade.Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0.16),
            NumberSequenceKeypoint.new(1, 1),
        })
        subGlowFade.Parent = SubGlow

        local SubContent = Instance.new("Frame")
        SubContent.Name                   = "SubContent"
        SubContent.Parent                 = SubHolder
        SubContent.BackgroundTransparency = 1
        SubContent.BorderSizePixel        = 0
        SubContent.Size                   = UDim2.new(1, 0, 1, 0)
        SubContent.ZIndex                 = 1

        local function updateEntryLabels()
            RowLabel.Text = cfg2.Name
            local status = readEntryStatusText()
            RowExtra.Visible = status ~= nil
            RowExtra.Text = status or ""
            RowExtra.TextColor3 = entry.Bind and P.HUE or P.INK_LOW

            local extraWidth = RowExtra.Visible and math.min(ROW_W - 40, measureTextWidth(status, FONT_VALUE, 8) + 8) or 0
            RowExtra.Size = UDim2.new(0, extraWidth, 0, ROW_H)
            local reserved = RowExtra.Visible and (extraWidth + badgeInset + 6) or (badgeInset + 8)
            RowLabel.Size = UDim2.new(1, -reserved, 1, 0)
        end

        if hiddenInUi then
            Row.Visible = false
            Row.Size = UDim2.new(0, ROW_W, 0, 0)
            SubHolder.Visible = false
            SubHolder.Size = UDim2.new(0, ROW_W, 0, 0)
        end

        local SubFlow = Instance.new("UIListLayout")
        SubFlow.Parent             = SubContent
        SubFlow.HorizontalAlignment = Enum.HorizontalAlignment.Center
        SubFlow.VerticalAlignment   = Enum.VerticalAlignment.Top
        SubFlow.SortOrder          = Enum.SortOrder.LayoutOrder
        SubFlow.Padding            = UDim.new(0, PADDING_SM)
        mkPad(SubContent, PADDING_MD, PADDING_MD, 0, 0)

        local BindRow, BindLabel
        if not IS_MOBILE then
            BindRow = Instance.new("TextButton")
            BindRow.Name                   = "BindRow"; BindRow.Parent = SubContent
            BindRow.BackgroundColor3       = P.BASE2; BindRow.BackgroundTransparency = 0
            BindRow.BorderSizePixel        = 0; BindRow.LayoutOrder = 2
            BindRow.Size                   = UDim2.new(0, SUB_W, 0, TOGGLE_H)
            BindRow.Font                   = Enum.Font.GothamSemibold; BindRow.Text = ""
            BindRow.TextColor3             = P.INK_MID; BindRow.TextSize = TEXT_SIZE_SM
            BindRow.AutoButtonColor = false; BindRow.Visible = true
            mkCorner(BindRow, R_SM)
            local bindEdge = mkBorder(BindRow, P.EDGE, 1, 0.5)

            BindLabel = Instance.new("TextLabel")
            BindLabel.Name               = "Name"; BindLabel.Parent = BindRow
            BindLabel.BackgroundTransparency = 1; BindLabel.BorderSizePixel = 0
            BindLabel.Position           = UDim2.new(0, 9, 0, 0); BindLabel.Size = UDim2.new(1, -11, 1, 0)
            BindLabel.Font               = Enum.Font.GothamSemibold; BindLabel.Text = "bind: none"
            BindLabel.TextColor3         = P.INK_LOW; BindLabel.TextSize = TEXT_SIZE_SM
            BindLabel.TextXAlignment     = Enum.TextXAlignment.Left

            kit:track(BindRow.MouseEnter:Connect(function()
                bindEdge.Transparency = 0; BindRow.BackgroundColor3 = P.BASE_HOV
            end))
            kit:track(BindRow.MouseLeave:Connect(function()
                bindEdge.Transparency = 0.5; BindRow.BackgroundColor3 = P.BASE2
            end))
            kit:track(BindRow.MouseButton1Click:Connect(function()
                if Spectrum.IsRecording then return end
                entry.Recording = not entry.Recording
                BindRow.Visible = true
                if entry.Recording then
                    Spectrum.IsRecording = true
                    BindLabel.Text       = "press a key..."
                    BindLabel.TextColor3 = P.HUE
                end
            end))
        end

        local TouchBindRow, TouchBindLabel
        if allowMobileButton then
            TouchBindRow = Instance.new("TextButton")
            TouchBindRow.Name                   = "TouchBindRow"; TouchBindRow.Parent = SubContent
            TouchBindRow.BackgroundColor3       = P.BASE2; TouchBindRow.BackgroundTransparency = 0
            TouchBindRow.BorderSizePixel        = 0; TouchBindRow.LayoutOrder = 2
            TouchBindRow.Size                   = UDim2.new(0, SUB_W, 0, TOGGLE_H)
            TouchBindRow.Font                   = Enum.Font.GothamSemibold; TouchBindRow.Text = ""
            TouchBindRow.TextColor3             = P.INK_MID; TouchBindRow.TextSize = TEXT_SIZE_SM
            TouchBindRow.AutoButtonColor = false; TouchBindRow.Visible = true
            mkCorner(TouchBindRow, R_SM)
            local touchBindEdge = mkBorder(TouchBindRow, P.EDGE, 1, 0.5)

            TouchBindLabel = Instance.new("TextLabel")
            TouchBindLabel.Name               = "Name"; TouchBindLabel.Parent = TouchBindRow
            TouchBindLabel.BackgroundTransparency = 1; TouchBindLabel.BorderSizePixel = 0
            TouchBindLabel.Position           = UDim2.new(0, 9, 0, 0); TouchBindLabel.Size = UDim2.new(1, -11, 1, 0)
            TouchBindLabel.Font               = Enum.Font.GothamSemibold; TouchBindLabel.Text = "screen button: off"
            TouchBindLabel.TextColor3         = P.INK_LOW; TouchBindLabel.TextSize = TEXT_SIZE_SM
            TouchBindLabel.TextXAlignment     = Enum.TextXAlignment.Left

            kit:track(TouchBindRow.MouseEnter:Connect(function()
                touchBindEdge.Transparency = 0; TouchBindRow.BackgroundColor3 = P.BASE_HOV
            end))
            kit:track(TouchBindRow.MouseLeave:Connect(function()
                touchBindEdge.Transparency = 0.5; TouchBindRow.BackgroundColor3 = P.BASE2
            end))
        end

        local OptionHolder = Instance.new("Frame")
        OptionHolder.Name                   = "OptionHolder"
        OptionHolder.Parent                 = SubContent
        OptionHolder.BackgroundTransparency = 1
        OptionHolder.BorderSizePixel        = 0
        OptionHolder.LayoutOrder            = 1
        OptionHolder.Size                   = UDim2.new(0, ROW_W, 0, 0)

        local OptionFlow = Instance.new("UIListLayout")
        OptionFlow.Parent             = OptionHolder
        OptionFlow.HorizontalAlignment = Enum.HorizontalAlignment.Center
        OptionFlow.VerticalAlignment   = Enum.VerticalAlignment.Top
        OptionFlow.SortOrder          = Enum.SortOrder.LayoutOrder
        OptionFlow.Padding            = UDim.new(0, PADDING_SM)

        local function updateTouchBindRow()
            if not TouchBindLabel then return end
            TouchBindLabel.Text = "screen button: " .. (entry.MobileButtonEnabled and "on" or "off")
            TouchBindLabel.TextColor3 = entry.MobileButtonEnabled and P.HUE or P.INK_LOW
        end

        function entry.SetBind(key)
            entry.Recording    = false
            Spectrum.IsRecording = false
            entry.Bind         = key or nil
            if BindLabel then
                BindLabel.Text     = "bind: " .. (entry.Bind and entry.Bind:lower() or "none")
                BindLabel.TextColor3 = entry.Bind and P.INK_HI or P.INK_LOW
            end
            if BindRow then
                BindRow.Visible = true
            end
            updateEntryLabels()
            if entry.SyncMobileButtonFromBind then
                entry.SyncMobileButtonFromBind()
            end
            BindSync:Emit(cfg2.Name, entry.Bind, panelId, entry)
        end

        function entry.SetExtraText(text)
            cfg2.ExtraText = text
            updateEntryLabels()
            return text
        end

        function entry.SetTitle(text)
            cfg2.Name = tostring(text or cfg2.Name)
            updateEntryLabels()
            if entry.MobileButton then
                entry.MobileButton.Text = cfg2.Name
                if entry.MobileButtonHandle and entry.MobileButtonHandle.RefreshSize then
                    entry.MobileButtonHandle.RefreshSize()
                end
            end
            return cfg2.Name
        end
        local bk = cfg2.Bind or cfg2.DefaultBind

        function entry.RefreshMobileButton()
            if entry.MobileButtonTheme and entry.MobileButtonTheme.Refresh then
                entry.MobileButtonTheme.Refresh()
            end
        end

        function entry.DestroyMobileButton()
            if entry.MobileButtonHandle and entry.MobileButtonHandle.Destroy then
                entry.MobileButtonHandle:Destroy()
            end
            if entry.MobileButtonTheme and entry.MobileButtonTheme.ThemeBinding then
                entry.MobileButtonTheme.ThemeBinding:Unbind()
            end
            if entry.MobileButton then
                entry.MobileButton:Destroy()
            end
            entry.MobileButton = nil
            entry.MobileButtonHandle = nil
            entry.MobileButtonTheme = nil
        end

        function entry.EnsureMobileButton()
            if not IS_MOBILE or not entry.MobileBindState or entry.MobileButton then return end

            local button = Instance.new("TextButton")
            button.Name = entryId .. "TouchButton"
            button.Parent = Screen
            button.AnchorPoint = Vector2.new(0.5, 0.5)
            button.AutoButtonColor = false
            button.BorderSizePixel = 0
            button.BackgroundColor3 = P.BASE1
            button.Font = Enum.Font.GothamBold
            button.Text = cfg2.Name
            button.TextSize = 12
            button.TextTruncate = Enum.TextTruncate.AtEnd
            button.ZIndex = 28
            mkCorner(button, UDim.new(0, 10))

            local theme = styleFloatingButton(button, function()
                if entry.Enabled then
                    return true, kit:activeColor()
                end
                return false, P.EDGE_HI
            end)
            local handle = attachFloatingButton(button, {
                text = cfg2.Name,
                defaultX = entry.MobileBindState.X,
                defaultY = entry.MobileBindState.Y,
                getStore = function() return entry.MobileBindState end,
                onTap = function()
                    entry.Toggle(true)
                end,
            })

            entry.MobileButton = button
            entry.MobileButtonHandle = handle
            entry.MobileButtonTheme = theme
            entry.RefreshMobileButton()
        end

        function entry.SetMobileBindEnabled(enabled, isManual)
            if not entry.MobileBindState then return false end
            entry.MobileButtonEnabled = enabled == true
            entry.MobileBindState.Enabled = entry.MobileButtonEnabled
            if isManual ~= nil then
                entry.MobileBindState.Manual = isManual == true
            end
            if entry.MobileButtonEnabled then
                entry.EnsureMobileButton()
            else
                entry.DestroyMobileButton()
            end
            updateTouchBindRow()
            saveMobileUIState()
            return entry.MobileButtonEnabled
        end

        function entry.SyncMobileButtonFromBind()
            if not entry.MobileBindState or entry.MobileBindState.Manual then return end
            local hasBind = entry.Bind ~= nil and entry.Bind ~= ""
            local shouldEnable = hasBind and cfg2.NoSave ~= true
            entry.SetMobileBindEnabled(shouldEnable, false)
        end

        if bk then
            entry.SetBind(bk)
        elseif entry.MobileBindState and not entry.MobileBindState.Manual then
            entry.SetMobileBindEnabled(false, false)
        end

        if TouchBindRow then
            kit:track(PaletteSync:Bind(updateTouchBindRow))
            kit:track(TouchBindRow.MouseButton1Click:Connect(function()
                entry.SetMobileBindEnabled(not entry.MobileButtonEnabled, true)
            end))
            updateTouchBindRow()
            if entry.MobileButtonEnabled then
                entry.EnsureMobileButton()
            end
        end

        local function renderEntryVisuals(instant)
            local rowColor = entry.Enabled and P.BASE_LIT or (rowHovered and P.BASE_HOV or P.BASE2)
            local glowColor = entry.Enabled and lighten(P.HUE, 0.12) or (rowHovered and P.EDGE_HI or darken(P.BASE2, 0.18))
            local labelColor = entry.Enabled and P.INK_HI or (rowHovered and P.INK_HI or P.INK_MID)
            local extraColor = entry.Bind and P.HUE or (entry.Enabled and P.INK_HI or P.INK_LOW)
            local arrowColor = entry.Enabled and P.INK_HI or (entry.Expanded and P.INK_MID or P.INK_LOW)
            local strokeColor = entry.Enabled and P.EDGE_HI or (rowHovered and P.EDGE_HI or P.EDGE)
            local strokeTransparency = entry.Enabled and 0.08 or (rowHovered and 0.18 or 0.36)
            local targetRotation = entry.Expanded and 0 or 180

            if instant then
                Row.BackgroundColor3 = rowColor
                RowGlow.BackgroundColor3 = glowColor
                RowLabel.TextColor3 = labelColor
                RowExtra.TextColor3 = extraColor
                RowArrow.ImageColor3 = arrowColor
                RowArrow.Rotation = targetRotation
                RowEdge.Color = strokeColor
                RowEdge.Transparency = strokeTransparency
            else
                Row.BackgroundColor3 = rowColor
                RowGlow.BackgroundColor3 = glowColor
                RowLabel.TextColor3 = labelColor
                RowExtra.TextColor3 = extraColor
                RowArrow.ImageColor3 = arrowColor
                RowArrow.Rotation = targetRotation
                RowEdge.Color = strokeColor
                RowEdge.Transparency = strokeTransparency
            end
        end
        local function renderSubHolder(instant)
            local scale = (Scaler.Scale > 0 and Scaler.Scale or 1)
            local optionSize = OptionFlow.AbsoluteContentSize
            local subSize = SubFlow.AbsoluteContentSize
            local targetHeight = entry.Expanded and math.max(0, (subSize.Y + 14 * scale) / scale) or 0

            OptionHolder.Size = UDim2.new(0, ROW_W, 0, optionSize.Y / scale)
            if entry.Expanded then
                SubHolder.Visible = true
            end

            if instant then
                SubHolder.Size = UDim2.new(0, ROW_W, 0, targetHeight)
                SubHolder.BackgroundTransparency = entry.Expanded and 0.04 or 1
                SubEdge.Color = P.EDGE
                SubEdge.Transparency = 1
                if not entry.Expanded then
                    SubHolder.Visible = false
                end
            else
                playStoredTween(entry, "_subTween", SubHolder, panelTI, {
                    Size = UDim2.new(0, ROW_W, 0, targetHeight),
                    BackgroundTransparency = entry.Expanded and 0.04 or 1,
                }, function(state)
                    if state == Enum.PlaybackState.Completed and not entry.Expanded then
                        SubHolder.Visible = false
                    end
                end)
                playTween(SubEdge, accentTI, {
                    Color = P.EDGE,
                    Transparency = 1,
                })
            end
        end

        function entry.Update(instant)
            renderSubHolder(instant == true)
        end

        function entry.SetSearchVisible(visible)
            local rowVisible = entry.Hidden ~= true and visible ~= false
            Row.Visible = rowVisible
            Row.Size = UDim2.new(0, ROW_W, 0, rowVisible and ROW_H or 0)
            if not rowVisible then
                SubHolder.Visible = false
                SubHolder.Size = UDim2.new(0, ROW_W, 0, 0)
            else
                renderSubHolder(true)
            end
            panel.Update(true)
            return rowVisible
        end

        kit:track(OptionFlow:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
            entry.Update(false)
        end))
        kit:track(SubFlow:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
            entry.Update(false)
        end))

        kit:track(PaletteSync:Bind(function()
            RowGlow.BackgroundColor3 = entry.Enabled and lighten(P.HUE, 0.12) or (rowHovered and P.EDGE_HI or darken(P.BASE2, 0.18))
            SubGlow.BackgroundColor3 = P.HUE_FADE
            renderEntryVisuals(true)
            renderSubHolder(true)
        end))

        kit:track(Row.MouseEnter:Connect(function()
            rowHovered = true
            local instant = skipToast or not Row:IsDescendantOf(game)
            renderEntryVisuals(instant)
        end))
        kit:track(Row.MouseLeave:Connect(function()
            rowHovered = false
            local instant = skipToast or not Row:IsDescendantOf(game)
            renderEntryVisuals(instant)
        end))
        bindHoverTooltip(Row, cfg2.Tooltip or cfg2.HoverText)

        local function shouldHideSubOptionForBadExecutor(cfg3)
            if type(cfg3) ~= "table" then
                return false
            end

            if cfg3.HideInUI == true then
                return true
            end

            local shared = getgenv()
            if type(shared) ~= "table" then
                return false
            end

            local executorInfo = type(shared.phantomExecutor) == "table" and shared.phantomExecutor or {}
            local hideUnsupported = executorInfo.hideUnsupportedModules == true or shared.phantomHideBadExecutorModules == true
            local badExecutor = executorInfo.isBad == true or shared.phantomIsBadExecutor == true
            if not (hideUnsupported and badExecutor) then
                return false
            end

            if cfg3.AllowBadExecutor == true or cfg3.AllowLowExecutor == true or cfg3.AllowBadExecutorFallback == true or cfg3.Bad == false then
                return false
            end

            if cfg3.AllowBadExecutor == false or cfg3.AllowLowExecutor == false then
                return true
            end

            if cfg3.Bad == true or cfg3.HideOnBadExecutor == true then
                return true
            end

            local required = cfg3.RequireMainFunctions
            if type(required) ~= "table" then
                return false
            end

            local missingLookup = type(executorInfo.missingMainLookup) == "table" and executorInfo.missingMainLookup
            if type(missingLookup) ~= "table" then
                missingLookup = shared.phantomMissingMainFunctions
            end
            if type(missingLookup) ~= "table" then
                return false
            end

            for _, fnName in ipairs(required) do
                if missingLookup[fnName] == true then
                    return true
                end
            end

            return false
        end

        local function applyEntryState(enabled, fromKey, skipCallback, skipToast)
            entry.Enabled = enabled == true
            entry.Value = entry.Enabled
            local instant = skipToast or not Row:IsDescendantOf(game)
            renderEntryVisuals(instant)
            entry.RefreshMobileButton()
            local extra = type(cfg2.ExtraText) == "function" and cfg2.ExtraText() or cfg2.ExtraText
            ModuleSync:Emit(cfg2.Name, extra, entry.Enabled, fromKey, panelId, cfg2.Private)
            if not skipCallback and cfg2.Function then task.spawn(cfg2.Function, entry.Enabled, fromKey) end
            if not skipToast then
                Spectrum.toast(
                    string.upper(string.sub(cfg2.Name, 1, 1)) .. string.sub(cfg2.Name, 2),
                    entry.Enabled, 2)
            end
        end

        function entry.Toggle(fromKey)
            if entry.Hidden then
                entry.Enabled = false
                entry.Value = false
                return false
            end
            applyEntryState(not entry.Enabled, fromKey, false, false)
            return entry.Enabled
        end

        function entry.SetEnabled(enabled, skipCallback, skipToast)
            if entry.Hidden then
                entry.Enabled = false
                entry.Value = false
                return false
            end
            if entry.Enabled == (enabled == true) then
                entry.Value = entry.Enabled
                return entry.Enabled
            end
            applyEntryState(enabled == true, nil, skipCallback == true, skipToast == true)
            return entry.Enabled
        end
        entry.Function = cfg2.Function

        function entry.Expand()
            if entry.Hidden then
                return false
            end
            entry.Expanded = not entry.Expanded
            if entry.Expanded then
                SubHolder.Visible = true
            end
            local instant = skipToast or not Row:IsDescendantOf(game)
            renderEntryVisuals(instant)
            entry.Update(false)
            panel.Update(false)
            return entry.Expanded
        end

        kit:track(Row.MouseButton1Click:Connect(entry.Toggle))
        kit:track(Row.MouseButton2Click:Connect(entry.Expand))
        if ExpandHitbox then
            kit:track(ExpandHitbox.MouseButton1Click:Connect(entry.Expand))
        end

        renderEntryVisuals(true)
        entry.Update(true)
        updateEntryLabels()
        
        function entry.CreateToggle(cfg3)
            local sw = { Enabled = false, Value = false, Dependents = {}, _depSaved = {} }
            sw.Hidden = shouldHideSubOptionForBadExecutor(cfg3)
            if sw.Hidden then
                cfg3.NoSave = true
            end

            local SwitchRow = Instance.new("TextButton")
            SwitchRow.Name                   = "Switch"; SwitchRow.Parent = OptionHolder
            SwitchRow.BackgroundColor3       = P.BASE2; SwitchRow.BackgroundTransparency = 0
            SwitchRow.BorderSizePixel        = 0
            SwitchRow.Size                   = UDim2.new(0, SUB_W, 0, TOGGLE_H)
            SwitchRow.Text                   = ""; SwitchRow.AutoButtonColor = false
            sw.Instance                      = SwitchRow
            mkCorner(SwitchRow, R_SM)

            local ToggleBox = Instance.new("Frame")
            ToggleBox.Name               = "Box"; ToggleBox.Parent = SwitchRow
            ToggleBox.AnchorPoint        = Vector2.new(0, 0.5)
            ToggleBox.BackgroundColor3   = P.BASE1; ToggleBox.BackgroundTransparency = 0
            ToggleBox.BorderSizePixel    = 0
            ToggleBox.Position           = UDim2.new(0, 6, 0.5, 0)
            ToggleBox.Size               = UDim2.fromOffset(IS_MOBILE and 12 or 10, IS_MOBILE and 12 or 10)
            mkCorner(ToggleBox, UDim.new(0, IS_MOBILE and 3 or 2))

            local ToggleCheck = Instance.new("TextLabel")
            ToggleCheck.Name               = "Check"; ToggleCheck.Parent = ToggleBox
            ToggleCheck.BackgroundTransparency = 1; ToggleCheck.BorderSizePixel = 0
            ToggleCheck.Size               = UDim2.new(1, 0, 1, 0)
            ToggleCheck.Font               = Enum.Font.GothamBold; ToggleCheck.Text = "✓"
            ToggleCheck.TextColor3         = P.INK_HI; ToggleCheck.TextSize = IS_MOBILE and 11 or 9
            ToggleCheck.TextTransparency   = 1

            local SwitchLabel = Instance.new("TextLabel")
            SwitchLabel.Name               = "Name"; SwitchLabel.Parent = SwitchRow
            SwitchLabel.BackgroundTransparency = 1; SwitchLabel.BorderSizePixel = 0
            SwitchLabel.Position           = UDim2.new(0, IS_MOBILE and 24 or 22, 0, 0)
            SwitchLabel.Size               = UDim2.new(1, -(IS_MOBILE and 28 or 26), 1, 0)
            SwitchLabel.Font               = FONT_ROW; SwitchLabel.Text = cfg3.Name
            SwitchLabel.TextColor3         = P.INK_MID; SwitchLabel.TextSize = TEXT_SIZE_SM
            SwitchLabel.TextScaled         = false; SwitchLabel.TextTruncate = Enum.TextTruncate.AtEnd
            SwitchLabel.TextXAlignment     = Enum.TextXAlignment.Left

            if sw.Hidden then
                SwitchRow.Visible = false
                SwitchRow.Size = UDim2.new(0, SUB_W, 0, 0)
            end

            local switchHovered = false

            local function renderSwitch(instant)
                local rowColor = switchHovered and P.BASE_HOV or P.BASE2
                local boxColor = sw.Enabled and P.HUE or P.BASE1
                local labelColor = sw.Enabled and P.INK_HI or (switchHovered and P.INK_HI or P.INK_MID)
                local checkTransparency = sw.Enabled and 0 or 1

                if instant then
                    SwitchRow.BackgroundColor3 = rowColor
                    ToggleBox.BackgroundColor3 = boxColor
                    ToggleCheck.TextTransparency = checkTransparency
                    SwitchLabel.TextColor3 = labelColor
                else
                    playTween(SwitchRow, hoverTI, { BackgroundColor3 = rowColor })
                    playTween(ToggleBox, accentTI, { BackgroundColor3 = boxColor })
                    playTween(ToggleCheck, accentTI, { TextTransparency = checkTransparency })
                    playTween(SwitchLabel, accentTI, { TextColor3 = labelColor })
                end
            end

            kit:track(PaletteSync:Bind(function()
                ToggleCheck.TextColor3 = P.INK_HI
                renderSwitch(true)
            end))

            function sw.Toggle(skipAnim)
                if sw.Hidden then
                    sw.Enabled = false
                    sw.Value = false
                    return false
                end
                sw.Enabled = not sw.Enabled
                sw.Value = sw.Enabled
                renderSwitch(skipAnim == true)
                if cfg3.Function then task.spawn(cfg3.Function, sw.Enabled) end
                for _, dep in next, sw.Dependents do
                    dep.Instance.Visible = sw.Enabled
                    if not sw.Enabled then
                        sw._depSaved[dep] = dep.Enabled
                        if dep.Enabled and dep.Toggle then dep.Toggle() end
                    else
                        local shouldEnable = sw._depSaved[dep]
                        if dep.Toggle then
                            if shouldEnable and not dep.Enabled then
                                dep.Toggle()
                            elseif shouldEnable == false and dep.Enabled then
                                dep.Toggle()
                            end
                        end
                    end
                end
            end

            function sw.SetEnabled(value, skipAnim)
                if sw.Hidden then
                    sw.Enabled = false
                    sw.Value = false
                    return false
                end
                local target = value == true
                if sw.Enabled ~= target then
                    sw.Toggle(skipAnim)
                else
                    sw.Value = sw.Enabled
                end
                return sw.Enabled
            end

            function sw.AddDependent(_, dep)
                table.insert(sw.Dependents, dep)
                dep.Instance.Visible = sw.Enabled
                if not sw.Enabled then
                    sw._depSaved[dep] = dep.Enabled
                    if dep.Enabled and dep.Toggle then dep.Toggle() end
                end
            end

            kit:track(SwitchRow.MouseButton1Click:Connect(sw.Toggle))
            sw.Function = cfg3.Function

            kit:track(SwitchRow.MouseEnter:Connect(function()
                switchHovered = true
                renderSwitch(false)
            end))
            kit:track(SwitchRow.MouseLeave:Connect(function()
                switchHovered = false
                renderSwitch(false)
            end))
            bindHoverTooltip(SwitchRow, cfg3.Tooltip or cfg3.HoverText)

            if not sw.Hidden and cfg3.Default and sw.Enabled ~= cfg3.Default then sw.Toggle(true) end
            renderSwitch(true)

            kit:register(cfg3.Name .. "Toggle_" .. entryId,
                { Name = cfg3.Name, Instance = SwitchRow, Type = "Toggle",
                  OptionsButton = entryId, API = sw, args = cfg3 })
            return sw
        end

        function entry.CreateButton(cfg3)
            local button = {}
            button.Hidden = shouldHideSubOptionForBadExecutor(cfg3)
            if button.Hidden then
                cfg3.NoSave = true
            end

            local ActionRow = Instance.new("TextButton")
            ActionRow.Name                   = "Button"
            ActionRow.Parent                 = OptionHolder
            ActionRow.BackgroundColor3       = P.BASE2
            ActionRow.BackgroundTransparency = 0
            ActionRow.BorderSizePixel        = 0
            ActionRow.Size                   = UDim2.new(0, SUB_W, 0, TOGGLE_H)
            ActionRow.Text                   = ""
            ActionRow.AutoButtonColor        = false
            button.Instance                  = ActionRow
            mkCorner(ActionRow, R_SM)
            local actionEdge = mkBorder(ActionRow, P.EDGE, 1, 0.4)

            local ActionLabel = Instance.new("TextLabel")
            ActionLabel.Name               = "Name"
            ActionLabel.Parent             = ActionRow
            ActionLabel.BackgroundTransparency = 1
            ActionLabel.BorderSizePixel    = 0
            ActionLabel.Position           = UDim2.new(0, 9, 0, 0)
            ActionLabel.Size               = UDim2.new(1, -24, 1, 0)
            ActionLabel.Font               = Enum.Font.GothamSemibold
            ActionLabel.Text               = cfg3.Name
            ActionLabel.TextColor3         = P.INK_HI
            ActionLabel.TextSize           = TEXT_SIZE_SM
            ActionLabel.TextTruncate       = Enum.TextTruncate.AtEnd
            ActionLabel.TextXAlignment     = Enum.TextXAlignment.Left

            local ActionChevron = Instance.new("TextLabel")
            ActionChevron.Name               = "Chevron"
            ActionChevron.Parent             = ActionRow
            ActionChevron.BackgroundTransparency = 1
            ActionChevron.BorderSizePixel    = 0
            ActionChevron.AnchorPoint        = Vector2.new(1, 0.5)
            ActionChevron.Position           = UDim2.new(1, -8, 0.5, 0)
            ActionChevron.Size               = UDim2.new(0, 10, 0, 10)
            ActionChevron.Font               = Enum.Font.GothamBold
            ActionChevron.Text               = ">"
            ActionChevron.TextColor3         = P.HUE
            ActionChevron.TextSize           = 10
            ActionChevron.TextXAlignment     = Enum.TextXAlignment.Right

            local function renderButton(hovered)
                ActionRow.BackgroundColor3 = hovered and P.BASE_HOV or (cfg3.BackgroundColor or P.BASE2)
                actionEdge.Color = hovered and P.EDGE_HI or P.EDGE
                actionEdge.Transparency = hovered and 0.12 or 0.4
                ActionChevron.TextColor3 = hovered and P.INK_HI or P.HUE
            end

            if button.Hidden then
                ActionRow.Visible = false
                ActionRow.Size = UDim2.new(0, SUB_W, 0, 0)
            end

            kit:track(PaletteSync:Bind(function()
                renderButton(false)
            end))
            kit:track(ActionRow.MouseEnter:Connect(function()
                renderButton(true)
            end))
            kit:track(ActionRow.MouseLeave:Connect(function()
                renderButton(false)
            end))
            kit:track(ActionRow.MouseButton1Click:Connect(function()
                if button.Hidden then
                    return
                end
                if cfg3.Function then
                    task.spawn(cfg3.Function)
                end
                if cfg3.ToastText then
                    Spectrum.toast(cfg3.Name, cfg3.ToastText, 2)
                end
            end))
            bindHoverTooltip(ActionRow, cfg3.Tooltip or cfg3.HoverText)
            renderButton(false)

            kit:register(cfg3.Name .. "Button_" .. entryId,
                { Name = cfg3.Name, Instance = ActionRow, Type = "Button",
                  OptionsButton = entryId, API = button, args = cfg3 })
            return button
        end

        function entry.CreateSlider(cfg3)
            local range     = {}
            local rMin, rMax = cfg3.Min, cfg3.Max
            local rDef       = cfg3.Default or rMin
            local rnd        = cfg3.Round or 1
            local rMult      = 10 ^ rnd

            local function fmt(v)
                return math.floor(v) == v and (tostring(v) .. ".0") or tostring(v)
            end

            local RangeFrame = Instance.new("Frame")
            RangeFrame.Name                   = "Range"; RangeFrame.Parent = OptionHolder
            RangeFrame.BackgroundColor3       = P.BASE2; RangeFrame.BackgroundTransparency = 0
            RangeFrame.BorderSizePixel        = 0; RangeFrame.Size = UDim2.new(0, SUB_W, 0, SLIDER_H)
            range.Instance                    = RangeFrame
            mkCorner(RangeFrame, R_SM)
            local rangeEdge = mkBorder(RangeFrame, P.EDGE, 1, 0.45)

            local RangeLabel = Instance.new("TextLabel")
            RangeLabel.Name               = "Name"; RangeLabel.Parent = RangeFrame
            RangeLabel.BackgroundTransparency = 1; RangeLabel.BorderSizePixel = 0
            RangeLabel.Position           = UDim2.new(0, 6, 0, 2); RangeLabel.Size = UDim2.new(1, -46, 0, 12)
            RangeLabel.Font               = FONT_ROW; RangeLabel.Text = cfg3.Name
            RangeLabel.TextColor3         = P.INK_MID; RangeLabel.TextSize = TEXT_SIZE_SM
            RangeLabel.TextScaled         = false; RangeLabel.TextTruncate = Enum.TextTruncate.AtEnd
            RangeLabel.TextXAlignment     = Enum.TextXAlignment.Left

            local ValBox = Instance.new("TextBox")
            ValBox.Name                  = "Val"; ValBox.Parent = RangeFrame
            ValBox.AnchorPoint           = Vector2.new(1, 0)
            ValBox.BackgroundTransparency = 1; ValBox.Position = UDim2.new(1, -6, 0, 2)
            ValBox.Size                  = UDim2.new(0, 38, 0, 12)
            ValBox.Font                  = FONT_VALUE; ValBox.PlaceholderText = "val"
            ValBox.Text                  = fmt(rDef); ValBox.TextColor3 = P.HUE
            ValBox.TextSize              = TEXT_SIZE_SM; ValBox.TextXAlignment = Enum.TextXAlignment.Right
            ValBox.BackgroundColor3      = P.BASE2

            local ValLine = Instance.new("Frame")
            ValLine.Name             = "ValLine"; ValLine.Parent = ValBox
            ValLine.AnchorPoint      = Vector2.new(1, 0); ValLine.BackgroundColor3 = P.HUE
            ValLine.BorderSizePixel  = 0; ValLine.Position = UDim2.new(1, 0, 1, 1)
            ValLine.Size             = UDim2.new(0.9, 0, 0, 1); ValLine.Visible = false

            local Track = Instance.new("Frame")
            Track.Name             = "Track"; Track.Parent = RangeFrame
            Track.AnchorPoint      = Vector2.new(0.5, 1)
            Track.BackgroundColor3 = P.EDGE; Track.BorderSizePixel = 0
            Track.Position         = UDim2.new(0.5, 0, 1, -4)
            Track.Size             = UDim2.new(1, -12, 0, 2)
            mkCorner(Track, R_SM)

            local Fill = Instance.new("Frame")
            Fill.Name             = "Fill"; Fill.Parent = Track
            Fill.AnchorPoint      = Vector2.new(0, 0.5)
            Fill.BackgroundColor3 = P.HUE; Fill.BorderSizePixel = 0
            Fill.Position         = UDim2.new(0, 0, 0.5, 0)
            Fill.Size             = UDim2.new(0, 50, 1, 0)
            mkCorner(Fill, R_SM)

            kit:track(PaletteSync:Bind(function() Fill.BackgroundColor3 = P.HUE end))
            kit:track(RangeFrame.MouseEnter:Connect(function()
                RangeFrame.BackgroundColor3 = P.BASE_HOV
                rangeEdge.Color = P.EDGE_HI
            end))
            kit:track(RangeFrame.MouseLeave:Connect(function()
                RangeFrame.BackgroundColor3 = P.BASE2
                rangeEdge.Color = P.EDGE
            end))
            kit:track(ValBox.MouseEnter:Connect(function() ValLine.Visible = true end))
            kit:track(ValBox.MouseLeave:Connect(function()
                if not ValBox:IsFocused() then ValLine.Visible = false end
            end))
            kit:track(ValBox.Focused:Connect(function() ValLine.Visible = true end))
            kit:track(ValBox.FocusLost:Connect(function()
                ValLine.Visible = false
                local n = tonumber(ValBox.Text)
                if n then range.Set(n, true)
                else ValBox.Text = fmt(range.Value) end
            end))
            bindHoverTooltip(RangeFrame, cfg3.Tooltip or cfg3.HoverText)

            local function drag(input)
                local sx = math.clamp(
                    (input.Position.X - Track.AbsolutePosition.X) / Track.AbsoluteSize.X, 0, 1)
                Fill.Size     = UDim2.new(sx, 0, 1, 0)
                local v = math.round(((rMax - rMin) * sx + rMin) * rMult) / rMult
                range.Value = v; ValBox.Text = fmt(v)
                if not cfg3.OnInputEnded and cfg3.Function then task.spawn(cfg3.Function, v) end
            end

            local sliding = false
            kit:track(RangeFrame.InputBegan:Connect(function(input)
                local ut = input.UserInputType
                if ut == Enum.UserInputType.MouseButton1 or ut == Enum.UserInputType.Touch then
                    sliding = true; drag(input)
                end
            end))
            kit:track(RangeFrame.InputEnded:Connect(function(input)
                local ut = input.UserInputType
                if ut == Enum.UserInputType.MouseButton1 or ut == Enum.UserInputType.Touch then
                    if cfg3.OnInputEnded and cfg3.Function then task.spawn(cfg3.Function, range.Value) end
                    sliding = false
                end
            end))
            kit:track(UIS.InputChanged:Connect(function(input)
                if sliding and isPointerMove(input.UserInputType) then drag(input) end
            end))

            function range.Set(val, overMax)
                local clamped = not overMax
                    and math.floor(math.clamp(val, rMin, rMax) * rMult + 0.5) / rMult
                    or  math.clamp(val, cfg3.RealMin or -math.huge, cfg3.RealMax or math.huge)
                local sVal = math.floor(math.clamp(clamped, rMin, rMax) * rMult + 0.5) / rMult
                range.Value  = clamped
                Fill.Size    = UDim2.new((sVal - rMin) / (rMax - rMin), 0, 1, 0)
                ValBox.Text  = fmt(clamped)
                if cfg3.Function then task.spawn(cfg3.Function, clamped) end
            end
            range.Set(rDef)

            kit:register(cfg3.Name .. "Slider_" .. entryId,
                { Name = cfg3.Name, Instance = RangeFrame, Type = "Slider",
                  OptionsButton = entryId, API = range, args = cfg3 })
            return range
        end

        function entry.CreateTextbox(cfg3)
            local inp = {}

            local InputWrap = Instance.new("Frame")
            InputWrap.Name                   = "Input"; InputWrap.Parent = OptionHolder
            InputWrap.BackgroundTransparency = 1; InputWrap.BorderSizePixel = 0
            InputWrap.Size                   = UDim2.new(0, SUB_W, 0, TEXTBOX_H)
            inp.Instance                     = InputWrap

            local InputBack = Instance.new("Frame")
            InputBack.Name                   = "InputBack"; InputBack.Parent = InputWrap
            InputBack.AnchorPoint            = Vector2.new(0.5, 0.5)
            InputBack.BackgroundColor3       = P.BASE2; InputBack.BackgroundTransparency = 0
            InputBack.BorderSizePixel        = 0
            InputBack.Position               = UDim2.new(0.5, 0, 0.5, 0)
            InputBack.Size                   = UDim2.new(0, SUB_W - 8, 0, 20)
            mkCorner(InputBack, R_SM)
            local inputEdge = mkBorder(InputBack, P.EDGE, 1, 0.4)

            local InputField = Instance.new("TextBox")
            InputField.Name                  = "Field"; InputField.Parent = InputBack
            InputField.AnchorPoint           = Vector2.new(0.5, 0.5)
            InputField.BackgroundTransparency = 1; InputField.BorderSizePixel = 0
            InputField.Position              = UDim2.new(0.5, 0, 0.5, 0)
            InputField.Size                  = UDim2.new(1, -14, 1, 0)
            InputField.ClearTextOnFocus      = false
            InputField.Font                  = Enum.Font.GothamSemibold
            InputField.PlaceholderColor3     = P.INK_LOW; InputField.PlaceholderText = cfg3.Name
            InputField.Text                  = cfg3.Default or ""; InputField.TextColor3 = P.INK_HI
            InputField.TextSize              = 10; InputField.TextXAlignment = Enum.TextXAlignment.Left

            kit:track(InputBack.MouseEnter:Connect(function()
                inputEdge.Color = P.EDGE_HI; inputEdge.Transparency = 0
            end))
            kit:track(InputBack.MouseLeave:Connect(function()
                inputEdge.Color = P.EDGE; inputEdge.Transparency = 0.4
            end))
            bindHoverTooltip(InputBack, cfg3.Tooltip or cfg3.HoverText)

            function inp.Set(val)
                val       = val or cfg3.Default or ""
                inp.Value = val; InputField.Text = val
                if cfg3.Function then task.spawn(cfg3.Function, val) end
            end
            kit:track(InputField.FocusLost:Connect(function()
                local t = InputField.Text; if t then inp.Set(t) end
            end))

            kit:register(cfg3.Name .. "Textbox_" .. entryId,
                { Name = cfg3.Name, Instance = InputWrap, Type = "Textbox",
                  OptionsButton = entryId, API = inp, args = cfg3 })
            return inp
        end
        entry.CreateTextBox = entry.CreateTextbox
        
        function entry.CreateDropdown(cfg3)
            local sel = { Values = {}, Expanded = false, ValueDependents = {}, _depSaved = {} }
            local SelWrap = Instance.new("Frame")
            SelWrap.Name = "Select"
            SelWrap.Parent = OptionHolder
            SelWrap.BackgroundTransparency = 1
            SelWrap.BorderSizePixel = 0
            SelWrap.Size = UDim2.new(0, SUB_W, 0, TEXTBOX_H)
            sel.Instance = SelWrap

            local SelBack = Instance.new("Frame")
            SelBack.Name = "SelBack"
            SelBack.Parent = SelWrap
            SelBack.AnchorPoint = Vector2.new(0.5, 0)
            SelBack.BackgroundColor3 = P.BASE2
            SelBack.BackgroundTransparency = 0
            SelBack.BorderSizePixel = 0
            SelBack.Position = UDim2.new(0.5, 0, 0, 2)
            SelBack.Size = UDim2.new(0, SUB_W, 0, TEXTBOX_H)
            mkCorner(SelBack, R_SM)
            local selEdge = mkBorder(SelBack, P.EDGE, 1, 0.4)

            local SelLabel = Instance.new("TextLabel")
            SelLabel.Name = "Name"
            SelLabel.Parent = SelBack
            SelLabel.BackgroundTransparency = 1
            SelLabel.BorderSizePixel = 0
            SelLabel.Position = UDim2.new(0, 6, 0, 0)
            SelLabel.Size = UDim2.new(1, -26, 1, 0)
            SelLabel.Font = FONT_ROW
            SelLabel.Text = cfg3.Name
            SelLabel.TextColor3 = P.INK_MID
            SelLabel.TextSize = TEXT_SIZE_SM
            SelLabel.TextXAlignment = Enum.TextXAlignment.Left
            SelLabel.TextTruncate = Enum.TextTruncate.AtEnd

            local SelChevron = Instance.new("ImageButton")
            SelChevron.Name = "Chevron"
            SelChevron.Parent = SelBack
            SelChevron.AnchorPoint = Vector2.new(0, 0.5)
            SelChevron.BackgroundTransparency = 1
            SelChevron.BorderSizePixel = 0
            SelChevron.Position = UDim2.new(1, -11, 0.5, 0)
            SelChevron.Size = UDim2.new(0, 8, 0, 8)
            SelChevron.ZIndex = 2
            SelChevron.Image = "http://www.roblox.com/asset/?id=6031094679"
            SelChevron.ImageColor3 = P.INK_LOW
            SelChevron.ScaleType = Enum.ScaleType.Fit

            local SelList = Instance.new("Frame")
            SelList.Name = "SelList"
            SelList.Parent = SelWrap
            SelList.AnchorPoint = Vector2.new(0.5, 0)
            SelList.BackgroundColor3 = P.BASE1
            SelList.BackgroundTransparency = 0
            SelList.BorderSizePixel = 0
            SelList.ClipsDescendants = true
            SelList.Position = UDim2.new(0.5, 0, 0, TEXTBOX_H + 4)
            SelList.Size = UDim2.new(0, SUB_W, 0, 0)
            SelList.Visible = false
            mkCorner(SelList, R_SM)
            mkBorder(SelList, P.EDGE, 1, 0.4)
            mkPad(SelList, 1, 1, 0, 0)

            local SelScroll = Instance.new("ScrollingFrame")
            SelScroll.Parent = SelList
            SelScroll.BackgroundTransparency = 1
            SelScroll.BorderSizePixel = 0
            SelScroll.Size = UDim2.new(1, 0, 1, 0)
            SelScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
            SelScroll.ScrollBarThickness = 2
            SelScroll.ScrollBarImageColor3 = P.INK_LOW

            local SelItemFlow = Instance.new("UIListLayout")
            SelItemFlow.Parent = SelScroll
            SelItemFlow.HorizontalAlignment = Enum.HorizontalAlignment.Center
            SelItemFlow.SortOrder = Enum.SortOrder.LayoutOrder
            SelItemFlow.Padding = UDim.new(0, 1)

            kit:track(SelBack.MouseEnter:Connect(function()
                selEdge.Color = P.EDGE_HI
                selEdge.Transparency = 0
                SelBack.BackgroundColor3 = P.BASE_HOV
            end))
            kit:track(SelBack.MouseLeave:Connect(function()
                selEdge.Color = P.EDGE
                selEdge.Transparency = 0.4
                SelBack.BackgroundColor3 = P.BASE2
            end))

            local MAX_H = 160

            function sel.Update()
                local scale = Scaler.Scale or 1
                local sz = SelItemFlow.AbsoluteContentSize.Y
                local capped = math.min(sz, MAX_H * scale)
                local listH = sel.Expanded and (capped / scale) or 0
                local wrapH = sel.Expanded and (TEXTBOX_H + 4 + listH) or TEXTBOX_H

                SelWrap.Size = UDim2.new(0, SUB_W, 0, wrapH)
                SelList.Size = UDim2.new(0, SUB_W, 0, listH)
                SelScroll.CanvasSize = UDim2.new(0, 0, 0, sz / scale)

                SelChevron.Rotation = sel.Expanded and 180 or 0
                SelChevron.ImageColor3 = sel.Expanded and P.HUE or P.INK_LOW

                if not sel.Expanded then
                    SelList.Visible = false
                else
                    SelList.Visible = true
                end
            end

            kit:track(SelItemFlow:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(sel.Update))

            function sel.SetValue(val)
                for _, v in next, sel.Values do
                    local match = (v.Value == val)
                    if v.SelectedInstance then v.SelectedInstance.Visible = match end
                    if match then
                        sel.Value = tostring(val)
                        SelLabel.Text = cfg3.Name .. ": " .. tostring(val)
                        SelLabel.TextColor3 = P.INK_HI
                        if cfg3.Function then task.spawn(cfg3.Function, val) end

                        for _, vd in next, sel.ValueDependents do
                            local show = (sel.Value == vd.value)
                            for _, dep in next, vd.elements do
                                if dep and dep.Instance then dep.Instance.Visible = show end
                                if not show then
                                    sel._depSaved[dep] = dep.Enabled
                                    if dep.Enabled and dep.Toggle then dep.Toggle() end
                                else
                                    local should = sel._depSaved[dep]
                                    if should ~= nil and dep.Toggle then
                                        if should and not dep.Enabled then dep.Toggle() end
                                        if not should and dep.Enabled then dep.Toggle() end
                                    end
                                end
                            end
                        end
                    end
                end
            end

            function sel.ShowWhen(_, value, ...)
                local deps = {...}
                table.insert(sel.ValueDependents, {value = tostring(value), elements = deps})
                local show = (sel.Value == tostring(value))

                for _, dep in next, deps do
                    if dep and dep.Instance and typeof(dep.Instance) == "Instance" and dep.Instance.Parent then
                        safeVisible(dep.Instance, show)

                        if not show then
                            sel._depSaved[dep] = dep.Enabled
                            if dep.Enabled and dep.Toggle then
                                pcall(dep.Toggle)
                            end
                        else
                            local shouldEnable = sel._depSaved[dep]
                            if shouldEnable ~= nil and dep.Toggle then
                                if shouldEnable and not dep.Enabled then
                                    pcall(dep.Toggle)
                                elseif shouldEnable == false and dep.Enabled then
                                    pcall(dep.Toggle)
                                end
                            end
                        end
                    end
                end
            end

            local function newItem(val)
                local vi = {Value = val}
                local Btn = Instance.new("TextButton")
                Btn.Parent = SelScroll
                Btn.BackgroundColor3 = P.BASE1
                Btn.BackgroundTransparency = 0
                Btn.BorderSizePixel = 0
                Btn.Size = UDim2.new(0, SUB_W - 4, 0, 18)
                Btn.Text = ""
                Btn.AutoButtonColor = false
                mkCorner(Btn, R_SM)

                Btn.MouseButton1Click:Connect(function()
                    if tostring(val) == sel.Value then return end
                    sel.SetValue(val)
                end)
                kit:track(Btn.MouseEnter:Connect(function() Btn.BackgroundColor3 = P.BASE_HOV end))
                kit:track(Btn.MouseLeave:Connect(function() Btn.BackgroundColor3 = P.BASE1 end))

                local Lbl = Instance.new("TextLabel")
                Lbl.Parent = Btn
                Lbl.BackgroundTransparency = 1
                Lbl.Position = UDim2.new(0, 10, 0, 0)
                Lbl.Size = UDim2.new(1, -20, 1, 0)
                Lbl.Font = FONT_ROW
                Lbl.Text = tostring(val)
                Lbl.TextColor3 = P.INK_MID
                Lbl.TextSize = TEXT_SIZE_SM
                Lbl.TextXAlignment = Enum.TextXAlignment.Left

                local Dot = Instance.new("Frame")
                Dot.Parent = Btn
                Dot.AnchorPoint = Vector2.new(0, 0.5)
                Dot.BackgroundColor3 = P.HUE
                Dot.Visible = false
                Dot.BorderSizePixel = 0
                Dot.Position = UDim2.new(0, 3, 0.5, 0)
                Dot.Size = UDim2.new(0, 4, 0, 10)
                mkCorner(Dot, R_SM)

                vi.SelectedInstance = Dot
                vi.Instance = Btn
                return vi
            end

            function sel.Expand()
                sel.Expanded = not sel.Expanded
                sel.Update()
            end

            kit:track(SelChevron.MouseButton1Click:Connect(sel.Expand))

            for _, v in next, cfg3.List or {} do
                table.insert(sel.Values, newItem(v))
            end

            if cfg3.Default then
                sel.SetValue(cfg3.Default)
            end

            sel.Update()

            function sel.SetList(list)
                for _, v in next, sel.Values do v.Instance:Destroy() end
                sel.Values = {}
                for _, v in next, list or {} do
                    table.insert(sel.Values, newItem(v))
                end
                sel.Update()
            end

            kit:register(cfg3.Name .. "Dropdown_" .. entryId, {
                Name = cfg3.Name,
                Instance = SelWrap,
                Type = "Dropdown",
                OptionsButton = entryId,
                API = sel,
                args = cfg3
            })

            return sel
        end
        
        function entry.CreateMultiDropdown(cfg3)
            local ms = { Values = {}, Expanded = false }

            local MSWrap = Instance.new("Frame")
            MSWrap.Name                   = "MultiSelect"; MSWrap.Parent = OptionHolder
            MSWrap.BackgroundTransparency = 1; MSWrap.BorderSizePixel = 0
            MSWrap.Size                   = UDim2.new(0, SUB_W, 0, TEXTBOX_H)
            ms.Instance                   = MSWrap

            local MSBack = Instance.new("Frame")
            MSBack.Name                   = "MSBack"; MSBack.Parent = MSWrap
            MSBack.AnchorPoint            = Vector2.new(0.5, 0)
            MSBack.BackgroundColor3       = P.BASE2; MSBack.BackgroundTransparency = 0
            MSBack.BorderSizePixel        = 0; MSBack.Position = UDim2.new(0.5, 0, 0, 4)
            MSBack.Size                   = UDim2.new(0, SUB_W - 8, 0, 20)
            mkCorner(MSBack, R_SM)
            local msEdge = mkBorder(MSBack, P.EDGE, 1, 0.4)

            local MSLabel = Instance.new("TextLabel")
            MSLabel.Name               = "Name"; MSLabel.Parent = MSBack
            MSLabel.BackgroundTransparency = 1; MSLabel.BorderSizePixel = 0
            MSLabel.Position           = UDim2.new(0, 9, 0, 0); MSLabel.Size = UDim2.new(1, -26, 1, 0)
            MSLabel.Font               = Enum.Font.GothamSemibold; MSLabel.Text = cfg3.Name
            MSLabel.TextColor3         = P.INK_MID; MSLabel.TextSize = TEXT_SIZE_SM
            MSLabel.TextXAlignment     = Enum.TextXAlignment.Left
            MSLabel.TextTruncate       = Enum.TextTruncate.AtEnd

            local MSChevron = Instance.new("ImageButton")
            MSChevron.Name               = "Chevron"; MSChevron.Parent = MSBack
            MSChevron.AnchorPoint        = Vector2.new(0, 0.5)
            MSChevron.BackgroundTransparency = 1; MSChevron.BorderSizePixel = 0
            MSChevron.Position           = UDim2.new(1, -18, 0.5, 0); MSChevron.Size = UDim2.new(0, 14, 0, 14)
            MSChevron.ZIndex             = 2
            MSChevron.Image              = "http://www.roblox.com/asset/?id=6031094679"
            MSChevron.ImageColor3        = P.INK_LOW; MSChevron.ScaleType = Enum.ScaleType.Fit

            local MSList = Instance.new("Frame")
            MSList.Name                   = "MSList"; MSList.Parent = MSWrap
            MSList.AnchorPoint            = Vector2.new(0.5, 0)
            MSList.BackgroundColor3       = P.BASE1; MSList.BackgroundTransparency = 0
            MSList.BorderSizePixel        = 0; MSList.ClipsDescendants = true
            MSList.Position               = UDim2.new(0.5, 0, 0, 28)
            MSList.Size                   = UDim2.new(0, SUB_W - 8, 0, 0); MSList.Visible = false
            mkCorner(MSList, R_SM); mkBorder(MSList, P.EDGE, 1, 0.4); mkPad(MSList, 2, 2, 0, 0)

            local MSScroll = Instance.new("ScrollingFrame")
            MSScroll.Parent               = MSList
            MSScroll.BackgroundTransparency = 1; MSScroll.BorderSizePixel = 0
            MSScroll.Size                 = UDim2.new(1, 0, 1, 0)
            MSScroll.CanvasSize           = UDim2.new(0, 0, 0, 0)
            MSScroll.ScrollBarThickness   = 2
            MSScroll.ScrollBarImageColor3 = P.INK_LOW
            MSScroll.ScrollingDirection   = Enum.ScrollingDirection.Y

            local MSItemFlow = Instance.new("UIListLayout")
            MSItemFlow.Parent             = MSScroll
            MSItemFlow.HorizontalAlignment = Enum.HorizontalAlignment.Center
            MSItemFlow.SortOrder          = Enum.SortOrder.LayoutOrder

            kit:track(MSBack.MouseEnter:Connect(function()
                msEdge.Transparency = 0; msEdge.Color = P.EDGE_HI
                MSBack.BackgroundColor3 = P.BASE_HOV
            end))
            kit:track(MSBack.MouseLeave:Connect(function()
                msEdge.Transparency = 0.4; msEdge.Color = P.EDGE
                MSBack.BackgroundColor3 = P.BASE2
            end))

            local MS_MAX_H = 160
            function ms.Update(instant)
                local scale = (Scaler.Scale > 0 and Scaler.Scale or 1)
                local sz = MSItemFlow.AbsoluteContentSize.Y
                local cappedSz = math.min(sz, MS_MAX_H * scale)
                local wrapHeight = ms.Expanded and ((28 * scale + cappedSz + 6) / scale) or 22
                local listHeight = ms.Expanded and (cappedSz / scale + 4) or 0

                MSScroll.CanvasSize = UDim2.new(0, 0, 0, sz / scale)
                if ms.Expanded then
                    MSList.Visible = true
                end

                if instant then
                    MSWrap.Size = UDim2.new(0, SUB_W, 0, wrapHeight)
                    MSList.Size = UDim2.new(0, SUB_W - 8, 0, listHeight)
                    MSChevron.Rotation = ms.Expanded and 180 or 0
                    MSChevron.ImageColor3 = ms.Expanded and P.HUE or P.INK_LOW
                    if not ms.Expanded then
                        MSList.Visible = false
                    end
                else
                    playStoredTween(ms, "_wrapTween", MSWrap, panelTI, {
                        Size = UDim2.new(0, SUB_W, 0, wrapHeight),
                    })
                    playStoredTween(ms, "_listTween", MSList, panelTI, {
                        Size = UDim2.new(0, SUB_W - 8, 0, listHeight),
                    }, function(state)
                        if state == Enum.PlaybackState.Completed and not ms.Expanded then
                            MSList.Visible = false
                        end
                    end)
                    playStoredTween(ms, "_chevronTween", MSChevron, accentTI, {
                        Rotation = ms.Expanded and 180 or 0,
                        ImageColor3 = ms.Expanded and P.HUE or P.INK_LOW,
                    })
                end
            end
            kit:track(MSItemFlow:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
                ms.Update(false)
            end))

            function ms.ToggleValue(val)
                for _, v in next, ms.Values do
                    if v.Value == val then
                        v.Toggle()
                        local active, strs = {}, {}
                        for _, vv in next, ms.Values do
                            if vv.Enabled then active[#active+1] = vv.Value; strs[#strs+1] = tostring(vv.Value) end
                        end
                        MSLabel.Text       = cfg3.Name .. (#strs ~= 0 and (" > " .. table.concat(strs, ", ")) or "")
                        MSLabel.TextColor3 = #strs ~= 0 and P.INK_HI or P.INK_MID
                        if cfg3.Function then task.spawn(cfg3.Function, active) end
                        break
                    end
                end
            end

            local function newMSItem(val)
                local vi = { Enabled = false, Value = val }
                local Btn = Instance.new("TextButton"); Btn.Parent = MSScroll
                Btn.BackgroundColor3 = P.BASE1; Btn.BackgroundTransparency = 0
                Btn.BorderSizePixel  = 0; Btn.Size = UDim2.new(0, SUB_W - 14, 0, 20)
                Btn.Text             = ""; Btn.AutoButtonColor = false
                mkCorner(Btn, R_SM)
                kit:track(Btn.MouseEnter:Connect(function() Btn.BackgroundColor3 = P.BASE_HOV end))
                kit:track(Btn.MouseLeave:Connect(function() Btn.BackgroundColor3 = P.BASE1 end))
                local Lbl = Instance.new("TextLabel"); Lbl.Parent = Btn
                Lbl.BackgroundTransparency = 1; Lbl.BorderSizePixel = 0
                Lbl.Position = UDim2.new(0, 12, 0, 0); Lbl.Size = UDim2.new(1, -18, 1, 0)
                Lbl.Font = Enum.Font.GothamSemibold; Lbl.Text = tostring(val)
                Lbl.TextColor3 = P.INK_MID; Lbl.TextSize = TEXT_SIZE_SM
                Lbl.TextXAlignment = Enum.TextXAlignment.Left
                local Dot = Instance.new("Frame"); Dot.Parent = Btn
                Dot.AnchorPoint = Vector2.new(0, 0.5); Dot.BackgroundColor3 = P.HUE
                Dot.Visible     = false; Dot.BorderSizePixel = 0
                Dot.Position    = UDim2.new(0, 3, 0.5, 0); Dot.Size = UDim2.new(0, 2, 0.5, 0)
                mkCorner(Dot, UDim.new(1, 0))
                kit:track(PaletteSync:Bind(function() Dot.BackgroundColor3 = P.HUE end))
                function vi.Toggle()
                    vi.Enabled  = not vi.Enabled
                    Dot.Visible = vi.Enabled
                    Lbl.TextColor3 = vi.Enabled and P.INK_HI or P.INK_MID
                end
                Btn.MouseButton1Click:Connect(function() ms.ToggleValue(val) end)
                vi.SelectedInstance = Dot; vi.Instance = Btn; return vi
            end

            for _, v in next, cfg3.List do ms.Values[tostring(v)] = newMSItem(v) end
            for _, v in next, (cfg3.Default or {}) do ms.ToggleValue(v) end

            function ms.SetList(list)
                for i, v in next, ms.Values do v.Instance:Destroy(); ms.Values[i] = nil end
                ms.Values = {}
                for _, v in next, list do ms.Values[tostring(v)] = newMSItem(v) end
                ms.Update(true)
            end

            function ms.Expand()
                ms.Expanded = not ms.Expanded
                if ms.Expanded then
                    MSList.Visible = true
                end
                ms.Update(false)
            end
            ms.Update(true)
            kit:track(MSChevron.MouseButton1Click:Connect(ms.Expand))

            kit:register(cfg3.Name .. "MultiDropdown_" .. entryId,
                { Name = cfg3.Name, Instance = MSWrap, Type = "MultiDropdown",
                  OptionsButton = entryId, API = ms, args = cfg3 })
            return ms
        end

        function entry.CreateTextlist(cfg3)
            local tl = { Values = {} }

            local TLWrap = Instance.new("Frame")
            TLWrap.Name                   = "TagList"; TLWrap.Parent = OptionHolder
            TLWrap.BackgroundTransparency = 1; TLWrap.BorderSizePixel = 0
            TLWrap.Size                   = UDim2.new(0, SUB_W, 0, 30)
            tl.Instance                   = TLWrap

            local InputBar = Instance.new("Frame")
            InputBar.Name                   = "InputBar"; InputBar.Parent = TLWrap
            InputBar.AnchorPoint            = Vector2.new(0.5, 0)
            InputBar.BackgroundColor3       = P.BASE2; InputBar.BackgroundTransparency = 0
            InputBar.BorderSizePixel        = 0; InputBar.Position = UDim2.new(0.5, 0, 0, 4)
            InputBar.Size                   = UDim2.new(0, SUB_W - 8, 0, 20)
            mkCorner(InputBar, R_SM); local tlEdge = mkBorder(InputBar, P.EDGE, 1, 0.4)

            local InputField = Instance.new("TextBox"); InputField.Parent = InputBar
            InputField.AnchorPoint            = Vector2.new(0, 0.5)
            InputField.BackgroundTransparency = 1; InputField.BorderSizePixel = 0
            InputField.Position               = UDim2.new(0, 8, 0.5, 0); InputField.Size = UDim2.new(1, -28, 1, 0)
            InputField.ClearTextOnFocus       = false; InputField.Font = Enum.Font.GothamSemibold
            InputField.PlaceholderColor3      = P.INK_LOW; InputField.PlaceholderText = cfg3.Name
            InputField.Text                   = ""; InputField.TextColor3 = P.INK_HI
            InputField.TextSize               = 10; InputField.TextXAlignment = Enum.TextXAlignment.Left

            kit:track(InputBar.MouseEnter:Connect(function() tlEdge.Color = P.EDGE_HI; tlEdge.Transparency = 0 end))
            kit:track(InputBar.MouseLeave:Connect(function() tlEdge.Color = P.EDGE; tlEdge.Transparency = 0.4 end))

            local AddBtn = Instance.new("TextButton"); AddBtn.Parent = InputBar
            AddBtn.AnchorPoint            = Vector2.new(1, 0.5); AddBtn.BackgroundTransparency = 1
            AddBtn.BorderSizePixel        = 0; AddBtn.Position = UDim2.new(1, -5, 0.5, 0)
            AddBtn.Size                   = UDim2.new(0, 14, 0, 14); AddBtn.Font = Enum.Font.GothamBold
            AddBtn.Text                   = "+"; AddBtn.TextColor3 = P.INK_LOW; AddBtn.TextSize = 16; AddBtn.AutoButtonColor = false
            kit:track(AddBtn.MouseEnter:Connect(function() AddBtn.TextColor3 = P.HUE end))
            kit:track(AddBtn.MouseLeave:Connect(function() AddBtn.TextColor3 = P.INK_LOW end))

            local ItemList = Instance.new("Frame"); ItemList.Parent = TLWrap
            ItemList.AnchorPoint            = Vector2.new(0.5, 0); ItemList.BackgroundTransparency = 1
            ItemList.BorderSizePixel        = 0; ItemList.Position = UDim2.new(0.5, 0, 0, 28)
            ItemList.Size                   = UDim2.new(0, SUB_W - 8, 0, 0)
            local ItemFlow = Instance.new("UIListLayout"); ItemFlow.Parent = ItemList
            ItemFlow.HorizontalAlignment  = Enum.HorizontalAlignment.Center
            ItemFlow.SortOrder            = Enum.SortOrder.LayoutOrder; ItemFlow.Padding = UDim.new(0, 2)

            local function syncH()
                TLWrap.Size = UDim2.new(0, SUB_W, 0,
                    (ItemFlow.AbsoluteContentSize.Y + 36 * Scaler.Scale) / Scaler.Scale)
            end
            kit:track(ItemFlow:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(syncH))
            syncH()

            local function addItem(val)
                local vi = { value = val }
                local Chip = Instance.new("TextButton"); Chip.Parent = ItemList
                Chip.BackgroundColor3 = P.BASE2; Chip.BackgroundTransparency = 0; Chip.BorderSizePixel = 0
                Chip.Size             = UDim2.new(0, SUB_W - 8, 0, 20); Chip.Text = ""; Chip.AutoButtonColor = false
                mkCorner(Chip, R_SM)
                local ChipLbl = Instance.new("TextLabel"); ChipLbl.Parent = Chip; ChipLbl.BackgroundTransparency = 1
                ChipLbl.BorderSizePixel = 0; ChipLbl.Position = UDim2.new(0, 8, 0, 0); ChipLbl.Size = UDim2.new(1, -26, 1, 0)
                ChipLbl.Font = Enum.Font.GothamSemibold; ChipLbl.Text = val
                ChipLbl.TextColor3 = P.INK_MID; ChipLbl.TextSize = 10; ChipLbl.TextXAlignment = Enum.TextXAlignment.Left
                kit:track(Chip.MouseEnter:Connect(function() Chip.BackgroundColor3 = P.BASE_HOV end))
                kit:track(Chip.MouseLeave:Connect(function() Chip.BackgroundColor3 = P.BASE2 end))
                local RemBtn = Instance.new("TextButton"); RemBtn.Parent = Chip; RemBtn.AnchorPoint = Vector2.new(1, 0.5)
                RemBtn.BackgroundTransparency = 1; RemBtn.BorderSizePixel = 0
                RemBtn.Position = UDim2.new(1, -6, 0.5, 0); RemBtn.Size = UDim2.new(0, 12, 0, 12)
                RemBtn.Font = Enum.Font.GothamBold; RemBtn.Text = "x"; RemBtn.TextColor3 = P.INK_LOW
                RemBtn.TextSize = 14; RemBtn.AutoButtonColor = false; vi.Instance = Chip
                kit:track(RemBtn.MouseEnter:Connect(function() RemBtn.TextColor3 = P.STATE_OFF end))
                kit:track(RemBtn.MouseLeave:Connect(function() RemBtn.TextColor3 = P.INK_LOW end))
                function vi.Remove() tl.Values[vi.value] = nil; Chip:Destroy() end
                kit:track(RemBtn.MouseButton1Click:Connect(vi.Remove))
                kit:track(Chip.MouseButton1Click:Connect(vi.Remove))
                return vi
            end

            function tl.Add(val)
                if tl.Values[val] then return end
                addItem(val); tl.Values[val] = val
                if cfg3.Function then task.spawn(cfg3.Function, tl.Values) end
            end
            if cfg3.Default then for _, v in next, cfg3.Default do tl.Add(v) end end
            AddBtn.MouseButton1Click:Connect(function()
                local v = InputField.Text; if v == "" then return end
                tl.Add(v); InputField.Text = ""
            end)

            kit:register(cfg3.Name .. "Textlist_" .. entryId,
                { Name = cfg3.Name, Instance = TLWrap, Type = "Textlist",
                  OptionsButton = entryId, API = tl, args = cfg3 })
            return tl
        end

        kit:register(entryId,
            { Name = entryId, Instance = Row, Type = "OptionsButton",
              Window = panelId, API = entry, args = cfg2 })
        return entry
    end

    
    panel.AddNew = panel.CreateOptionsButton
    panel.module = panel.AddNew

    kit:register(panelId,
        { Name = panelId, Instance = Body, Type = "Window", API = panel, args = cfg })
    return panel
end

Spectrum.CreateWindow = Spectrum.window

local OVERLAY_FILE = "Phantom/storage/config/overlay.cfg.json"

local function _normalizeOverlayPath(path)
    return tostring(path or OVERLAY_FILE):gsub("\\", "/")
end

local function _ensureOverlayDir(path)
    local parent = _normalizeOverlayPath(path):match("^(.*)/[^/]+$")
    local current = ""

    if not parent or parent == "" then
        return
    end

    for segment in parent:gmatch("[^/]+") do
        current = current == "" and segment or (current .. "/" .. segment)
        if not isfolder(current) then
            pcall(makefolder, current)
        end
    end
end

local function _readOverlayCfg(path)
    local overlayFile = _normalizeOverlayPath(path)
    local ok, d = pcall(function() return HttpService:JSONDecode(readfile(overlayFile)) end)
    return (ok and type(d) == "table") and d or {}
end
local function _writeOverlayCfg(path, t)
    pcall(function()
        local overlayFile = _normalizeOverlayPath(path)
        _ensureOverlayDir(overlayFile)
        writefile(overlayFile, HttpService:JSONEncode(t))
    end)
end

function Spectrum.CreateHudConfig(cfg)
    cfg = cfg or {}
    local ovl       = {}
    local overlayFile = cfg.StateFile or OVERLAY_FILE
    local persisted = _readOverlayCfg(overlayFile)
    local stateCache = {}
    local overlayLayoutKey = tostring(cfg.Name or "OverlayEditor")
    local overlayLayoutRecord

    for key, value in pairs(persisted) do
        stateCache[key] = value
    end

    local function persist(key, val)
        stateCache[key] = val; _writeOverlayCfg(overlayFile, stateCache)
    end

    local OvlFrame = Instance.new("Frame")
    OvlFrame.Name                   = "OverlayEditor"; OvlFrame.Parent = Screen
    OvlFrame.BackgroundColor3       = P.BASE0; OvlFrame.BackgroundTransparency = 0
    OvlFrame.BorderSizePixel        = 0; OvlFrame.AnchorPoint = Vector2.new(0.5, 0.5)
    OvlFrame.Position               = UDim2.new(0.5, 0, 0.5, 0); OvlFrame.Size = UDim2.new(0, 500, 0, 380)
    OvlFrame.Visible                = false; OvlFrame.ZIndex = 100
    mkCorner(OvlFrame, R_MD); mkBorder(OvlFrame, P.EDGE, 1)
    ovl.Instance = OvlFrame
    overlayLayoutRecord = registerFloatingLayout(overlayLayoutKey, OvlFrame, {
        DefaultPosition = OvlFrame.Position,
    })
    if Spectrum.FloatingLayout and Spectrum.FloatingLayout[overlayLayoutKey] then
        applyResponsiveFloatingLayout(OvlFrame, Spectrum.FloatingLayout[overlayLayoutKey])
    end

    local OvlHeader = Instance.new("Frame")
    OvlHeader.Name             = "OvlHeader"; OvlHeader.Parent = OvlFrame
    OvlHeader.BackgroundColor3 = P.BASE2; OvlHeader.BorderSizePixel = 0
    OvlHeader.Active           = true
    OvlHeader.Size             = UDim2.new(1, 0, 0, HDR_H)
    mkCorner(OvlHeader, R_MD); mkBorder(OvlHeader, P.EDGE, 1)
    local OvlHeaderFix = Instance.new("Frame"); OvlHeaderFix.Parent = OvlHeader
    OvlHeaderFix.BackgroundColor3 = P.BASE2; OvlHeaderFix.BorderSizePixel = 0
    OvlHeaderFix.Position = UDim2.new(0, 0, 0.5, 0); OvlHeaderFix.Size = UDim2.new(1, 0, 0.5, 0)

    local OvlTitle = Instance.new("TextLabel"); OvlTitle.Parent = OvlHeader
    OvlTitle.BackgroundTransparency = 1; OvlTitle.BorderSizePixel = 0
    OvlTitle.Position = UDim2.new(0, 14, 0, 0); OvlTitle.Size = UDim2.new(1, -50, 1, 0)
    OvlTitle.Font = Enum.Font.GothamBold; OvlTitle.Text = "Overlay Editor"
    OvlTitle.TextColor3 = P.INK_HI; OvlTitle.TextSize = 10
    OvlTitle.TextXAlignment = Enum.TextXAlignment.Left; OvlTitle.ZIndex = 2

    local OvlClose = Instance.new("TextButton"); OvlClose.Parent = OvlHeader
    OvlClose.AnchorPoint = Vector2.new(1, 0.5); OvlClose.BackgroundTransparency = 1
    OvlClose.BorderSizePixel = 0; OvlClose.Position = UDim2.new(1, -8, 0.5, 0)
    OvlClose.Size = UDim2.new(0, 14, 0, 14); OvlClose.Font = Enum.Font.GothamBold
    OvlClose.Text = "x"; OvlClose.TextColor3 = P.INK_LOW; OvlClose.TextSize = 14
    OvlClose.AutoButtonColor = false; OvlClose.ZIndex = 3
    OvlClose.MouseEnter:Connect(function() OvlClose.TextColor3 = P.STATE_OFF end)
    OvlClose.MouseLeave:Connect(function() OvlClose.TextColor3 = P.INK_LOW end)
    OvlClose.MouseButton1Click:Connect(function()
        if ovl.Hide then
            ovl.Hide()
        else
            OvlFrame.Visible = false
        end
    end)
    kit:drag(OvlFrame, OvlHeader, {
        OnReleased = function()
            if overlayLayoutRecord then
                overlayLayoutRecord.DefaultLayout = captureResponsiveFloatingLayout(OvlFrame)
            end
            if Spectrum.SaveLayout then
                Spectrum.SaveLayout()
            end
        end,
    })

    
    local PresetPane = Instance.new("Frame"); PresetPane.Parent = OvlFrame
    PresetPane.BackgroundColor3 = P.BASE1; PresetPane.BorderSizePixel = 0
    PresetPane.Position = UDim2.new(0, 0, 0, HDR_H); PresetPane.Size = UDim2.new(0, 200, 1, -HDR_H)
    mkBorder(PresetPane, P.EDGE, 1, 0.3)

    local PresetTitle = Instance.new("TextLabel"); PresetTitle.Parent = PresetPane
    PresetTitle.BackgroundColor3 = P.BASE2; PresetTitle.BorderSizePixel = 0
    PresetTitle.Size = UDim2.new(1, 0, 0, 20)
    PresetTitle.Font = Enum.Font.GothamBold; PresetTitle.Text = "PRESETS"
    PresetTitle.TextColor3 = P.INK_LOW; PresetTitle.TextSize = 9
    PresetTitle.TextXAlignment = Enum.TextXAlignment.Center
    mkBorder(PresetTitle, P.EDGE, 1, 0.5)

    local PresetScroll = Instance.new("ScrollingFrame"); PresetScroll.Parent = PresetPane
    PresetScroll.BackgroundTransparency = 1; PresetScroll.BorderSizePixel = 0
    PresetScroll.Position = UDim2.new(0, 0, 0, 20); PresetScroll.Size = UDim2.new(1, 0, 0, 150)
    PresetScroll.CanvasSize = UDim2.new(0, 0, 0, 0); PresetScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    PresetScroll.ScrollBarThickness = 2; PresetScroll.ScrollBarImageColor3 = P.EDGE_HI
    local PresetFlow = Instance.new("UIListLayout"); PresetFlow.Parent = PresetScroll
    PresetFlow.SortOrder = Enum.SortOrder.LayoutOrder; PresetFlow.Padding = UDim.new(0, 1)
    mkPad(PresetScroll, 3, 3, 0, 0)

    local activePreset, activeRow, presetRows = nil, nil, {}

    local function highlightRow(name, rowFrame)
        if activeRow then activeRow.BackgroundColor3 = P.BASE2 end
        activePreset = name; activeRow = rowFrame
        rowFrame.BackgroundColor3 = P.BASE_LIT
    end

    local function rebuildPresetList(dir)
        for _, r in ipairs(presetRows) do r:Destroy() end
        presetRows = {}
        local d = dir or ("Phantom/storage/configs/" .. tostring(game.PlaceId) .. "/")
        if not isfolder(d) then makefolder(d) end
        local ok, files = pcall(listfiles, d)
        if not ok then return end
        for _, f in ipairs(files) do
            local fname = string.match(f, "([^/\\]+)$") or f
            if fname:match("%.json$") then
                local pname = fname:gsub("%.json$", "")
                local row = Instance.new("TextButton"); row.Parent = PresetScroll
                row.BackgroundColor3 = P.BASE2; row.BackgroundTransparency = 0
                row.BorderSizePixel  = 0; row.Size = UDim2.new(1, -6, 0, 22)
                row.Text             = ""; row.AutoButtonColor = false; mkCorner(row, R_SM)
                local lbl = Instance.new("TextLabel"); lbl.Parent = row
                lbl.BackgroundTransparency = 1; lbl.BorderSizePixel = 0
                lbl.Position = UDim2.new(0, 8, 0, 0); lbl.Size = UDim2.new(1, -10, 1, 0)
                lbl.Font = Enum.Font.GothamSemibold; lbl.Text = pname
                lbl.TextColor3 = P.INK_MID; lbl.TextSize = 10
                lbl.TextTruncate = Enum.TextTruncate.AtEnd
                lbl.TextXAlignment = Enum.TextXAlignment.Left
                row.MouseButton1Click:Connect(function()
                    highlightRow(pname, row); lbl.TextColor3 = P.INK_HI
                end)
                row.MouseEnter:Connect(function()
                    if activePreset ~= pname then row.BackgroundColor3 = P.BASE_HOV end
                end)
                row.MouseLeave:Connect(function()
                    if activePreset ~= pname then row.BackgroundColor3 = P.BASE2 end
                end)
                table.insert(presetRows, row)
            end
        end
    end

    local Sep1 = Instance.new("Frame"); Sep1.Parent = PresetPane
    Sep1.BackgroundColor3 = P.EDGE; Sep1.BorderSizePixel = 0
    Sep1.Position = UDim2.new(0, 6, 0, 172); Sep1.Size = UDim2.new(1, -12, 0, 1)

    local NameBox = Instance.new("Frame"); NameBox.Parent = PresetPane
    NameBox.BackgroundColor3 = P.BASE2; NameBox.BorderSizePixel = 0
    NameBox.Position = UDim2.new(0, 6, 0, 176); NameBox.Size = UDim2.new(1, -12, 0, 22)
    mkCorner(NameBox, R_SM); mkBorder(NameBox, P.EDGE, 1, 0.4)
    local NameField = Instance.new("TextBox"); NameField.Parent = NameBox
    NameField.BackgroundTransparency = 1; NameField.BorderSizePixel = 0
    NameField.Position = UDim2.new(0, 6, 0, 0); NameField.Size = UDim2.new(1, -12, 1, 0)
    NameField.Font = Enum.Font.GothamSemibold; NameField.PlaceholderText = "preset name..."
    NameField.Text = ""; NameField.TextColor3 = P.INK_HI; NameField.TextSize = TEXT_SIZE_SM
    NameField.PlaceholderColor3 = P.INK_LOW; NameField.ClearTextOnFocus = false

    local StatusLbl = Instance.new("TextLabel"); StatusLbl.Parent = PresetPane
    StatusLbl.BackgroundTransparency = 1; StatusLbl.BorderSizePixel = 0
    StatusLbl.Position = UDim2.new(0, 6, 0, 256); StatusLbl.Size = UDim2.new(1, -12, 0, 12)
    StatusLbl.Font = Enum.Font.GothamSemibold; StatusLbl.Text = ""
    StatusLbl.TextColor3 = P.INK_LOW; StatusLbl.TextSize = 9
    StatusLbl.TextXAlignment = Enum.TextXAlignment.Center

    local function flash(msg, col)
        StatusLbl.Text = msg; StatusLbl.TextColor3 = col or P.INK_LOW
        task.delay(3, function() if StatusLbl.Text == msg then StatusLbl.Text = "" end end)
    end

    local Sep2 = Instance.new("Frame"); Sep2.Parent = PresetPane
    Sep2.BackgroundColor3 = P.EDGE; Sep2.BorderSizePixel = 0
    Sep2.Position = UDim2.new(0, 6, 0, 270); Sep2.Size = UDim2.new(1, -12, 0, 1)

    local AutoLbl = Instance.new("TextLabel"); AutoLbl.Parent = PresetPane
    AutoLbl.BackgroundTransparency = 1; AutoLbl.BorderSizePixel = 0
    AutoLbl.Position = UDim2.new(0, 6, 0, 275); AutoLbl.Size = UDim2.new(1, -50, 0, 12)
    AutoLbl.Font = Enum.Font.GothamBold; AutoLbl.Text = "AUTO-LOAD ON JOIN"
    AutoLbl.TextColor3 = P.INK_LOW; AutoLbl.TextSize = 8
    AutoLbl.TextXAlignment = Enum.TextXAlignment.Left

    local autoEnabled = persisted["__preload"] == true
    local AutoTrack = Instance.new("Frame"); AutoTrack.Parent = PresetPane
    AutoTrack.BackgroundColor3 = P.BASE1; AutoTrack.BorderSizePixel = 0
    AutoTrack.Position = UDim2.new(1, -36, 0, 274); AutoTrack.Size = UDim2.new(0, 28, 0, 14)
    mkCorner(AutoTrack, UDim.new(1, 0)); local autoEdge = mkBorder(AutoTrack, P.EDGE, 1)
    local AutoKnob = Instance.new("Frame"); AutoKnob.Parent = AutoTrack
    AutoKnob.AnchorPoint = Vector2.new(0, 0.5); AutoKnob.BackgroundColor3 = P.HUE
    AutoKnob.BorderSizePixel = 0; AutoKnob.Size = UDim2.new(0, 10, 0, 10)
    AutoKnob.Position = autoEnabled and UDim2.fromScale(0.55, 0.5) or UDim2.fromScale(0.1, 0.5)
    mkCorner(AutoKnob, UDim.new(1, 0))
    kit:track(PaletteSync:Bind(function() AutoKnob.BackgroundColor3 = P.HUE end))

    local function setAutoLoad(on, skipAnim)
        autoEnabled              = on
        AutoTrack.BackgroundColor3 = on and P.HUE:Lerp(P.BASE1, 0.55) or P.BASE1
        autoEdge.Color           = on and P.HUE or P.EDGE
        local tgt = on and UDim2.fromScale(0.58, 0.5) or UDim2.fromScale(0.10, 0.5)
        if skipAnim then AutoKnob.Position = tgt
        else AutoKnob:TweenPosition(tgt, "Out", "Quad", 0.15, true) end
        persist("__preload", on)
    end
    if autoEnabled then setAutoLoad(true, true) end

    local AutoBtn = Instance.new("TextButton"); AutoBtn.Parent = PresetPane
    AutoBtn.BackgroundTransparency = 1; AutoBtn.BorderSizePixel = 0
    AutoBtn.Position = UDim2.new(1, -36, 0, 268); AutoBtn.Size = UDim2.new(0, 28, 0, 14)
    AutoBtn.Text = ""; AutoBtn.AutoButtonColor = false
    AutoBtn.MouseButton1Click:Connect(function() setAutoLoad(not autoEnabled) end)

    local AutoNameLbl = Instance.new("TextLabel"); AutoNameLbl.Parent = PresetPane
    AutoNameLbl.BackgroundColor3 = P.BASE2; AutoNameLbl.BackgroundTransparency = 0
    AutoNameLbl.BorderSizePixel  = 0
    AutoNameLbl.Position = UDim2.new(0, 6, 0, 292); AutoNameLbl.Size = UDim2.new(1, -12, 0, 18)
    AutoNameLbl.Font = Enum.Font.GothamSemibold
    AutoNameLbl.Text = "  " .. (persisted["__preloadCfg"] or "default")
    AutoNameLbl.TextColor3 = P.INK_MID; AutoNameLbl.TextSize = 10
    AutoNameLbl.TextXAlignment = Enum.TextXAlignment.Left
    mkCorner(AutoNameLbl, R_SM); mkBorder(AutoNameLbl, P.EDGE, 1, 0.4)

    local SetAutoBtn = Instance.new("TextButton"); SetAutoBtn.Parent = PresetPane
    SetAutoBtn.BackgroundTransparency = 1; SetAutoBtn.BorderSizePixel = 0
    SetAutoBtn.Position = UDim2.new(0, 6, 0, 292); SetAutoBtn.Size = UDim2.new(1, -12, 0, 18)
    SetAutoBtn.Text = ""; SetAutoBtn.AutoButtonColor = false
    SetAutoBtn.MouseButton1Click:Connect(function()
        if activePreset then
            persist("__preloadCfg", activePreset)
            AutoNameLbl.Text      = "  " .. activePreset
            AutoNameLbl.TextColor3 = P.INK_HI
            flash("Auto-load -> " .. activePreset, P.STATE_ON)
        else
            flash("Select a preset first", P.CAUTION)
        end
    end)

    local function makeActionBtn(lbl, x, y, w, col, fn)
        local btn = Instance.new("TextButton"); btn.Parent = PresetPane
        btn.BackgroundColor3 = col or P.BASE2; btn.BorderSizePixel = 0
        btn.Position = UDim2.new(0, x, 0, y); btn.Size = UDim2.new(0, w, 0, 22)
        btn.Font = Enum.Font.GothamBold; btn.Text = lbl
        btn.TextColor3 = P.INK_HI; btn.TextSize = 10; btn.AutoButtonColor = false
        mkCorner(btn, R_SM); mkBorder(btn, P.EDGE, 1, 0.4)
        btn.MouseEnter:Connect(function() btn.BackgroundColor3 = col == P.STATE_OFF and P.STATE_OFF or P.BASE_HOV end)
        btn.MouseLeave:Connect(function() btn.BackgroundColor3 = col or P.BASE2 end)
        btn.MouseButton1Click:Connect(fn); return btn
    end

    local LoadBtn = makeActionBtn("Load", 6,   202, 42, P.BASE2, function()
        if not activePreset then flash("Select a preset first", P.CAUTION); return end
        ovl.LoadRequest = activePreset; flash("Loading " .. activePreset .. "...", P.HUE)
    end)
    local SaveBtn = makeActionBtn("Save", 52,  202, 42, P.BASE2, function()
        if not activePreset then flash("Select a preset first", P.CAUTION); return end
        ovl.SaveRequest = activePreset; flash("Saved " .. activePreset, P.STATE_ON)
    end)
    local NewBtn = makeActionBtn("New",  98,  202, 42, P.BASE2, function()
        local n = NameField.Text:gsub("[^%w_%-]", "_")
        if n == "" then flash("Enter a name first", P.CAUTION); return end
        ovl.SaveRequest = n; NameField.Text = ""
        flash("Created " .. n, P.STATE_ON)
        rebuildPresetList(ovl._dir)
    end)
    local DeleteBtn = makeActionBtn("Del",  144, 202, 50, P.STATE_OFF, function()
        if not activePreset then flash("Select a preset first", P.CAUTION); return end
        ovl.DeleteRequest = activePreset
        activePreset = nil; activeRow = nil
        flash("Deleted", P.STATE_OFF); rebuildPresetList(ovl._dir)
    end)

    
    local SettingsPane = Instance.new("Frame"); SettingsPane.Parent = OvlFrame
    SettingsPane.BackgroundColor3 = P.BASE1; SettingsPane.BorderSizePixel = 0
    SettingsPane.Position = UDim2.new(0, 202, 0, HDR_H); SettingsPane.Size = UDim2.new(1, -202, 1, -HDR_H)
    mkBorder(SettingsPane, P.EDGE, 1, 0.3)

    local SettingsList = Instance.new("ScrollingFrame"); SettingsList.Parent = SettingsPane
    SettingsList.BackgroundTransparency = 1; SettingsList.BorderSizePixel = 0
    SettingsList.Size = UDim2.new(1, 0, 1, 0); SettingsList.CanvasSize = UDim2.new(0, 0, 0, 0)
    SettingsList.AutomaticCanvasSize = Enum.AutomaticSize.Y
    SettingsList.ScrollBarThickness = 2; SettingsList.ScrollBarImageColor3 = P.EDGE_HI
    local SettingsFlow = Instance.new("UIListLayout"); SettingsFlow.Parent = SettingsList
    SettingsFlow.HorizontalAlignment = Enum.HorizontalAlignment.Center
    SettingsFlow.SortOrder = Enum.SortOrder.LayoutOrder; SettingsFlow.Padding = UDim.new(0, 1)
    mkPad(SettingsList, 4, 4, 0, 0)

    local function layoutOverlay()
        local viewport = getViewportSize()

        local frameWidth = math.clamp(math.floor(viewport.X * 0.34), 430, 520)
        local frameHeight = math.clamp(math.floor(viewport.Y * 0.42), 320, 390)
        local sidebarWidth = math.clamp(math.floor(frameWidth * 0.38), 188, 212)

        local contentInset = 6
        local bodyTop = HDR_H
        local bodyHeight = frameHeight - bodyTop
        local footerHeight = 134

        local listHeight = math.max(96, bodyHeight - footerHeight)
        local actionY = bodyTop + listHeight + 8
        local fieldY = actionY + 26
        local statusY = fieldY + 26
        local autoDividerY = statusY + 18
        local autoLabelY = autoDividerY + 6
        local autoRowY = autoLabelY + 18

        OvlFrame.Size = UDim2.fromOffset(frameWidth, frameHeight)

        task.defer(function()
            if not OvlFrame or not OvlFrame.Parent then return end

            local sol = Spectrum.FloatingLayout and Spectrum.FloatingLayout[overlayLayoutKey]

            if sol then
                applyResponsiveFloatingLayout(OvlFrame, sol)
            else
                OvlFrame.AnchorPoint = Vector2.new(0.5, 0.5)
                OvlFrame.Position = UDim2.fromScale(0.5, 0.5)
            end
        end)

        PresetPane.Position = UDim2.new(0, 0, 0, bodyTop)
        PresetPane.Size = UDim2.new(0, sidebarWidth, 1, -bodyTop)

        SettingsPane.Position = UDim2.new(0, sidebarWidth + 2, 0, bodyTop)
        SettingsPane.Size = UDim2.new(1, -(sidebarWidth + 2), 1, -bodyTop)

        PresetTitle.Size = UDim2.new(1, 0, 0, 20)
        PresetScroll.Position = UDim2.new(0, 0, 0, 20)
        PresetScroll.Size = UDim2.new(1, 0, 0, listHeight)

        Sep1.Position = UDim2.new(0, contentInset, 0, actionY - 4)
        Sep1.Size = UDim2.new(1, -(contentInset * 2), 0, 1)

        NameBox.Position = UDim2.new(0, contentInset, 0, fieldY)
        NameBox.Size = UDim2.new(1, -(contentInset * 2), 0, 22)

        StatusLbl.Position = UDim2.new(0, contentInset, 0, statusY)
        StatusLbl.Size = UDim2.new(1, -(contentInset * 2), 0, 12)

        Sep2.Position = UDim2.new(0, contentInset, 0, autoDividerY)
        Sep2.Size = UDim2.new(1, -(contentInset * 2), 0, 1)

        AutoLbl.Position = UDim2.new(0, contentInset, 0, autoLabelY)
        AutoLbl.Size = UDim2.new(1, -50, 0, 12)

        AutoTrack.Position = UDim2.new(1, -36, 0, autoLabelY - 1)
        AutoBtn.Position = UDim2.new(1, -36, 0, autoLabelY - 7)

        AutoNameLbl.Position = UDim2.new(0, contentInset, 0, autoRowY)
        AutoNameLbl.Size = UDim2.new(1, -(contentInset * 2), 0, 18)

        SetAutoBtn.Position = UDim2.new(0, contentInset, 0, autoRowY)
        SetAutoBtn.Size = UDim2.new(1, -(contentInset * 2), 0, 18)

        local buttonWidth = math.floor((sidebarWidth - (contentInset * 2) - 6) / 4)
        local buttonGap = 2

        LoadBtn.Position = UDim2.new(0, contentInset, 0, actionY)
        LoadBtn.Size = UDim2.new(0, buttonWidth, 0, 22)

        SaveBtn.Position = UDim2.new(0, contentInset + buttonWidth + buttonGap, 0, actionY)
        SaveBtn.Size = UDim2.new(0, buttonWidth, 0, 22)

        NewBtn.Position = UDim2.new(0, contentInset + ((buttonWidth + buttonGap) * 2), 0, actionY)
        NewBtn.Size = UDim2.new(0, buttonWidth, 0, 22)

        DeleteBtn.Position = UDim2.new(0, contentInset + ((buttonWidth + buttonGap) * 3), 0, actionY)
        DeleteBtn.Size = UDim2.new(0, buttonWidth, 0, 22)
    end

    if workspace.CurrentCamera then
        kit:track(workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
            task.defer(layoutOverlay)
        end))
    end
    kit:track(Scaler:GetPropertyChangedSignal("Scale"):Connect(function()
        task.defer(layoutOverlay)
    end))
    task.defer(layoutOverlay)

    ovl.SettingsList    = SettingsList
    ovl._resetCbs       = {}
    ovl._dir            = nil

    ovl.SetDir = function(dir)
        ovl._dir = dir; rebuildPresetList(dir)
    end
    ovl.RefreshConfigs = function() rebuildPresetList(ovl._dir) end
    task.defer(function() rebuildPresetList(ovl._dir) end)

    function ovl.AddSectionHeader(label)
        local sec = Instance.new("Frame"); sec.Parent = SettingsList
        sec.BackgroundTransparency = 1; sec.BorderSizePixel = 0; sec.Size = UDim2.new(1, -8, 0, 18)
        local line = Instance.new("Frame"); line.Parent = sec
        line.BackgroundColor3 = P.EDGE; line.BorderSizePixel = 0
        line.Position = UDim2.new(0, 0, 0.5, 0); line.Size = UDim2.new(1, 0, 0, 1)
        local lbl = Instance.new("TextLabel"); lbl.Parent = sec
        lbl.BackgroundColor3 = P.BASE1; lbl.BackgroundTransparency = 0; lbl.BorderSizePixel = 0
        lbl.AutomaticSize = Enum.AutomaticSize.X; lbl.Size = UDim2.new(0, 0, 1, 0); lbl.Position = UDim2.new(0, 6, 0, 0)
        lbl.Font = Enum.Font.GothamBold; lbl.Text = "  " .. label .. "  "
        lbl.TextColor3 = P.INK_LOW; lbl.TextSize = 9
    end

    function ovl.AddToggleRow(label, default, cb)
        local persistedValue = persisted[label]
        local initVal  = type(persistedValue) == "boolean" and persistedValue or (default == true)
        local togState = false

        local TogRow = Instance.new("TextButton"); TogRow.Parent = SettingsList
        TogRow.BackgroundColor3 = P.BASE2; TogRow.BackgroundTransparency = 0
        TogRow.BorderSizePixel  = 0; TogRow.Size = UDim2.new(1, -8, 0, 22)
        TogRow.Text             = ""; TogRow.AutoButtonColor = false; mkCorner(TogRow, R_SM)

        local lbl = Instance.new("TextLabel"); lbl.Parent = TogRow
        lbl.BackgroundTransparency = 1; lbl.BorderSizePixel = 0
        lbl.Position = UDim2.new(0, 9, 0, 0); lbl.Size = UDim2.new(1, -42, 1, 0)
        lbl.Font = Enum.Font.GothamSemibold; lbl.Text = label
lbl.TextColor3 = P.INK_MID; lbl.TextSize = TEXT_SIZE_SM; lbl.TextXAlignment = Enum.TextXAlignment.Left

        local Trk = Instance.new("Frame"); Trk.Parent = TogRow
        Trk.AnchorPoint = Vector2.new(1, 0.5); Trk.BackgroundColor3 = P.BASE1; Trk.BorderSizePixel = 0
        Trk.Position = UDim2.new(1, -8, 0.5, 0); Trk.Size = UDim2.new(0, 22, 0, 11)
        mkCorner(Trk, UDim.new(1, 0)); local trkEdge = mkBorder(Trk, P.EDGE, 1)

        local Knob = Instance.new("Frame"); Knob.Parent = Trk
        Knob.AnchorPoint = Vector2.new(0, 0); Knob.BackgroundColor3 = P.HUE
        Knob.BorderSizePixel = 0; Knob.Position = UDim2.fromOffset(2, 2)
        Knob.Size = UDim2.new(0, 7, 0, 7); mkCorner(Knob, UDim.new(1, 0))
        kit:track(PaletteSync:Bind(function() Knob.BackgroundColor3 = P.HUE end))

        local rowApi = { Enabled = false }
        function rowApi.Set(on, skipAnim)
            togState = on; rowApi.Enabled = on
            Trk.BackgroundColor3 = on and P.HUE:Lerp(P.BASE1, 0.55) or P.BASE1
            trkEdge.Color        = on and P.HUE or P.EDGE
            lbl.TextColor3       = on and P.INK_HI or P.INK_MID
            local tgt = on and UDim2.fromOffset(13, 2) or UDim2.fromOffset(2, 2)
            if skipAnim then Knob.Position = tgt
            else Knob:TweenPosition(tgt, "Out", "Quad", 0.15, true) end
            persist(label, on)
            if cb then task.spawn(cb, on) end
        end
        rowApi.Set(initVal, true)

        TogRow.MouseButton1Click:Connect(function() rowApi.Set(not togState) end)
        kit:track(TogRow.MouseEnter:Connect(function() TogRow.BackgroundColor3 = P.BASE_HOV end))
        kit:track(TogRow.MouseLeave:Connect(function() TogRow.BackgroundColor3 = P.BASE2 end))
        return rowApi
    end

    function ovl.AddSliderRow(label, mn, mx, def, rnd, cb)
        local persistedValue = persisted[label]
        local initVal = type(persistedValue) == "number" and persistedValue or (def or mn)
        local cur     = initVal
        local r       = rnd or 0
        local function fmt(v)
            return r == 0 and tostring(math.floor(v)) or string.format("%." .. r .. "f", v)
        end

        local SlRow = Instance.new("Frame"); SlRow.Parent = SettingsList
        SlRow.BackgroundColor3 = P.BASE2; SlRow.BackgroundTransparency = 0
        SlRow.BorderSizePixel  = 0; SlRow.Size = UDim2.new(1, -8, 0, 34); mkCorner(SlRow, R_SM)

        local nmLbl = Instance.new("TextLabel"); nmLbl.Parent = SlRow
        nmLbl.BackgroundTransparency = 1; nmLbl.BorderSizePixel = 0
        nmLbl.Position = UDim2.new(0, 9, 0, 3); nmLbl.Size = UDim2.new(1, -52, 0, 13)
        nmLbl.Font = Enum.Font.GothamSemibold; nmLbl.Text = label
        nmLbl.TextColor3 = P.INK_MID; nmLbl.TextSize = 10; nmLbl.TextXAlignment = Enum.TextXAlignment.Left

        local vLbl = Instance.new("TextLabel"); vLbl.Parent = SlRow
        vLbl.BackgroundTransparency = 1; vLbl.BorderSizePixel = 0
        vLbl.AnchorPoint = Vector2.new(1, 0); vLbl.Position = UDim2.new(1, -7, 0, 3)
        vLbl.Size = UDim2.new(0, 38, 0, 13); vLbl.Font = Enum.Font.GothamBold
        vLbl.Text = fmt(cur); vLbl.TextColor3 = P.HUE; vLbl.TextSize = 10
        vLbl.TextXAlignment = Enum.TextXAlignment.Right
        kit:track(PaletteSync:Bind(function() vLbl.TextColor3 = P.HUE end))

        local Trk = Instance.new("Frame"); Trk.Parent = SlRow
        Trk.AnchorPoint = Vector2.new(0.5, 1); Trk.BackgroundColor3 = P.BASE1
        Trk.BorderSizePixel = 0; Trk.Position = UDim2.new(0.5, 0, 1, -7)
        Trk.Size = UDim2.new(1, -18, 0, 3); mkCorner(Trk, UDim.new(1, 0))

        local Fill = Instance.new("Frame"); Fill.Parent = Trk
        Fill.AnchorPoint = Vector2.new(0, 0.5); Fill.BackgroundColor3 = P.HUE
        Fill.BorderSizePixel = 0; Fill.Position = UDim2.new(0, 0, 0.5, 0)
        Fill.Size = UDim2.new((cur - mn) / math.max(mx - mn, 0.001), 0, 1, 0)
        mkCorner(Fill, UDim.new(1, 0))
        kit:track(PaletteSync:Bind(function() Fill.BackgroundColor3 = P.HUE end))

        local rowApi = {}
        function rowApi.Set(v, silent)
            cur = math.clamp(v, mn, mx)
            Fill.Size = UDim2.new((cur - mn) / math.max(mx - mn, 0.001), 0, 1, 0)
            vLbl.Text = fmt(cur)
            if not silent then persist(label, cur) end
            if cb then task.spawn(cb, cur) end
        end

        local sliding = false
        kit:track(Trk.InputBegan:Connect(function(i)
            if i.UserInputType == Enum.UserInputType.MouseButton1 then sliding = true end
        end))
        kit:track(Trk.InputEnded:Connect(function(i)
            if i.UserInputType == Enum.UserInputType.MouseButton1 then sliding = false end
        end))
        kit:track(UIS.InputChanged:Connect(function(i)
            if not sliding or not isPointerMove(i.UserInputType) then return end
            local sx = math.clamp((i.Position.X - Trk.AbsolutePosition.X) / Trk.AbsoluteSize.X, 0, 1)
            local nv = math.floor((((mx - mn) * sx + mn) * (10 ^ r)) + 0.5) / (10 ^ r)
            rowApi.Set(nv)
        end))
        kit:track(SlRow.MouseEnter:Connect(function() SlRow.BackgroundColor3 = P.BASE_HOV end))
        kit:track(SlRow.MouseLeave:Connect(function() SlRow.BackgroundColor3 = P.BASE2 end))
        rowApi.Set(cur, true)
        table.insert(ovl._resetCbs, function() rowApi.Set(def or mn) end)
        return rowApi
    end

    function ovl.CaptureDefaultPosition()
        if overlayLayoutRecord then
            overlayLayoutRecord.DefaultPosition = OvlFrame.Position
            overlayLayoutRecord.DefaultLayout = captureResponsiveFloatingLayout(OvlFrame)
        end
        return OvlFrame.Position
    end

    function ovl.SavePosition()
        if Spectrum.SaveLayout then
            Spectrum.SaveLayout()
        end
    end

    local function tweenOverlayVisible(visible)
        local position = OvlFrame.Position
        local target = UDim2.new(position.X.Scale, position.X.Offset, position.Y.Scale, position.Y.Offset)
        local offset = UDim2.new(position.X.Scale, position.X.Offset, position.Y.Scale, position.Y.Offset + (visible and 0 or 10))

        if visible then
            OvlFrame.Visible = true
            OvlFrame.Position = UDim2.new(position.X.Scale, position.X.Offset, position.Y.Scale, position.Y.Offset + 10)
            playStoredTween(ovl, "_overlayVisibilityTween", OvlFrame, panelTI, {
                Position = target,
            })
        else
            playStoredTween(ovl, "_overlayVisibilityTween", OvlFrame, accentTI, {
                Position = offset,
            }, function(state)
                if state == Enum.PlaybackState.Completed and not ovl._visible then
                    OvlFrame.Visible = false
                end
            end)
        end
    end

    function ovl.Show()
        ovl._visible = true
        tweenOverlayVisible(true)
    end

    function ovl.Hide()
        ovl._visible = false
        tweenOverlayVisible(false)
    end

    function ovl.Toggle()
        if OvlFrame.Visible and ovl._visible ~= false then
            ovl.Hide()
        else
            ovl.Show()
        end
    end

    return ovl
end

function Spectrum.CreateConfigBar(editor)
    local BAR_H = 18
    local mobileButton
    local mobileButtonTheme
    local mobileButtonHandle
    local mobileButtonVisibleSync
    local barManualPosition = false

    local Bar = Instance.new("Frame")
    Bar.Name                   = "PresetBar"; Bar.Parent = Root
    Bar.BackgroundColor3       = P.BASE1; Bar.BackgroundTransparency = 0
    Bar.BorderSizePixel        = 0; Bar.AnchorPoint = Vector2.new(0.5, 0)
    Bar.Active                 = true
    Bar.Position               = UDim2.new(0.5, 0, 0, getPresetBarTopOffset(BAR_H)); Bar.Size = UDim2.new(0, 260, 0, BAR_H)
    mkCorner(Bar, R_SM); mkBorder(Bar, P.EDGE, 1, 0.3)

    local BarGlow = Instance.new("Frame")
    BarGlow.Name = "Glow"
    BarGlow.Parent = Bar
    BarGlow.BackgroundColor3 = P.HUE
    BarGlow.BackgroundTransparency = 0.9
    BarGlow.BorderSizePixel = 0
    BarGlow.Size = UDim2.new(1, 0, 0.7, 0)
    local BarGlowFade = Instance.new("UIGradient")
    BarGlowFade.Rotation = 90
    BarGlowFade.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.12),
        NumberSequenceKeypoint.new(1, 1),
    })
    BarGlowFade.Parent = BarGlow

    local BarTitle = Instance.new("TextLabel"); BarTitle.Parent = Bar
    BarTitle.BackgroundTransparency = 1; BarTitle.BorderSizePixel = 0
    BarTitle.Position = UDim2.new(0, 8, 0, 0); BarTitle.Size = UDim2.new(1, -50, 1, 0)
    BarTitle.Font = Enum.Font.GothamBold; BarTitle.Text = "Presets"
    BarTitle.TextColor3 = P.INK_MID; BarTitle.TextSize = 9; BarTitle.TextXAlignment = Enum.TextXAlignment.Left

    local ActiveLbl = Instance.new("TextLabel"); ActiveLbl.Parent = Bar
    ActiveLbl.BackgroundTransparency = 1; ActiveLbl.BorderSizePixel = 0
    ActiveLbl.AnchorPoint = Vector2.new(1, 0.5)
    ActiveLbl.Position = UDim2.new(1, -28, 0.5, 0); ActiveLbl.Size = UDim2.new(0, 100, 1, 0)
    ActiveLbl.Font = Enum.Font.GothamSemibold; ActiveLbl.Text = "default"
    ActiveLbl.TextColor3 = P.HUE; ActiveLbl.TextSize = 9; ActiveLbl.TextXAlignment = Enum.TextXAlignment.Right
    kit:track(PaletteSync:Bind(function() ActiveLbl.TextColor3 = P.HUE end))

    local OpenBtn = Instance.new("TextButton"); OpenBtn.Parent = Bar
    OpenBtn.AnchorPoint = Vector2.new(1, 0.5); OpenBtn.BackgroundTransparency = 1
    OpenBtn.BorderSizePixel = 0; OpenBtn.Position = UDim2.new(1, -6, 0.5, 0)
    OpenBtn.Size = UDim2.new(0, 16, 0, 16); OpenBtn.Font = Enum.Font.GothamBold
    OpenBtn.Text = ">"; OpenBtn.TextColor3 = P.INK_MID; OpenBtn.TextSize = 14; OpenBtn.AutoButtonColor = false
    OpenBtn.MouseEnter:Connect(function() OpenBtn.TextColor3 = P.INK_HI end)
    OpenBtn.MouseLeave:Connect(function() OpenBtn.TextColor3 = P.INK_MID end)

    local barLayoutRecord = registerFloatingLayout("PresetBar", Bar, {
        DefaultPosition = Bar.Position,
        OnRestore = function()
            barManualPosition = false
        end,
    })
    if Spectrum.FloatingLayout and Spectrum.FloatingLayout.PresetBar then
        barManualPosition = applyResponsiveFloatingLayout(Bar, Spectrum.FloatingLayout.PresetBar)
    end
    kit:drag(Bar, Bar, {
        OnStart = function()
            barManualPosition = true
        end,
        OnReleased = function()
            if Spectrum.SaveLayout then
                Spectrum.SaveLayout()
            end
        end,
    })

    local function syncMobileButtonText(name)
        if not mobileButton then return end
        mobileButton.Text = "preset " .. tostring(name or ActiveLbl.Text or "default")
        if mobileButtonHandle and mobileButtonHandle.RefreshSize then
            mobileButtonHandle.RefreshSize()
        end
    end

    local function toggleEditor()
        if editor then
            editor.Toggle()
            local vis = editor.Instance.Visible
            OpenBtn.Text       = vis and "v" or ">"
            OpenBtn.TextColor3 = vis and P.STATE_OFF or P.INK_MID
            if mobileButtonTheme and mobileButtonTheme.Refresh then
                mobileButtonTheme.Refresh()
            end
        end
    end
    OpenBtn.MouseButton1Click:Connect(toggleEditor)

    if IS_MOBILE then
        local presetStore = MobileUIState.PresetBar
        presetStore.X, presetStore.Y = readMobilePoint(presetStore, 0.54, 0.11)

        mobileButton = Instance.new("TextButton")
        mobileButton.Name = "PresetBarButton"
        mobileButton.Parent = Screen
        mobileButton.AnchorPoint = Vector2.new(0.5, 0.5)
        mobileButton.AutoButtonColor = false
        mobileButton.BorderSizePixel = 0
        mobileButton.BackgroundColor3 = P.BASE1
        mobileButton.Font = Enum.Font.GothamBold
        mobileButton.Text = "preset " .. tostring(ActiveLbl.Text)
        mobileButton.TextSize = 12
        mobileButton.TextTruncate = Enum.TextTruncate.AtEnd
        mobileButton.ZIndex = 29
        mkCorner(mobileButton, UDim.new(0, 10))

        mobileButtonTheme = styleFloatingButton(mobileButton, function()
            local editorOpen = editor and editor.Instance and editor.Instance.Visible == true
            return true, editorOpen and P.HUE or P.EDGE_HI
        end)
        mobileButtonHandle = attachFloatingButton(mobileButton, {
            primary = true,
            defaultX = presetStore.X,
            defaultY = presetStore.Y,
            getStore = function() return MobileUIState.PresetBar end,
            onTap = toggleEditor,
        })
        if editor and editor.Instance then
            mobileButtonVisibleSync = editor.Instance:GetPropertyChangedSignal("Visible"):Connect(function()
                if mobileButtonTheme and mobileButtonTheme.Refresh then
                    mobileButtonTheme.Refresh()
                end
            end)
        end
    end

    local function refit()
        local vp = workspace.CurrentCamera.ViewportSize
        local s  = Scaler.Scale > 0 and Scaler.Scale or 1
        Bar.Size = UDim2.new(0, math.min(260, math.max(80, math.floor(vp.X / s - 20))), 0, BAR_H)
        task.defer(function()
            if not Bar or not Bar.Parent then return end
            if barManualPosition then
                local sbl = Spectrum.FloatingLayout and Spectrum.FloatingLayout.PresetBar
                if not (sbl and applyResponsiveFloatingLayout(Bar, sbl)) then
                    local _p = getAnchorPixelPosition(Bar)
                    applyFloatingAnchorPixels(Bar, _p.X, _p.Y)
                end
            else
                Bar.Position = UDim2.new(0.5, 0, 0, getPresetBarTopOffset(BAR_H))
            end
        end)
    end
    kit:track(workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
        task.defer(refit)
    end))
    kit:track(Scaler:GetPropertyChangedSignal("Scale"):Connect(function()
        task.defer(refit)
    end))
    refit()

    local barApi = {}
    function barApi.SetName(name)
        ActiveLbl.Text = tostring(name)
        syncMobileButtonText(name)
    end
    function barApi.SetVisible(on)
        local visible = on == true
        Bar.Visible = visible and not IS_MOBILE
        if mobileButton then
            mobileButton.Visible = visible
        end
    end
    barApi.Instance = Bar
    barApi.MobileButton = mobileButton
    barApi.MobileButtonTheme = mobileButtonTheme
    barApi.MobileButtonHandle = mobileButtonHandle
    barApi.MobileButtonVisibleSync = mobileButtonVisibleSync
    function barApi.CaptureDefaultPosition()
        if barLayoutRecord then
            barLayoutRecord.DefaultPosition = Bar.Position
            barLayoutRecord.DefaultLayout = captureResponsiveFloatingLayout(Bar)
        end
    end
    function barApi.SetDefaultPosition(position)
        if barLayoutRecord and typeof(position) == "UDim2" then
            barLayoutRecord.DefaultPosition = position
        end
    end
    barApi.SetVisible(false)
    return barApi
end

function Spectrum.CreateCustomWindow(cfg)
    local fp     = {}
    local fpId   = cfg.Name .. "Floater"

    local FloatFrame = Instance.new("Frame")
    FloatFrame.Name                   = "FloatFrame"; FloatFrame.Parent = Screen
    FloatFrame.BackgroundTransparency = 1
    FloatFrame.Position               = UDim2.new(0.5, 0, 0.5, 0)
    FloatFrame.AnchorPoint            = Vector2.new(0.5, 0.5)
    FloatFrame.Size                   = UDim2.new(0, COL_W + 8, 0, 240)
    FloatFrame.Visible                = false

    local FBar = Instance.new("Frame")
    FBar.Name             = "FBar"; FBar.Parent = FloatFrame
    FBar.BackgroundColor3 = P.BASE2; FBar.BorderSizePixel = 0
    FBar.Size             = UDim2.new(1, 0, 0, HDR_H)
    mkCorner(FBar, R_MD); mkBorder(FBar, P.EDGE, 1)
    kit:drag(FloatFrame, FBar)

    local FBarAccent = Instance.new("Frame")
    FBarAccent.Name             = "FBarAccent"; FBarAccent.Parent = FBar
    FBarAccent.BackgroundColor3 = P.HUE; FBarAccent.BorderSizePixel = 0
    FBarAccent.Size             = UDim2.new(0, 2, 0.5, 0); FBarAccent.Position = UDim2.new(0, 5, 0.25, 0)
    mkCorner(FBarAccent, UDim.new(1, 0))

    local FTitle = Instance.new("TextLabel")
    FTitle.Name               = "Name"; FTitle.Parent = FBar
    FTitle.BackgroundTransparency = 1; FTitle.BorderSizePixel = 0
    FTitle.Position           = UDim2.new(0, 13, 0, 0); FTitle.Size = UDim2.new(1, -38, 1, 0)
    FTitle.Font               = Enum.Font.GothamBold; FTitle.Text = cfg.Name
    FTitle.TextColor3         = P.INK_HI; FTitle.TextSize = 10; FTitle.TextXAlignment = Enum.TextXAlignment.Left

    local FGear = Instance.new("ImageButton")
    FGear.Name               = "FGear"; FGear.Parent = FBar
    FGear.BackgroundTransparency = 1; FGear.Position = UDim2.new(1, -26, 0.5, -8)
    FGear.Size               = UDim2.new(0, 16, 0, 16); FGear.ZIndex = 2
    FGear.Image              = "rbxassetid://3926305904"; FGear.ImageColor3 = P.INK_MID
    FGear.ImageRectOffset    = Vector2.new(84, 644); FGear.ImageRectSize = Vector2.new(36, 36)

    local FChildren = Instance.new("Frame")
    FChildren.Name                   = "FChildren"; FChildren.Parent = FloatFrame
    FChildren.BackgroundTransparency = 1; FChildren.Position = UDim2.new(0, 0, 0, HDR_H + 4)
    FChildren.Size                   = UDim2.new(1, 0, 1, -(HDR_H + 4)); FChildren.LayoutOrder = 99

    local FLayout = Instance.new("UIListLayout")
    FLayout.Parent = FloatFrame; FLayout.SortOrder = Enum.SortOrder.LayoutOrder

    local FSettings = Instance.new("Frame")
    FSettings.Name                   = "FSettings"; FSettings.Parent = FloatFrame
    FSettings.BackgroundColor3       = P.BASE1; FSettings.BackgroundTransparency = 0.02
    FSettings.BorderSizePixel        = 0; FSettings.Position = UDim2.new(0, 0, 0, HDR_H + 2)
    FSettings.Size                   = UDim2.new(1, 0, 0, 0); FSettings.Visible = false
    mkCorner(FSettings, R_MD); mkBorder(FSettings, P.EDGE, 1)

    local FOptionHolder = Instance.new("Frame")
    FOptionHolder.Name                   = "FOptionHolder"; FOptionHolder.Parent = FSettings
    FOptionHolder.BackgroundTransparency = 1; FOptionHolder.BorderSizePixel = 0
    FOptionHolder.Size                   = UDim2.new(1, 0, 1, 0)
    local FOptHolder = FOptionHolder

    local FFlow = Instance.new("UIListLayout")
    FFlow.Padding            = UDim.new(0, 1); FFlow.Parent = FOptionHolder
    FFlow.HorizontalAlignment = Enum.HorizontalAlignment.Center
    FFlow.SortOrder          = Enum.SortOrder.LayoutOrder
    mkPad(FOptionHolder, 3, 3, 0, 0)

    local _floatOn = false
    local function normalizeFloatFramePosition()
        local parent = FloatFrame.Parent
        if not parent then return false end

        local parentSize = parent.AbsoluteSize
        if parentSize.X <= 0 or parentSize.Y <= 0 then return false end

        local pos = FloatFrame.Position
        FloatFrame.Position = UDim2.new(
            0, math.floor(pos.X.Scale * parentSize.X + pos.X.Offset + 0.5),
            0, math.floor(pos.Y.Scale * parentSize.Y + pos.Y.Offset + 0.5)
        )
        return true
    end

    FBar.Visible = Spectrum.Root.Visible and _floatOn
    kit:track(Spectrum.Root:GetPropertyChangedSignal("Visible"):Connect(function()
        FBar.Visible = Spectrum.Root.Visible and _floatOn
        if not Spectrum.Root.Visible and fp.Expanded then fp.Expand() end
    end))

    function fp.SetVisible(on)
        _floatOn               = on
        FloatFrame.Visible     = on
        FBar.Visible           = Spectrum.Root.Visible and on
    end

    function fp.NormalizePosition()
        return normalizeFloatFramePosition()
    end

    local floatCamera = workspace.CurrentCamera
    if floatCamera then
        kit:track(floatCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
            if FloatFrame.Position.X.Scale ~= 0 or FloatFrame.Position.Y.Scale ~= 0 then
                normalizeFloatFramePosition()
            end
        end))
    end
    task.defer(normalizeFloatFramePosition)

    function fp.Update()
        local sz = FFlow.AbsoluteContentSize
        FOptionHolder.Size = UDim2.new(1, 0, 0, sz.Y / Scaler.Scale)
        FSettings.Size     = UDim2.new(1, 0, 0, (sz.Y + 6) / Scaler.Scale)
    end
    kit:track(FFlow:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(fp.Update))
    fp.Update()

    function fp.Expand()
        if fp.Expanded then
            FChildren.Visible        = true;  FSettings.Visible = false
            fp.Expanded              = false;  FOptionHolder.Visible = false
            FGear.ImageColor3        = P.INK_MID
        else
            FSettings.Visible        = true;   fp.Expanded = true
            FOptionHolder.Visible    = true;   FGear.ImageColor3 = P.HUE
        end
        fp.Update()
    end
    FGear.MouseButton1Click:Connect(fp.Expand)
    FGear.MouseButton2Click:Connect(fp.Expand)
    fp.Instance = FloatFrame

    function fp.new(class)
        local inst = Instance.new(class); inst.Parent = FChildren; return inst
    end

    function fp.CreateToggle(cfg2)
        local sw = { Enabled = false, Dependents = {}, _depSaved = {} }
        local SRow = Instance.new("TextButton"); SRow.Name = "Switch"; SRow.Parent = FOptHolder
        SRow.BackgroundColor3 = P.BASE2; SRow.BackgroundTransparency = 0; SRow.BorderSizePixel = 0
        SRow.Size = UDim2.new(0, COL_W + 4, 0, 22); SRow.Text = ""; SRow.AutoButtonColor = false
        sw.Instance = SRow; mkCorner(SRow, R_SM)
        local SLbl = Instance.new("TextLabel"); SLbl.Parent = SRow; SLbl.BackgroundTransparency = 1
        SLbl.BorderSizePixel = 0; SLbl.Position = UDim2.new(0, 9, 0, 0); SLbl.Size = UDim2.new(1, -38, 1, 0)
        SLbl.Font = Enum.Font.GothamSemibold; SLbl.Text = cfg2.Name; SLbl.TextColor3 = P.INK_MID
        SLbl.TextSize = 10; SLbl.TextTruncate = Enum.TextTruncate.AtEnd; SLbl.TextXAlignment = Enum.TextXAlignment.Left
        local STrk = Instance.new("TextButton"); STrk.Parent = SRow
        STrk.AnchorPoint = Vector2.new(0, 0.5); STrk.BackgroundColor3 = P.BASE1
        STrk.BackgroundTransparency = 0; STrk.BorderSizePixel = 0
        STrk.Position = UDim2.new(1, -32, 0.5, 0); STrk.Size = UDim2.new(0, 22, 0, 11)
        STrk.Text = ""; STrk.AutoButtonColor = false; mkCorner(STrk, UDim.new(1, 0))
        local sEdge = mkBorder(STrk, P.EDGE, 1)
        local SKnob = Instance.new("TextButton"); SKnob.Parent = STrk
        SKnob.AnchorPoint = Vector2.new(0, 0); SKnob.BackgroundColor3 = P.HUE
        SKnob.BorderSizePixel = 0; SKnob.Position = UDim2.fromOffset(2, 2)
        SKnob.Size = UDim2.fromOffset(7, 7); SKnob.Text = ""; SKnob.AutoButtonColor = false
        mkCorner(SKnob, UDim.new(1, 0))
        kit:track(PaletteSync:Bind(function()
            SKnob.BackgroundColor3 = P.HUE
            if sw.Enabled then STrk.BackgroundColor3 = P.HUE:Lerp(P.BASE1, 0.55); sEdge.Color = P.HUE end
        end))
        function sw.Toggle()
            if sw.Enabled then
                sw.Enabled = false; STrk.BackgroundColor3 = P.BASE1; sEdge.Color = P.EDGE
                SLbl.TextColor3 = P.INK_MID
                SKnob:TweenPosition(UDim2.fromOffset(2, 2), "Out", "Quad", 0.15, true)
            else
                sw.Enabled = true; STrk.BackgroundColor3 = P.HUE:Lerp(P.BASE1, 0.55)
                sEdge.Color = P.HUE; SKnob.BackgroundColor3 = P.HUE
                SLbl.TextColor3 = P.INK_HI
                SKnob:TweenPosition(UDim2.fromOffset(13, 2), "Out", "Quad", 0.15, true)
            end
            if cfg2.Function then task.spawn(cfg2.Function, sw.Enabled) end
            for _, dep in next, sw.Dependents do
                dep.Instance.Visible = sw.Enabled
                if not sw.Enabled then
                    sw._depSaved[dep] = dep.Enabled
                    if dep.Enabled and dep.Toggle then dep.Toggle() end
                else
                    local shouldEnable = sw._depSaved[dep]
                    if dep.Toggle then
                        if shouldEnable and not dep.Enabled then
                            dep.Toggle()
                        elseif shouldEnable == false and dep.Enabled then
                            dep.Toggle()
                        end
                    end
                end
            end
        end
        function sw.AddDependent(_, dep)
            table.insert(sw.Dependents, dep)
            dep.Instance.Visible = sw.Enabled
            if not sw.Enabled then
                sw._depSaved[dep] = dep.Enabled
                if dep.Enabled and dep.Toggle then dep.Toggle() end
            end
        end
        function sw.ShowWhen(_, ...)
            local deps = {...}
            for _, dep in next, deps do
                if dep and dep.Instance and typeof(dep.Instance) == "Instance" and dep.Instance.Parent then
                    table.insert(sw.Dependents, dep)
                    safeVisible(dep.Instance, sw.Enabled)
                    if not sw.Enabled then
                        sw._depSaved[dep] = dep.Enabled
                        if dep.Enabled and dep.Toggle then dep.Toggle() end
                    else
                        sw._depSaved[dep] = dep.Enabled
                    end
                end
            end
        end
        kit:track(SKnob.MouseButton1Click:Connect(sw.Toggle))
        kit:track(STrk.MouseButton1Click:Connect(sw.Toggle))
        kit:track(SRow.MouseButton1Click:Connect(sw.Toggle))
        kit:track(SRow.MouseEnter:Connect(function() SRow.BackgroundColor3 = P.BASE_HOV end))
        kit:track(SRow.MouseLeave:Connect(function() SRow.BackgroundColor3 = P.BASE2 end))
        if cfg2.Default == true then sw.Toggle() end
        kit:register(cfg2.Name .. "Toggle_" .. fpId,
            { Name = cfg2.Name, Instance = SRow, Type = "Toggle",
              CustomWindow = fpId, API = sw, args = cfg2 })
        return sw
    end

    function fp.CreateSlider(cfg2)
        local rng = {}
        local mn, mx = cfg2.Min, cfg2.Max
        local def    = cfg2.Default or mn
        local rnd    = cfg2.Round or 1
        local rMult  = 10 ^ rnd
        local function fmt(v) return math.floor(v) == v and (tostring(v) .. ".0") or tostring(v) end
        local SFrame = Instance.new("Frame"); SFrame.Parent = FOptHolder
        SFrame.BackgroundColor3 = P.BASE2; SFrame.BackgroundTransparency = 0; SFrame.BorderSizePixel = 0
        SFrame.Size = UDim2.new(0, COL_W + 4, 0, 38); rng.Instance = SFrame; mkCorner(SFrame, R_SM)
        local SLbl = Instance.new("TextLabel"); SLbl.Parent = SFrame; SLbl.BackgroundTransparency = 1
        SLbl.BorderSizePixel = 0; SLbl.Position = UDim2.new(0, 9, 0, 4); SLbl.Size = UDim2.new(1, -52, 0, 14)
        SLbl.Font = Enum.Font.GothamSemibold; SLbl.Text = cfg2.Name; SLbl.TextColor3 = P.INK_MID
        SLbl.TextSize = 10; SLbl.TextTruncate = Enum.TextTruncate.AtEnd; SLbl.TextXAlignment = Enum.TextXAlignment.Left
        local VBox = Instance.new("TextBox"); VBox.Parent = SFrame
        VBox.AnchorPoint = Vector2.new(1, 0); VBox.BackgroundTransparency = 1; VBox.BorderSizePixel = 0
        VBox.Position = UDim2.new(1, -9, 0, 4); VBox.Size = UDim2.new(0, 38, 0, 14)
        VBox.Font = Enum.Font.GothamBold; VBox.PlaceholderText = "val"; VBox.Text = fmt(def)
        VBox.TextColor3 = P.HUE; VBox.TextSize = 10; VBox.TextXAlignment = Enum.TextXAlignment.Right
        local VLine = Instance.new("Frame"); VLine.Parent = VBox
        VLine.AnchorPoint = Vector2.new(1, 0); VLine.BackgroundColor3 = P.HUE
        VLine.BorderSizePixel = 0; VLine.Position = UDim2.new(1, 0, 1, 1)
        VLine.Size = UDim2.new(0.9, 0, 0, 1); VLine.Visible = false
        local STrk = Instance.new("Frame"); STrk.Parent = SFrame
        STrk.AnchorPoint = Vector2.new(0.5, 1); STrk.BackgroundColor3 = P.BASE1
        STrk.BorderSizePixel = 0; STrk.Position = UDim2.new(0.5, 0, 1, -7)
        STrk.Size = UDim2.new(1, -18, 0, 3); mkCorner(STrk, UDim.new(1, 0))
        local SFill = Instance.new("Frame"); SFill.Parent = STrk
        SFill.AnchorPoint = Vector2.new(0, 0.5); SFill.BackgroundColor3 = P.HUE
        SFill.BorderSizePixel = 0; SFill.Position = UDim2.new(0, 0, 0.5, 0)
        SFill.Size = UDim2.new(0, 50, 1, 0); mkCorner(SFill, UDim.new(1, 0))
        kit:track(PaletteSync:Bind(function() SFill.BackgroundColor3 = P.HUE end))
        kit:track(SFrame.MouseEnter:Connect(function() SFrame.BackgroundColor3 = P.BASE_HOV end))
        kit:track(SFrame.MouseLeave:Connect(function() SFrame.BackgroundColor3 = P.BASE2 end))
        kit:track(VBox.MouseEnter:Connect(function() VLine.Visible = true end))
        kit:track(VBox.MouseLeave:Connect(function() if not VBox:IsFocused() then VLine.Visible = false end end))
        kit:track(VBox.Focused:Connect(function() VLine.Visible = true end))
        kit:track(VBox.FocusLost:Connect(function()
            VLine.Visible = false
            local n = tonumber(VBox.Text)
            if n then rng.Set(n, true) else VBox.Text = fmt(rng.Value) end
        end))
        local function drag(input)
            local sx = math.clamp((input.Position.X - STrk.AbsolutePosition.X) / STrk.AbsoluteSize.X, 0, 1)
            SFill.Size = UDim2.new(sx, 0, 1, 0)
            local v = math.round(((mx - mn) * sx + mn) * rMult) / rMult
            rng.Value = v; VBox.Text = fmt(v)
            if not cfg2.OnInputEnded and cfg2.Function then task.spawn(cfg2.Function, v) end
        end
        local isSliding = false
        kit:track(SFrame.InputBegan:Connect(function(i)
            local ut = i.UserInputType
            if ut == Enum.UserInputType.MouseButton1 or ut == Enum.UserInputType.Touch then isSliding = true; drag(i) end
        end))
        kit:track(SFrame.InputEnded:Connect(function(i)
            local ut = i.UserInputType
            if ut == Enum.UserInputType.MouseButton1 or ut == Enum.UserInputType.Touch then
                if cfg2.OnInputEnded and cfg2.Function then task.spawn(cfg2.Function, rng.Value) end
                isSliding = false
            end
        end))
        kit:track(UIS.InputChanged:Connect(function(i)
            if isSliding and isPointerMove(i.UserInputType) then drag(i) end
        end))
        function rng.Set(val, overMax)
            local clamped = not overMax
                and math.floor(math.clamp(val, mn, mx) * rMult + 0.5) / rMult
                or  math.clamp(val, cfg2.RealMin or -math.huge, cfg2.RealMax or math.huge)
            local sVal = math.floor(math.clamp(clamped, mn, mx) * rMult + 0.5) / rMult
            rng.Value = clamped; SFill.Size = UDim2.new((sVal - mn) / (mx - mn), 0, 1, 0)
            VBox.Text = fmt(clamped)
            if cfg2.Function then task.spawn(cfg2.Function, clamped) end
        end
        rng.Set(def)
        kit:register(cfg2.Name .. "Slider_" .. fpId,
            { Name = cfg2.Name, Instance = SFrame, Type = "Slider",
              CustomWindow = fpId, API = rng, args = cfg2 })
        return rng
    end

    function fp.CreateTextbox(cfg2)
        local inp = {}
        local IWrap = Instance.new("Frame"); IWrap.Parent = FOptionHolder
        IWrap.BackgroundTransparency = 1; IWrap.BorderSizePixel = 0
        IWrap.Size = UDim2.new(0, COL_W + 4, 0, 28); inp.Instance = IWrap
        local IBack = Instance.new("Frame"); IBack.Parent = IWrap
        IBack.AnchorPoint = Vector2.new(0.5, 0.5); IBack.BackgroundColor3 = P.BASE2
        IBack.BackgroundTransparency = 0; IBack.BorderSizePixel = 0
        IBack.Position = UDim2.new(0.5, 0, 0.5, 0); IBack.Size = UDim2.new(0, COL_W - 6, 0, 20)
        mkCorner(IBack, R_SM); local iEdge = mkBorder(IBack, P.EDGE, 1, 0.4)
        local IField = Instance.new("TextBox"); IField.Parent = IBack
        IField.AnchorPoint = Vector2.new(0.5, 0.5); IField.BackgroundTransparency = 1
        IField.BorderSizePixel = 0; IField.Position = UDim2.new(0.5, 0, 0.5, 0)
        IField.Size = UDim2.new(1, -14, 1, 0); IField.ClearTextOnFocus = false
        IField.Font = Enum.Font.GothamSemibold; IField.PlaceholderColor3 = P.INK_LOW
        IField.PlaceholderText = cfg2.Name; IField.Text = cfg2.Default or ""
        IField.TextColor3 = P.INK_HI; IField.TextSize = 10; IField.TextXAlignment = Enum.TextXAlignment.Left
        kit:track(IBack.MouseEnter:Connect(function() iEdge.Color = P.EDGE_HI; iEdge.Transparency = 0 end))
        kit:track(IBack.MouseLeave:Connect(function() iEdge.Color = P.EDGE; iEdge.Transparency = 0.4 end))
        function inp.Set(val)
            val = val or cfg2.Default or ""; inp.Value = val; IField.Text = val
            if cfg2.Function then task.spawn(cfg2.Function, val) end
        end
        kit:track(IField.FocusLost:Connect(function()
            local t = IField.Text; if t then inp.Set(t) end
        end))
        kit:register(cfg2.Name .. "Textbox_" .. fpId,
            { Name = cfg2.Name, Instance = IWrap, Type = "Textbox",
              CustomWindow = fpId, API = inp, args = cfg2 })
        return inp
    end
    fp.CreateTextBox = fp.CreateTextbox

    function fp.CreateDropdown(cfg2)
        local sel = { Values = {}, Expanded = false, ValueDependents = {}, _depSaved = {} }
        local DWrap = Instance.new("Frame"); DWrap.Parent = FOptHolder
        DWrap.BackgroundTransparency = 1; DWrap.BorderSizePixel = 0
        DWrap.Size = UDim2.new(0, COL_W + 4, 0, 28); sel.Instance = DWrap
        local DBack = Instance.new("Frame"); DBack.Parent = DWrap
        DBack.AnchorPoint = Vector2.new(0.5, 0); DBack.BackgroundColor3 = P.BASE2
        DBack.BorderSizePixel = 0; DBack.Position = UDim2.new(0.5, 0, 0, 4)
        DBack.Size = UDim2.new(0, COL_W - 6, 0, 20); mkCorner(DBack, R_SM)
        local dEdge = mkBorder(DBack, P.EDGE, 1, 0.4)
        local DLbl = Instance.new("TextLabel"); DLbl.Parent = DBack; DLbl.BackgroundTransparency = 1
        DLbl.BorderSizePixel = 0; DLbl.Position = UDim2.new(0, 9, 0, 0); DLbl.Size = UDim2.new(1, -26, 1, 0)
        DLbl.Font = Enum.Font.GothamSemibold; DLbl.Text = cfg2.Name; DLbl.TextColor3 = P.INK_MID
        DLbl.TextSize = 10; DLbl.TextXAlignment = Enum.TextXAlignment.Left; DLbl.TextTruncate = Enum.TextTruncate.AtEnd
        local DChev = Instance.new("ImageButton"); DChev.Parent = DBack
        DChev.AnchorPoint = Vector2.new(0, 0.5); DChev.BackgroundTransparency = 1; DChev.BorderSizePixel = 0
        DChev.Position = UDim2.new(1, -18, 0.5, 0); DChev.Size = UDim2.new(0, 14, 0, 14); DChev.ZIndex = 2
        DChev.Image = "http://www.roblox.com/asset/?id=6031094679"; DChev.ImageColor3 = P.INK_LOW
        DChev.ScaleType = Enum.ScaleType.Fit
        local DList = Instance.new("Frame"); DList.Parent = DWrap
        DList.AnchorPoint = Vector2.new(0.5, 0); DList.BackgroundColor3 = P.BASE1
        DList.BackgroundTransparency = 0; DList.BorderSizePixel = 0; DList.ClipsDescendants = true
        DList.Position = UDim2.new(0.5, 0, 0, 28); DList.Size = UDim2.new(0, COL_W - 6, 0, 0)
        DList.Visible = false; mkCorner(DList, R_SM)
        mkBorder(DList, P.EDGE, 1, 0.4); mkPad(DList, 2, 2, 0, 0)
        local DScroll = Instance.new("ScrollingFrame"); DScroll.Parent = DList
        DScroll.BackgroundTransparency = 1; DScroll.BorderSizePixel = 0
        DScroll.Size = UDim2.new(1, 0, 1, 0); DScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
        DScroll.ScrollBarThickness = 2; DScroll.ScrollBarImageColor3 = P.INK_LOW
        DScroll.ScrollingDirection = Enum.ScrollingDirection.Y
        local DItemFlow = Instance.new("UIListLayout"); DItemFlow.Parent = DScroll
        DItemFlow.HorizontalAlignment = Enum.HorizontalAlignment.Center
        DItemFlow.SortOrder = Enum.SortOrder.LayoutOrder
        kit:track(DBack.MouseEnter:Connect(function()
            dEdge.Color = P.EDGE_HI; dEdge.Transparency = 0; DBack.BackgroundColor3 = P.BASE_HOV end))
        kit:track(DBack.MouseLeave:Connect(function()
            dEdge.Color = P.EDGE; dEdge.Transparency = 0.4; DBack.BackgroundColor3 = P.BASE2 end))
        local D_MAX_H = 160
        function sel.Update()
            local sz = DItemFlow.AbsoluteContentSize.Y
            local cappedSz = math.min(sz, D_MAX_H * Scaler.Scale)
            if DList.Visible then
                DWrap.Size = UDim2.new(0, COL_W + 4, 0, (28 * Scaler.Scale + cappedSz + 6) / Scaler.Scale)
                DList.Size = UDim2.new(0, COL_W - 6, 0, cappedSz / Scaler.Scale + 4)
                DScroll.CanvasSize = UDim2.new(0, 0, 0, sz / Scaler.Scale)
            else DWrap.Size = UDim2.new(0, COL_W + 4, 0, 28) end
        end
        kit:track(DItemFlow:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(sel.Update))
        function sel.SetValue(val)
            for _, v in next, sel.Values do
                local match = v.Value == val
                v.SelectedInstance.Visible = match
                if match then
                    sel.Value = val; DLbl.Text = cfg2.Name .. " > " .. tostring(val)
                    DLbl.TextColor3 = P.INK_HI
                    if cfg2.Function then task.spawn(cfg2.Function, val) end
                    for _, vd in next, sel.ValueDependents do
                        local show = sel.Value == vd.value
                        for _, dep in next, vd.elements do
                            dep.Instance.Visible = show
                            if not show then
                                sel._depSaved[dep] = dep.Enabled
                                if dep.Enabled and dep.Toggle then dep.Toggle() end
                            else
                                local shouldEnable = sel._depSaved[dep]
                                if shouldEnable ~= nil and dep.Toggle then
                                    if shouldEnable and not dep.Enabled then
                                        dep.Toggle()
                                    elseif shouldEnable == false and dep.Enabled then
                                        dep.Toggle()
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
        function sel.ShowWhen(_, value, ...)
            local deps = {...}
            table.insert(sel.ValueDependents, { value = tostring(value), elements = deps })
            local show = sel.Value == tostring(value)
            for _, dep in next, deps do
                if dep and dep.Instance and typeof(dep.Instance) == "Instance" and dep.Instance.Parent then
                    safeVisible(dep.Instance, show)
                    if not show then
                        sel._depSaved[dep] = dep.Enabled
                        if dep.Enabled and dep.Toggle then dep.Toggle() end
                    else
                        sel._depSaved[dep] = dep.Enabled
                        local shouldEnable = sel._depSaved[dep]
                        if shouldEnable ~= nil and dep.Toggle then
                            if shouldEnable and not dep.Enabled then
                                dep.Toggle()
                            elseif shouldEnable == false and dep.Enabled then
                                dep.Toggle()
                            end
                        end
                    end
                end
            end
        end
        local function newDItem(val)
            local vi = { Value = val }
            local Btn = Instance.new("TextButton"); Btn.Parent = DScroll
            Btn.BackgroundColor3 = P.BASE1; Btn.BackgroundTransparency = 0; Btn.BorderSizePixel = 0
            Btn.Size = UDim2.new(0, COL_W - 12, 0, 20); Btn.Text = ""; Btn.AutoButtonColor = false; mkCorner(Btn, R_SM)
            Btn.MouseButton1Click:Connect(function() sel.SetValue(val) end)
            kit:track(Btn.MouseEnter:Connect(function() Btn.BackgroundColor3 = P.BASE_HOV end))
            kit:track(Btn.MouseLeave:Connect(function() Btn.BackgroundColor3 = P.BASE1 end))
            local Lbl = Instance.new("TextLabel"); Lbl.Parent = Btn; Lbl.BackgroundTransparency = 1
            Lbl.BorderSizePixel = 0; Lbl.Position = UDim2.new(0, 12, 0, 0); Lbl.Size = UDim2.new(1, -18, 1, 0)
            Lbl.Font = Enum.Font.GothamSemibold; Lbl.Text = tostring(val); Lbl.TextColor3 = P.INK_MID
            Lbl.TextSize = 10; Lbl.TextXAlignment = Enum.TextXAlignment.Left
            local Dot = Instance.new("Frame"); Dot.Parent = Btn; Dot.AnchorPoint = Vector2.new(0, 0.5)
            Dot.BackgroundColor3 = P.HUE; Dot.Visible = false; Dot.BorderSizePixel = 0
            Dot.Position = UDim2.new(0, 3, 0.5, 0); Dot.Size = UDim2.new(0, 2, 0.5, 0); mkCorner(Dot, UDim.new(1, 0))
            kit:track(PaletteSync:Bind(function() Dot.BackgroundColor3 = P.HUE end))
            vi.SelectedInstance = Dot; vi.Instance = Btn; return vi
        end
        function sel.Expand()
            if sel.Expanded then
                sel.Expanded = false; DList.Visible = false; DChev.Rotation = 0; DChev.ImageColor3 = P.INK_LOW
            else DChev.Rotation = 180; DChev.ImageColor3 = P.HUE; sel.Expanded = true; DList.Visible = true end
            sel.Update()
        end
        kit:track(DChev.MouseButton1Click:Connect(sel.Expand))
        for _, v in next, cfg2.List do sel.Values[#sel.Values + 1] = newDItem(v) end
        if cfg2.Default then sel.SetValue(cfg2.Default) end
        function sel.SetList(list)
            for i, v in next, sel.Values do v.Instance:Destroy(); sel.Values[i] = nil end
            sel.Values = {}
            for _, v in next, list do sel.Values[#sel.Values + 1] = newDItem(v) end
        end
        kit:register(cfg2.Name .. "Dropdown_" .. fpId,
            { Name = cfg2.Name, Instance = DWrap, Type = "Dropdown",
              CustomWindow = fpId, API = sel, args = cfg2 })
        return sel
    end

    kit:register(cfg.Name .. "CustomWindow",
        { Name = cfg.Name, Instance = FloatFrame, Type = "CustomWindow", API = fp, args = cfg })
    return fp
end


function Spectrum.CreateDefaultTabs(cfg)
    local tabs = {}
    local order = (cfg and cfg.Order) or {
	    "combat", "blatant", "render", "utillity", "world", "misc", "inventory", "other"
	}
    local iconResolver = cfg and cfg.IconResolver
    local showIcons = cfg and cfg.ShowIcons == true
    for _, descriptor in ipairs(order) do
        local tabName = descriptor
        local tabTitle = descriptor
        local aliases = nil

        if type(descriptor) == "table" then
            tabName = descriptor.Name or descriptor.Id or descriptor[1]
            tabTitle = descriptor.Title or descriptor.Text or tabName
            aliases = descriptor.Aliases
        end

        local panel = Spectrum.window({
            Name = tabName,
            Title = tabTitle,
            Icon = iconResolver and iconResolver(tabName) or nil,
            ShowIcon = showIcons,
        })
        tabs[tabName] = panel
        if type(aliases) == "table" then
            for _, alias in ipairs(aliases) do
                tabs[alias] = panel
                if Spectrum.Registry and Spectrum.Registry[tabName .. "Panel"] then
                    Spectrum.Registry[alias .. "Panel"] = Spectrum.Registry[tabName .. "Panel"]
                end
            end
        end
    end
    return tabs
end

function Spectrum.CreateArrayListWidget(cfg)
    local floater = Spectrum.CreateCustomWindow({
        Name = (cfg and cfg.Name) or "array list",
        HideSettings = true,
    })
    floater.Instance.Size = UDim2.new(0, 200, 0, 0)
    floater.Instance.AutomaticSize = Enum.AutomaticSize.Y
    
    local widget = {
        Instance = floater.Instance,
        Window = floater,
        Lines = {},
        Objects = {},
        Scale = 1,
        SortMode = "Size",
        LineMode = "Line",
        LinesVisible = true,
        WatermarkVisible = true,
        CustomTextEnabled = false,
        CustomTextValue = "",
    }

    local arrayList = floater.new("Frame")
    arrayList.Name = "ArrayList"
    arrayList.BackgroundTransparency = 1
    arrayList.Position = UDim2.new(-0.551886797, 0, 0, 0)
    arrayList.Size = UDim2.new(0, 319, 0, 362)

    local uiListLayout = Instance.new("UIListLayout")
    uiListLayout.Parent = arrayList
    uiListLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
    uiListLayout.SortOrder = Enum.SortOrder.LayoutOrder

    local watermark = Instance.new("TextLabel")
    watermark.Name = "Watermark"
    watermark.Parent = arrayList
    watermark.BackgroundTransparency = 1
    watermark.Position = UDim2.new(0, 0, 0.05, 0)
    watermark.Size = UDim2.new(0, 601, 0.1456832382, 0)
    watermark.Font = Enum.Font.GothamSemibold
    watermark.Text = "Phantom"
    watermark.TextColor3 = kit:objectColor(watermark)
    watermark.TextScaled = true
    watermark.TextStrokeTransparency = 0
    watermark.TextWrapped = true
    watermark.TextXAlignment = Enum.TextXAlignment.Right
    kit:track(PaletteSync:Bind(function()
        watermark.TextColor3 = kit:objectColor(watermark)
    end))

    local watermarkText = Instance.new("TextLabel")
    watermarkText.Name = "WatermarkText"
    watermarkText.Parent = arrayList
    watermarkText.BackgroundTransparency = 1
    watermarkText.Position = UDim2.new(0, 0, 0.1, 0)
    watermarkText.Size = UDim2.new(0, 601, 0.0756832382, 0)
    watermarkText.Font = Enum.Font.GothamSemibold
    watermarkText.Text = "Custom Text!"
    watermarkText.TextColor3 = kit:objectColor(watermarkText)
    watermarkText.TextScaled = true
    watermarkText.TextStrokeTransparency = 0
    watermarkText.TextWrapped = true
    watermarkText.TextXAlignment = Enum.TextXAlignment.Right
    kit:track(PaletteSync:Bind(function()
        watermarkText.TextColor3 = kit:objectColor(watermarkText)
    end))

    local function buildLine(lbl, mode)
        local oldLine = lbl:FindFirstChild("Line")
        if oldLine then
            for i = #widget.Lines, 1, -1 do
                if widget.Lines[i] == oldLine then
                    table.remove(widget.Lines, i)
                    break
                end
            end
            oldLine:Destroy()
        end
        local line = Instance.new("Frame")
        line.Name = "Line"
        line.Parent = lbl
        line.BackgroundColor3 = kit:activeColor()
        line.BorderSizePixel = 0
        line.AnchorPoint = Vector2.new(0, 0.5)
        if mode == "Striped" then
            line.Size = UDim2.new(0, 3.7, 0.7, 0)
            line.Position = UDim2.new(1.01, 0, 0.56, 0)
            mkCorner(line, UDim.new(1, 0))
        elseif mode == "Dot" then
            line.Size = UDim2.new(0, 6, 0, 6)
            line.Position = UDim2.new(1.01, 0, 0.56, 0)
            mkCorner(line, UDim.new(1, 0))
        else
            line.Size = UDim2.new(0, 3.7, 1, 0)
            line.Position = UDim2.new(1.01, 0, 0.56, 0)
        end
        line.Visible = widget.LinesVisible == true and mode ~= "None"
        table.insert(widget.Lines, line)
        kit:track(PaletteSync:Bind(function() line.BackgroundColor3 = kit:activeColor() end))
    end

    function widget.SetScale(scale)
        widget.Scale = math.clamp(tonumber(scale) or 1, 0.5, 2)
        arrayList.Size = UDim2.new(0, 319, 0, 362 * widget.Scale)
    end

    function widget.SetVisible(on)
        floater.SetVisible(on)
    end

    function widget.SetSortMode(mode)
        mode = tostring(mode or "Size")
        widget.SortMode = (mode == "Alphabetical" and "Alphabetical") or "Size"
        local children = arrayList:GetChildren()
        table.sort(children, function(a, b)
            if not a:IsA("TextLabel") then return false end
            if not b:IsA("TextLabel") then return true end
            if widget.SortMode == "Alphabetical" then return a.Text < b.Text end
            return a.TextBounds.X > b.TextBounds.X
        end)
        for i, child in next, children do
            if child.Name:find("Watermark") then
                child.LayoutOrder = (child.Name:find("Text") and 2) or 0
            elseif child:IsA("TextLabel") then
                child.LayoutOrder = i + 2
            end
        end
        return widget.SortMode
    end

    function widget.SetLineMode(mode)
        widget.LineMode = tostring(mode or "Line")
        for _, lbl in pairs(widget.Objects) do
            buildLine(lbl, widget.LineMode)
        end
        return widget.LineMode
    end

    function widget.SetLinesVisible(on)
        widget.LinesVisible = on == true
        local activeMode = widget.LineMode or "Line"
        for _, ln in pairs(widget.Lines) do
            ln.Visible = widget.LinesVisible and activeMode ~= "None"
        end
        return widget.LinesVisible
    end

    function widget.SetWatermarkVisible(on)
        widget.WatermarkVisible = on == true
        watermark.Visible = widget.WatermarkVisible
        return widget.WatermarkVisible
    end

    function widget.SetCustomTextEnabled(on)
        widget.CustomTextEnabled = on == true
        watermarkText.Visible = widget.CustomTextEnabled and widget.CustomTextValue ~= ""
        return widget.CustomTextEnabled
    end

    function widget.SetCustomText(text)
        widget.CustomTextValue = tostring(text or "")
        watermarkText.Text = widget.CustomTextValue
        watermarkText.Visible = widget.CustomTextEnabled and widget.CustomTextValue ~= ""
        return widget.CustomTextValue
    end

    function widget.HandleEntry(name, extraText, enabled, isPrivate)
        if not enabled then
            local existing = widget.Objects[name]
            if existing then
                local existingLine = existing:FindFirstChild("Line")
                if existingLine then
                    for i = #widget.Lines, 1, -1 do
                        if widget.Lines[i] == existingLine then
                            table.remove(widget.Lines, i)
                            break
                        end
                    end
                end
                existing:Destroy()
                widget.Objects[name] = nil
            end
            return
        end

        local lbl = widget.Objects[name] or Instance.new("TextLabel")
        lbl.Name = "ArrayListModule"
        lbl.Parent = arrayList
        lbl.BackgroundTransparency = 1
        lbl.Position = UDim2.new(0, 0, 0.151490679, 0)
        lbl.Size = UDim2.new(0, 601, 0.0556832382, 0)
        lbl.Font = Enum.Font.GothamSemibold
        lbl.RichText = true
        lbl.Text = name
            .. ((extraText and extraText ~= "") and (' <font color="rgb(200,200,200)">[' .. extraText .. ']</font>') or "")
            .. (isPrivate and ' <font color="rgb(255,160,60)">[Private]</font>' or "")
        lbl.TextColor3 = kit:objectColor(lbl)
        lbl.TextScaled = true
        lbl.TextStrokeTransparency = 0.5
        lbl.TextWrapped = true
        lbl.TextXAlignment = Enum.TextXAlignment.Right
        kit:track(PaletteSync:Bind(function() lbl.TextColor3 = kit:objectColor(lbl) end))
        widget.Objects[name] = lbl

        buildLine(lbl, widget.LineMode or "Line")
        widget.SetSortMode(widget.SortMode)
    end

    kit:track(ModuleSync:Bind(function(name, extraText, enabled, _, _, isPrivate)
        widget.HandleEntry(name, extraText, enabled, isPrivate)
    end))

    widget.SetScale((cfg and cfg.Scale) or 1)
    widget.SetSortMode((cfg and cfg.SortMode) or "Size")
    widget.SetLineMode((cfg and cfg.LineMode) or "Line")
    widget.SetLinesVisible(cfg == nil or cfg.LinesVisible ~= false)
    widget.SetWatermarkVisible(cfg == nil or cfg.WatermarkVisible ~= false)
    widget.SetCustomTextEnabled(cfg and cfg.CustomTextEnabled == true)
    widget.SetCustomText((cfg and cfg.CustomText) or "")

    widget.Watermark = watermark
    widget.WatermarkText = watermarkText
    return widget
end

kit:track(UIS.InputBegan:Connect(function(input)
    if UIS:GetFocusedTextBox() then return end
    if input.KeyCode == Enum.KeyCode.Unknown then return end
    local key = input.KeyCode.Name
    if key == "Backspace" or key == "Delete" or key == "Escape" then key = nil end
    if not Spectrum.Registry then return end
    for _, v in next, Spectrum.Registry do
        if Spectrum.IsRecording then
            if v.Type == "OptionsButton" and v.API.Recording then
                Spectrum.IsRecording = false; v.API.Recording = false; v.API.SetBind(key); return
            end
        else
            if v.Type == "OptionsButton" and v.API.Bind == (key or "") then
                v.API.Toggle(true)
            end
        end
    end
end))


Spectrum.Objects     = Spectrum.Registry
Spectrum.Connections = Spectrum.Tracked

Spectrum.CreateColorOption = function(moduleApi, config, storagePrefix)
	local defaults = config.Default or {R = 255, G = 255, B = 255}
	local colorState = {
		R = defaults.R or 255,
		G = defaults.G or 255,
		B = defaults.B or 255,
		Color = Color3.fromRGB(defaults.R or 255, defaults.G or 255, defaults.B or 255)
	}
	local function UpdateColor()
		colorState.Color = Color3.fromRGB(colorState.R, colorState.G, colorState.B)
		if config.Function then config.Function(colorState.Color) end
	end
	local redSlider = moduleApi.CreateSlider({
		Name = (config.Name or "color") .. " R",
		Min = 0, Max = 255, Default = colorState.R, Round = 0,
		Function = function(value) colorState.R = value; UpdateColor() end
	})
	local greenSlider = moduleApi.CreateSlider({
		Name = (config.Name or "color") .. " G",
		Min = 0, Max = 255, Default = colorState.G, Round = 0,
		Function = function(value) colorState.G = value; UpdateColor() end
	})
	local blueSlider = moduleApi.CreateSlider({
		Name = (config.Name or "color") .. " B",
		Min = 0, Max = 255, Default = colorState.B, Round = 0,
		Function = function(value) colorState.B = value; UpdateColor() end
	})
	function colorState:Set(newColor)
		colorState.R = math.floor((newColor.R or 1) * 255 + 0.5)
		colorState.G = math.floor((newColor.G or 1) * 255 + 0.5)
		colorState.B = math.floor((newColor.B or 1) * 255 + 0.5)
		if redSlider and redSlider.Set then redSlider.Set(colorState.R, true) end
		if greenSlider and greenSlider.Set then greenSlider.Set(colorState.G, true) end
		if blueSlider and blueSlider.Set then blueSlider.Set(colorState.B, true) end
		UpdateColor()
	end
	UpdateColor()
	return colorState
end

if isBad then
    local wm = Instance.new("TextLabel", Spectrum.Screen)
    wm.BackgroundTransparency = 1
    wm.Size                   = UDim2.new(0, 0, 0, 18)
    wm.AutomaticSize          = Enum.AutomaticSize.X
    wm.Position               = UDim2.new(1, -8, 0, 8)
    wm.AnchorPoint            = Vector2.new(1, 0)
    wm.Font                   = Enum.Font.GothamBold
    wm.TextColor3             = P.STATE_OFF
    wm.TextScaled             = false
    wm.TextSize               = 10
    wm.Text                   = "unsupported executor"
end

return Spectrum