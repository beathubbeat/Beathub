local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")
local Debris            = game:GetService("Debris")
local CoreGui           = game:GetService("CoreGui")
local TeleportService   = game:GetService("TeleportService")
local HttpService       = game:GetService("HttpService")
local Lighting          = game:GetService("Lighting")
local VirtualUser       = game:GetService("VirtualUser")

local LocalPlayer = Players.LocalPlayer
local Camera      = workspace.CurrentCamera

local newcclosure = newcclosure or function(f) return f end

--=============================================================
-- CONFIG
--=============================================================
local CONFIG = {
    Enabled    = true,
    ShowName   = true,
    ShowHealth = true,
    ShowTool   = true,
    ShowArmor  = true,
    ShowAdmins = true,
    ShowRadar  = true,
    ShowBoxes  = false,
    ShowFPS    = true,

    Noclip          = false,
    MountainClimber = false,
    WallClimber     = false,
    WalkSpeed       = 17,
    JumpPower       = 50,
    Gravity         = 196.2,
    InfiniteJump    = false,
    BunnyHop        = false,

    -- Hitbox widener
    HitboxEnabled  = false,
    HitboxSize     = 6,        -- studs (X, Y, Z each)
    HitboxTransparency = 0.7,
    HitboxTeamCheck = false,   -- only enlarge enemies (not teammates)

    FlingEnabled  = true,
    FlingKey      = Enum.KeyCode.F,
    FlingRange    = 30,
    FlingPower    = 420,
    FlingLift     = 220,
    FlingSpin     = 160,
    FlingCooldown = 0.35,

    AntiKick  = false,
    AntiAFK   = true,
    Fullbright = false,
    PotatoMode = false,

    HeavyUpdateHz = 30,
    ToolRefreshHz = 2,

    Accent       = Color3.fromRGB(220, 30, 30),
    AccentBright = Color3.fromRGB(255, 70, 70),
    AccentDim    = Color3.fromRGB(80, 10, 10),
    Bg           = Color3.fromRGB(8, 8, 10),
    Bg1          = Color3.fromRGB(16, 16, 18),
    Bg2          = Color3.fromRGB(24, 24, 28),
    Text         = Color3.fromRGB(230, 230, 230),
    TextDim      = Color3.fromRGB(120, 120, 125),

    NameColor   = Color3.fromRGB(255, 255, 255),
    HealthColor = Color3.fromRGB(255, 255, 255),
    ToolColor   = Color3.fromRGB(255, 200, 80),
    ArmorColor  = Color3.fromRGB(200, 200, 210),
    AdminColor  = Color3.fromRGB(255, 60, 60),
    BoxColor    = Color3.fromRGB(255, 90, 90),
    HitboxColor = Color3.fromRGB(255, 120, 120),

    NameSize   = 11,
    HealthSize = 11,
    ToolSize   = 10,
    ArmorSize  = 10,
    AdminSize  = 11,

    MaxDistance = 1500,
    RadarSize   = 170,
    RadarRange  = 340,
    GuiKey      = Enum.KeyCode.RightShift,
}

--=============================================================
-- STATE
--=============================================================
local espData, armorCache, adminCache = {}, {}, {}
local toolCache = {}
local radarDots = {}
local radarState = { center = Vector2.new(0,0), half = 0 }
local guiRefs = {}

local heavyAccum = 0
local lastFling  = 0

local targetPlayers  = {}
local targetListRows = {}
local refreshTargetList = function() end

local savedLighting = nil
local fpsFrames, fpsTimeAccum, fpsValue = 0, 0, 0

-- Hitbox state: [player] = { part = BasePart, originalSize = Vector3, originalTransparency = number }
local hitboxes = {}

-- Potato mode state
local potatoState = {
    enabled       = false,
    saved         = {},   -- [instance] = { propName = originalValue }
    conn          = nil,
    savedLighting = nil,
    savedQuality  = nil,
}

-- FPS overlay
local fpsText = Drawing.new("Text")
fpsText.Size = 14
fpsText.Color = Color3.new(1, 1, 1)
fpsText.Outline = true
fpsText.OutlineColor = Color3.new(0, 0, 0)
fpsText.Position = Vector2.new(10, 8)
fpsText.Visible = false
fpsText.Text = "FPS: --  |  Ping: --"

--=============================================================
-- NOTIFY
--=============================================================
local function notify(msg)
    print("[Booga] " .. msg)
    if guiRefs.toast then
        guiRefs.toast.Text = msg
        guiRefs.toast.Visible = true
        local token = tick()
        guiRefs.toastToken = token
        task.delay(2.5, function()
            if guiRefs.toast and guiRefs.toastToken == token then
                guiRefs.toast.Visible = false
            end
        end)
    end
end

--=============================================================
-- HTTP HELPER
--=============================================================
local function httpGet(url)
    local fn
    if syn and syn.request then fn = syn.request
    elseif http_request then fn = http_request
    elseif request then fn = request
    end
    if fn then
        local ok, res = pcall(fn, { Url = url, Method = "GET" })
        if ok and res and res.Body then return res.Body end
    end
    if game.HttpGet then
        local ok, body = pcall(function() return game:HttpGet(url) end)
        if ok and body then return body end
    end
    local ok, body = pcall(function() return HttpService:GetAsync(url) end)
    if ok then return body end
    return nil
end

local function toProxyUrl(url)
    return (url:gsub("([%w%-]+)%.roblox%.com", "%1.roproxy.com"))
end

local function httpGetJson(url)
    local body = httpGet(url)
    if body then
        local ok, data = pcall(function() return HttpService:JSONDecode(body) end)
        if ok and data then return data end
    end
    local proxied = toProxyUrl(url)
    if proxied ~= url then
        body = httpGet(proxied)
        if body then
            local ok, data = pcall(function() return HttpService:JSONDecode(body) end)
            if ok and data then return data end
        end
    end
    return nil
end

--=============================================================
-- DRAWING HELPERS
--=============================================================
local function newText(c, s)
    local t = Drawing.new("Text")
    t.Color, t.Size = c, s
    t.Center, t.Outline = true, true
    t.OutlineColor = Color3.new(0,0,0)
    t.Transparency, t.Visible = 1, false
    return t
end

local function newSquare(c, s, f)
    local sq = Drawing.new("Square")
    sq.Color, sq.Size, sq.Filled = c, s, f
    sq.Thickness, sq.Transparency, sq.Visible = 1, 1, false
    return sq
end

local function newLine(c, th)
    local l = Drawing.new("Line")
    l.Color, l.Thickness = c, th
    l.Transparency, l.Visible = 0.85, false
    return l
end

local function setVisible(obj, v) if obj.Visible ~= v then obj.Visible = v end end
local function setPos(obj, p)     if obj.Position ~= p then obj.Position = p end end
local function setText(obj, t)    if obj.Text ~= t then obj.Text = t end end

--=============================================================
-- ARMOR / ADMIN
--=============================================================
local function summarizeArmor(character)
    local seen, sets = {}, {}
    for _, d in ipairs(character:GetDescendants()) do
        local armor = d:GetAttribute("mainArmor")
        if armor and armor ~= "" and not seen[armor] then
            seen[armor] = true
            sets[armor:match("^(%S+)") or armor] = true
        end
    end
    local names = {}
    for n in pairs(sets) do table.insert(names, n) end
    if #names == 0 then return false end
    table.sort(names)
    return table.concat(names, " · ")
end

local ADMIN_ATTRS = {
    "Admin","IsAdmin","Staff","Moderator","Mod","Owner","Developer",
    "Spectator","Invisible","GM","GameMaster","IsStaff","IsMod",
}
local ADMIN_TAGS = { "Admin", "Staff", "Moderator", "GM" }

