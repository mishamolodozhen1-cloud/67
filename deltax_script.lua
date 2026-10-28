-- ============================================================
--  DELTA X  |  v1.0  |  Fling · Fly · SpeedHack
--  Lua 5.1 — Roblox executor (Delta X / synapse-compatible)
-- ============================================================

local Players      = game:GetService("Players")
local RunService   = game:GetService("RunService")
local UIS          = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local LP  = Players.LocalPlayer
local PG  = LP:WaitForChild("PlayerGui")

-- ── Helpers ─────────────────────────────────────────────────

local function Char()  return LP.Character end
local function Root()  local c = Char() return c and c:FindFirstChild("HumanoidRootPart") end
local function Hum()   local c = Char() return c and c:FindFirstChildOfClass("Humanoid")  end

local Mobile = UIS.TouchEnabled and not UIS.KeyboardEnabled

local function tw(obj, props, t, sty, dir)
    TweenService:Create(obj,
        TweenInfo.new(t or 0.25,
            sty or Enum.EasingStyle.Quart,
            dir or Enum.EasingDirection.Out),
        props):Play()
end

local function inst(cls, parent, props)
    local i = Instance.new(cls)
    if props then for k, v in pairs(props) do i[k] = v end end
    if parent then i.Parent = parent end
    return i
end

-- ── State ────────────────────────────────────────────────────

local S = {
    target  = nil,    -- Player selected for fling
    fly     = false,
    spd     = false,
    flySpd  = 60,
    walkSpd = 60,
    flyBV   = nil,
    flyBG   = nil,
    flyLp   = nil,
    spdLp   = nil,
    mobUp   = false,
    mobDn   = false,
}

local flyKeys = { up=false, dn=false, fw=false, bk=false, lt=false, rt=false }
local flyConns = {}

-- ════════════════════════════════════════════════════════════
--  FLING
-- ════════════════════════════════════════════════════════════

local function Fling(player)
    local r = Root()
    if not r then return end

    local tc = player and player.Character
    if not tc then return end

    local tr = tc:FindFirstChild("HumanoidRootPart")
    if not tr then return end

    -- Record target's standing position; we'll land here after fling
    local targetPos = tr.CFrame

    -- Teleport onto target so physics collision transfers our force to them
    r.CFrame = tr.CFrame

    -- Massive angular + downward linear velocity on ourselves
    -- Roblox physics propagates this through the collision contact
    local bav = Instance.new("BodyAngularVelocity")
    bav.AngularVelocity = Vector3.new(9e8, 9e8, 9e8)
    bav.MaxTorque       = Vector3.new(9e8, 9e8, 9e8)
    bav.Parent          = r

    local bv = Instance.new("BodyVelocity")
    bv.Velocity  = Vector3.new(0, -9e4, 0)
    bv.MaxForce  = Vector3.new(9e8, 9e8, 9e8)
    bv.Parent    = r

    -- Also push target directly (executor-level; pcall so silent-fail on
    -- games that lock foreign HRPs — collision method above still works)
    pcall(function()
        local tbv      = Instance.new("BodyVelocity")
        tbv.Name       = "__dx_fv"
        tbv.Velocity   = Vector3.new(math.random(-300,300), -9e4, math.random(-300,300))
        tbv.MaxForce   = Vector3.new(9e8, 9e8, 9e8)
        tbv.Parent     = tr

        -- Hold them under the map for 30 seconds
        local elapsed = 0
        local lp
        lp = RunService.Heartbeat:Connect(function(dt)
            elapsed = elapsed + dt
            if elapsed >= 30 or not tr.Parent then
                lp:Disconnect()
                pcall(function() tbv:Destroy() end)
                return
            end
            -- Caught trying to surface? Push back down.
            if tr.Position.Y > -50 then
                tbv.Velocity = Vector3.new(
                    math.random(-200, 200), -9e4, math.random(-200, 200))
            end
        end)
    end)

    -- Clean up our movers, then teleport to where target stood
    task.delay(0.15, function()
        pcall(function() bav:Destroy() end)
        pcall(function() bv:Destroy()  end)
        local r2 = Root()
        if r2 then r2.CFrame = targetPos end
    end)
end

-- ════════════════════════════════════════════════════════════
--  FLY
-- ════════════════════════════════════════════════════════════

