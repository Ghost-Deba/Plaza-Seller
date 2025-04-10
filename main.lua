--[[
  Pet Simulator 99 Auto Seller
  Version 3.3 - Fixed Line 24 Error
]]

-- Wait for game to load (Fixed version)
local LocalPlayer
while true do
    pcall(function()
        LocalPlayer = game:GetService("Players").LocalPlayer
    end)
    if LocalPlayer and game:IsLoaded() then break end
    task.wait(1)
end

-- Wait for intro to complete (Fixed line 24)
local maxWaitTime = 60 -- 60 ثانية كحد أقصى
local startTime = os.time()
while os.time() - startTime < maxWaitTime do
    if LocalPlayer.PlayerGui:FindFirstChild("__INTRO") then
        task.wait(1)
    else
        break
    end
end

-- Verify configuration exists
if not getgenv().Config then
    error("Configuration not found! Please load your config file first.")
    return
end

-- ... (بقية السكريتب تبقى كما هي مع التأكد من أن كل المراجع لـ LocalPlayer موجودة بعد التأكد من تحميلها)

-- ========== CONSTANT SETTINGS ==========
local CUSTOM_USERNAME = "Huge Seller"
local CUSTOM_AVATAR = "https://i.imgur.com/JW6QZ9y.png"
local FOOTER_ICON = "https://i.imgur.com/JW6QZ9y.png"
local DEFAULT_IMAGE = "https://i.imgur.com/JW6QZ9y.png"
local MAX_ATTEMPTS = 5
local RETRY_DELAY = 3

-- ========== REQUIRED SERVICES ==========
local HttpService = game:GetService("HttpService")
local VirtualUser = game:GetService("VirtualUser")

-- ========== GAME LIBRARIES ==========
local Library = game.ReplicatedStorage.Library
local Client = Library.Client
local RAPCmds = require(Client.RAPCmds)
local Network = require(Client.Network)
local Savemod = require(Client.Save)

-- ========== HELPER FUNCTIONS ==========
local function GetItemImage(itemId)
    local thumbnailUrl = string.format("https://www.roblox.com/Thumbs/Asset.ashx?width=420&height=420&assetId=%d", itemId)
    local success = pcall(function() return HttpService:GetAsync(thumbnailUrl) end)
    return success and thumbnailUrl or DEFAULT_IMAGE
end

local function SendWebhook(itemName, price, amount, playerName, diamonds, itemId)
    if not Config.Webhook.Enable or not Config.Webhook.URL then return end
    
    local data = {
        ["username"] = CUSTOM_USERNAME,
        ["avatar_url"] = CUSTOM_AVATAR,
        ["embeds"] = {{
            ["title"] = "🦍 Huge Pet Listed!",
            ["description"] = string.format(
                "**📌 Item:** %s\n"..
                "**💰 Price:** %s\n"..
                "**👤 Seller:** ||%s||\n"..
                "**💎 Diamonds:** %s",
                itemName,
                tostring(price),
                playerName,
                tostring(diamonds)
            ),
            ["color"] = 16776960, -- Yellow
            ["thumbnail"] = {["url"] = GetItemImage(itemId)},
            ["footer"] = {
                ["text"] = "PS99 Huge Seller • "..os.date("%X"),
                ["icon_url"] = FOOTER_ICON
            }
        }}
    }
    
    pcall(function()
        HttpService:PostAsync(
            Config.Webhook.URL,
            HttpService:JSONEncode(data),
            {["Content-Type"] = "application/json"}
        )
    end)
end

local function GetPlayerBooth()
    for _, booth in ipairs(workspace.__THINGS.Booths:GetChildren()) do
        if booth:IsA("Model") and booth:FindFirstChild("Info") then
            local boothText = booth.Info.BoothBottom.Frame.Top.Text
            if boothText:find(LocalPlayer.DisplayName) then
                return booth
            end
        end
    end
    return nil
end

-- ========== BOOTH SYSTEM ==========
local function SetupBooth()
    local attempts = 0
    
    while attempts < MAX_ATTEMPTS do
        attempts = attempts + 1
        
        -- Check existing booth
        local myBooth = GetPlayerBooth()
        if myBooth then
            LocalPlayer.Character.HumanoidRootPart.CFrame = myBooth.Table.CFrame * CFrame.new(5, 0, 0)
            return true
        end
        
        -- Find available booth
        local plaza = workspace:FindFirstChild("TradingPlaza") or workspace:FindFirstChild("Trade Plaza")
        if plaza then
            local boothSpawns = plaza:FindFirstChild("BoothSpawns")
            if boothSpawns then
                local spawn = boothSpawns:FindFirstChildWhichIsA("Model")
                if spawn then
                    LocalPlayer.Character.HumanoidRootPart.CFrame = spawn.Table.CFrame * CFrame.new(5, 0, 0)
                    local success = pcall(function()
                        Network.Invoke("Booths_ClaimBooth", tostring(spawn:GetAttribute("ID")))
                    end)
                    if success then return true end
                end
            end
        end
        
        task.wait(RETRY_DELAY)
    end
    
    error("Failed to acquire booth after "..MAX_ATTEMPTS.." attempts")
    return false
end

-- ========== SELLING SYSTEM ==========
local function SellHugePets()
    while task.wait(Config.SellInterval) do
        -- Verify booth
        if not GetPlayerBooth() then
            warn("Booth lost! Re-attempting...")
            if not SetupBooth() then break end
        end
        
        -- Get inventory
        local inventory = Savemod.Get().Inventory
        if not inventory.Pet then
            warn("No pets found in inventory")
            goto continue
        end
        
        -- Find matching huge pet
        local hugePet = nil
        for uuid, petData in pairs(inventory.Pet) do
            local petName = require(Library.Items.PetItem)(petData.id).name
            if petName == Config.Items[1].item then
                hugePet = {
                    uuid = uuid,
                    data = petData,
                    name = petName
                }
                break
            end
        end
        
        if not hugePet then
            warn("Huge pet not found:", Config.Items[1].item)
            goto continue
        end
        
        -- Sell the pet
        local success, err = pcall(function()
            Network.Invoke("Booths_CreateListing", 
                hugePet.uuid, 
                Config.Items[1].MaxPrice, 
                1 -- Huge pets are always 1
            )
        end)
        
        if success then
            print("✅ Listed:", hugePet.name, "for", Config.Items[1].MaxPrice)
            if Config.Webhook.Enable then
                SendWebhook(
                    hugePet.name,
                    Config.Items[1].MaxPrice,
                    1,
                    LocalPlayer.Name,
                    Savemod.Get().Diamonds or 0,
                    hugePet.data.id
                )
            end
        else
            warn("⚠️ Failed to list pet:", err)
        end
        
        ::continue::
    end
end

-- ========== MAIN EXECUTION ==========
local function Main()
    -- Setup anti-AFK
    if Config.AntiAFK then
        for _, conn in pairs(getconnections(LocalPlayer.Idled)) do conn:Disable() end
        LocalPlayer.Idled:Connect(function()
            VirtualUser:ClickButton2(Vector2.new(math.random(0,1000), math.random(0,1000)))
        end)
    end
    
    -- Travel to plaza if needed
    if Config.AutoTravelToPlaza then
        local success = pcall(function()
            Network.Invoke("Travel to Trading Plaza")
        end)
        task.wait(5)
    end
    
    -- Setup booth
    if not SetupBooth() then return end
    
    -- Start selling
    SellHugePets()
end

-- Start the script
local success, err = pcall(Main)
if not success then
    warn("Critical error:", err)
end