local function isAdmin(player, character)
    if not character then return false end
    for _, a in ipairs(ADMIN_ATTRS) do
        if player:GetAttribute(a) == true then return true end
        if character:GetAttribute(a) == true then return true end
    end
    for _, t in ipairs(ADMIN_TAGS) do
        if CollectionService:HasTag(player, t) then return true end
        if CollectionService:HasTag(character, t) then return true end
    end
    local parts, allInv = 0, true
    for _, d in ipairs(character:GetDescendants()) do
        if d:IsA("BasePart") then
            parts = parts + 1
            if d.Transparency < 0.9 then allInv = false; break end
        end
    end
    return parts > 0 and allInv
end

--=============================================================
-- ESP
--=============================================================
local function createESP(player)
    if player == LocalPlayer or espData[player] then return end
    espData[player] = {
        admin  = newText(CONFIG.AdminColor,  CONFIG.AdminSize),
        name   = newText(CONFIG.NameColor,   CONFIG.NameSize),
        health = newText(CONFIG.HealthColor, CONFIG.HealthSize),
        tool   = newText(CONFIG.ToolColor,   CONFIG.ToolSize),
        armor  = newText(CONFIG.ArmorColor,  CONFIG.ArmorSize),
        box    = newSquare(CONFIG.BoxColor,  Vector2.new(0,0), false),
    }
    armorCache[player] = nil
    adminCache[player] = nil
    toolCache[player]  = nil
end

local function removeESP(player)
    local d = espData[player]
    if not d then return end
    for _, o in pairs(d) do o:Remove() end
    espData[player]    = nil
    armorCache[player] = nil
    adminCache[player] = nil
    toolCache[player]  = nil
end

--=============================================================
-- RADAR
--=============================================================
local function ensureRadarDot(player)
    if radarDots[player] then return end
    radarDots[player] = {
        dot = newSquare(Color3.new(1,1,1), Vector2.new(4,4), true),
        dir = newLine(Color3.new(1,1,1), 2),
    }
end

local function buildRadar()
    local vp = Camera.ViewportSize
    local S  = CONFIG.RadarSize
    local H  = S / 2
    local center = Vector2.new(vp.X - H - 20, vp.Y - H - 20)
    radarState.center = center
    radarState.half = H
    local tl = center - Vector2.new(H, H)

    radarState.bg = newSquare(CONFIG.Bg, Vector2.new(S,S), true)
    radarState.bg.Position = tl
    radarState.bg.Transparency = 0.4

    radarState.border = newSquare(CONFIG.Accent, Vector2.new(S,S), false)
    radarState.border.Position = tl
    radarState.border.Thickness = 2
    radarState.border.Transparency = 1

    radarState.localDot = newSquare(Color3.new(255,255,255), Vector2.new(6,6), true)
    radarState.localDot.Position = center - Vector2.new(3,3)
    radarState.localDot.Transparency = 1

    radarState.label = Drawing.new("Text")
    radarState.label.Text = "RADAR"
    radarState.label.Size = 10
    radarState.label.Center, radarState.label.Outline = true, true
    radarState.label.OutlineColor = Color3.new(0,0,0)
    radarState.label.Color = CONFIG.Accent
    radarState.label.Position = Vector2.new(center.X, tl.Y - 12)
    radarState.label.Transparency = 1

    for p in pairs(espData) do ensureRadarDot(p) end
end

local function hideRadar()
    if radarState.bg then setVisible(radarState.bg, false) end
    if radarState.border then setVisible(radarState.border, false) end
    if radarState.localDot then setVisible(radarState.localDot, false) end
    if radarState.label then setVisible(radarState.label, false) end
    for _, d in pairs(radarDots) do
        setVisible(d.dot, false)
        setVisible(d.dir, false)
    end
end

local function updateRadar()
    if not CONFIG.ShowRadar or not radarState.bg then hideRadar(); return end
    local lpChar = LocalPlayer.Character
    local lpRoot = lpChar and lpChar:FindFirstChild("HumanoidRootPart")
    if not lpRoot then hideRadar(); return end

    setVisible(radarState.bg, true)
    setVisible(radarState.border, true)
    setVisible(radarState.localDot, true)
    setVisible(radarState.label, true)

    local camCF = Camera.CFrame
    local camR = Vector3.new(camCF.RightVector.X, 0, camCF.RightVector.Z)
    local camL = Vector3.new(camCF.LookVector.X, 0, camCF.LookVector.Z)
    if camR.Magnitude < 0.01 then camR = Vector3.new(1,0,0) end
    if camL.Magnitude < 0.01 then camL = Vector3.new(0,0,-1) end
    camR, camL = camR.Unit, camL.Unit

    local localPos = lpRoot.Position
    local H = radarState.half
    local C = radarState.center
    local edge = H - 6
    local scale = edge / CONFIG.RadarRange
    local now = os.clock()

    for player, dot in pairs(radarDots) do
        local char = player.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        if not root then
            setVisible(dot.dot, false)
            setVisible(dot.dir, false)
            continue
        end
        local rel = root.Position - localPos
        local dx = rel:Dot(camR) * scale
        local dz = rel:Dot(camL) * scale
        local m = math.max(math.abs(dx), math.abs(dz))
        if m > edge then
            local s = edge / m
            dx, dz = dx * s, dz * s
        end
        local sx, sy = C.X + dx, C.Y - dz

        local ac = adminCache[player]
        if ac == nil or now - ac.t > 1.0 then
            ac = { isAdmin = isAdmin(player, char), t = now }
            adminCache[player] = ac
        end
        local color, size
        if ac.isAdmin then
            color, size = CONFIG.AdminColor, Vector2.new(9,9)
        elseif targetPlayers[player] then
            color, size = CONFIG.AccentBright, Vector2.new(8,8)
        else
            local dyW = rel.Y
            if dyW > 10 then color = Color3.fromRGB(255, 90, 90)
            elseif dyW < -10 then color = Color3.fromRGB(90, 160, 255)
            else color = Color3.fromRGB(235, 235, 235) end
            size = Vector2.new(5,5)
        end
        dot.dot.Size = size
        dot.dot.Color = color
        setPos(dot.dot, Vector2.new(sx - size.X/2, sy - size.Y/2))
        setVisible(dot.dot, true)

        local look = root.CFrame.LookVector
        local lx, lz = look:Dot(camR), look:Dot(camL)
        local mag = math.sqrt(lx*lx + lz*lz)
        if mag > 0.01 then
            lx, lz = lx/mag, lz/mag
            dot.dir.From = Vector2.new(sx, sy)
            dot.dir.To = Vector2.new(sx + lx*9, sy - lz*9)
            dot.dir.Color = color
            setVisible(dot.dir, true)
        else
            setVisible(dot.dir, false)
        end
    end
end

--=============================================================
-- MOVEMENT
--=============================================================
local function applyMovement()
    local char = LocalPlayer.Character
    if not char then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum then return end

    if CONFIG.WalkSpeed ~= 17 and hum.WalkSpeed ~= CONFIG.WalkSpeed then
        hum.WalkSpeed = CONFIG.WalkSpeed
    end

    if CONFIG.JumpPower ~= 50 then
        hum.UseJumpPower = true
        if hum.JumpPower ~= CONFIG.JumpPower then
            hum.JumpPower = CONFIG.JumpPower
        end
    end

    if CONFIG.Noclip then
        for _, d in ipairs(char:GetDescendants()) do
            if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" and d.CanCollide then
                d.CanCollide = false
            end
        end
    end