local function FlyClean()
    pcall(function() if S.flyBV then S.flyBV:Destroy() end end)
    pcall(function() if S.flyBG then S.flyBG:Destroy() end end)
    if S.flyLp then S.flyLp:Disconnect(); S.flyLp = nil end
    for _, c in ipairs(flyConns) do c:Disconnect() end
    flyConns = {}
    for k in pairs(flyKeys) do flyKeys[k] = false end
    local h = Hum(); if h then h.PlatformStand = false end
end

local function FlyOn()
    FlyClean()
    S.fly = true

    local r = Root(); if not r then return end

    S.flyBV          = Instance.new("BodyVelocity")
    S.flyBV.Velocity  = Vector3.new(0, 0, 0)
    S.flyBV.MaxForce  = Vector3.new(9e8, 9e8, 9e8)
    S.flyBV.P         = 10000
    S.flyBV.Parent    = r

    S.flyBG           = Instance.new("BodyGyro")
    S.flyBG.D         = 500
    S.flyBG.P         = 50000
    S.flyBG.MaxTorque = Vector3.new(9e8, 9e8, 9e8)
    S.flyBG.CFrame    = r.CFrame
    S.flyBG.Parent    = r

    -- PC keyboard bindings
    flyConns[#flyConns+1] = UIS.InputBegan:Connect(function(inp, gp)
        if gp then return end
        local k = inp.KeyCode
        if k == Enum.KeyCode.Space        then flyKeys.up = true end
        if k == Enum.KeyCode.LeftControl  then flyKeys.dn = true end
        if k == Enum.KeyCode.W            then flyKeys.fw = true end
        if k == Enum.KeyCode.S            then flyKeys.bk = true end
        if k == Enum.KeyCode.A            then flyKeys.lt = true end
        if k == Enum.KeyCode.D            then flyKeys.rt = true end
    end)
    flyConns[#flyConns+1] = UIS.InputEnded:Connect(function(inp, gp)
        if gp then return end
        local k = inp.KeyCode
        if k == Enum.KeyCode.Space        then flyKeys.up = false end
        if k == Enum.KeyCode.LeftControl  then flyKeys.dn = false end
        if k == Enum.KeyCode.W            then flyKeys.fw = false end
        if k == Enum.KeyCode.S            then flyKeys.bk = false end
        if k == Enum.KeyCode.A            then flyKeys.lt = false end
        if k == Enum.KeyCode.D            then flyKeys.rt = false end
    end)

    S.flyLp = RunService.Heartbeat:Connect(function()
        if not S.fly then FlyClean(); return end
        local r2 = Root(); if not r2 then return end

        -- BYPASS: recreate BodyVelocity / BodyGyro every frame if anti-cheat
        -- removes them. O(1) check — no allocation unless they're gone.
        if not S.flyBV or not S.flyBV.Parent then
            S.flyBV          = Instance.new("BodyVelocity")
            S.flyBV.MaxForce  = Vector3.new(9e8, 9e8, 9e8)
            S.flyBV.P         = 10000
            S.flyBV.Parent    = r2
        end
        if not S.flyBG or not S.flyBG.Parent then
            S.flyBG           = Instance.new("BodyGyro")
            S.flyBG.D         = 500
            S.flyBG.P         = 50000
            S.flyBG.MaxTorque = Vector3.new(9e8, 9e8, 9e8)
            S.flyBG.Parent    = r2
        end

        -- PlatformStand bypass (some ACs reset this each frame)
        local h = Hum(); if h then h.PlatformStand = true end

        local cam = workspace.CurrentCamera
        local spd = S.flySpd
        local vel = Vector3.new(0, 0, 0)
        local lv  = cam.CFrame.LookVector
        local rv  = cam.CFrame.RightVector

        -- PC movement
        if flyKeys.fw then vel = vel + lv * spd end
        if flyKeys.bk then vel = vel - lv * spd end
        if flyKeys.rt then vel = vel + rv * spd end
        if flyKeys.lt then vel = vel - rv * spd end
        if flyKeys.up or S.mobUp then vel = vel + Vector3.new(0, spd, 0) end
        if flyKeys.dn or S.mobDn then vel = vel - Vector3.new(0, spd, 0) end

        -- Mobile: read Humanoid.MoveDirection from the thumbstick
        if h then
            local md = h.MoveDirection
            if md.Magnitude > 0.1 then
                local fl = Vector3.new(lv.X, 0, lv.Z).Unit
                local fr = Vector3.new(rv.X, 0, rv.Z).Unit
                vel = vel + fl * (-md.Z) * spd
                vel = vel + fr *   md.X  * spd
            end
        end

        S.flyBV.Velocity = vel
        S.flyBG.CFrame   = cam.CFrame
    end)
