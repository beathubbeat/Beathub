local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera

local CONFIG = {
    Enabled = true,
    ShowName = true,
    ShowHealth = true,
    ShowTool = true,
    ShowArmor = true,
    ShowAdmins = true,
    ShowTracers = false,
    ShowRadar = true,

    Noclip = false,
    MountainClimber = false,
    WallClimber = false,
    WalkSpeed = 16,

    ShowAimIndicator = true,
    ShowRangeRing    = true,
    ShowTrajectory   = true,
    ShowProjectiles  = true,

    AimLineLength   = 6,
    RangeRingRadius = 50,
    RangeRingSteps  = 24,
    TrajectorySpeed = 90,
    TrajectorySteps = 20,
    TrajectoryDt    = 0.08,

    ProjectileSpeedMin = 55,
    ProjectileMaxLife  = 4,
    ProjectileMaxCount = 25,

    HeavyUpdateHz = 30,
    ToolRefreshHz = 2,

    Accent       = Color3.fromRGB(220, 30, 30),
    AccentBright = Color3.fromRGB(255, 70, 70),
    AccentDim    = Color3.fromRGB(80, 10, 10),
    Bg           = Color3.fromRGB(8, 8, 10),
    Bg1          = Color3.fromRGB(16, 16, 18),
    Bg2          = Color3.fromRGB(24, 24, 28),
    Line         = Color3.fromRGB(50, 50, 55),
    Text         = Color3.fromRGB(230, 230, 230),
    TextDim      = Color3.fromRGB(120, 120, 125),

    NameColor    = Color3.fromRGB(255, 255, 255),
    HealthColor  = Color3.fromRGB(255, 255, 255),
    ToolColor    = Color3.fromRGB(255, 200, 80),
    ArmorColor   = Color3.fromRGB(200, 200, 210),
    AdminColor   = Color3.fromRGB(255, 60, 60),
    AimColor     = Color3.fromRGB(255, 120, 120),
    RangeColor   = Color3.fromRGB(255, 60, 60),
    TrajColor    = Color3.fromRGB(255, 180, 60),
    ProjColor    = Color3.fromRGB(255, 100, 100),

    NameSize   = 11,
    HealthSize = 11,
    ToolSize   = 10,
    ArmorSize  = 10,
    AdminSize  = 11,
    TracerThick = 1,
    AimThick    = 1,

    MaxDistance = 1500,
    RadarSize   = 170,
    RadarRange  = 340,
    GuiKey      = Enum.KeyCode.RightShift,
}

local espData, armorCache, adminCache = {}, {}, {}
local toolCache = {}
local radarDots = {}
local radarState = { center = Vector2.new(0,0), half = 0 }
local guiRefs = {}

local rangeRingLines = {}
local trajDots = {}
local projectiles = {}
local projectileCount = 0
local heavyAccum = 0

local function newText(c, s)
    local t = Drawing.new("Text")
    t.Color, t.Size = c, s
    t.Center, t.Outline = true, true
    t.OutlineColor = Color3.new(0,0,0)
    t.Transparency, t.Visible = 1, false
    return t
end

local function newLine(c, th)
    local l = Drawing.new("Line")
    l.Color, l.Thickness = c, th
    l.Transparency, l.Visible = 0.85, false
    return l
end

local function newSquare(c, s, f)
    local sq = Drawing.new("Square")
    sq.Color, sq.Size, sq.Filled = c, s, f
    sq.Thickness, sq.Transparency, sq.Visible = 1, 1, false
    return sq
end

local function setVisible(obj, v)
    if obj.Visible ~= v then obj.Visible = v end
end

local function setPos(obj, p)
    if obj.Position ~= p then obj.Position = p end
end

local function setText(obj, t)
    if obj.Text ~= t then obj.Text = t end
end

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

