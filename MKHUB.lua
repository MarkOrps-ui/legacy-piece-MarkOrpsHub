-- ================================================================
--  LEGACY ADMIN HUB V2 - COMPLETE LOCALSCRIPT (FULLY FIXED)
--  Roblox Admin Panel for Personal Use
--  Version 2.0 - All features working
-- ================================================================

-- ================================================================
-- PART 1 - CONFIGURATION & DATABASE
-- ================================================================

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

-- === CONFIG CONSTANTS ===
local MAX_FARM_DISTANCE = 75
local BOSS_FLY_SPEED = 250
local STAT_POINTS_PER_TICK = 1
local STAT_LIST = {"Style", "Defense", "Weapon", "Ability"}

-- === ISLAND COORDS (for fallback teleport) ===
local ISLAND_COORDS = {
    ["Starter Island"] = Vector3.new(-1612.133, 33.062, 1076.469),
    ["Legacy Island"] = Vector3.new(-130.885, 15.185, 13.930),
    ["Jungle Island"] = Vector3.new(-2056.093, 11.981, 302.550),
    ["Ice Island"] = Vector3.new(389.628, 33.475, -3093.314),
    ["A-City"] = Vector3.new(1063.113, 11.488, 1985.108),
    ["Jujutsu Academy"] = Vector3.new(-743.184, 14.337, -1220.281),
    ["Hollow Land"] = Vector3.new(-193.204, 24.469, 3099.400),
    ["Slayer Mansion"] = Vector3.new(1292.201, 23.765, 490.993),
    ["Tokyo Ghoul"] = Vector3.new(3615.019, 20.026, -504.959),
    ["Ruin City"] = Vector3.new(-2558.683, 27.805, 3134.489)
}

-- === REQUIRED MODULES & REMOTES ===
local IslandsConfig = require(ReplicatedStorage.Modules.Configurations:WaitForChild("IslandsConfig"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local TeleportToPortal = Remotes:WaitForChild("TeleportToPortal")

-- === ISLAND LIST ===
local islandList = {}
for iName, iData in pairs(IslandsConfig) do
    if iData.PortalId then
        table.insert(islandList, iName)
    end
end
table.sort(islandList)

-- === GLOBAL STATE ===
local TARGET_STAT = STAT_LIST[1]
local SELECTED_WEAPON = "None/Melee"
local SELECTED_ISLAND = islandList[1] or "None"

-- Toggle states
local isFarming = false
local isStating = false
local isBossing = false
local scriptRunning = true

-- Position system
local savedPosition = nil
local autoSaveEnabled = false
local autoReturnEnabled = false

-- Smart boss state
local bossModeActive = false
local farmPaused = false

-- Runtime stats
local runtimeSeconds = 0
local enemyKills = 0
local bossKills = 0
local currentMode = "Idle"

-- ================================================================
-- PART 2 - UI CREATION
-- ================================================================

-- Utility: round corners
local function applyCorner(guiObject, radius)
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, radius)
    corner.Parent = guiObject
end

-- Main ScreenGui
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "LegacyAdminHub"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = PlayerGui

-- ================================================================
-- NOTIFICATION SYSTEM
-- ================================================================

local notificationContainer = Instance.new("Frame")
notificationContainer.Size = UDim2.new(0, 300, 0, 0)
notificationContainer.Position = UDim2.new(1, -320, 0, 20)
notificationContainer.BackgroundTransparency = 1
notificationContainer.Parent = ScreenGui
local notifLayout = Instance.new("UIListLayout")
notifLayout.Parent = notificationContainer
notifLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
notifLayout.VerticalAlignment = Enum.VerticalAlignment.Top
notifLayout.Padding = UDim.new(0, 8)

-- Notification function
local function ShowNotification(text, isSuccess, duration)
    duration = duration or 3
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(0, 280, 0, 40)
    frame.BackgroundColor3 = isSuccess and Color3.fromRGB(50, 180, 80) or Color3.fromRGB(180, 50, 50)
    frame.BackgroundTransparency = 0.15
    applyCorner(frame, 8)
    frame.Parent = notificationContainer

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, -10, 1, 0)
    label.Position = UDim2.new(0, 5, 0, 0)
    label.BackgroundTransparency = 1
    label.Text = text
    label.TextColor3 = Color3.fromRGB(255,255,255)
    label.Font = Enum.Font.GothamSemibold
    label.TextSize = 14
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = frame

    -- Slide in animation
    frame.Position = UDim2.new(0, 320, 0, 0)
    local tween = TweenService:Create(frame, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Position = UDim2.new(0, 0, 0, 0)})
    tween:Play()

    task.delay(duration, function()
        local outTween = TweenService:Create(frame, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {Position = UDim2.new(0, 320, 0, 0)})
        outTween:Play()
        outTween.Completed:Wait()
        frame:Destroy()
    end)
end

-- ================================================================
-- DRAGGABLE FUNCTION (Mobile friendly)
-- ================================================================

local function makeDraggable(gui)
    local dragging, dragInput, dragStart, startPos

    local function update(input)
        local delta = input.Position - dragStart
        gui.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
    end

    gui.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = gui.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)

    gui.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
            dragInput = input
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if input == dragInput and dragging then
            update(input)
        end
    end)
end

-- ================================================================
-- MAIN UI FRAME
-- ================================================================

local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, 320, 0, 520)
MainFrame.Position = UDim2.new(0.5, -160, 0.5, -260)
MainFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
MainFrame.BackgroundTransparency = 0.05
MainFrame.Active = true
MainFrame.Draggable = false
MainFrame.Visible = true
MainFrame.ZIndex = 1
MainFrame.Parent = ScreenGui
applyCorner(MainFrame, 16)