end

local function FlyOff()
    S.fly = false
    FlyClean()
end

-- ════════════════════════════════════════════════════════════
--  SPEEDHACK
-- ════════════════════════════════════════════════════════════

local function SpdOn()
    S.spd = true
    if S.spdLp then S.spdLp:Disconnect() end
    S.spdLp = RunService.Heartbeat:Connect(function()
        if not S.spd then S.spdLp:Disconnect(); return end
        local h = Hum()
        -- Re-assert every frame; many games reset WalkSpeed server-side
        if h and h.WalkSpeed ~= S.walkSpd then
            h.WalkSpeed = S.walkSpd
        end
    end)
end

local function SpdOff()
    S.spd = false
    if S.spdLp then S.spdLp:Disconnect() end
    local h = Hum(); if h then h.WalkSpeed = 16 end
end

-- ════════════════════════════════════════════════════════════
--  UI
-- ════════════════════════════════════════════════════════════

local old = PG:FindFirstChild("DeltaXGui")
if old then old:Destroy() end

-- ── Theme ──

local T = {
    bg      = Color3.fromRGB(13,  13,  20),
    surf    = Color3.fromRGB(22,  22,  34),
    surf2   = Color3.fromRGB(32,  32,  48),
    surf3   = Color3.fromRGB(42,  42,  60),
    accent  = Color3.fromRGB(88,  138, 210),
    accentD = Color3.fromRGB(58,  100, 170),
    text    = Color3.fromRGB(215, 218, 228),
    muted   = Color3.fromRGB(118, 124, 148),
    green   = Color3.fromRGB(68,  185, 118),
    border  = Color3.fromRGB(44,  44,  64),
}

local W    = Mobile and 320 or 285   -- window width
local BH   = Mobile and 46  or 36   -- standard button height
local TH   = 44                     -- title bar height
local TabH = 38                     -- tab bar height
local P    = 12                     -- base padding
local ConY = TH + TabH              -- content area start Y offset

-- ── Root GUI ──

local sg = inst("ScreenGui", PG, {
    Name            = "DeltaXGui",
    ResetOnSpawn    = false,
    ZIndexBehavior  = Enum.ZIndexBehavior.Sibling,
    DisplayOrder    = 99,
})

-- ── Main window ──

local main = inst("Frame", sg, {
    Name             = "Main",
    Size             = UDim2.new(0, W, 0, 300),
    Position         = UDim2.new(0.5, -W/2, 0.12, 0),
    BackgroundColor3 = T.bg,
    BorderSizePixel  = 0,
    ClipsDescendants = true,
})
inst("UICorner", main, { CornerRadius = UDim.new(0, 12) })
inst("UIStroke", main, { Color = T.border, Thickness = 1 })

-- ── Header ──

local hdr = inst("Frame", main, {
    Name             = "Header",
    Size             = UDim2.new(1, 0, 0, TH),
    BackgroundColor3 = T.surf,
    BorderSizePixel  = 0,
})
inst("UICorner", hdr, { CornerRadius = UDim.new(0, 12) })
-- fill bottom so only the top edges round
inst("Frame", hdr, {
    Size             = UDim2.new(1, 0, 0, 12),
    Position         = UDim2.new(0, 0, 1, -12),
    BackgroundColor3 = T.surf,
    BorderSizePixel  = 0,
})

-- accent dot
local dot = inst("Frame", hdr, {
    Size             = UDim2.new(0, 8, 0, 8),
    Position         = UDim2.new(0, 14, 0.5, -4),
    BackgroundColor3 = T.accent,
    BorderSizePixel  = 0,
})
inst("UICorner", dot, { CornerRadius = UDim.new(1, 0) })

inst("TextLabel", hdr, {
    Size                   = UDim2.new(1, -80, 1, 0),
    Position               = UDim2.new(0, 30, 0, 0),
    BackgroundTransparency = 1,
    Text                   = "DELTA  X",
    TextColor3             = T.text,
    Font                   = Enum.Font.GothamBold,
    TextSize               = 15,
    TextXAlignment         = Enum.TextXAlignment.Left,
})