end

local function applyGravity()
    if workspace.Gravity ~= CONFIG.Gravity then
        workspace.Gravity = CONFIG.Gravity
    end
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function updateClimbers()
    if not (CONFIG.MountainClimber or CONFIG.WallClimber) then return end
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    rayParams.FilterDescendantsInstances = { char }
    local ray = workspace:Raycast(hrp.Position, hrp.CFrame.LookVector * 2.5, rayParams)
    if not ray then return end
    local nY = ray.Normal.Y
    if CONFIG.MountainClimber and nY > 0.1 and nY < 0.9 then
        hrp.Velocity = Vector3.new(hrp.Velocity.X, math.max(hrp.Velocity.Y, 22), hrp.Velocity.Z)
    end
    if CONFIG.WallClimber and math.abs(nY) < 0.35 then
        hrp.Velocity = Vector3.new(hrp.Velocity.X, 28, hrp.Velocity.Z)
    end
end

local function updateBunnyHop()
    if not CONFIG.BunnyHop then return end
    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if hum and hum.FloorMaterial ~= Enum.Material.Air then
        hum.Jump = true
    end
end

--=============================================================
-- HITBOX WIDENER
--=============================================================
local function isEnemy(player)
    if not CONFIG.HitboxTeamCheck then return true end
    local myTeam = LocalPlayer.Team
    if not myTeam then return true end
    return player.Team ~= myTeam
end

local function applyHitbox(player)
    if player == LocalPlayer then return end
    local char = player.Character
    if not char then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then return end
    if not isEnemy(player) then return end

    -- Prefer HumanoidRootPart — bigger and doesn't rotate with head
    local part = char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Head")
    if not part then return end

    local existing = hitboxes[player]
    if existing and existing.part == part then
        -- Just re-apply size in case game reset it
        if part.Size ~= existing.appliedSize then
            pcall(function() part.Size = existing.appliedSize end)
        end
        if part.Transparency ~= CONFIG.HitboxTransparency then
            pcall(function() part.Transparency = CONFIG.HitboxTransparency end)
        end
        return
    end

    -- New part — save originals
    hitboxes[player] = {
        part = part,
        originalSize = part.Size,
        originalTransparency = part.Transparency,
        appliedSize = Vector3.new(CONFIG.HitboxSize, CONFIG.HitboxSize, CONFIG.HitboxSize),
    }
    pcall(function() part.Size = hitboxes[player].appliedSize end)
    pcall(function() part.Transparency = CONFIG.HitboxTransparency end)
end

local function restoreHitbox(player)
    local rec = hitboxes[player]
    if not rec then return end
    if rec.part and rec.part.Parent then
        pcall(function() rec.part.Size = rec.originalSize end)
        pcall(function() rec.part.Transparency = rec.originalTransparency end)
    end
    hitboxes[player] = nil
end

local function restoreAllHitboxes()
    for player in pairs(hitboxes) do
        restoreHitbox(player)
    end
    hitboxes = {}
end

local function updateHitboxes()
    if not CONFIG.HitboxEnabled then
        if next(hitboxes) then restoreAllHitboxes() end
        return
    end

    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            applyHitbox(player)
        end
    end

    -- Restore any player who no longer qualifies (left team, died, etc.)
    for player, rec in pairs(hitboxes) do
        local char = player.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if not char or not hum or hum.Health <= 0 or not isEnemy(player) then
            restoreHitbox(player)
        end
    end
end

--=============================================================
-- FULLBRIGHT
--=============================================================
local function setFullbright(on)
    if on then
        if not savedLighting then
            savedLighting = {
                Brightness     = Lighting.Brightness,
                Ambient        = Lighting.Ambient,
                OutdoorAmbient = Lighting.OutdoorAmbient,
                ClockTime      = Lighting.ClockTime,
                FogEnd         = Lighting.FogEnd,
                GlobalShadows  = Lighting.GlobalShadows,
            }
        end
        Lighting.Brightness     = 3
        Lighting.Ambient        = Color3.fromRGB(200, 200, 200)
        Lighting.OutdoorAmbient = Color3.fromRGB(200, 200, 200)
        Lighting.ClockTime      = 14
        Lighting.FogEnd         = 100000
        Lighting.GlobalShadows  = false
    else
        if savedLighting then
            Lighting.Brightness     = savedLighting.Brightness
            Lighting.Ambient        = savedLighting.Ambient
            Lighting.OutdoorAmbient = savedLighting.OutdoorAmbient
            Lighting.ClockTime      = savedLighting.ClockTime
            Lighting.FogEnd         = savedLighting.FogEnd
            Lighting.GlobalShadows  = savedLighting.GlobalShadows
            savedLighting = nil
        end
    end
end

--=============================================================
-- POTATO MODE
--=============================================================
local POTATO_DISABLE = {
    "ParticleEmitter","Smoke","Fire","Sparkles","Trail","Beam",
    "PointLight","SpotLight","SurfaceLight",
    "BloomEffect","BlurEffect","DepthOfFieldEffect","SunRaysEffect",
    "ColorCorrectionEffect",
}

local function potatoSave(inst, prop)
    local s = potatoState.saved[inst]
    if not s then s = {}; potatoState.saved[inst] = s end
    if s[prop] == nil then s[prop] = inst[prop] end
end

local function potatoApply(inst)
    if not inst or not inst.Parent then return end

    if inst:IsA("BasePart") then
        potatoSave(inst, "Material")
        potatoSave(inst, "Reflectance")
        potatoSave(inst, "CastShadow")
        potatoSave(inst, "Color")
        pcall(function()
            inst.Material    = Enum.Material.SmoothPlastic
            inst.Reflectance = 0
            inst.CastShadow  = false
            inst.Color       = Color3.fromRGB(160, 130, 100)
        end)
        return
    end

    for _, t in ipairs(POTATO_DISABLE) do
        if inst:IsA(t) then
            potatoSave(inst, "Enabled")
            pcall(function() inst.Enabled = false end)
            return
        end
    end

    if inst:IsA("Atmosphere") then
        potatoSave(inst, "Density")
        potatoSave(inst, "Haze")
        potatoSave(inst, "Glare")
        pcall(function()
            inst.Density = 0
            inst.Haze    = 0
            inst.Glare   = 0
        end)
        return
    end

    if inst:IsA("Decal") or inst:IsA("Texture") then
        potatoSave(inst, "Transparency")
        pcall(function() inst.Transparency = 1 end)
        return
    end

    if inst:IsA("LayerCollector") then
        if inst.Name == "BoogaHub" then return end
        potatoSave(inst, "Enabled")
        pcall(function() inst.Enabled = false end)
        return
    end

    if inst:IsA("GuiObject") then
        potatoSave(inst, "Visible")
        pcall(function() inst.Visible = false end)
        return
    end
end