local function createESP(player)
    if player == LocalPlayer or espData[player] then return end
    espData[player] = {
        admin   = newText(CONFIG.AdminColor,  CONFIG.AdminSize),
        name    = newText(CONFIG.NameColor,   CONFIG.NameSize),
        health  = newText(CONFIG.HealthColor, CONFIG.HealthSize),
        tool    = newText(CONFIG.ToolColor,   CONFIG.ToolSize),
        armor   = newText(CONFIG.ArmorColor,  CONFIG.ArmorSize),
        tracer  = newLine(CONFIG.Accent,      CONFIG.TracerThick),
        aim     = newLine(CONFIG.AimColor,    CONFIG.AimThick),
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

local function buildRangeRing()
    for i = 1, CONFIG.RangeRingSteps do
        table.insert(rangeRingLines, newLine(CONFIG.RangeColor, 1))
    end
end

local function updateRangeRing()
    if not CONFIG.ShowRangeRing then
        for _, l in ipairs(rangeRingLines) do setVisible(l, false) end
        return
    end
    local char = LocalPlayer.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not root then
        for _, l in ipairs(rangeRingLines) do setVisible(l, false) end
        return
    end
    local center = root.Position
    local n = CONFIG.RangeRingSteps
    local r = CONFIG.RangeRingRadius
    local step = (math.pi * 2) / n
    for i = 1, n do
        local a1 = (i - 1) * step
        local a2 = i * step
        local p1 = center + Vector3.new(math.cos(a1) * r, 0, math.sin(a1) * r)
        local p2 = center + Vector3.new(math.cos(a2) * r, 0, math.sin(a2) * r)
        local s1, o1 = Camera:WorldToViewportPoint(p1)
        local s2, o2 = Camera:WorldToViewportPoint(p2)
        local line = rangeRingLines[i]
        if o1 and o2 then
            line.From = Vector2.new(s1.X, s1.Y)
            line.To   = Vector2.new(s2.X, s2.Y)
            setVisible(line, true)
        else
            setVisible(line, false)
        end
    end
end

local function buildTrajectory()
    for i = 1, CONFIG.TrajectorySteps do
        table.insert(trajDots, newSquare(CONFIG.TrajColor, Vector2.new(4,4), true))
    end
end

local function updateTrajectory()
    if not CONFIG.ShowTrajectory then
        for _, d in ipairs(trajDots) do setVisible(d, false) end
        return
    end
    local char = LocalPlayer.Character
    if not char or not char:FindFirstChildOfClass("Tool") then
        for _, d in ipairs(trajDots) do setVisible(d, false) end
        return
    end
    local vel = Camera.CFrame.LookVector * CONFIG.TrajectorySpeed
    local pos = Camera.CFrame.Position
    local dt = CONFIG.TrajectoryDt
    local g = workspace.Gravity
    local active = 0
    for i = 1, CONFIG.TrajectorySteps do
        vel = Vector3.new(vel.X, vel.Y - g * dt, vel.Z)
        pos = pos + vel * dt
        local sc, on = Camera:WorldToViewportPoint(pos)
        local dot = trajDots[i]
        if on then
            setPos(dot, Vector2.new(sc.X - 2, sc.Y - 2))
            setVisible(dot, true)
            active = i
        else
            setVisible(dot, false)
        end
        if pos.Y < -100 then break end
    end
    for i = active + 1, CONFIG.TrajectorySteps do
        setVisible(trajDots[i], false)
    end
end

local function isProjectileCandidate(part)
    if not part:IsA("BasePart") then return false end
    if part.Anchored then return false end
    local model = part:FindFirstAncestorOfClass("Model")
    if model and Players:GetPlayerFromCharacter(model) then return false end
    if part.AssemblyLinearVelocity.Magnitude < CONFIG.ProjectileSpeedMin then return false end
    return true
end

local function trackProjectile(part)
    if projectileCount >= CONFIG.ProjectileMaxCount then return end
    if projectiles[part] then return end
    projectiles[part] = {
        square = newSquare(CONFIG.ProjColor, Vector2.new(6,6), true),
        born   = tick(),
    }
    projectileCount = projectileCount + 1
end

local function untrackProjectile(part)
    local rec = projectiles[part]
    if not rec then return end
    rec.square:Remove()
    projectiles[part] = nil
    projectileCount = projectileCount - 1
end

workspace.DescendantAdded:Connect(function(inst)
    if not CONFIG.ShowProjectiles then return end
    if not inst:IsA("BasePart") then return end
    task.defer(function()
        if not inst.Parent then return end
        if isProjectileCandidate(inst) then
            trackProjectile(inst)
        end
    end)
end)

local function updateProjectiles()
    if not CONFIG.ShowProjectiles then
        for part in pairs(projectiles) do untrackProjectile(part) end
        return
    end
    local now = tick()
    for part, p in pairs(projectiles) do
        if not part.Parent or now - p.born > CONFIG.ProjectileMaxLife then
            untrackProjectile(part)
        else
            local sc, on = Camera:WorldToViewportPoint(part.Position)
            if on then
                setPos(p.square, Vector2.new(sc.X - 3, sc.Y - 3))
                setVisible(p.square, true)
            else
                setVisible(p.square, false)
            end
        end
    end
end

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

local function applyMovement()
    local char = LocalPlayer.Character
    if not char then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum then return end
    if CONFIG.WalkSpeed ~= 16 and hum.WalkSpeed ~= CONFIG.WalkSpeed then
        hum.WalkSpeed = CONFIG.WalkSpeed
    end
    if CONFIG.Noclip then
        for _, d in ipairs(char:GetDescendants()) do
            if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" and d.CanCollide then
                d.CanCollide = false
            end
        end
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

local function tracerOrigin()
    local vp = Camera.ViewportSize
    return Vector2.new(vp.X * 0.5, vp.Y + 5)
end

local function renderESP(now)
    if not CONFIG.Enabled then
        for _, d in pairs(espData) do
            setVisible(d.admin, false)
            setVisible(d.name, false)
            setVisible(d.health, false)
            setVisible(d.tool, false)
            setVisible(d.armor, false)
            setVisible(d.tracer, false)
            setVisible(d.aim, false)
        end
        return
    end

    local camPos = Camera.CFrame.Position
    local origin = tracerOrigin()

    for player, data in pairs(espData) do
        local char = player.Character
        local hum  = char and char:FindFirstChildOfClass("Humanoid")
        local head = char and char:FindFirstChild("Head")
        local root = char and char:FindFirstChild("HumanoidRootPart")

        local alive = char and hum and head and root and hum.Health > 0
        local inRange = alive and (camPos - root.Position).Magnitude <= CONFIG.MaxDistance

        if not inRange then
            setVisible(data.admin, false)
            setVisible(data.name, false)
            setVisible(data.health, false)
            setVisible(data.tool, false)
            setVisible(data.armor, false)
            setVisible(data.tracer, false)
            setVisible(data.aim, false)
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
            setVisible(data.tracer, false)
            setVisible(data.aim, false)
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
            setText(data.name, player.Name)
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

        if CONFIG.ShowTracers then
            data.tracer.From = origin
            data.tracer.To = pos + Vector2.new(0, -6)
            setVisible(data.tracer, true)
        else setVisible(data.tracer, false) end

        if CONFIG.ShowAimIndicator then
            local hp3 = head.Position
            local le  = hp3 + head.CFrame.LookVector * CONFIG.AimLineLength
            local s1, o1 = Camera:WorldToViewportPoint(hp3)
            local s2, o2 = Camera:WorldToViewportPoint(le)
            if o1 and o2 then
                data.aim.From = Vector2.new(s1.X, s1.Y)
                data.aim.To   = Vector2.new(s2.X, s2.Y)
                setVisible(data.aim, true)
            else setVisible(data.aim, false) end
        else setVisible(data.aim, false) end
    end
end

for _, p in ipairs(Players:GetPlayers()) do
    createESP(p); ensureRadarDot(p)
end

Players.PlayerAdded:Connect(function(p)
    createESP(p); ensureRadarDot(p)
    p.CharacterAdded:Connect(function()
        armorCache[p] = nil
        adminCache[p] = nil
        toolCache[p]  = nil
    end)
end)

Players.PlayerRemoving:Connect(function(p)
    removeESP(p)
    local d = radarDots[p]
    if d then d.dot:Remove(); d.dir:Remove(); radarDots[p] = nil end
end)

local function make(class, props, parent)
    local i = Instance.new(class)
    for k, v in pairs(props or {}) do i[k] = v end
    if parent then i.Parent = parent end
    return i
end

local function buildGUI()
    local gui = make("ScreenGui", {
        Name = "BeatHub",
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
        Color = CONFIG.Accent,
        Thickness = 1,
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
        Text = "BeatHub",
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
        Text = "made by Beat",
        ZIndex = 5,
    }, header)

    local minBtn = make("TextButton", {
        Size = UDim2.new(0, 24, 0, 24),
        Position = UDim2.new(1, -52, 0, 8),
        BackgroundColor3 = CONFIG.Bg2,
        BorderSizePixel = 0,
        Font = Enum.Font.Code,
        TextSize = 14,
        TextColor3 = CONFIG.TextDim,
        Text = "-",
        AutoButtonColor = false,
        ZIndex = 5,
    }, header)
    local closeBtn = make("TextButton", {
        Size = UDim2.new(0, 24, 0, 24),
        Position = UDim2.new(1, -26, 0, 8),
        BackgroundColor3 = CONFIG.Bg2,
        BorderSizePixel = 0,
        Font = Enum.Font.Code,
        TextSize = 14,
        TextColor3 = CONFIG.TextDim,
        Text = "X",
        AutoButtonColor = false,
        ZIndex = 5,
    }, header)

    local tabBar = make("Frame", {
        Size = UDim2.new(1, -20, 0, 24),
        Position = UDim2.new(0, 10, 0, 48),
        BackgroundTransparency = 1,
        ZIndex = 3,
    }, panel)
    make("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        Padding = UDim.new(0, 6),
    }, tabBar)

    local pageHolder = make("Frame", {
        Size = UDim2.new(1, -20, 1, -86),
        Position = UDim2.new(0, 10, 0, 78),
        BackgroundTransparency = 1,
        ZIndex = 3,
    }, panel)

    local function makePage()
        local page = make("Frame", {
            Size = UDim2.new(1, 0, 1, 0),
            BackgroundTransparency = 1,
            Visible = false,
            ZIndex = 3,
        }, pageHolder)
        make("UIListLayout", {
            Padding = UDim.new(0, 3),
            SortOrder = Enum.SortOrder.LayoutOrder,
        }, page)
        return page
    end

    local espPage  = makePage()
    local movePage = makePage()
    local aimPage  = makePage()
    local miscPage = makePage()
    local pages = { espPage, movePage, aimPage, miscPage }
    local tabs  = {}

    local function makeTab(label, order, page, defaultOn)
        local btn = make("TextButton", {
            Size = UDim2.new(0, 50, 1, 0),
            BackgroundColor3 = defaultOn and CONFIG.AccentDim or CONFIG.Bg1,
            BorderSizePixel = 0,
            Font = Enum.Font.GothamBold,
            TextSize = 11,
            TextColor3 = defaultOn and CONFIG.AccentBright or CONFIG.TextDim,
            Text = label,
            AutoButtonColor = false,
            LayoutOrder = order,
            ZIndex = 4,
        }, tabBar)
        tabs[page] = btn
        btn.MouseButton1Click:Connect(function()
            for p, b in pairs(tabs) do
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

    makeTab("ESP",  1, espPage,  true)
    makeTab("MOVE", 2, movePage, false)
    makeTab("AIM",  3, aimPage,  false)
    makeTab("MISC", 4, miscPage, false)

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
            Font = Enum.Font.Gotham,
            TextSize = 12,
            TextColor3 = CONFIG.Text,
            TextXAlignment = Enum.TextXAlignment.Left,
            Text = label,
            ZIndex = 4,
        }, row)

        local status = make("TextLabel", {
            Size = UDim2.new(0, 36, 1, 0),
            Position = UDim2.new(1, -40, 0, 0),
            BackgroundTransparency = 1,
            Font = Enum.Font.Code,
            TextSize = 11,
            TextColor3 = getter() and CONFIG.AccentBright or CONFIG.TextDim,
            TextXAlignment = Enum.TextXAlignment.Right,
            Text = getter() and "ON" or "OFF",
            ZIndex = 4,
        }, row)

        local btn = make("TextButton", {
            Size = UDim2.new(1, 0, 1, 0),
            BackgroundTransparency = 1,
            Text = "",
            AutoButtonColor = false,
            ZIndex = 6,
        }, row)

        btn.MouseButton1Click:Connect(function()
            setter(not getter())
            local on = getter()
            bar.BackgroundColor3 = on and CONFIG.Accent or CONFIG.Bg2
            status.Text = on and "ON" or "OFF"
            status.TextColor3 = on and CONFIG.AccentBright or CONFIG.TextDim
        end)
        btn.MouseEnter:Connect(function() row.BackgroundColor3 = CONFIG.Bg2 end)
        btn.MouseLeave:Connect(function() row.BackgroundColor3 = CONFIG.Bg1 end)
    end

    makeRow(espPage, "Enable ESP", 1, function() return CONFIG.Enabled    end, function(v) CONFIG.Enabled = v    end)
    makeRow(espPage, "Username",   2, function() return CONFIG.ShowName   end, function(v) CONFIG.ShowName = v   end)
    makeRow(espPage, "Health",     3, function() return CONFIG.ShowHealth end, function(v) CONFIG.ShowHealth = v end)
    makeRow(espPage, "Tool",       4, function() return CONFIG.ShowTool   end, function(v) CONFIG.ShowTool = v   end)
    makeRow(espPage, "Armor",      5, function() return CONFIG.ShowArmor  end, function(v) CONFIG.ShowArmor = v  end)

    makeRow(movePage, "Noclip",           1, function() return CONFIG.Noclip          end, function(v) CONFIG.Noclip = v          end)
    makeRow(movePage, "Mountain Climber", 2, function() return CONFIG.MountainClimber end, function(v) CONFIG.MountainClimber = v end)
    makeRow(movePage, "Wall Climber",     3, function() return CONFIG.WallClimber     end, function(v) CONFIG.WallClimber = v     end)

    local wsRow = make("Frame", {
        Size = UDim2.new(1, 0, 0, 26),
        BackgroundColor3 = CONFIG.Bg1,
        BorderSizePixel = 0,
        LayoutOrder = 4,
    }, movePage)
    make("TextLabel", {
        Size = UDim2.new(1, -110, 1, 0),
        Position = UDim2.new(0, 12, 0, 0),
        BackgroundTransparency = 1,
        Font = Enum.Font.Gotham,
        TextSize = 12,
        TextColor3 = CONFIG.Text,
        TextXAlignment = Enum.TextXAlignment.Left,
        Text = "WalkSpeed",
        ZIndex = 4,
    }, wsRow)
    local wsLabel = make("TextLabel", {
        Size = UDim2.new(0, 40, 1, 0),
        Position = UDim2.new(1, -94, 0, 0),
        BackgroundTransparency = 1,
        Font = Enum.Font.Code,
        TextSize = 12,
        TextColor3 = CONFIG.AccentBright,
        Text = tostring(CONFIG.WalkSpeed),
        ZIndex = 4,
    }, wsRow)
    local minusBtn = make("TextButton", {
        Size = UDim2.new(0, 22, 0, 20),
        Position = UDim2.new(1, -48, 0, 3),
        BackgroundColor3 = CONFIG.Bg2,
        BorderSizePixel = 0,
        Font = Enum.Font.Code,
        TextSize = 14,
        TextColor3 = CONFIG.Text,
        Text = "-",
        AutoButtonColor = false,
        ZIndex = 5,
    }, wsRow)
    local plusBtn = make("TextButton", {
        Size = UDim2.new(0, 22, 0, 20),
        Position = UDim2.new(1, -24, 0, 3),
        BackgroundColor3 = CONFIG.Bg2,
        BorderSizePixel = 0,
        Font = Enum.Font.Code,
        TextSize = 14,
        TextColor3 = CONFIG.Text,
        Text = "+",
        AutoButtonColor = false,
        ZIndex = 5,
    }, wsRow)
    minusBtn.MouseButton1Click:Connect(function()
        CONFIG.WalkSpeed = math.max(16, CONFIG.WalkSpeed - 4)
        wsLabel.Text = tostring(CONFIG.WalkSpeed)
    end)
    plusBtn.MouseButton1Click:Connect(function()
        CONFIG.WalkSpeed = math.min(500, CONFIG.WalkSpeed + 4)
        wsLabel.Text = tostring(CONFIG.WalkSpeed)
    end)

    makeRow(aimPage, "Aim Indicator",  1, function() return CONFIG.ShowAimIndicator end, function(v) CONFIG.ShowAimIndicator = v end)
    makeRow(aimPage, "Range Ring",     2, function() return CONFIG.ShowRangeRing    end, function(v) CONFIG.ShowRangeRing = v    end)
    makeRow(aimPage, "Trajectory Arc", 3, function() return CONFIG.ShowTrajectory   end, function(v) CONFIG.ShowTrajectory = v   end)
    makeRow(aimPage, "Projectile ESP", 4, function() return CONFIG.ShowProjectiles  end, function(v) CONFIG.ShowProjectiles = v  end)

    makeRow(miscPage, "Admin Alert", 1, function() return CONFIG.ShowAdmins  end, function(v) CONFIG.ShowAdmins = v  end)
    makeRow(miscPage, "Tracers",     2, function() return CONFIG.ShowTracers end, function(v) CONFIG.ShowTracers = v end)
    makeRow(miscPage, "Radar",       3, function() return CONFIG.ShowRadar   end, function(v) CONFIG.ShowRadar = v   end)

    local bIcon = make("TextButton", {
        Size = UDim2.new(0, 34, 0, 34),
        Position = UDim2.new(0, LEFT_X, 0, TOP_Y),
        BackgroundColor3 = CONFIG.Bg,
        BorderSizePixel = 0,
        Font = Enum.Font.GothamBold,
        TextSize = 16,
        TextColor3 = CONFIG.AccentBright,
        Text = "S",
        AutoButtonColor = false,
        Visible = false,
        ZIndex = 10,
    }, gui)
    make("UIStroke", {
        Color = CONFIG.Accent,
        Thickness = 1,
    }, bIcon)

    minBtn.MouseButton1Click:Connect(function() panel.Visible = false; bIcon.Visible = true end)
    bIcon.MouseButton1Click:Connect(function() panel.Visible = true; bIcon.Visible = false end)
    closeBtn.MouseButton1Click:Connect(function() gui.Enabled = false end)

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

UserInputService.InputBegan:Connect(function(input, gp)
    if gp then return end
    if input.KeyCode == CONFIG.GuiKey and guiRefs.gui then
        guiRefs.gui.Enabled = not guiRefs.gui.Enabled
    end
end)

local heavyInterval = 1 / CONFIG.HeavyUpdateHz

RunService.RenderStepped:Connect(function(dt)
    local now = os.clock()
    pcall(renderESP, now)
    heavyAccum = heavyAccum + dt
    if heavyAccum >= heavyInterval then
        heavyAccum = 0
        pcall(updateRadar)
        pcall(updateRangeRing)
        pcall(updateTrajectory)
        pcall(updateProjectiles)
    end
end)

RunService.Heartbeat:Connect(function()
    pcall(applyMovement)
    pcall(updateClimbers)
end)

buildRangeRing()
buildTrajectory()
buildGUI()
buildRadar()
print("[ BeatHub] Loaded — Right Shift toggles the menu.")