local minBtn = inst("TextButton", hdr, {
    Size             = UDim2.new(0, 28, 0, 28),
    Position         = UDim2.new(1, -36, 0.5, -14),
    BackgroundColor3 = T.surf2,
    Text             = "─",
    TextColor3       = T.muted,
    Font             = Enum.Font.GothamBold,
    TextSize         = 13,
    BorderSizePixel  = 0,
})
inst("UICorner", minBtn, { CornerRadius = UDim.new(0, 6) })

-- ── Drag ──

do
    local drag, ds, sp = false, nil, nil
    hdr.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1
        or i.UserInputType == Enum.UserInputType.Touch then
            drag = true; ds = i.Position; sp = main.Position
        end
    end)
    hdr.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1
        or i.UserInputType == Enum.UserInputType.Touch then
            drag = false
        end
    end)
    UIS.InputChanged:Connect(function(i)
        if drag and (i.UserInputType == Enum.UserInputType.MouseMovement
                  or i.UserInputType == Enum.UserInputType.Touch) then
            local d = i.Position - ds
            main.Position = UDim2.new(
                sp.X.Scale, sp.X.Offset + d.X,
                sp.Y.Scale, sp.Y.Offset + d.Y)
        end
    end)
end

-- ── Tab bar ──

local tabBar = inst("Frame", main, {
    Size             = UDim2.new(1, 0, 0, TabH),
    Position         = UDim2.new(0, 0, 0, TH),
    BackgroundColor3 = T.surf,
    BorderSizePixel  = 0,
})
inst("Frame", tabBar, {  -- patch bottom
    Size             = UDim2.new(1, 0, 0, 8),
    Position         = UDim2.new(0, 0, 1, -8),
    BackgroundColor3 = T.surf,
    BorderSizePixel  = 0,
})
inst("UIListLayout", tabBar, {
    FillDirection = Enum.FillDirection.Horizontal,
    SortOrder     = Enum.SortOrder.LayoutOrder,
    Padding       = UDim.new(0, 0),
})

local tabNames = { "Fling", "Fly", "Speed" }
local tabBtns  = {}
local tabInds  = {}