local function potatoLighting(on)
    if on then
        if not potatoState.savedLighting then
            potatoState.savedLighting = {
                Brightness     = Lighting.Brightness,
                Ambient        = Lighting.Ambient,
                OutdoorAmbient = Lighting.OutdoorAmbient,
                GlobalShadows  = Lighting.GlobalShadows,
                FogStart       = Lighting.FogStart,
                FogEnd         = Lighting.FogEnd,
                FogColor       = Lighting.FogColor,
                EnvironmentDiffuseScale  = Lighting.EnvironmentDiffuseScale,
                EnvironmentSpecularScale = Lighting.EnvironmentSpecularScale,
            }
        end
        Lighting.Brightness     = 1
        Lighting.Ambient        = Color3.fromRGB(130, 130, 130)
        Lighting.OutdoorAmbient = Color3.fromRGB(130, 130, 130)
        Lighting.GlobalShadows  = false
        Lighting.FogStart       = 0
        Lighting.FogEnd         = 120
        Lighting.FogColor       = Color3.fromRGB(130, 130, 130)
        Lighting.EnvironmentDiffuseScale  = 0
        Lighting.EnvironmentSpecularScale = 0
    else
        local s = potatoState.savedLighting
        if s then
            Lighting.Brightness     = s.Brightness
            Lighting.Ambient        = s.Ambient
            Lighting.OutdoorAmbient = s.OutdoorAmbient
            Lighting.GlobalShadows  = s.GlobalShadows
            Lighting.FogStart       = s.FogStart
            Lighting.FogEnd         = s.FogEnd
            Lighting.FogColor       = s.FogColor
            Lighting.EnvironmentDiffuseScale  = s.EnvironmentDiffuseScale
            Lighting.EnvironmentSpecularScale = s.EnvironmentSpecularScale
            potatoState.savedLighting = nil
        end
    end
end

local function potatoQuality(on)
    local ok, UGS = pcall(function()
        return UserSettings():GetService("UserGameSettings")
    end)
    if not ok or not UGS then return end
    if on then
        potatoState.savedQuality = UGS.SavedQualityLevel
        pcall(function()
            UGS.SavedQualityLevel = Enum.SavedQualitySetting.QualityLevel1
        end)
    else
        if potatoState.savedQuality then
            pcall(function()
                UGS.SavedQualityLevel = potatoState.savedQuality
            end)
            potatoState.savedQuality = nil
        end
    end
end

local function potatoEnable()
    if potatoState.enabled then return end
    potatoState.enabled = true

    for _, inst in ipairs(workspace:GetDescendants()) do
        potatoApply(inst)
    end

    potatoLighting(true)
    potatoQuality(true)

    potatoState.conn = workspace.DescendantAdded:Connect(function(inst)
        if not potatoState.enabled then return end
        potatoApply(inst)
    end)

    notify("Potato mode ON")
end

local function potatoDisable()
    if not potatoState.enabled then return end
    potatoState.enabled = false

    if potatoState.conn then
        potatoState.conn:Disconnect()
        potatoState.conn = nil
    end

    for inst, props in pairs(potatoState.saved) do
        if inst and inst.Parent then
            for prop, val in pairs(props) do
                pcall(function() inst[prop] = val end)
            end
        end
    end
    potatoState.saved = {}

    potatoLighting(false)
    potatoQuality(false)

    notify("Potato mode OFF")
end

--=============================================================
-- ANTI-AFK
--=============================================================
LocalPlayer.Idled:Connect(function()
    if not CONFIG.AntiAFK then return end
    pcall(function()
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new())
    end)
end)

--=============================================================
-- INFINITE JUMP
--=============================================================
UserInputService.JumpRequest:Connect(function()
    if not CONFIG.InfiniteJump then return end
    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if hum then
        pcall(function()
            hum:ChangeState(Enum.HumanoidStateType.Jumping)
        end)
    end
end)


--=============================================================
-- ANTI-KICK
--=============================================================
local function initAntiKick()
    local ok, err = pcall(function()
        local mt = getrawmetatable(game)
        local oldNamecall = mt.__namecall
        setreadonly(mt, false)
        mt.__namecall = newcclosure(function(self, ...)
            local method = getnamecallmethod()
            if CONFIG.AntiKick and method == "Kick" and self == LocalPlayer then
                return
            end
            return oldNamecall(self, ...)
        end)
        setreadonly(mt, true)
    end)
    if not ok then
        warn("[Booga] Anti-Kick hook failed: " .. tostring(err))
    end
end

--=============================================================
-- SERVER HOP / SUB-PLACES / REJOIN / COPY JOB ID
--=============================================================
local function serverHop()
    task.spawn(function()
        local placeId = game.PlaceId
        local jobId   = game.JobId
        local data = httpGetJson(
            "https://games.roblox.com/v1/games/" .. placeId ..
            "/servers/Public?sortOrder=Asc&limit=100"
        )
        if not data or not data.data then
            notify("Server hop failed")
            return
        end
        for _, server in ipairs(data.data) do
            if server.id ~= jobId and server.playing < server.maxPlayers then
                notify("Hopping servers...")
                pcall(function()
                    TeleportService:TeleportToPlaceInstance(placeId, server.id, LocalPlayer)
                end)
                return
            end
        end
        notify("No available servers")
    end)
end

local function getSubPlaces()
    local universeId = game.GameId
    local url = "https://develop.roblox.com/v1/universes/" .. universeId ..
                "/places?limit=100&sortOrder=Asc"
    local data = httpGetJson(url)
    if not data or not data.data then
        warn("[Booga] Failed to fetch sub-places. URL tried: " .. url)
        return {}
    end
    return data.data
end

local function teleportToPlace(placeId)
    notify("Teleporting...")
    pcall(function()
        TeleportService:Teleport(placeId, LocalPlayer)
    end)
end

local function rejoin()
    notify("Rejoining...")
    pcall(function()
        TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer)
    end)
end

local function copyJobId()
    local id = game.JobId
    if #id == 0 then id = "(reserved server)" end
    local ok = pcall(function() setclipboard(id) end)
    if ok then
        notify("Copied Job ID")
    else
        notify("Job ID: " .. id:sub(1, 18) .. "...")
    end
end

