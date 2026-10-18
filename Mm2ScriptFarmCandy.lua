--// =============================================================================
--// Catfeex Farm v4.1 — Auto farm candy + Auto farm candy 2.0 (50 candy)
--// =============================================================================

if getgenv()._CATFEEX_FARM_WIN then
    pcall(function() getgenv()._CATFEEX_FARM_WIN:Destroy() end)
end

local okW, WindUI = pcall(function()
    return loadstring(game:HttpGet("https://raw.githubusercontent.com/Footagesus/WindUI/main/dist/main.lua"))()
end)
if not okW or not WindUI then
    warn("[Catfeex Farm] WindUI failed")
    return
end

local Players    = game:GetService("Players")
local RS         = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenSvc   = game:GetService("TweenService")
local VU         = game:GetService("VirtualUser")
local CoreGui    = game:GetService("CoreGui")

local LP = Players.LocalPlayer
local PG = LP:WaitForChild("PlayerGui")

--=============================== CONFIG ===============================
local CONFIG = {
    -- Auto farm candy (fly + noclip)
    SPEED          = 31,
    LIFT           = -4,
    PROBE_WAIT     = 0.4,
    POST_COIN_WAIT = 1.0,
    MAX_TP_DIST    = 300,
    MAX_COINS      = 50,   -- 👈 изменено с 40 на 50

    -- Auto farm candy 2.0 (Sky TP)
    SKY_HEIGHT     = 2160,
    SKY_TP_WAIT    = 0.30,
    SKY_BACK_WAIT  = 2.0,

    BAG_UI_POLL    = 0.15,
}

--=============================== STATE ===============================
local state = {
    running=false, mode=nil, busy=false, status="Idle",
    bag=0, totalCoins=0, probeDone=false,
    sessionStart=0, lastReset=0, lastBagRead=0,
    floatPart=nil, floatSync=nil, floatActive=false,
    activeTween=nil,
    skyPlat=nil, skyPos=nil,
}

--=============================== HELPERS ===============================
local function getChar() return LP.Character end
local function getHRP() local c=getChar() return c and (c:FindFirstChild("HumanoidRootPart") or c:FindFirstChild("Torso")) end
local function getHum() local c=getChar() return c and c:FindFirstChildOfClass("Humanoid") end
local function hasTool(n) local c=getChar() local bp=LP:FindFirstChild("Backpack") return (c and c:FindFirstChild(n)) or (bp and bp:FindFirstChild(n)) end

--=============================== ANTI-AFK ===============================
local afkConn
local function startAfk() if afkConn then return end afkConn=LP.Idled:Connect(function() pcall(function() VU:CaptureController() VU:ClickButton2(Vector2.new()) end) end) end
local function stopAfk() if afkConn then afkConn:Disconnect() afkConn=nil end end

--=============================== NOCLIP ===============================
local function setNoclip(on)
    local c=getChar() if not c then return end
    for _,p in ipairs(c:GetDescendants()) do
        if p:IsA("BasePart") then pcall(function() p.CanCollide=not on end) end
    end
end

--=============================== COINS ===============================
local function findCC()
    for _,ch in ipairs(workspace:GetChildren()) do
        if ch:IsA("Model") then local cc=ch:FindFirstChild("CoinContainer") if cc then return cc end end
    end