for i, name in ipairs(tabNames) do
    local active = i == 1
    local btn = inst("TextButton", tabBar, {
        Size                   = UDim2.new(1/#tabNames, 0, 1, 0),
        BackgroundTransparency = 1,
        Text                   = name,
        TextColor3             = active and T.text or T.muted,
        Font                   = active and Enum.Font.GothamBold or Enum.Font.Gotham,
        TextSize               = 13,
        BorderSizePixel        = 0,
        LayoutOrder            = i,
    })
    local ind = inst("Frame", btn, {
        Size             = UDim2.new(active and 0.65 or 0, 0, 0, 2),
        Position         = UDim2.new(0.175, 0, 1, -2),
        BackgroundColor3 = T.accent,
        BorderSizePixel  = 0,
    })
    inst("UICorner", ind, { CornerRadius = UDim.new(1, 0) })
    tabBtns[i] = btn
    tabInds[i]  = ind
end

-- ── Content container ──

local contentF = inst("Frame", main, {
    Name                   = "Content",
    Size                   = UDim2.new(1, 0, 0, 260),
    Position               = UDim2.new(0, 0, 0, ConY),
    BackgroundTransparency = 1,
    ClipsDescendants       = true,
})

local pages = {}
local pageH = {}   -- height of each tab's content

-- ── UI component helpers ──

local function card(parent, yOff, h)
    local f = inst("Frame", parent, {
        Size             = UDim2.new(1, -P*2, 0, h),
        Position         = UDim2.new(0, P, 0, yOff),
        BackgroundColor3 = T.surf,
        BorderSizePixel  = 0,
    })
    inst("UICorner", f, { CornerRadius = UDim.new(0, 10) })
    inst("UIStroke",  f, { Color = T.border, Thickness = 1 })
    return f
end

local function lbl(parent, text, sz, color, font, x, y, wS, h)
    return inst("TextLabel", parent, {
        Size                   = UDim2.new(wS, 0, 0, h),
        Position               = UDim2.new(0, x, 0, y),
        BackgroundTransparency = 1,
        Text                   = text,
        TextColor3             = color,
        Font                   = font or Enum.Font.Gotham,
        TextSize               = sz,
        TextXAlignment         = Enum.TextXAlignment.Left,
    })
end

local function toggle(parent, label, yOff, init, cb)
    local c = card(parent, yOff, BH + P * 2)
    lbl(c, label, 13, T.text, Enum.Font.GothamBold, P, (BH + P*2)/2 - 8, 0.65, 16)

    local trk = inst("Frame", c, {
        Size             = UDim2.new(0, 46, 0, 25),
        Position         = UDim2.new(1, -46 - P, 0.5, -12),
        BackgroundColor3 = init and T.green or T.surf3,
        BorderSizePixel  = 0,
    })
    inst("UICorner", trk, { CornerRadius = UDim.new(1, 0) })

    local knob = inst("Frame", trk, {
        Size             = UDim2.new(0, 19, 0, 19),
        Position         = UDim2.new(0, init and 24 or 3, 0.5, -9),
        BackgroundColor3 = Color3.new(1, 1, 1),
        BorderSizePixel  = 0,
    })
    inst("UICorner", knob, { CornerRadius = UDim.new(1, 0) })

    local state = init
    local clk = inst("TextButton", trk, {
        Size                   = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
        Text                   = "",
    })
    clk.MouseButton1Click:Connect(function()
        state = not state
        tw(trk,  { BackgroundColor3 = state and T.green or T.surf3 }, 0.2)
        tw(knob, { Position = UDim2.new(0, state and 24 or 3, 0.5, -9) },
            0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
        cb(state)
    end)
    return c
end

local function slider(parent, label, yOff, mn, mx, init, fmt, cb)
    local h = Mobile and 72 or 64
    local c = card(parent, yOff, h)

    lbl(c, label, 11, T.muted, Enum.Font.GothamBold, P, 9, 0.6, 14)

    local vl = inst("TextLabel", c, {
        Size                   = UDim2.new(0.4, -P, 0, 14),
        Position               = UDim2.new(0.6, 0, 0, 9),
        BackgroundTransparency = 1,
        Text                   = string.format(fmt, init),
        TextColor3             = T.accent,
        Font                   = Enum.Font.GothamBold,
        TextSize               = 12,
        TextXAlignment         = Enum.TextXAlignment.Right,
    })

    local trk = inst("Frame", c, {
        Size             = UDim2.new(1, -P*2, 0, 5),
        Position         = UDim2.new(0, P, 0.5, 10),
        BackgroundColor3 = T.surf3,
        BorderSizePixel  = 0,
    })
    inst("UICorner", trk, { CornerRadius = UDim.new(1, 0) })

    local pct  = (init - mn) / (mx - mn)
    local fill = inst("Frame", trk, {
        Size             = UDim2.new(pct, 0, 1, 0),
        BackgroundColor3 = T.accent,
        BorderSizePixel  = 0,
    })
    inst("UICorner", fill, { CornerRadius = UDim.new(1, 0) })

    local kSz  = Mobile and 22 or 16
    local knob = inst("Frame", trk, {
        Size             = UDim2.new(0, kSz, 0, kSz),
        Position         = UDim2.new(pct, -kSz/2, 0.5, -kSz/2),
        BackgroundColor3 = T.text,
        BorderSizePixel  = 0,
    })
    inst("UICorner", knob, { CornerRadius = UDim.new(1, 0) })
    inst("UIStroke",  knob, { Color = T.accent, Thickness = 2 })

    local dragging = false
    local function update(absX)
        local ap  = trk.AbsolutePosition
        local as  = trk.AbsoluteSize
        local pct2 = math.clamp((absX - ap.X) / as.X, 0, 1)
        local val  = math.floor(mn + (mx - mn) * pct2)
        fill.Size     = UDim2.new(pct2, 0, 1, 0)
        knob.Position = UDim2.new(pct2, -kSz/2, 0.5, -kSz/2)
        vl.Text       = string.format(fmt, val)
        cb(val)
    end
    trk.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1
        or i.UserInputType == Enum.UserInputType.Touch then
            dragging = true; update(i.Position.X)
        end
    end)
    UIS.InputChanged:Connect(function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement
                      or i.UserInputType == Enum.UserInputType.Touch) then
            update(i.Position.X)
        end
    end)
    UIS.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1
        or i.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
    return c, h
end