--=============================================================
-- ESP RENDER
--=============================================================
local function renderESP(now)
    if not CONFIG.Enabled then
        for _, d in pairs(espData) do
            setVisible(d.admin, false)
            setVisible(d.name, false)
            setVisible(d.health, false)
            setVisible(d.tool, false)
            setVisible(d.armor, false)
            setVisible(d.box, false)
        end
        return
    end

    local camPos = Camera.CFrame.Position

    for player, data in pairs(espData) do
        local char = player.Character
        local hum  = char and char:FindFirstChildOfClass("Humanoid")
        local head = char and char:FindFirstChild("Head")
        local root = char and char:FindFirstChild("HumanoidRootPart")

        local alive   = char and hum and head and root and hum.Health > 0
        local inRange = alive and (camPos - root.Position).Magnitude <= CONFIG.MaxDistance

        if not inRange then
            setVisible(data.admin, false)
            setVisible(data.name, false)
            setVisible(data.health, false)
            setVisible(data.tool, false)
            setVisible(data.armor, false)
            setVisible(data.box, false)
            continue
        end

        local wp = head.Position + Vector3.new(0, 1.35, 0)
        local sc, on = Camera:WorldToViewportPoint(wp)
        if not on then
            setVisible(data.admin, false)
            setVisible(data.name, false)
            setVisible(data.health, false)
            setVisible(data.tool, false)
            setVisible(data.armor, false)
            setVisible(data.box, false)
            continue
        end

        local pos = Vector2.new(sc.X, sc.Y)
        local y = 0

        if CONFIG.ShowAdmins then
            local ac = adminCache[player]
            if ac == nil or now - ac.t > 1.0 then
                ac = { isAdmin = isAdmin(player, char), t = now }
                adminCache[player] = ac
            end
            if ac.isAdmin then
                setText(data.admin, "! ADMIN")
                setPos(data.admin, pos - Vector2.new(0, 14))
                setVisible(data.admin, true)
            else setVisible(data.admin, false) end
        else setVisible(data.admin, false) end

        if CONFIG.ShowName then
            local nameStr = player.Name
            if targetPlayers[player] then nameStr = "★ " .. nameStr end
            setText(data.name, nameStr)
            setPos(data.name, pos + Vector2.new(0, y))
            setVisible(data.name, true)
            y = y + 13
        else setVisible(data.name, false) end

        if CONFIG.ShowHealth then
            setText(data.health, math.floor(hum.Health) .. " HP")
            setPos(data.health, pos + Vector2.new(0, y))
            setVisible(data.health, true)
            y = y + 13
        else setVisible(data.health, false) end

        if CONFIG.ShowTool then
            local tc = toolCache[player]
            if tc == nil or now - tc.t > (1 / CONFIG.ToolRefreshHz) then
                local tool = char:FindFirstChildOfClass("Tool")
                tc = { tool = tool, t = now }
                toolCache[player] = tc
            end
            if tc.tool then
                setText(data.tool, "> " .. tc.tool.Name)
                setPos(data.tool, pos + Vector2.new(0, y))
                setVisible(data.tool, true)
                y = y + 13
            else setVisible(data.tool, false) end
        else setVisible(data.tool, false) end

        if CONFIG.ShowArmor then
            local c = armorCache[player]
            if c == nil or now - c.t > 0.8 then
                c = { text = summarizeArmor(char), t = now }
                armorCache[player] = c
            end
            if c.text then
                setText(data.armor, "[" .. c.text .. "]")
                setPos(data.armor, pos + Vector2.new(0, y))
                setVisible(data.armor, true)
            else setVisible(data.armor, false) end
        else setVisible(data.armor, false) end

        if CONFIG.ShowBoxes then
            local topPos = head.Position + Vector3.new(0, 0.5, 0)
            local botPos = root.Position - Vector3.new(0, 3, 0)
            local topSc, topOn = Camera:WorldToViewportPoint(topPos)
            local botSc, botOn = Camera:WorldToViewportPoint(botPos)
            if topOn and botOn then
                local boxH = botSc.Y - topSc.Y
                local boxW = boxH * 0.55
                data.box.Size = Vector2.new(boxW, boxH)
                data.box.Position = Vector2.new(topSc.X - boxW/2, topSc.Y)
                if targetPlayers[player] then
                    data.box.Color = CONFIG.AccentBright
                elseif adminCache[player] and adminCache[player].isAdmin then
                    data.box.Color = CONFIG.AdminColor
                else
                    data.box.Color = CONFIG.BoxColor
                end
                setVisible(data.box, true)
            else
                setVisible(data.box, false)
            end
        else
            setVisible(data.box, false)
        end
    end
end

--=============================================================
-- PLAYER LIFECYCLE
--=============================================================
for _, p in ipairs(Players:GetPlayers()) do
    createESP(p); ensureRadarDot(p)
end

Players.PlayerAdded:Connect(function(p)
    createESP(p); ensureRadarDot(p)
    p.CharacterAdded:Connect(function()
        armorCache[p] = nil
        adminCache[p] = nil
        toolCache[p]  = nil
        restoreHitbox(p)
    end)
    if refreshTargetList then refreshTargetList() end
end)

Players.PlayerRemoving:Connect(function(p)
    removeESP(p)
    restoreHitbox(p)
    local d = radarDots[p]
    if d then d.dot:Remove(); d.dir:Remove(); radarDots[p] = nil end
    targetPlayers[p] = nil
    if refreshTargetList then refreshTargetList() end
end)

--=============================================================
-- GUI
--=============================================================
local function make(class, props, parent)
    local i = Instance.new(class)
    for k, v in pairs(props or {}) do i[k] = v end
    if parent then i.Parent = parent end
    return i
end