-- Add shadow
local shadow = Instance.new("ImageLabel")
shadow.Size = UDim2.new(1, 12, 1, 12)
shadow.Position = UDim2.new(0, -6, 0, -6)
shadow.BackgroundTransparency = 1
shadow.Image = "rbxassetid://1316045357"
shadow.ImageColor3 = Color3.new(0,0,0)
shadow.ImageTransparency = 0.6
shadow.ZIndex = 0
shadow.Parent = MainFrame

makeDraggable(MainFrame)

-- ================================================================
-- HEADER
-- ================================================================
local Header = Instance.new("Frame", MainFrame)
Header.Size = UDim2.new(1, 0, 0, 70)
Header.BackgroundTransparency = 1

local Title = Instance.new("TextLabel", Header)
Title.Size = UDim2.new(1, 0, 0, 30)
Title.Position = UDim2.new(0, 0, 0, 6)
Title.BackgroundTransparency = 1
Title.Text = "Legacy Admin Hub"
Title.TextColor3 = Color3.fromRGB(255,255,255)
Title.Font = Enum.Font.GothamBold
Title.TextSize = 20
Title.TextXAlignment = Enum.TextXAlignment.Center

local SubTitle = Instance.new("TextLabel", Header)
SubTitle.Size = UDim2.new(1, 0, 0, 20)
SubTitle.Position = UDim2.new(0, 0, 0, 36)
SubTitle.BackgroundTransparency = 1
SubTitle.Text = "Owner Panel  |  v2.0"
SubTitle.TextColor3 = Color3.fromRGB(180,180,180)
SubTitle.Font = Enum.Font.GothamSemibold
SubTitle.TextSize = 14
SubTitle.TextXAlignment = Enum.TextXAlignment.Center

local Separator1 = Instance.new("Frame", MainFrame)
Separator1.Size = UDim2.new(0.9, 0, 0, 1)
Separator1.Position = UDim2.new(0.05, 0, 0, 75)
Separator1.BackgroundColor3 = Color3.fromRGB(60,60,70)
Separator1.BorderSizePixel = 0

-- ================================================================
-- STATUS PANEL
-- ================================================================
local StatusFrame = Instance.new("Frame", MainFrame)
StatusFrame.Size = UDim2.new(0.9, 0, 0, 110)
StatusFrame.Position = UDim2.new(0.05, 0, 0, 85)
StatusFrame.BackgroundColor3 = Color3.fromRGB(40,40,45)
StatusFrame.BackgroundTransparency = 0.3
applyCorner(StatusFrame, 10)

local statusLabels = {}
local function createStatusLabel(text, x, y)
    local label = Instance.new("TextLabel", StatusFrame)
    label.Size = UDim2.new(0, 130, 0, 18)
    label.Position = UDim2.new(0, x, 0, y)
    label.BackgroundTransparency = 1
    label.Text = text .. ": N/A"
    label.TextColor3 = Color3.fromRGB(220,220,220)
    label.Font = Enum.Font.GothamSemibold
    label.TextSize = 12
    label.TextXAlignment = Enum.TextXAlignment.Left
    return label
end

statusLabels.Farm = createStatusLabel("Farm", 5, 5)
statusLabels.Boss = createStatusLabel("Boss", 140, 5)
statusLabels.Stats = createStatusLabel("Stats", 5, 27)
statusLabels.Weapon = createStatusLabel("Weapon", 140, 27)
statusLabels.Island = createStatusLabel("Island", 5, 49)
statusLabels.Pos = createStatusLabel("Pos", 140, 49)
statusLabels.BossStatus = createStatusLabel("Boss Status", 5, 71)
statusLabels.Runtime = createStatusLabel("Runtime", 140, 71)
statusLabels.Mode = createStatusLabel("Mode", 5, 93)

-- Function to update status labels
local function UpdateStatus()
    statusLabels.Farm.Text = "Farm: " .. (isFarming and "ON" or "OFF")
    statusLabels.Farm.TextColor3 = isFarming and Color3.fromRGB(50,220,80) or Color3.fromRGB(220,70,70)
    statusLabels.Boss.Text = "Boss: " .. (isBossing and "ON" or "OFF")
    statusLabels.Boss.TextColor3 = isBossing and Color3.fromRGB(180,100,255) or Color3.fromRGB(220,70,70)
    statusLabels.Stats.Text = "Stats: " .. (isStating and "ON" or "OFF")
    statusLabels.Stats.TextColor3 = isStating and Color3.fromRGB(50,220,80) or Color3.fromRGB(220,70,70)
    statusLabels.Weapon.Text = "Weapon: " .. SELECTED_WEAPON
    statusLabels.Island.Text = "Island: " .. SELECTED_ISLAND
    statusLabels.Pos.Text = "Pos: " .. (savedPosition and "Saved" or "None")
    statusLabels.BossStatus.Text = "Boss: " .. (bossModeActive and "Active" or "Idle")
    statusLabels.Runtime.Text = "Runtime: " .. os.date("!%H:%M:%S", runtimeSeconds)
    statusLabels.Mode.Text = "Mode: " .. currentMode
end