local function actionBtn(parent, text, yOff, color, cb)
    local btn = inst("TextButton", parent, {
        Size             = UDim2.new(1, -P*2, 0, BH),
        Position         = UDim2.new(0, P, 0, yOff),
        BackgroundColor3 = color,
        Text             = text,
        TextColor3       = T.text,
        Font             = Enum.Font.GothamBold,
        TextSize         = 13,
        BorderSizePixel  = 0,
    })
    inst("UICorner", btn, { CornerRadius = UDim.new(0, 8) })
    btn.MouseButton1Click:Connect(function()
        tw(btn, { BackgroundColor3 = color:Lerp(Color3.new(0,0,0), 0.2) }, 0.08)
        task.delay(0.08, function() tw(btn, { BackgroundColor3 = color }, 0.15) end)
        cb()
    end)
    btn.MouseEnter:Connect(function() tw(btn, { BackgroundColor3 = color:Lerp(Color3.new(1,1,1), 0.08) }, 0.15) end)
    btn.MouseLeave:Connect(function() tw(btn, { BackgroundColor3 = color }, 0.15) end)
    return btn
end

-- ════════════════════════════════════════════════════════════
--  TAB 1 — FLING
-- ════════════════════════════════════════════════════════════

do
    local pg = inst("Frame", contentF, {
        Size                   = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
        Visible                = true,
    })
    pages[1] = pg
    local y = P

    -- Player list
    local listH = Mobile and 168 or 150
    local listCard = card(pg, y, listH)
    y = y + listH + P

    lbl(listCard, "SELECT TARGET", 10, T.muted, Enum.Font.GothamBold, P, 8, 1, 14)

    local scroll = inst("ScrollingFrame", listCard, {
        Size                    = UDim2.new(1, -P*2, 1, -28),
        Position                = UDim2.new(0, P, 0, 24),
        BackgroundTransparency  = 1,
        BorderSizePixel         = 0,
        ScrollBarThickness      = 3,
        ScrollBarImageColor3    = T.accent,
        CanvasSize              = UDim2.new(0, 0, 0, 0),
    })
    local layout = inst("UIListLayout", scroll, {
        Padding       = UDim.new(0, 4),
        FillDirection = Enum.FillDirection.Vertical,
        SortOrder     = Enum.SortOrder.LayoutOrder,
    })

    local pBtns  = {}
    local selBtn = nil

    local function refresh()
        for _, b in pairs(pBtns) do b:Destroy() end
        pBtns = {}; selBtn = nil; S.target = nil

        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= LP then
                local pb = inst("TextButton", scroll, {
                    Size             = UDim2.new(1, 0, 0, Mobile and 38 or 30),
                    BackgroundColor3 = T.surf2,
                    Text             = "  " .. p.Name,
                    TextColor3       = T.text,
                    Font             = Enum.Font.Gotham,
                    TextSize         = 12,
                    TextXAlignment   = Enum.TextXAlignment.Left,
                    BorderSizePixel  = 0,
                })
                inst("UICorner", pb, { CornerRadius = UDim.new(0, 7) })
                pb.MouseButton1Click:Connect(function()
                    if selBtn then
                        tw(selBtn, { BackgroundColor3 = T.surf2 }, 0.15)
                        local s = selBtn:FindFirstChildOfClass("UIStroke")
                        if s then s:Destroy() end
                    end
                    S.target = p; selBtn = pb
                    tw(pb, { BackgroundColor3 = T.accentD }, 0.15)
                    inst("UIStroke", pb, { Color = T.accent, Thickness = 1.5 })
                end)
                table.insert(pBtns, pb)
            end
        end
        task.defer(function()
            scroll.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + 4)
        end)
    end

    refresh()
    Players.PlayerAdded:Connect(refresh)
    Players.PlayerRemoving:Connect(function() task.wait(0.1); refresh() end)

    -- Refresh button (compact)
    local rfBtn = inst("TextButton", pg, {
        Size             = UDim2.new(0, 92, 0, 26),
        Position         = UDim2.new(0, P, 0, y - P + 2),
        BackgroundColor3 = T.surf2,
        Text             = "⟳  Refresh",
        TextColor3       = T.muted,
        Font             = Enum.Font.GothamBold,
        TextSize         = 11,
        BorderSizePixel  = 0,
    })
    inst("UICorner", rfBtn, { CornerRadius = UDim.new(0, 7) })
    rfBtn.MouseButton1Click:Connect(refresh)
    y = y + 32

    actionBtn(pg, "⚡  Fling Player", y, T.accent, function()
        if S.target then
            Fling(S.target)
        end
    end)
    y = y + BH + P

    pageH[1] = y