local function buildGUI()
    local uiRefreshers = {}

    local gui = make("ScreenGui", {
        Name = "BoogaHub",
        ResetOnSpawn = false,
        IgnoreGuiInset = true,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    })
    local ok = pcall(function() gui.Parent = CoreGui end)
    if not ok then gui.Parent = LocalPlayer:WaitForChild("PlayerGui") end

    local W, H = 250, 340
    local TOP_Y, LEFT_X = 90, 24

    local panel = make("Frame", {
        Size = UDim2.new(0, W, 0, H),
        Position = UDim2.new(0, LEFT_X, 0, TOP_Y),
        BackgroundColor3 = CONFIG.Bg,
        BorderSizePixel = 0,
        Active = true,
        ClipsDescendants = true,
        ZIndex = 2,
    }, gui)
    make("UIStroke", {
        Color = CONFIG.Accent, Thickness = 1,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    }, panel)

    local header = make("Frame", {
        Size = UDim2.new(1, 0, 0, 40),
        BackgroundColor3 = CONFIG.Bg1,
        BorderSizePixel = 0,
        Active = true,
        ZIndex = 3,
    }, panel)
    make("Frame", {
        Size = UDim2.new(1, 0, 0, 1),
        Position = UDim2.new(0, 0, 1, -1),
        BackgroundColor3 = CONFIG.Accent,
        BorderSizePixel = 0,
        ZIndex = 4,
    }, header)

    make("TextLabel", {
        Size = UDim2.new(1, -60, 0, 20),
        Position = UDim2.new(0, 14, 0, 4),
        BackgroundTransparency = 1,
        Font = Enum.Font.GothamBold,
        TextSize = 15,
        TextColor3 = CONFIG.AccentBright,
        TextXAlignment = Enum.TextXAlignment.Left,
        Text = "BoogaHub",
        ZIndex = 5,
    }, header)

    make("TextLabel", {
        Size = UDim2.new(1, -60, 0, 14),
        Position = UDim2.new(0, 14, 0, 22),
        BackgroundTransparency = 1,
        Font = Enum.Font.Gotham,
        TextSize = 10,
        TextColor3 = CONFIG.TextDim,
        TextXAlignment = Enum.TextXAlignment.Left,
        Text = "made by gage",
        ZIndex = 5,
    }, header)

    local minBtn = make("TextButton", {
        Size = UDim2.new(0, 24, 0, 24),
        Position = UDim2.new(1, -52, 0, 8),
        BackgroundColor3 = CONFIG.Bg2,
        BorderSizePixel = 0,
        Font = Enum.Font.Code, TextSize = 14,
        TextColor3 = CONFIG.TextDim, Text = "-",
        AutoButtonColor = false, ZIndex = 5,
    }, header)
    local closeBtn = make("TextButton", {
        Size = UDim2.new(0, 24, 0, 24),
        Position = UDim2.new(1, -26, 0, 8),
        BackgroundColor3 = CONFIG.Bg2,
        BorderSizePixel = 0,
        Font = Enum.Font.Code, TextSize = 14,
        TextColor3 = CONFIG.TextDim, Text = "X",
        AutoButtonColor = false, ZIndex = 5,
    }, header)

    local tabBar = make("Frame", {
        Size = UDim2.new(1, -20, 0, 24),
        Position = UDim2.new(0, 10, 0, 48),
        BackgroundTransparency = 1,
        ZIndex = 3,
    }, panel)
    make("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        Padding = UDim.new(0, 4),
    }, tabBar)

    local pageHolder = make("Frame", {
        Size = UDim2.new(1, -20, 1, -86),
        Position = UDim2.new(0, 10, 0, 78),
        BackgroundTransparency = 1,
        ZIndex = 3,
    }, panel)

    local function makePage()
        local page = make("ScrollingFrame", {
            Size = UDim2.new(1, 0, 1, 0),
            BackgroundTransparency = 1,
            Visible = false,
            ZIndex = 3,
            CanvasSize = UDim2.new(0, 0, 0, 0),
            ScrollBarThickness = 3,
            ScrollBarImageColor3 = CONFIG.Accent,
            ScrollingDirection = Enum.ScrollingDirection.Y,
            AutomaticCanvasSize = Enum.AutomaticSize.Y,
        }, pageHolder)
        make("UIListLayout", {
            Padding = UDim.new(0, 3),
            SortOrder = Enum.SortOrder.LayoutOrder,
        }, page)
        return page
    end

    local espPage    = makePage()
    local movePage   = makePage()
    local combatPage = makePage()
    local miscPage   = makePage()
    local pages = { espPage, movePage, combatPage, miscPage }
    local tabs  = {}

    local function makeTab(label, order, page, defaultOn)
        local btn = make("TextButton", {
            Size = UDim2.new(0, 38, 1, 0),
            BackgroundColor3 = defaultOn and CONFIG.AccentDim or CONFIG.Bg1,
            BorderSizePixel = 0,
            Font = Enum.Font.GothamBold,
            TextSize = 9,
            TextColor3 = defaultOn and CONFIG.AccentBright or CONFIG.TextDim,
            Text = label,
            AutoButtonColor = false,
            LayoutOrder = order,
            ZIndex = 4,
        }, tabBar)
        tabs[page] = btn
        btn.MouseButton1Click:Connect(function()
            for _, b in pairs(tabs) do
                b.BackgroundColor3 = CONFIG.Bg1
                b.TextColor3 = CONFIG.TextDim
            end
            for _, p in ipairs(pages) do p.Visible = false end
            page.Visible = true
            btn.BackgroundColor3 = CONFIG.AccentDim
            btn.TextColor3 = CONFIG.AccentBright
        end)
        if defaultOn then page.Visible = true end
    end

    makeTab("ESP",    1, espPage,    true)
    makeTab("MOVE",   2, movePage,   false)
    makeTab("COMBAT", 3, combatPage, false)
    makeTab("MISC",   6, miscPage,   false)

    local function makeRow(parent, label, order, getter, setter)
        local row = make("Frame", {
            Size = UDim2.new(1, 0, 0, 26),
            BackgroundColor3 = CONFIG.Bg1,
            BorderSizePixel = 0,
            LayoutOrder = order,
        }, parent)
        local bar = make("Frame", {
            Size = UDim2.new(0, 3, 1, 0),
            BackgroundColor3 = getter() and CONFIG.Accent or CONFIG.Bg2,
            BorderSizePixel = 0,
            ZIndex = 4,
        }, row)
        make("TextLabel", {
            Size = UDim2.new(1, -50, 1, 0),
            Position = UDim2.new(0, 12, 0, 0),
            BackgroundTransparency = 1,
            Font = Enum.Font.Gotham, TextSize = 12,
            TextColor3 = CONFIG.Text,
            TextXAlignment = Enum.TextXAlignment.Left,
            Text = label, ZIndex = 4,
        }, row)
        local status = make("TextLabel", {
            Size = UDim2.new(0, 36, 1, 0),
            Position = UDim2.new(1, -40, 0, 0),
            BackgroundTransparency = 1,
            Font = Enum.Font.Code, TextSize = 11,
            TextColor3 = getter() and CONFIG.AccentBright or CONFIG.TextDim,
            TextXAlignment = Enum.TextXAlignment.Right,
            Text = getter() and "ON" or "OFF",
            ZIndex = 4,
        }, row)
        local btn = make("TextButton", {
            Size = UDim2.new(1, 0, 1, 0),
            BackgroundTransparency = 1, Text = "",
            AutoButtonColor = false, ZIndex = 6,
        }, row)
        local function refreshRow()
            local on = getter()
            bar.BackgroundColor3 = on and CONFIG.Accent or CONFIG.Bg2
            status.Text = on and "ON" or "OFF"
            status.TextColor3 = on and CONFIG.AccentBright or CONFIG.TextDim
        end
        btn.MouseButton1Click:Connect(function()
            setter(not getter())
            refreshRow()
        end)
        btn.MouseEnter:Connect(function() row.BackgroundColor3 = CONFIG.Bg2 end)
        btn.MouseLeave:Connect(function() row.BackgroundColor3 = CONFIG.Bg1 end)
        table.insert(uiRefreshers, refreshRow)
    end

    local function makeActionRow(parent, label, order, callback)
        local row = make("Frame", {
            Size = UDim2.new(1, 0, 0, 30),
            BackgroundColor3 = CONFIG.Bg2,
            BorderSizePixel = 0,
            LayoutOrder = order,
        }, parent)
        make("Frame", {
            Size = UDim2.new(0, 3, 1, 0),
            BackgroundColor3 = CONFIG.Accent,
            BorderSizePixel = 0, ZIndex = 4,
        }, row)
        make("TextLabel", {
            Size = UDim2.new(1, -20, 1, 0),
            Position = UDim2.new(0, 12, 0, 0),
            BackgroundTransparency = 1,
            Font = Enum.Font.GothamBold, TextSize = 12,
            TextColor3 = CONFIG.AccentBright,
            TextXAlignment = Enum.TextXAlignment.Left,
            Text = label, ZIndex = 4,
        }, row)
        local btn = make("TextButton", {
            Size = UDim2.new(1, 0, 1, 0),
            BackgroundTransparency = 1, Text = "",
            AutoButtonColor = false, ZIndex = 6,
        }, row)
        btn.MouseButton1Click:Connect(callback)
        btn.MouseEnter:Connect(function() row.BackgroundColor3 = CONFIG.AccentDim end)
        btn.MouseLeave:Connect(function() row.BackgroundColor3 = CONFIG.Bg2 end)
        return row
    end

    local function makeSlider(parent, label, order, minV, maxV, step, getter, setter, formatter)
        local row = make("Frame", {
            Size = UDim2.new(1, 0, 0, 26),
            BackgroundColor3 = CONFIG.Bg1,
            BorderSizePixel = 0, LayoutOrder = order,
        }, parent)
        make("TextLabel", {
            Size = UDim2.new(1, -110, 1, 0),
            Position = UDim2.new(0, 12, 0, 0),
            BackgroundTransparency = 1,
            Font = Enum.Font.Gotham, TextSize = 12,
            TextColor3 = CONFIG.Text,
            TextXAlignment = Enum.TextXAlignment.Left,
            Text = label, ZIndex = 4,
        }, row)
        local function fmt(v)
            if formatter then return formatter(v) end
            return tostring(v)
        end
        local valLbl = make("TextLabel", {
            Size = UDim2.new(0, 44, 1, 0),
            Position = UDim2.new(1, -94, 0, 0),
            BackgroundTransparency = 1,
            Font = Enum.Font.Code, TextSize = 12,
            TextColor3 = CONFIG.AccentBright,
            Text = fmt(getter()), ZIndex = 4,
        }, row)
        local minusBtn = make("TextButton", {
            Size = UDim2.new(0, 22, 0, 20),
            Position = UDim2.new(1, -48, 0, 3),
            BackgroundColor3 = CONFIG.Bg2, BorderSizePixel = 0,
            Font = Enum.Font.Code, TextSize = 14,
            TextColor3 = CONFIG.Text, Text = "-",
            AutoButtonColor = false, ZIndex = 5,
        }, row)
        local plusBtn = make("TextButton", {
            Size = UDim2.new(0, 22, 0, 20),
            Position = UDim2.new(1, -24, 0, 3),
            BackgroundColor3 = CONFIG.Bg2, BorderSizePixel = 0,
            Font = Enum.Font.Code, TextSize = 14,
            TextColor3 = CONFIG.Text, Text = "+",
            AutoButtonColor = false, ZIndex = 5,
        }, row)
        local function refreshSlider()
            valLbl.Text = fmt(getter())
        end
        minusBtn.MouseButton1Click:Connect(function()
            setter(math.max(minV, getter() - step))
            refreshSlider()
        end)
        plusBtn.MouseButton1Click:Connect(function()
            setter(math.min(maxV, getter() + step))
            refreshSlider()
        end)
        table.insert(uiRefreshers, refreshSlider)
    end

    --==== ESP ====--
    makeRow(espPage, "Enable ESP", 1, function() return CONFIG.Enabled    end, function(v) CONFIG.Enabled = v    end)
    makeRow(espPage, "Username",   2, function() return CONFIG.ShowName   end, function(v) CONFIG.ShowName = v   end)
    makeRow(espPage, "Health",     3, function() return CONFIG.ShowHealth end, function(v) CONFIG.ShowHealth = v end)
    makeRow(espPage, "Tool",       4, function() return CONFIG.ShowTool   end, function(v) CONFIG.ShowTool = v   end)
    makeRow(espPage, "Armor",      5, function() return CONFIG.ShowArmor  end, function(v) CONFIG.ShowArmor = v  end)
    makeRow(espPage, "Boxes",      6, function() return CONFIG.ShowBoxes  end, function(v) CONFIG.ShowBoxes = v  end)
    makeSlider(espPage, "Range",   7, 100, 5000, 100,
        function() return CONFIG.MaxDistance end,
        function(v) CONFIG.MaxDistance = v end)

    --==== MOVE ====--
    makeRow(movePage, "Noclip",           1, function() return CONFIG.Noclip          end, function(v) CONFIG.Noclip = v          end)
    makeRow(movePage, "Mountain Climber", 2, function() return CONFIG.MountainClimber end, function(v) CONFIG.MountainClimber = v end)
    makeRow(movePage, "Wall Climber",     3, function() return CONFIG.WallClimber     end, function(v) CONFIG.WallClimber = v     end)
    makeRow(movePage, "Infinite Jump",    4, function() return CONFIG.InfiniteJump    end, function(v) CONFIG.InfiniteJump = v    end)
    makeRow(movePage, "Bunny Hop",        5, function() return CONFIG.BunnyHop        end, function(v) CONFIG.BunnyHop = v        end)
    makeSlider(movePage, "WalkSpeed",  6, 16, 500, 4,
        function() return CONFIG.WalkSpeed end,
        function(v) CONFIG.WalkSpeed = v end)
    makeSlider(movePage, "JumpPower",  7, 50, 500, 10,
        function() return CONFIG.JumpPower end,
        function(v) CONFIG.JumpPower = v end)
    makeSlider(movePage, "Gravity",    8, 0, 300, 10,
        function() return CONFIG.Gravity end,
        function(v) CONFIG.Gravity = v end)

    --==== COMBAT ====--
    makeRow(combatPage, "Hitbox Widener", 1,
        function() return CONFIG.HitboxEnabled end,
        function(v) CONFIG.HitboxEnabled = v end)
    makeRow(combatPage, "Team Check",     2,
        function() return CONFIG.HitboxTeamCheck end,
        function(v) CONFIG.HitboxTeamCheck = v end)
    makeSlider(combatPage, "Hitbox Size", 3, 2, 20, 1,
        function() return CONFIG.HitboxSize end,
        function(v)
            CONFIG.HitboxSize = v
            -- Force re-apply with new size
            for player, rec in pairs(hitboxes) do
                if rec and rec.part and rec.part.Parent then
                    rec.appliedSize = Vector3.new(v, v, v)
                end
            end
        end)
    makeSlider(combatPage, "Hitbox Opacity", 4, 0, 100, 10,
        function() return math.floor((1 - CONFIG.HitboxTransparency) * 100) end,
        function(v)
            CONFIG.HitboxTransparency = 1 - (v / 100)
            for _, rec in pairs(hitboxes) do
                if rec and rec.part and rec.part.Parent then
                    pcall(function() rec.part.Transparency = CONFIG.HitboxTransparency end)
                end
            end
        end)

    --==== MISC ====--
    makeRow(miscPage, "Admin Alert",   1, function() return CONFIG.ShowAdmins  end, function(v) CONFIG.ShowAdmins = v  end)
    makeRow(miscPage, "Radar",         2, function() return CONFIG.ShowRadar   end, function(v) CONFIG.ShowRadar = v   end)
    makeRow(miscPage, "FPS Overlay",   3, function() return CONFIG.ShowFPS     end, function(v) CONFIG.ShowFPS = v     end)
    makeRow(miscPage, "Anti-Kick",     4, function() return CONFIG.AntiKick    end, function(v) CONFIG.AntiKick = v    end)
    makeRow(miscPage, "Anti-AFK",      5, function() return CONFIG.AntiAFK     end, function(v) CONFIG.AntiAFK = v     end)
    makeRow(miscPage, "Fullbright",    6,
        function() return CONFIG.Fullbright end,
        function(v) CONFIG.Fullbright = v; setFullbright(v) end)
    makeRow(miscPage, "Potato Mode",   7,
        function() return CONFIG.PotatoMode end,
        function(v)
            CONFIG.PotatoMode = v
            if v then
                if CONFIG.Fullbright then
                    CONFIG.Fullbright = false
                    setFullbright(false)
                end
                potatoEnable()
                for _, fn in ipairs(uiRefreshers) do pcall(fn) end
            else
                potatoDisable()
            end
        end)
    makeActionRow(miscPage, "SERVER HOP",  8,  serverHop)
    makeActionRow(miscPage, "REJOIN",      9,  rejoin)
    makeActionRow(miscPage, "COPY JOB ID", 10, copyJobId)

    do
        local hdr = make("Frame", {
            Size = UDim2.new(1, 0, 0, 22),
            BackgroundColor3 = CONFIG.Bg2,
            BorderSizePixel = 0, LayoutOrder = 20,
        }, miscPage)
        make("TextLabel", {
            Size = UDim2.new(1, 0, 1, 0),
            BackgroundTransparency = 1,
            Font = Enum.Font.GothamBold, TextSize = 11,
            TextColor3 = CONFIG.AccentBright,
            Text = "SUB-PLACES",
            ZIndex = 4,
        }, hdr)
    end

    local subPlaceHolder = make("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        BackgroundTransparency = 1,
        LayoutOrder = 21,
        AutomaticSize = Enum.AutomaticSize.Y,
    }, miscPage)
    make("UIListLayout", {
        Padding = UDim.new(0, 3),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }, subPlaceHolder)

    guiRefs.subPlaceHolder = subPlaceHolder

    --==== Toast ====--
    local toast = make("TextLabel", {
        Size = UDim2.new(0, 300, 0, 28),
        Position = UDim2.new(0.5, -150, 0, 40),
        BackgroundColor3 = CONFIG.Bg,
        BorderSizePixel = 0,
        Font = Enum.Font.GothamBold, TextSize = 13,
        TextColor3 = CONFIG.AccentBright,
        Text = "",
        Visible = false, ZIndex = 30,
    }, gui)
    make("UIStroke", { Color = CONFIG.Accent, Thickness = 1 }, toast)
    guiRefs.toast = toast

    --==== Disable-all helper ====--
    local function disableAllFeatures()
        -- ESP / visuals
        CONFIG.Enabled    = false
        CONFIG.ShowName   = false
        CONFIG.ShowHealth = false
        CONFIG.ShowTool   = false
        CONFIG.ShowArmor  = false
        CONFIG.ShowBoxes  = false
        CONFIG.ShowAdmins = false
        CONFIG.ShowRadar  = false
        CONFIG.ShowFPS    = false

        -- movement
        CONFIG.Noclip          = false
        CONFIG.MountainClimber = false
        CONFIG.WallClimber     = false
        CONFIG.InfiniteJump    = false
        CONFIG.BunnyHop        = false
        CONFIG.WalkSpeed       = 17
        CONFIG.JumpPower       = 50
        CONFIG.Gravity         = 196.2

        -- combat
        CONFIG.HitboxEnabled      = false
        CONFIG.HitboxTeamCheck    = false
        CONFIG.HitboxSize         = 6
        CONFIG.HitboxTransparency = 0.7

        -- misc
        CONFIG.AntiKick   = false
        CONFIG.AntiAFK    = false
        if CONFIG.Fullbright then
            CONFIG.Fullbright = false
            setFullbright(false)
        end
        if CONFIG.PotatoMode then
            CONFIG.PotatoMode = false
            potatoDisable()
        end

        -- restore world state
        restoreAllHitboxes()
        hideRadar()
        if fpsText.Visible then fpsText.Visible = false end

        -- restore character defaults
        local char = LocalPlayer.Character
        local hum  = char and char:FindFirstChildOfClass("Humanoid")
        if hum then
            pcall(function() hum.WalkSpeed = 16 end)
            pcall(function() hum.UseJumpPower = true; hum.JumpPower = 50 end)
        end
        pcall(function() workspace.Gravity = 196.2 end)

        -- refresh all toggle/slider visuals
        for _, fn in ipairs(uiRefreshers) do pcall(fn) end

        notify("All features disabled")
    end

    --==== Minimize/close/drag ====--
    local bIcon = make("TextButton", {
        Size = UDim2.new(0, 34, 0, 34),
        Position = UDim2.new(0, LEFT_X, 0, TOP_Y),
        BackgroundColor3 = CONFIG.Bg, BorderSizePixel = 0,
        Font = Enum.Font.GothamBold, TextSize = 16,
        TextColor3 = CONFIG.AccentBright, Text = "S",
        AutoButtonColor = false, Visible = false, ZIndex = 10,
    }, gui)
    make("UIStroke", { Color = CONFIG.Accent, Thickness = 1 }, bIcon)

    minBtn.MouseButton1Click:Connect(function() panel.Visible = false; bIcon.Visible = true end)
    bIcon.MouseButton1Click:Connect(function() panel.Visible = true; bIcon.Visible = false end)
    closeBtn.MouseButton1Click:Connect(function()
        disableAllFeatures()
        gui.Enabled = false
    end)

    minBtn.MouseEnter:Connect(function() minBtn.BackgroundColor3 = CONFIG.Bg2; minBtn.TextColor3 = CONFIG.AccentBright end)
    minBtn.MouseLeave:Connect(function() minBtn.BackgroundColor3 = CONFIG.Bg2; minBtn.TextColor3 = CONFIG.TextDim end)
    closeBtn.MouseEnter:Connect(function() closeBtn.BackgroundColor3 = CONFIG.AccentDim; closeBtn.TextColor3 = CONFIG.AccentBright end)
    closeBtn.MouseLeave:Connect(function() closeBtn.BackgroundColor3 = CONFIG.Bg2; closeBtn.TextColor3 = CONFIG.TextDim end)

    local drag, dStart, pStart
    header.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            drag = true; dStart = input.Position; pStart = panel.Position
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if drag and (input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch) then
            local d = input.Position - dStart
            local np = UDim2.new(pStart.X.Scale, pStart.X.Offset + d.X,
                                 pStart.Y.Scale, pStart.Y.Offset + d.Y)
            panel.Position = np; bIcon.Position = np
        end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            drag = false
        end
    end)

    guiRefs.gui = gui