-- ================================================================
-- SCROLL CONTAINER FOR SECTIONS
-- ================================================================
local ScrollContainer = Instance.new("ScrollingFrame", MainFrame)
ScrollContainer.Size = UDim2.new(1, 0, 0, 310)
ScrollContainer.Position = UDim2.new(0, 0, 0, 200)
ScrollContainer.BackgroundTransparency = 1
ScrollContainer.BorderSizePixel = 0
ScrollContainer.ScrollBarThickness = 4
ScrollContainer.CanvasSize = UDim2.new(0, 0, 0, 530)

-- ================================================================
-- HELPER: CREATE SECTION
-- ================================================================
local function createSection(parent, title, yPos, height)
    local section = Instance.new("Frame", parent)
    section.Size = UDim2.new(0.9, 0, 0, height)
    section.Position = UDim2.new(0.05, 0, 0, yPos)
    section.BackgroundTransparency = 1

    local titleLabel = Instance.new("TextLabel", section)
    titleLabel.Size = UDim2.new(1, 0, 0, 20)
    titleLabel.BackgroundTransparency = 1
    titleLabel.Text = title
    titleLabel.TextColor3 = Color3.fromRGB(200,200,200)
    titleLabel.Font = Enum.Font.GothamBold
    titleLabel.TextSize = 14
    titleLabel.TextXAlignment = Enum.TextXAlignment.Left

    local content = Instance.new("Frame", section)
    content.Size = UDim2.new(1, 0, 0, height - 25)
    content.Position = UDim2.new(0, 0, 0, 22)
    content.BackgroundTransparency = 1

    return content
end

-- ================================================================
-- HELPER: CREATE TOGGLE BUTTON
-- ================================================================
local colorOn = Color3.fromRGB(50,180,80)
local colorOff = Color3.fromRGB(180,50,50)
local colorBoss = Color3.fromRGB(140,60,200)

local function createToggle(parent, text, xPos, yPos, getter, setter, colorOnVal, colorOffVal)
    colorOnVal = colorOnVal or colorOn
    colorOffVal = colorOffVal or colorOff
    
    local frame = Instance.new("Frame", parent)
    frame.Size = UDim2.new(0.45, 0, 0, 30)
    frame.Position = UDim2.new(xPos or 0, 0, 0, yPos or 0)
    frame.BackgroundTransparency = 1

    local btn = Instance.new("TextButton", frame)
    btn.Size = UDim2.new(0.5, 0, 1, 0)
    btn.BackgroundColor3 = getter() and colorOnVal or colorOffVal
    btn.Text = getter() and "ON" or "OFF"
    btn.TextColor3 = Color3.fromRGB(255,255,255)
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 12
    applyCorner(btn, 6)

    local label = Instance.new("TextLabel", frame)
    label.Size = UDim2.new(0.5, 0, 1, 0)
    label.Position = UDim2.new(0.5, 5, 0, 0)
    label.BackgroundTransparency = 1
    label.Text = text
    label.TextColor3 = Color3.fromRGB(200,200,200)
    label.Font = Enum.Font.GothamSemibold
    label.TextSize = 12
    label.TextXAlignment = Enum.TextXAlignment.Left

    btn.MouseButton1Click:Connect(function()
        local newState = not getter()
        setter(newState)
        btn.BackgroundColor3 = newState and colorOnVal or colorOffVal
        btn.Text = newState and "ON" or "OFF"
        UpdateStatus()
    end)
    return btn
end

-- ================================================================
-- SECTION: FARMING
-- ================================================================
local farmSection = createSection(ScrollContainer, "⚔ Farming", 0, 70)
createToggle(farmSection, "Farm", 0, 0, function() return isFarming end, function(v) isFarming = v end, colorOn, colorOff)
createToggle(farmSection, "Boss", 0.5, 0, function() return isBossing end, function(v) isBossing = v end, colorBoss, colorOff)

-- ================================================================
-- SECTION: STATS
-- ================================================================
local statsSection = createSection(ScrollContainer, "📈 Stats", 80, 70)
createToggle(statsSection, "Stats", 0, 0, function() return isStating end, function(v) isStating = v end, colorOn, colorOff)

-- Stat dropdown button
local statDropdownBtn = Instance.new("TextButton", statsSection)
statDropdownBtn.Size = UDim2.new(0.45, 0, 0, 30)
statDropdownBtn.Position = UDim2.new(0.5, 0, 0, 0)
statDropdownBtn.BackgroundColor3 = Color3.fromRGB(50,50,55)
statDropdownBtn.Text = "Target: " .. TARGET_STAT .. " ▼"
statDropdownBtn.TextColor3 = Color3.fromRGB(255,255,255)
statDropdownBtn.Font = Enum.Font.GothamSemibold
statDropdownBtn.TextSize = 12
applyCorner(statDropdownBtn, 6)