end
local function getCoins()
    local cc=findCC() if not cc then return {} end
    local out={}
    for _,c in ipairs(cc:GetChildren()) do
        if (c.Name=="Coin_Server" or c.Name=="Coin") and c:IsA("BasePart") then out[#out+1]=c end
    end
    return out
end
local function pickNearestCoin(fromPos, maxDist)
    local best,bd=nil, maxDist or math.huge
    for _,c in ipairs(getCoins()) do
        local ok,d=pcall(function() return (c.Position-fromPos).Magnitude end)
        if ok and d<bd then bd=d; best=c end
    end
    return best,bd
end
local function inRound() return findCC()~=nil end

--=============================== BAG UI ===============================
local function readBagFromUI()
    local main=PG:FindFirstChild("MainGUI")
    if not main then return 0 end
    local best=0
    for _,d in ipairs(main:GetDescendants()) do
        if d:IsA("TextLabel") or d:IsA("TextBox") then
            -- берём формат "X / 50" или просто "X"
            local text = d.Text or ""
            local v = tonumber(text:match("^(%d+)%s*/"))
                    or tonumber(text:match("^%s*(%d+)%s*$"))
            if v and v>=0 and v<=CONFIG.MAX_COINS then
                local p=d.Parent
                for _=1,6 do
                    if not p then break end
                    local n=string.lower(p.Name)
                    if n:find("coin") or n:find("bag") then
                        if v>best then best=v end
                        break
                    end
                    p=p.Parent
                end
            end
        end
    end
    return best
end

--=============================== COIN EVENT ===============================
local ccConn
local function bindCC()
    if ccConn then ccConn:Disconnect() end
    local g=RS:FindFirstChild("Remotes") g = g and g:FindFirstChild("Gameplay")
    local cc = g and g:FindFirstChild("CoinCollected")
    if not cc then return end
    ccConn = cc.OnClientEvent:Connect(function(name, now, max)
        if name==LP.Name then
            local prev=state.bag
            state.bag = tonumber(now) or 0
            if state.bag>prev then state.totalCoins = state.totalCoins + (state.bag-prev) end
        end
    end)
end

--=============================== TOUCH ===============================
local function touchPart(part, hrp)
    if not part or not part.Parent or not hrp then return end
    pcall(function()
        if firetouchinterest then
            firetouchinterest(hrp, part, 0)
            task.wait(0.01)
            firetouchinterest(hrp, part, 1)
        end
        task.defer(function() pcall(function() part:Destroy() end) end)
    end)
end

--=============================== FLOAT PART ===============================
local function destroyFP()
    if state.floatPart then pcall(function() state.floatPart:Destroy() end) state.floatPart=nil end
end
local function createFP()
    destroyFP()
    local hrp=getHRP() if not hrp then return end
    local p=Instance.new("Part")
    p.Name="Catfeex_FloatPart"; p.Size=Vector3.one; p.Transparency=1
    p.Anchored=true; p.CanCollide=false; p.Massless=true; p.CastShadow=false
    p.CFrame=hrp.CFrame; p.Parent=workspace
    state.floatPart=p
    return p
end
local function syncHrp()
    local hrp=getHRP(); local fp=state.floatPart
    if not hrp or not fp or not fp.Parent then return end
    local cam=workspace.CurrentCamera; local yaw=0
    if cam then local l=cam.CFrame.LookVector yaw=math.atan2(-l.X,-l.Z) end
    hrp.CFrame=CFrame.new(fp.Position)*CFrame.Angles(math.pi/2,yaw,0)
    hrp.AssemblyLinearVelocity=Vector3.zero
    hrp.AssemblyAngularVelocity=Vector3.zero
end
local function startFD()
    if state.floatActive then return end
    state.floatActive=true
    setNoclip(true)
    createFP()
    local hum=getHum() if hum then hum.PlatformStand=true hum.AutoRotate=false end
    if state.floatSync then state.floatSync:Disconnect() end
    state.floatSync=RunService.Heartbeat:Connect(syncHrp)
end
local function stopFD()
    if state.activeTween then pcall(function() state.activeTween:Cancel() end) state.activeTween=nil end
    if state.floatSync then state.floatSync:Disconnect() state.floatSync=nil end
    state.floatActive=false
    destroyFP()
    setNoclip(false)
    local hum=getHum() if hum then hum.PlatformStand=false hum.AutoRotate=true end
end

--=============================== SKY PLATFORM ===============================
local function destroySkyPlat()
    if state.skyPlat then pcall(function() state.skyPlat:Destroy() end) state.skyPlat=nil end
    state.skyPos=nil
end
local function createSkyPlat()
    destroySkyPlat()
    local hrp=getHRP() if not hrp then return false end
    local plat=Instance.new("Part")
    plat.Name="Catfeex_SkyPlat"; plat.Size=Vector3.new(20,1,20)
    plat.Anchored=true; plat.CanCollide=true; plat.Transparency=0.4
    plat.Color=Color3.fromHex("#dc2626"); plat.Material=Enum.Material.Neon
    plat.CastShadow=false; plat.Parent=workspace
    local basePos=Vector3.new(hrp.Position.X, hrp.Position.Y+CONFIG.SKY_HEIGHT, hrp.Position.Z)
    plat.CFrame=CFrame.new(basePos)
    state.skyPlat=plat
    state.skyPos=basePos+Vector3.new(0,3,0)
    return true
end

--=============================== PROBE ===============================
local function probe()
    local hrp=getHRP() if not hrp then return false end
    setNoclip(false)
    local target,dist = pickNearestCoin(hrp.Position, CONFIG.MAX_TP_DIST)
    if not target then state.status="Probe: no coin" return false end
    state.status = string.format("Probe TP %d", math.floor(dist))
    local oldBag = state.bag
    pcall(function()
        hrp.CFrame = CFrame.new(target.Position + Vector3.new(0,2.5,0))
        hrp.AssemblyLinearVelocity = Vector3.zero
        hrp.AssemblyAngularVelocity = Vector3.zero
    end)
    task.wait(CONFIG.PROBE_WAIT)
    touchPart(target, hrp)
    task.wait(0.15)
    if (not target.Parent) or (state.bag > oldBag) then
        state.probeDone = true
        state.status = "Probe OK → fly"
        startFD()
        return true
    end
    state.status = "Probe FAIL"
    return false
end

--=============================== FLY ===============================
local function flyToPart(part)
    local hrp = getHRP()
    local fp  = state.floatPart
    if not hrp or not fp or not part or not part.Parent then return false end
    local target = part.Position + Vector3.new(0, CONFIG.LIFT, 0)
    local dist = (target - fp.Position).Magnitude
    local dur  = math.max(0.05, dist / CONFIG.SPEED)
    local tw = TweenSvc:Create(fp,
        TweenInfo.new(dur, Enum.EasingStyle.Linear, Enum.EasingDirection.Out),
        { CFrame = CFrame.new(target) })
    state.activeTween = tw
    tw:Play()
    while state.running and state.floatActive and part.Parent do
        if tw.PlaybackState ~= Enum.PlaybackState.Playing then break end
        task.wait()
    end
    syncHrp()
    if part.Parent then touchPart(part, hrp) end
    state.activeTween = nil
    return true
end

--=============================== LOBBY ===============================
local function clickPlay()
    local main=PG:FindFirstChild("MainGUI") if not main then return false end
    for _,d in ipairs(main:GetDescendants()) do
        if (d:IsA("TextButton") or d:IsA("ImageButton")) and d.Visible then
            local isPlay=false
            if d:IsA("TextButton") and string.find(string.lower(d.Text),"play") then isPlay=true end
            if string.find(string.lower(d.Name),"play") then isPlay=true end
            if isPlay then
                if getconnections then
                    local ok,conns=pcall(getconnections,d.Activated)
                    if ok and conns then
                        for _,cc in ipairs(conns) do pcall(function() cc:Fire() end) end
                        return true
                    end
                end
                if firesignal then pcall(firesignal,d.Activated) return true end
                pcall(function()
                    local pos=d.AbsolutePosition+d.AbsoluteSize/2
                    VU:SendMouseButtonEvent(pos.X,pos.Y,0,true,game,0)
                    task.wait(0.03)
                    VU:SendMouseButtonEvent(pos.X,pos.Y,0,false,game,0)
                end)
                return true
            end
        end
    end
    return false
end

--=============================== RESET ===============================
local function doReset(reason)
    if tick()-state.lastReset < 2 then return end
    state.lastReset=tick()
    state.status="Dying ("..tostring(reason)..")"
    stopFD()
    destroySkyPlat()
    local hum=getHum()
    if hum and hum.Health>0 then pcall(function() hum.Health=0 end) end
    local char=getChar()
    if char then pcall(function() char:BreakJoints() end) end
    local t0=tick()
    while state.running and tick()-t0 < 10 do
        local h=getHum()
        if h and h.Health>0 and getHRP() then break end
        task.wait(0.12)
    end
    state.bag=0
    state.probeDone=false
    task.wait(0.4)
end

--=============================== KILL ALL ===============================
local function doKillAll()
    if not hasTool("Knife") then return 0 end
    local char=getChar() if not char then return 0 end
    local hum=char:FindFirstChildOfClass("Humanoid")
    local knife=char:FindFirstChild("Knife")
    if not knife then
        local bk=LP:FindFirstChild("Backpack") and LP.Backpack:FindFirstChild("Knife")
        if bk and hum then hum:EquipTool(bk) task.wait(0.05) end
        knife=char:FindFirstChild("Knife")
    end
    if not knife then return 0 end
    local killed=0
    for _,plr in ipairs(Players:GetPlayers()) do
        if plr~=LP and plr.Character then
            local hrp=plr.Character:FindFirstChild("HumanoidRootPart")
            local h=plr.Character:FindFirstChildOfClass("Humanoid")
            if hrp and h and h.Health>0 then
                killed+=1
                pcall(function()
                    if firetouchinterest then
                        firetouchinterest(hrp,knife.Handle,0)
                        firetouchinterest(hrp,knife.Handle,1)
                    end
                    local ev=knife:FindFirstChild("Events")
                    if ev and ev:FindFirstChild("HandleTouched") then
                        ev.HandleTouched:FireServer(hrp)
                    end
                end)
            end
        end
    end
    return killed
end
local function countAliveOthers()
    local n=0
    for _,plr in ipairs(Players:GetPlayers()) do
        if plr~=LP and plr.Character then
            local h=plr.Character:FindFirstChildOfClass("Humanoid")
            if h and h.Health>0 then n+=1 end
        end
    end
    return n
end

--=============================== HANDLE 50/50 ===============================
local function handleFullBag()
    if state.mode=="basic" and hasTool("Knife") then
        state.status="🔪 Murderer — Kill All!"
        local t0=tick()
        while state.running and inRound() and tick()-t0 < 20 do
            doKillAll()
            if countAliveOthers()==0 then
                state.status="All dead"
                task.wait(0.5)
                if not inRound() then break end
            end
            task.wait(0.15)
        end
        if inRound() then doReset("kill timeout") end
        state.bag=0
        return
    end
    doReset("50/50")
end

--=============================== AUTO FARM CANDY (fly) ===============================
local function stepBasic()
    local hrp = getHRP()
    if not hrp then return end

    if not state.probeDone then probe() return end
    if not state.floatActive then startFD() return end
    local fp = state.floatPart
    if not fp or not fp.Parent then startFD() return end

    local coin, dist = pickNearestCoin(fp.Position, CONFIG.MAX_TP_DIST)
    if not coin then
        state.status = "No coins — wait"
        task.wait(0.2)
        return
    end

    state.status = string.format("Fly %d → %d", math.floor(dist), CONFIG.SPEED)
    flyToPart(coin)

    if state.running and state.bag < CONFIG.MAX_COINS then
        state.status = "Wait 1s"
        local t0 = tick()
        while state.running and tick() - t0 < CONFIG.POST_COIN_WAIT do
            task.wait(0.03)
        end
    end
end

--=============================== AUTO FARM CANDY 2.0 (Sky TP) ===============================
local function stepFarm2()
    local hrp = getHRP()
    if not hrp then return end
    setNoclip(false)

    if not state.skyPlat or not state.skyPlat.Parent then
        if not createSkyPlat() then return end
        hrp.CFrame = CFrame.new(state.skyPos)
        hrp.AssemblyLinearVelocity = Vector3.zero
        hrp.AssemblyAngularVelocity = Vector3.zero
        state.status = "Sky platform ready"
        task.wait(0.4)
        return
    end

    local skyDist = math.abs(hrp.Position.Y - state.skyPos.Y)
    if skyDist > 100 then
        hrp.CFrame = CFrame.new(state.skyPos)
        hrp.AssemblyLinearVelocity = Vector3.zero
        hrp.AssemblyAngularVelocity = Vector3.zero
        task.wait(0.2)
        return
    end

    local coin, dist = pickNearestCoin(hrp.Position, math.huge)
    if not coin then
        state.status = "No coins — wait"
        task.wait(0.3)
        return
    end

    state.status = string.format("Sky TP → %d", math.floor(dist))
    hrp.CFrame = CFrame.new(coin.Position + Vector3.new(0, 2.5, 0))
    hrp.AssemblyLinearVelocity = Vector3.zero
    hrp.AssemblyAngularVelocity = Vector3.zero

    task.wait(CONFIG.SKY_TP_WAIT)
    touchPart(coin, hrp)

    hrp.CFrame = CFrame.new(state.skyPos)
    hrp.AssemblyLinearVelocity = Vector3.zero
    hrp.AssemblyAngularVelocity = Vector3.zero

    state.status = "Wait " .. CONFIG.SKY_BACK_WAIT .. "s"
    local t0 = tick()
    while state.running and inRound() and state.bag < CONFIG.MAX_COINS
          and tick() - t0 < CONFIG.SKY_BACK_WAIT do
        task.wait(0.05)
    end
end

--=============================== MAIN LOOP ===============================
local function farmLoop()
    if state.busy then return end
    state.busy = true
    state.sessionStart = tick()
    state.totalCoins = 0
    state.bag = 0
    state.probeDone = false

    while state.running do
        task.wait()
        local ok, err = pcall(function()
            if not getHRP() then state.status="Respawning..." return end

            if not inRound() then
                state.status="Waiting round..."
                state.bag = 0
                state.probeDone = false
                stopFD()
                destroySkyPlat()
                clickPlay()
                return
            end

            if tick()-state.lastBagRead > CONFIG.BAG_UI_POLL then
                state.lastBagRead = tick()
                local uiBag = readBagFromUI()
                if uiBag > state.bag then state.bag = uiBag end
            end

            if state.bag >= CONFIG.MAX_COINS then
                handleFullBag()
                return
            end

            if state.mode == "basic" then
                stepBasic()
            elseif state.mode == "farm2" then
                stepFarm2()
            end
        end)
        if not ok then
            state.status="Err: "..tostring(err):sub(1,55)
            task.wait(0.3)
        end
    end

    stopFD()
    destroySkyPlat()
    state.status="Idle"
    state.busy=false
    state.mode=nil
end

--=============================== API ===============================
local function stopFarm()
    state.running=false
    state.busy=false
    stopFD()
    destroySkyPlat()
    stopAfk()
    if ccConn then ccConn:Disconnect() ccConn=nil end
    pcall(function()
        WindUI:Notify({Title="Catfeex Farm", Content="⏹ STOP", Icon="pause", Duration=2})
    end)
end

local function startMode(mode, label)
    if state.running then stopFarm() task.wait(0.15) end
    state.running=true
    state.mode=mode
    state.probeDone=false
    startAfk()
    bindCC()
    pcall(function()
        WindUI:Notify({Title="Catfeex Farm", Content="▶ "..label.." START", Icon="play", Duration=3})
    end)
    task.spawn(farmLoop)
end

getgenv().CatfeexFarm = {
    stop=stopFarm,
    autoFarmCandy = function() startMode("basic","Auto farm candy") end,
    autoFarmCandy2 = function() startMode("farm2","Auto farm candy 2.0") end,
    state=state, config=CONFIG,
}

--=============================== WINDUI ===============================
WindUI:SetTheme("Crimson")

local CAT_ICON      = "rbxassetid://101992008196867"
local FARM_TAB_ICON = "rbxassetid://91756141734699"
local RED_BRIGHT    = Color3.fromHex("#dc2626")
local RED_DARK      = Color3.fromHex("#991b1b")

local Window = WindUI:CreateWindow({
    Title        = "Catfeex Farm",
    Icon         = CAT_ICON,
    Author       = "Delta",
    Folder       = "CatfeexFarm",
    Size         = UDim2.fromOffset(400, 350),
    Transparent  = true,
    Theme        = "Crimson",
    SideBarWidth = 150,
    HideSearchBar = true,
    OpenButton = {
        Title           = "Catfeex Farm",
        Icon            = CAT_ICON,
        CornerRadius    = UDim.new(1, 0),
        StrokeThickness = 2,
        Enabled         = true,
        OnlyMobile      = false,
        Color           = ColorSequence.new(RED_BRIGHT, RED_DARK),
    },
})
getgenv()._CATFEEX_FARM_WIN = Window

local FarmTab = Window:Tab({ Title = "Farm", Icon = FARM_TAB_ICON })

FarmTab:Section({ Title = "Status" })
local statusPara  = FarmTab:Paragraph({ Title = "Status",  Desc = "Idle" })
local bagPara     = FarmTab:Paragraph({ Title = "Bag",     Desc = "0 / 50" })
local sessionPara = FarmTab:Paragraph({ Title = "Session", Desc = "0 coins · 0s" })
local phasePara   = FarmTab:Paragraph({ Title = "Phase",   Desc = "-" })

FarmTab:Section({ Title = "Modes" })

local btnAuto = FarmTab:Button({
    Title = "▶ Auto farm candy",
    Callback = function()
        if state.running and state.mode=="basic" then stopFarm()
        else startMode("basic","Auto farm candy") end
    end,
})

local btnAuto2 = FarmTab:Button({
    Title = "▶ Auto farm candy 2.0",
    Callback = function()
        if state.running and state.mode=="farm2" then stopFarm()
        else startMode("farm2","Auto farm candy 2.0") end
    end,
})

FarmTab:Divider()

FarmTab:Button({
    Title = "⏹ Stop",
    Callback = function()
        if state.running then stopFarm() end
    end,
})

-- Live update
task.spawn(function()
    while getgenv()._CATFEEX_FARM_WIN == Window do
        pcall(function()
            if statusPara  then statusPara:SetDesc(state.status) end
            if bagPara     then bagPara:SetDesc(string.format("%d / %d", state.bag, CONFIG.MAX_COINS)) end
            if sessionPara then
                local t = state.sessionStart>0 and math.floor(tick()-state.sessionStart) or 0
                sessionPara:SetDesc(string.format("%d coins · %ds", state.totalCoins, t))
            end
            if phasePara then
                if state.mode == "farm2" and state.running then
                    phasePara:SetDesc("☁ SKY TP")
                elseif state.probeDone then
                    phasePara:SetDesc("🌊 FLY + NOCLIP (31)")
                elseif state.running then
                    phasePara:SetDesc("🔍 PROBE")
                else
                    phasePara:SetDesc("-")
                end
            end
            if btnAuto then
                pcall(function()
                    local active = state.running and state.mode=="basic"
                    btnAuto:SetTitle(active and "⏹ Auto farm candy (running)" or "▶ Auto farm candy")
                end)
            end
            if btnAuto2 then
                pcall(function()
                    local active = state.running and state.mode=="farm2"
                    btnAuto2:SetTitle(active and "⏹ Auto farm candy 2.0 (running)" or "▶ Auto farm candy 2.0")
                end)
            end
        end)
        task.wait(0.3)
    end
end)

-- 🔴 Красная обводка
task.spawn(function()
    task.wait(1.2)
    local function paint(root)
        if not root then return end
        for _, d in ipairs(root:GetDescendants()) do
            if d:IsA("UIStroke") then
                pcall(function()
                    d.Color = RED_BRIGHT
                    if d.Thickness < 1.5 then d.Thickness = 1.5 end
                    d.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
                end)
            end
        end
    end
    local sg
    for _, ch in ipairs(CoreGui:GetChildren()) do
        if ch:IsA("ScreenGui") and (ch.Name=="CatfeexFarm" or ch.Name:find("WindUI")) then
            sg = ch; break
        end
    end
    if sg then
        paint(sg)
        task.spawn(function()
            while sg.Parent do task.wait(2) paint(sg) end
        end)
    end
end)

pcall(function()
    WindUI:Notify({Title="Catfeex Farm", Content="🐱 Loaded! Лимит 50 конфет", Icon="check", Duration=3})
end)
print("[Catfeex Farm v4.1] loaded — MAX_COINS = 50")