end

--=============================================================
-- SUB-PLACE LOADER
--=============================================================
local function populateSubPlaces()
    local holder = guiRefs.subPlaceHolder
    if not holder then return end
    local subs = getSubPlaces()
    if #subs == 0 then
        make("TextLabel", {
            Size = UDim2.new(1, 0, 0, 24),
            BackgroundTransparency = 1,
            Font = Enum.Font.Gotham, TextSize = 11,
            TextColor3 = CONFIG.TextDim,
            Text = "Failed to load sub-places (check console)",
            LayoutOrder = 1, ZIndex = 4,
        }, holder)
        return
    end
    local order = 1
    for _, sub in ipairs(subs) do
        if sub.id == game.PlaceId then continue end
        local name = sub.name or ("Place " .. tostring(sub.id))
        if #name > 24 then name = name:sub(1, 22) .. "..." end
        local row = make("Frame", {
            Size = UDim2.new(1, 0, 0, 26),
            BackgroundColor3 = CONFIG.Bg1,
            BorderSizePixel = 0, LayoutOrder = order,
        }, holder)
        order = order + 1
        make("TextLabel", {
            Size = UDim2.new(1, -70, 1, 0),
            Position = UDim2.new(0, 10, 0, 0),
            BackgroundTransparency = 1,
            Font = Enum.Font.Gotham, TextSize = 12,
            TextColor3 = CONFIG.Text,
            TextXAlignment = Enum.TextXAlignment.Left,
            Text = name, ZIndex = 4,
        }, row)
        local btn = make("TextButton", {
            Size = UDim2.new(0, 56, 0, 20),
            Position = UDim2.new(1, -60, 0, 3),
            BackgroundColor3 = CONFIG.Bg2,
            BorderSizePixel = 0,
            Font = Enum.Font.GothamBold, TextSize = 10,
            TextColor3 = CONFIG.Text,
            Text = "GO",
            AutoButtonColor = false, ZIndex = 5,
        }, row)
        btn.MouseButton1Click:Connect(function()
            teleportToPlace(sub.id)
        end)
    end