-- Stat dropdown list
local statListFrame = Instance.new("Frame", statsSection)
statListFrame.Size = UDim2.new(0.45, 0, 0, #STAT_LIST * 25)
statListFrame.Position = UDim2.new(0.5, 0, 0, 30)
statListFrame.BackgroundColor3 = Color3.fromRGB(40,40,45)
statListFrame.Visible = false
applyCorner(statListFrame, 6)
local layoutStat = Instance.new("UIListLayout", statListFrame)
for _, stat in ipairs(STAT_LIST) do
    local btn = Instance.new("TextButton", statListFrame)
    btn.Size = UDim2.new(1, 0, 0, 25)
    btn.BackgroundTransparency = 1
    btn.Text = stat
    btn.TextColor3 = Color3.fromRGB(220,220,220)
    btn.Font = Enum.Font.GothamSemibold
    btn.TextSize = 12
    btn.MouseButton1Click:Connect(function()
        TARGET_STAT = stat
        statDropdownBtn.Text = "Target: " .. TARGET_STAT .. " ▼"
        statListFrame.Visible = false
        UpdateStatus()
    end)
end
statDropdownBtn.MouseButton1Click:Connect(function()
    statListFrame.Visible = not statListFrame.Visible
end)

-- ================================================================
-- SECTION: COMBAT (Weapon)
-- ================================================================
local combatSection = createSection(ScrollContainer, "⚔ Combat", 160, 70)
local weaponDropdownBtn = Instance.new("TextButton", combatSection)
weaponDropdownBtn.Size = UDim2.new(0.9, 0, 0, 30)
weaponDropdownBtn.Position = UDim2.new(0.05, 0, 0, 0)
weaponDropdownBtn.BackgroundColor3 = Color3.fromRGB(50,50,55)
weaponDropdownBtn.Text = "Weapon: " .. SELECTED_WEAPON .. " ▼"
weaponDropdownBtn.TextColor3 = Color3.fromRGB(255,255,255)
weaponDropdownBtn.Font = Enum.Font.GothamSemibold
weaponDropdownBtn.TextSize = 12
applyCorner(weaponDropdownBtn, 6)

local weaponScroll = Instance.new("ScrollingFrame", combatSection)
weaponScroll.Size = UDim2.new(0.9, 0, 0, 100)
weaponScroll.Position = UDim2.new(0.05, 0, 0, 35)
weaponScroll.BackgroundColor3 = Color3.fromRGB(40,40,45)
weaponScroll.BorderSizePixel = 0
weaponScroll.ScrollBarThickness = 4
weaponScroll.Visible = false
applyCorner(weaponScroll, 6)
local weaponLayout = Instance.new("UIListLayout", weaponScroll)

local function refreshWeaponList()
    for _, child in ipairs(weaponScroll:GetChildren()) do
        if child:IsA("TextButton") then child:Destroy() end
    end
    local weaponList = {"None/Melee"}
    local backpack = LocalPlayer:FindFirstChild("Backpack")
    if backpack then
        for _, item in ipairs(backpack:GetChildren()) do
            if item:IsA("Tool") then table.insert(weaponList, item.Name) end
        end
    end
    local char = LocalPlayer.Character
    if char then
        for _, item in ipairs(char:GetChildren()) do
            if item:IsA("Tool") then table.insert(weaponList, item.Name) end
        end
    end
    weaponScroll.CanvasSize = UDim2.new(0, 0, 0, #weaponList * 25)
    for _, wName in ipairs(weaponList) do
        local btn = Instance.new("TextButton", weaponScroll)
        btn.Size = UDim2.new(1, 0, 0, 25)
        btn.BackgroundTransparency = 1
        btn.Text = wName
        btn.TextColor3 = Color3.fromRGB(220,220,220)
        btn.Font = Enum.Font.GothamSemibold
        btn.TextSize = 12
        btn.MouseButton1Click:Connect(function()
            SELECTED_WEAPON = wName
            weaponDropdownBtn.Text = "Weapon: " .. SELECTED_WEAPON .. " ▼"
            weaponScroll.Visible = false
            UpdateStatus()
        end)
    end
end
refreshWeaponList()

weaponDropdownBtn.MouseButton1Click:Connect(function()
    if weaponScroll.Visible then
        weaponScroll.Visible = false
    else
        refreshWeaponList()
        weaponScroll.Visible = true
    end
    statListFrame.Visible = false
end)

-- ================================================================
-- SECTION: POSITION (COMPLETE REWRITE - WORKING)
-- ================================================================
local posSection = createSection(ScrollContainer, "📍 Position", 240, 110)

-- Save button
local savePosBtn = Instance.new("TextButton", posSection)
savePosBtn.Size = UDim2.new(0.28, 0, 0, 30)
savePosBtn.Position = UDim2.new(0.05, 0, 0, 0)
savePosBtn.BackgroundColor3 = Color3.fromRGB(40,120,200)
savePosBtn.Text = "Save Pos"
savePosBtn.TextColor3 = Color3.fromRGB(255,255,255)
savePosBtn.Font = Enum.Font.GothamSemibold
savePosBtn.TextSize = 12
applyCorner(savePosBtn, 6)
savePosBtn.MouseButton1Click:Connect(function()
    print("Save Pos button clicked!")
    SavePosition()
end)

-- Return button
local returnPosBtn = Instance.new("TextButton", posSection)
returnPosBtn.Size = UDim2.new(0.28, 0, 0, 30)
returnPosBtn.Position = UDim2.new(0.37, 0, 0, 0)
returnPosBtn.BackgroundColor3 = Color3.fromRGB(200,120,40)
returnPosBtn.Text = "Return"
returnPosBtn.TextColor3 = Color3.fromRGB(255,255,255)
returnPosBtn.Font = Enum.Font.GothamSemibold
returnPosBtn.TextSize = 12
applyCorner(returnPosBtn, 6)
returnPosBtn.MouseButton1Click:Connect(function()
    print("Return button clicked!")
    ReturnPosition()
end)

-- Auto Return toggle
local function createSmallToggle(parent, text, xPos, yPos, getter, setter)
    local frame = Instance.new("Frame", parent)
    frame.Size = UDim2.new(0.28, 0, 0, 25)
    frame.Position = UDim2.new(xPos or 0, 0, 0, yPos or 35)
    frame.BackgroundTransparency = 1

    local btn = Instance.new("TextButton", frame)
    btn.Size = UDim2.new(0.5, 0, 1, 0)
    btn.BackgroundColor3 = getter() and colorOn or colorOff
    btn.Text = getter() and "ON" or "OFF"
    btn.TextColor3 = Color3.fromRGB(255,255,255)
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 10
    applyCorner(btn, 4)

    local label = Instance.new("TextLabel", frame)
    label.Size = UDim2.new(0.5, 0, 1, 0)
    label.Position = UDim2.new(0.5, 2, 0, 0)
    label.BackgroundTransparency = 1
    label.Text = text
    label.TextColor3 = Color3.fromRGB(200,200,200)
    label.Font = Enum.Font.GothamSemibold
    label.TextSize = 11
    label.TextXAlignment = Enum.TextXAlignment.Left

    btn.MouseButton1Click:Connect(function()
        local newState = not getter()
        setter(newState)
        btn.BackgroundColor3 = newState and colorOn or colorOff
        btn.Text = newState and "ON" or "OFF"
        UpdateStatus()
        print(text .. " toggled to: " .. tostring(newState))
    end)
    return btn
end

createSmallToggle(posSection, "Auto Return", 0.05, 35, function() return autoReturnEnabled end, function(v) autoReturnEnabled = v end)
createSmallToggle(posSection, "Auto Save", 0.37, 35, function() return autoSaveEnabled end, function(v) autoSaveEnabled = v end)

-- ================================================================
-- SECTION: TELEPORT
-- ================================================================
local teleportSection = createSection(ScrollContainer, "🌍 Teleport", 360, 90)

local islandDropdownBtn = Instance.new("TextButton", teleportSection)
islandDropdownBtn.Size = UDim2.new(0.7, 0, 0, 30)
islandDropdownBtn.Position = UDim2.new(0.05, 0, 0, 0)
islandDropdownBtn.BackgroundColor3 = Color3.fromRGB(50,50,55)
islandDropdownBtn.Text = "Island: " .. SELECTED_ISLAND .. " ▼"
islandDropdownBtn.TextColor3 = Color3.fromRGB(255,255,255)
islandDropdownBtn.Font = Enum.Font.GothamSemibold
islandDropdownBtn.TextSize = 12
applyCorner(islandDropdownBtn, 6)

local islandScroll = Instance.new("ScrollingFrame", teleportSection)
islandScroll.Size = UDim2.new(0.7, 0, 0, 80)
islandScroll.Position = UDim2.new(0.05, 0, 0, 35)
islandScroll.BackgroundColor3 = Color3.fromRGB(40,40,45)
islandScroll.BorderSizePixel = 0
islandScroll.ScrollBarThickness = 4
islandScroll.Visible = false
applyCorner(islandScroll, 6)
local islandLayout = Instance.new("UIListLayout", islandScroll)
islandScroll.CanvasSize = UDim2.new(0, 0, 0, #islandList * 25)
for _, iName in ipairs(islandList) do
    local btn = Instance.new("TextButton", islandScroll)
    btn.Size = UDim2.new(1, 0, 0, 25)
    btn.BackgroundTransparency = 1
    btn.Text = iName
    btn.TextColor3 = Color3.fromRGB(220,220,220)
    btn.Font = Enum.Font.GothamSemibold
    btn.TextSize = 12
    btn.MouseButton1Click:Connect(function()
        SELECTED_ISLAND = iName
        islandDropdownBtn.Text = "Island: " .. SELECTED_ISLAND .. " ▼"
        islandScroll.Visible = false
        UpdateStatus()
    end)
end
islandDropdownBtn.MouseButton1Click:Connect(function()
    islandScroll.Visible = not islandScroll.Visible
    statListFrame.Visible = false
    weaponScroll.Visible = false
end)

local teleportBtn = Instance.new("TextButton", teleportSection)
teleportBtn.Size = UDim2.new(0.2, 0, 0, 30)
teleportBtn.Position = UDim2.new(0.77, 0, 0, 0)
teleportBtn.BackgroundColor3 = Color3.fromRGB(40,120,200)
teleportBtn.Text = "TP"
teleportBtn.TextColor3 = Color3.fromRGB(255,255,255)
teleportBtn.Font = Enum.Font.GothamBold
teleportBtn.TextSize = 12
applyCorner(teleportBtn, 6)
teleportBtn.MouseButton1Click:Connect(function()
    if SELECTED_ISLAND ~= "None" then
        local islandData = IslandsConfig[SELECTED_ISLAND]
        if islandData and islandData.PortalId then
            pcall(function()
                TeleportToPortal:FireServer(islandData.PortalId)
                ShowNotification("Teleporting to " .. SELECTED_ISLAND, true)
            end)
        end
    end
end)

-- ================================================================
-- SECTION: UTILITIES
-- ================================================================
local utilSection = createSection(ScrollContainer, "⚙ Utilities", 460, 60)

local unloadBtn = Instance.new("TextButton", utilSection)
unloadBtn.Size = UDim2.new(0.45, 0, 0, 30)
unloadBtn.Position = UDim2.new(0.05, 0, 0, 0)
unloadBtn.BackgroundColor3 = Color3.fromRGB(60,60,65)
unloadBtn.Text = "Unload Hub"
unloadBtn.TextColor3 = Color3.fromRGB(255,100,100)
unloadBtn.Font = Enum.Font.GothamBold
unloadBtn.TextSize = 14
applyCorner(unloadBtn, 6)
unloadBtn.MouseButton1Click:Connect(function()
    scriptRunning = false
    isFarming = false
    isStating = false
    isBossing = false
    ScreenGui:Destroy()
    ShowNotification("Hub unloaded", false)
end)

local compactBtn = Instance.new("TextButton", utilSection)
compactBtn.Size = UDim2.new(0.45, 0, 0, 30)
compactBtn.Position = UDim2.new(0.5, 0, 0, 0)
compactBtn.BackgroundColor3 = Color3.fromRGB(50,50,55)
compactBtn.Text = "Compact"
compactBtn.TextColor3 = Color3.fromRGB(255,255,255)
compactBtn.Font = Enum.Font.GothamBold
compactBtn.TextSize = 14
applyCorner(compactBtn, 6)
compactBtn.MouseButton1Click:Connect(function()
    local visible = ScrollContainer.Visible
    ScrollContainer.Visible = not visible
    StatusFrame.Visible = not visible
    if not visible then
        MainFrame.Size = UDim2.new(0, 320, 0, 200)
    else
        MainFrame.Size = UDim2.new(0, 320, 0, 520)
    end
end)

-- ================================================================
-- FLOATING TOGGLE BUTTON
-- ================================================================
local ToggleButton = Instance.new("TextButton")
ToggleButton.Size = UDim2.new(0, 50, 0, 50)
ToggleButton.Position = UDim2.new(1, -65, 0.5, -25)
ToggleButton.BackgroundColor3 = Color3.fromRGB(30,30,35)
ToggleButton.Text = "⚙"
ToggleButton.TextColor3 = Color3.fromRGB(255,255,255)
ToggleButton.Font = Enum.Font.GothamBold
ToggleButton.TextSize = 28
ToggleButton.Active = true
ToggleButton.Parent = ScreenGui
applyCorner(ToggleButton, 12)
makeDraggable(ToggleButton)

local ToggleStroke = Instance.new("UIStroke", ToggleButton)
ToggleStroke.Color = Color3.fromRGB(100,100,255)
ToggleStroke.Thickness = 2

ToggleButton.MouseButton1Click:Connect(function()
    MainFrame.Visible = not MainFrame.Visible
    ToggleButton.BackgroundColor3 = MainFrame.Visible and Color3.fromRGB(50,50,60) or Color3.fromRGB(30,30,35)
    if MainFrame.Visible then
        UpdateStatus()
    end
end)

-- Initial update
UpdateStatus()

-- ================================================================
-- PART 3 - HELPER FUNCTIONS (COMPLETE REWRITE)
-- ================================================================

-- Get character
local function GetCharacter()
    local char = Workspace:FindFirstChild("Characters") and Workspace.Characters:FindFirstChild(LocalPlayer.Name)
    if not char then
        char = LocalPlayer.Character
    end
    return char
end

local function GetHumanoid(char)
    if not char then return nil end
    return char:FindFirstChild("Humanoid")
end

local function GetRootPart(char)
    if not char then return nil end
    return char:FindFirstChild("HumanoidRootPart")
end

-- Tween to a CFrame
local function TweenTo(part, targetCFrame, speed)
    if not part then return end
    local distance = (targetCFrame.Position - part.Position).Magnitude
    local duration = math.max(distance / (speed or 250), 0.1)
    local tween = TweenService:Create(part, TweenInfo.new(duration, Enum.EasingStyle.Linear), {CFrame = targetCFrame})
    tween:Play()
    return tween
end

-- Equip weapon
local function EquipWeapon(character)
    if SELECTED_WEAPON == "None/Melee" then
        local humanoid = GetHumanoid(character)
        if humanoid then humanoid:UnequipTools() end
        return nil
    end

    -- Check if already equipped
    local equipped = character:FindFirstChild(SELECTED_WEAPON)
    if equipped and equipped:IsA("Tool") then return equipped end

    -- Find in backpack
    local backpack = LocalPlayer:FindFirstChild("Backpack")
    if backpack then
        local stored = backpack:FindFirstChild(SELECTED_WEAPON)
        if stored and stored:IsA("Tool") then
            local humanoid = GetHumanoid(character)
            if humanoid then
                humanoid:EquipTool(stored)
                return stored
            end
        end
    end
    return nil
end

-- Attack enemy
local function AttackEnemy(character)
    local weapon = EquipWeapon(character)
    if weapon then
        weapon:Activate()
        return
    end
    
    pcall(function()
        VirtualInputManager:SendMouseButtonEvent(0, 0, 0, true, game, 1)
        task.wait(0.05)
        VirtualInputManager:SendMouseButtonEvent(0, 0, 0, false, game, 1)
    end)
end

-- ================================================================
-- POSITION SYSTEM (COMPLETE REWRITE - WORKING)
-- ================================================================

-- Save position function
local function SavePosition()
    print("Attempting to save position...")
    local char = GetCharacter()
    if not char then
        ShowNotification("❌ Character not found!", false)
        print("❌ Character not found!")
        return false
    end
    
    local hrp = GetRootPart(char)
    if not hrp then
        ShowNotification("❌ HumanoidRootPart not found!", false)
        print("❌ HumanoidRootPart not found!")
        return false
    end
    
    savedPosition = hrp.CFrame
    ShowNotification("✔ Position saved at: " .. tostring(savedPosition.Position), true)
    print("✔ Position saved at: " .. tostring(savedPosition.Position))
    UpdateStatus()
    return true
end

-- Return to saved position function
local function ReturnPosition()
    print("Attempting to return to saved position...")
    if not savedPosition then
        ShowNotification("❌ No saved position! Click 'Save Pos' first.", false)
        print("❌ No saved position!")
        return
    end
    
    local char = GetCharacter()
    if not char then
        ShowNotification("❌ Character not found!", false)
        return
    end
    
    local hrp = GetRootPart(char)
    if not hrp then
        ShowNotification("❌ HumanoidRootPart not found!", false)
        return
    end
    
    print("Returning to: " .. tostring(savedPosition.Position))
    TweenTo(hrp, savedPosition, 200)
    ShowNotification("↩ Returning to saved position!", true)
end
-- ================================================================
-- PART 4 - AUTO FARM (FULLY FIXED)
-- ================================================================

task.spawn(function()
    while scriptRunning do
        task.wait(0.3)
        
        -- Skip if farm is off or paused
        if not isFarming or farmPaused then
            task.wait(0.5)
            continue
        end

        currentMode = "Farming"
        local char = GetCharacter()
        if not char then 
            task.wait(1)
            continue 
        end

        local myHRP = GetRootPart(char)
        local myHumanoid = GetHumanoid(char)
        if not myHRP or not myHumanoid or myHumanoid.Health <= 0 then 
            task.wait(1)
            continue 
        end

        local enemiesFolder = Workspace:FindFirstChild("Enemies")
        if not enemiesFolder then 
            task.wait(1)
            continue 
        end

        local foundEnemy = false
        for _, enemy in ipairs(enemiesFolder:GetChildren()) do
            if not isFarming or farmPaused or not scriptRunning or myHumanoid.Health <= 0 then 
                break 
            end

            if enemy:IsA("Model") and enemy.Name ~= "R6" then
                local enemyHRP = enemy:FindFirstChild("HumanoidRootPart")
                local enemyHum = enemy:FindFirstChild("Humanoid")
                
                if enemyHRP and enemyHum and enemyHum.Health > 0 then
                    local distance = (enemyHRP.Position - myHRP.Position).Magnitude
                    if distance <= MAX_FARM_DISTANCE then
                        foundEnemy = true
                        
                        -- Noclip
                        local noclipConn
                        noclipConn = RunService.RenderStepped:Connect(function()
                            if char and char.Parent then
                                for _, part in ipairs(char:GetDescendants()) do
                                    if part:IsA("BasePart") then
                                        part.CanCollide = false
                                    end
                                end
                            end
                        end)

                        local lastAttack = 0
                        local attackCooldown = 0.1
                        
                        while enemy:IsDescendantOf(Workspace) and enemyHRP:IsDescendantOf(Workspace) 
                              and enemyHum.Health > 0 and myHumanoid.Health > 0 
                              and isFarming and not farmPaused and scriptRunning do 
                            
                            if not myHRP or not myHRP.Parent then break end
                            
                            -- Move to enemy
                            myHRP.CFrame = enemyHRP.CFrame * CFrame.new(0, 0, 1.5)
                            
                            -- Attack
                            if os.clock() - lastAttack >= attackCooldown then
                                lastAttack = os.clock()
                                AttackEnemy(char)
                            end
                            task.wait()
                        end
                        
                        if noclipConn then noclipConn:Disconnect() end
                        if myHumanoid.Health <= 0 then break end
                    end
                end
            end
        end
        
        -- If no enemy found, wait a bit
        if not foundEnemy then
            task.wait(0.5)
        end
    end
end)

-- ================================================================
-- PART 5 - AUTO STATS
-- ================================================================

task.spawn(function()
    while scriptRunning do
        task.wait(0.5)
        if isStating then
            local gameGlobals = getrenv()._G
            if gameGlobals and gameGlobals.InputFunction then
                pcall(function()
                    gameGlobals.InputFunction:InvokeServer("AddPoint", TARGET_STAT, STAT_POINTS_PER_TICK)
                end)
            end
        end
    end
end)

-- ================================================================
-- PART 6 - AUTO BOSS (FIXED - NO POSITION INTERFERENCE)
-- ================================================================

-- Helper: Go to boss and fight
local function GoToBoss(bossIndicator, bossName)
    local char = GetCharacter()
    if not char then return end
    local myHRP = GetRootPart(char)
    local myHumanoid = GetHumanoid(char)
    if not myHRP or not myHumanoid or myHumanoid.Health <= 0 then return end

    local bossPos = bossIndicator.Position
    local distance = (bossPos - myHRP.Position).Magnitude

    -- If too far, teleport to nearest island
    if distance > 1000 then
        local nearestIsland = nil
        local shortest = math.huge
        for iName, iPos in pairs(ISLAND_COORDS) do
            local d = (bossPos - iPos).Magnitude
            if d < shortest then
                shortest = d
                nearestIsland = iName
            end
        end
        if nearestIsland then
            local islandData = IslandsConfig[nearestIsland]
            if not islandData then
                for k, v in pairs(IslandsConfig) do
                    if string.find(string.lower(k), string.lower(nearestIsland)) then
                        islandData = v
                        break
                    end
                end
            end
            if islandData and islandData.PortalId then
                pcall(function()
                    TeleportToPortal:FireServer(islandData.PortalId)
                    ShowNotification("Teleporting to " .. nearestIsland, true)
                end)
                task.wait(3)
            end
        end
    end

    -- Update position after teleport
    char = GetCharacter()
    if not char then return end
    myHRP = GetRootPart(char)
    myHumanoid = GetHumanoid(char)
    if not myHRP or not myHumanoid or myHumanoid.Health <= 0 then return end

    -- Fly to boss if still far
    distance = (bossIndicator.Position - myHRP.Position).Magnitude
    if distance > 30 then
        TweenTo(myHRP, bossIndicator.CFrame, BOSS_FLY_SPEED)
        local timeout = 0
        while distance > 30 and isBossing and myHumanoid.Health > 0 and scriptRunning and timeout < 30 do
            task.wait(0.2)
            distance = (bossIndicator.Position - myHRP.Position).Magnitude
            timeout = timeout + 0.2
        end
    end

    -- Now fight the real boss
    local enemiesFolder = Workspace:FindFirstChild("Enemies")
    if not enemiesFolder then return end
    local realBoss = enemiesFolder:FindFirstChild(bossName)
    if not realBoss then return end

    local bossHRP = realBoss:FindFirstChild("HumanoidRootPart")
    local bossHum = realBoss:FindFirstChild("Humanoid")
    if not bossHRP or not bossHum or bossHum.Health <= 0 then return end

    -- Noclip during fight
    local noclipConn = RunService.RenderStepped:Connect(function()
        if char and char.Parent then
            for _, part in ipairs(char:GetDescendants()) do
                if part:IsA("BasePart") then
                    part.CanCollide = false
                end
            end
        end
    end)

    local lastAttack = 0
    local attackCooldown = 0.1
    
    while realBoss:IsDescendantOf(Workspace) and bossHRP:IsDescendantOf(Workspace)
          and bossHum.Health > 0 and myHumanoid.Health > 0
          and isBossing and scriptRunning do
        if not myHRP or not myHRP.Parent then break end
        
        myHRP.CFrame = bossHRP.CFrame * CFrame.new(0, 0, 1.5)
        
        if os.clock() - lastAttack >= attackCooldown then
            lastAttack = os.clock()
            AttackEnemy(char)
        end
        task.wait()
    end

    if noclipConn then noclipConn:Disconnect() end
    
    if bossHum and bossHum.Health <= 0 then
        bossKills = bossKills + 1
        ShowNotification("💀 Boss defeated!", true)
        UpdateStatus()
    end
end

-- Boss detection thread (DOES NOT TOUCH POSITION)
task.spawn(function()
    while scriptRunning do
        task.wait(1)
        
        if not isBossing then
            if farmPaused then
                farmPaused = false
                bossModeActive = false
                currentMode = isFarming and "Farming" or "Idle"
                UpdateStatus()
            end
            continue
        end

        -- Detect boss indicator
        local bossIndicator = nil
        local bossName = ""
        for _, obj in ipairs(Workspace:GetChildren()) do
            if string.match(obj.Name, "^BossIndicator_Shared_") then
                bossIndicator = obj
                bossName = string.gsub(obj.Name, "BossIndicator_Shared_", "")
                break
            end
        end

        if bossIndicator and isBossing and not farmPaused and not bossModeActive then
            ShowNotification("⚠ Boss spawned! Pausing farm.", false)
            
            -- ONLY pause farm - NO POSITION SAVING
            farmPaused = true
            bossModeActive = true
            currentMode = "Boss Mode"
            UpdateStatus()
            
            -- Go to boss and fight
            GoToBoss(bossIndicator, bossName)
            
            -- Resume farming - NO AUTO RETURN
            farmPaused = false
            bossModeActive = false
            currentMode = isFarming and "Farming" or "Idle"
            UpdateStatus()
            ShowNotification("✅ Boss fight ended, farm resumed", true)
        end
    end
end)

-- ================================================================
-- PART 7 - POSITION SYSTEM THREADS (WORKING)
-- ================================================================

-- Auto save thread
task.spawn(function()
    while scriptRunning do
        task.wait(5)
        if autoSaveEnabled then
            local char = GetCharacter()
            if char then
                local hrp = GetRootPart(char)
                if hrp then
                    savedPosition = hrp.CFrame
                    -- Silent update, no notification
                end
            end
        end
    end
end)

-- Auto return thread
task.spawn(function()
    while scriptRunning do
        task.wait(2)
        if autoReturnEnabled and savedPosition then
            local char = GetCharacter()
            if char then
                local hrp = GetRootPart(char)
                if hrp then
                    local dist = (savedPosition.Position - hrp.Position).Magnitude
                    if dist > 50 then
                        ReturnPosition()
                    end
                end
            end
        end
    end
end)

-- ================================================================
-- PART 8 - RUNTIME STATISTICS
-- ================================================================

task.spawn(function()
    while scriptRunning do
        task.wait(1)
        runtimeSeconds = runtimeSeconds + 1
        UpdateStatus()
    end
end)

-- ================================================================
-- PART 9 - ENEMY KILL DETECTION
-- ================================================================

local function onEnemyAdded(enemy)
    if enemy:IsA("Model") and enemy:FindFirstChild("Humanoid") then
        local hum = enemy:FindFirstChild("Humanoid")
        hum.Died:Connect(function()
            enemyKills = enemyKills + 1
            UpdateStatus()
        end)
    end
end

local enemiesFolder = Workspace:FindFirstChild("Enemies")
if enemiesFolder then
    for _, enemy in ipairs(enemiesFolder:GetChildren()) do
        onEnemyAdded(enemy)
    end
    enemiesFolder.ChildAdded:Connect(onEnemyAdded)
end

Workspace.ChildAdded:Connect(function(child)
    if child.Name == "Enemies" then
        child.ChildAdded:Connect(onEnemyAdded)
        for _, enemy in ipairs(child:GetChildren()) do
            onEnemyAdded(enemy)
        end
    end
end)

-- ================================================================
-- FINAL STATUS UPDATE
-- ================================================================
UpdateStatus()
ShowNotification("✅ Legacy Admin Hub V2 Loaded!", true, 2)