end

-- ════════════════════════════════════════════════════════════
--  TAB 2 — FLY
-- ════════════════════════════════════════════════════════════

local mobCtrl = nil   -- mobile up/down overlay; assigned below

do
    local pg = inst("Frame", contentF, {
        Size                   = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
        Visible                = false,
    })
    pages[2] = pg
    local y = P

    toggle(pg, "Fly Enabled", y, false, function(on)
        if on then FlyOn() else FlyOff() end
        if mobCtrl then mobCtrl.Visible = on end
    end)
    y = y + BH + P*2 + P

    slider(pg, "Fly Speed", y, 10, 300, S.flySpd, "%d stud/s", function(v)
        S.flySpd = v
    end)
    y = y + (Mobile and 72 or 64) + P

    -- Controls hint card
    local hH = Mobile and 84 or 70
    local hc  = card(pg, y, hH)
    y = y + hH + P
    lbl(hc, "Controls", 11, T.muted, Enum.Font.GothamBold, P, 8, 1, 14)
    if Mobile then
        lbl(hc, "Joystick  ─  Horizontal",       11, T.text, Enum.Font.Gotham, P, 26, 0.95, 14)
        lbl(hc, "▲ / ▼ buttons  ─  Up & Down",   11, T.text, Enum.Font.Gotham, P, 42, 0.95, 14)
        lbl(hc, "Drag camera  ─  Direction",      11, T.text, Enum.Font.Gotham, P, 58, 0.95, 14)
    else
        lbl(hc, "W / A / S / D  ─  Move",        11, T.text, Enum.Font.Gotham, P, 26, 0.95, 14)
        lbl(hc, "Space  ─  Up     LCtrl  ─  Down", 11, T.text, Enum.Font.Gotham, P, 42, 0.95, 14)
        lbl(hc, "Camera controls direction",      11, T.text, Enum.Font.Gotham, P, 58, 0.95, 14)
    end

    pageH[2] = y
end

-- ════════════════════════════════════════════════════════════
--  TAB 3 — SPEED
-- ════════════════════════════════════════════════════════════

do
    local pg = inst("Frame", contentF, {
        Size                   = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
        Visible                = false,
    })
    pages[3] = pg
    local y = P

    toggle(pg, "SpeedHack", y, false, function(on)
        if on then SpdOn() else SpdOff() end
    end)
    y = y + BH + P*2 + P

    -- Live speed display
    local dc = card(pg, y, 54)
    y = y + 54 + P
    lbl(dc, "Walk Speed", 11, T.muted, Enum.Font.GothamBold, P, 8, 1, 14)
    local dispVal = inst("TextLabel", dc, {
        Size                   = UDim2.new(0.65, 0, 0, 28),
        Position               = UDim2.new(0, P, 0, 22),
        BackgroundTransparency = 1,
        Text                   = tostring(S.walkSpd),
        TextColor3             = T.accent,
        Font                   = Enum.Font.GothamBold,
        TextSize               = 22,
        TextXAlignment         = Enum.TextXAlignment.Left,
    })
    inst("TextLabel", dc, {
        Size                   = UDim2.new(0.35, -P, 0, 14),
        Position               = UDim2.new(0.65, 0, 0, 34),
        BackgroundTransparency = 1,
        Text                   = "studs / s",
        TextColor3             = T.muted,
        Font                   = Enum.Font.Gotham,
        TextSize               = 10,
        TextXAlignment         = Enum.TextXAlignment.Right,
    })

    slider(pg, "Speed", y, 16, 500, S.walkSpd, "%d", function(v)
        S.walkSpd    = v
        dispVal.Text = tostring(v)
        if S.spd then local h = Hum(); if h then h.WalkSpeed = v end end
    end)
    y = y + (Mobile and 72 or 64) + P

    -- ± buttons
    local pmc = card(pg, y, BH + P*2)
    y = y + BH + P*2 + P

    local function pmBtn(text, xScale, delta)
        local b = inst("TextButton", pmc, {
            Size             = UDim2.new(0.455, 0, 0, BH),
            Position         = UDim2.new(xScale, 0, 0, P),
            BackgroundColor3 = T.surf2,
            Text             = text,
            TextColor3       = T.text,
            Font             = Enum.Font.GothamBold,
            TextSize         = 13,
            BorderSizePixel  = 0,
        })
        inst("UICorner", b, { CornerRadius = UDim.new(0, 8) })
        b.MouseButton1Click:Connect(function()
            S.walkSpd    = math.clamp(S.walkSpd + delta, 16, 500)
            dispVal.Text = tostring(S.walkSpd)
            if S.spd then local h = Hum(); if h then h.WalkSpeed = S.walkSpd end end
        end)
        b.MouseEnter:Connect(function() tw(b, { BackgroundColor3 = T.surf3 }, 0.15) end)
        b.MouseLeave:Connect(function() tw(b, { BackgroundColor3 = T.surf2 }, 0.15) end)
    end

    pmBtn("─  10", 0.02,   -10)
    pmBtn("+ 10",  0.525,  +10)

    pageH[3] = y