end

UserInputService.InputBegan:Connect(function(input, gp)
    if gp then return end
    if input.KeyCode == CONFIG.GuiKey and guiRefs.gui then
        guiRefs.gui.Enabled = not guiRefs.gui.Enabled
    end
end)

--=============================================================
-- FPS / PING OVERLAY
--=============================================================
local function updateFPS(dt)
    if not CONFIG.ShowFPS then
        if fpsText.Visible then fpsText.Visible = false end
        return
    end
    fpsFrames = fpsFrames + 1
    fpsTimeAccum = fpsTimeAccum + dt
    if fpsTimeAccum >= 0.5 then
        fpsValue = math.floor(fpsFrames / fpsTimeAccum)
        fpsFrames = 0
        fpsTimeAccum = 0
        local ping = 0
        pcall(function()
            ping = math.floor(LocalPlayer:GetNetworkPing() * 1000)
        end)
        fpsText.Text = string.format("FPS: %d  |  Ping: %d ms", fpsValue, ping)
    end
    if not fpsText.Visible then fpsText.Visible = true end
end

--=============================================================
-- MAIN LOOPS
--=============================================================
local heavyInterval = 1 / CONFIG.HeavyUpdateHz

RunService.RenderStepped:Connect(function(dt)
    local now = os.clock()
    pcall(renderESP, now)
    pcall(updateFPS, dt)
    heavyAccum = heavyAccum + dt
    if heavyAccum >= heavyInterval then
        heavyAccum = 0
        pcall(updateRadar)
    end
end)

RunService.Heartbeat:Connect(function()
    pcall(applyMovement)
    pcall(applyGravity)
    pcall(updateClimbers)
    pcall(updateBunnyHop)
    pcall(updateHitboxes)
end)

--=============================================================
-- BOOT
--=============================================================
buildGUI()
buildRadar()
initAntiKick()

task.spawn(populateSubPlaces)

notify("Booga Loaded")
print("[Booga] Booga Loaded")