end

-- ════════════════════════════════════════════════════════════
--  Tab switching
-- ════════════════════════════════════════════════════════════

local curTab = 1

local function setH(idx)
    tw(main, { Size = UDim2.new(0, W, 0, ConY + pageH[idx]) }, 0.22)
    contentF.Size = UDim2.new(1, 0, 0, pageH[idx])
end
setH(1)

local function switchTab(idx)
    if idx == curTab then return end
    pages[curTab].Visible = false
    tw(tabBtns[curTab], { TextColor3 = T.muted }, 0.15)
    tw(tabInds[curTab],  { Size = UDim2.new(0, 0, 0, 2) }, 0.15)
    tabBtns[curTab].Font = Enum.Font.Gotham

    curTab = idx
    pages[idx].Visible = true
    tw(tabBtns[idx], { TextColor3 = T.text }, 0.2)
    tw(tabInds[idx],  { Size = UDim2.new(0.65, 0, 0, 2) },
        0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
    tabBtns[idx].Font = Enum.Font.GothamBold
    setH(idx)
end

for i, btn in ipairs(tabBtns) do
    btn.MouseButton1Click:Connect(function() switchTab(i) end)
end

-- ── Minimize ──

local minimized = false
minBtn.MouseButton1Click:Connect(function()
    minimized = not minimized
    if minimized then
        tw(main, { Size = UDim2.new(0, W, 0, TH + TabH) }, 0.22)
        contentF.Visible = false
        minBtn.Text = "□"
    else
        tw(main, { Size = UDim2.new(0, W, 0, ConY + pageH[curTab]) }, 0.22)
        contentF.Visible = true
        minBtn.Text = "─"
    end
end)

-- ════════════════════════════════════════════════════════════
--  Mobile fly up/down overlay
-- ════════════════════════════════════════════════════════════

if Mobile then
    local mob = inst("Frame", sg, {
        Name                   = "MobFly",
        Size                   = UDim2.new(0, 76, 0, 162),
        Position               = UDim2.new(1, -96, 0.5, -81),
        BackgroundTransparency = 1,
        Visible                = false,
    })
    mobCtrl = mob

    local function mBtn(text, yOff)
        local b = inst("TextButton", mob, {
            Size             = UDim2.new(1, 0, 0, 72),
            Position         = UDim2.new(0, 0, 0, yOff),
            BackgroundColor3 = T.surf,
            Text             = text,
            TextColor3       = T.text,
            Font             = Enum.Font.GothamBold,
            TextSize         = 26,
            BorderSizePixel  = 0,
        })
        inst("UICorner", b, { CornerRadius = UDim.new(0, 14) })
        inst("UIStroke",  b, { Color = T.border, Thickness = 1.5 })
        return b
    end

    local upB = mBtn("▲", 0)
    local dnB = mBtn("▼", 82)

    upB.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.Touch then S.mobUp = true end
    end)
    upB.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.Touch then S.mobUp = false end
    end)
    dnB.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.Touch then S.mobDn = true end
    end)
    dnB.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.Touch then S.mobDn = false end
    end)
end

-- ════════════════════════════════════════════════════════════
--  Re-initialise on character respawn
-- ════════════════════════════════════════════════════════════

LP.CharacterAdded:Connect(function()
    task.wait(1.5)   -- wait for full character load
    if S.fly then
        FlyClean(); task.wait(0.1); FlyOn()
    end
    if S.spd then
        if S.spdLp then S.spdLp:Disconnect() end
        SpdOn()
    end
end)
