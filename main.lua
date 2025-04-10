--[[
  Pet Simulator 99 Auto Seller
  Version 3.0 - Optimized with Webhook Support
]]

-- Wait for game to load
repeat task.wait() until game:IsLoaded()
local LocalPlayer = game:GetService("Players").LocalPlayer
repeat task.wait() until not LocalPlayer.PlayerGui:FindFirstChild("__INTRO")

-- Load configuration
if not getgenv().Config then
    error("❌ Configuration not found! Please load your config file first.")
    return
end

-- ========== CONSTANT SETTINGS ==========
local CUSTOM_USERNAME = "PS99 Auto Seller"
local CUSTOM_AVATAR = "https://i.imgur.com/JW6QZ9y.png"
local FOOTER_ICON = "https://i.imgur.com/JW6QZ9y.png"
local DEFAULT_IMAGE = "https://i.imgur.com/JW6QZ9y.png"
local MAX_BOOTH_SLOTS = 25
local MAX_REGULAR_ITEMS = 50000
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
    
    local success = pcall(function()
        return HttpService:GetAsync(string.format(
            "https://www.roblox.com/Thumbs/Asset.ashx?width=100&height=100&assetId=%d",
            itemId
        ))
    end)
    
    return success and thumbnailUrl or DEFAULT_IMAGE
end

local function SendWebhook(itemName, price, amount, remaining, playerName, diamonds, itemId)
    if not Config.Webhook.Enable or not Config.Webhook.URL then return end
    
    local ping = Config.Webhook.PingOnSale and (Config.Webhook.PingRoleID and "<@"..Config.Webhook.PingRoleID..">") or ""
    local thumbnailUrl = GetItemImage(itemId)
    
    local embed = {
        title = "🛒 New Item Sold",
        description = string.format(
            "**📦 Item Sold Info**\n"..
            "> 🏷️ Item: %s\n"..
            "> 💰 Value: %s\n"..
            "> 🔢 Amount: %d\n"..
            "> 📦 Remaining: %d\n\n"..
            "**👤 User Info**\n"..
            "> 💎 Diamonds: %s\n"..
            "> 🆔 Account: ||%s||",
            itemName,
            tostring(price),
            amount,
            remaining,
            tostring(diamonds),
            playerName
        ),
        color = 65280,
        thumbnail = {url = thumbnailUrl},
        footer = {
            text = "PS99 Auto Seller • v3.0",
            icon_url = FOOTER_ICON
        },
        timestamp = DateTime.now():ToIsoDate()
    }
    
    local success, response = pcall(function()
        return HttpService:PostAsync(
            Config.Webhook.URL,
            HttpService:JSONEncode({
                username = CUSTOM_USERNAME,
                avatar_url = CUSTOM_AVATAR,
                content = ping,
                embeds = {embed}
            }),
            {["Content-Type"] = "application/json"}
        )
    end)
    
    if not success then
        warn("⚠️ Failed to send webhook:", response)
    end
end

local function IsExclusivePet(itemName)
    return itemName:find("Huge") or itemName:find("Titanic")
end

local function IsMatchingItem(itemData, itemId, configItem)
    local Item = require(Library.Items[configItem.Class .. "Item"])(itemId)
    
    -- Check basic match
    if Item.name ~= configItem.item then
        return false
    end
    
    -- Check power type if specified
    if configItem.PowerType ~= nil and itemData.pt ~= configItem.PowerType then
        return false
    end
    
    -- Check shiny if specified
    if configItem.Shiny ~= nil and (itemData.sh or false) ~= configItem.Shiny then
        return false
    end
    
    return true
end

local function GetRap(Class, ItemTable)
    local Item = require(Library.Items[Class .. "Item"])(ItemTable.id)

    -- Apply item modifications
    if ItemTable.sh then Item:SetShiny(true) end
    if ItemTable.pt == 1 then Item:SetGolden() end
    if ItemTable.pt == 2 then Item:SetRainbow() end
    if ItemTable.tn then Item:SetTier(ItemTable.tn) end

    return RAPCmds.Get(Item) or 0
end

-- ========== TRAVEL TO TRADING PLAZA ==========
local function TravelToPlaza()
    if not Config.AutoTravelToPlaza then return end
    
    local plazaIDs = {8737899170, 16498369169}
    local currentPlaceId = game.PlaceId
    
    if not table.find(plazaIDs, currentPlaceId) then
        warn("⚠️ Not in plaza, skipping travel")
        return
    end
    
    for attempt = 1, MAX_ATTEMPTS do
        local success, err = pcall(function()
            Network.Invoke("Travel to Trading Plaza")
        end)
        
        if success then
            print("✅ Successfully traveled to Trading Plaza")
            task.wait(5) -- Wait after traveling
            return true
        else
            warn("⚠️ Travel attempt "..attempt.." failed:", err)
            task.wait(RETRY_DELAY)
        end
    end
    
    warn("❌ Failed to travel to Trading Plaza after "..MAX_ATTEMPTS.." attempts")
    return false
end

-- ========== BOOTH CLAIM SYSTEM ==========
local function FindTradingPlaza()
    local possibleNames = {"TradingPlaza", "Trade Plaza", "Plaza", "Trading Hub"}
    for _, name in ipairs(possibleNames) do
        local plaza = workspace:FindFirstChild(name)
        if plaza and plaza:FindFirstChild("BoothSpawns") then
            return plaza
        end
    end
    return nil
end

local function ClaimBooth()
    local startTime = os.time()
    local boothClaimAttempts = 0
    
    while os.time() - startTime < 60 do -- 60 second timeout
        local tradingPlaza = FindTradingPlaza()
        
        if not tradingPlaza then
            warn("⌛ Trading Plaza not found, waiting...")
            task.wait(RETRY_DELAY)
            continue
        end

        local BoothSpawns = tradingPlaza:FindFirstChild("BoothSpawns")
        if not BoothSpawns then
            warn("⌛ BoothSpawns not found, waiting...")
            task.wait(RETRY_DELAY)
            continue
        end

        -- Check for existing booth
        for _, Booth in ipairs(workspace.__THINGS.Booths:GetChildren()) do
            if Booth:IsA("Model") and Booth.Info.BoothBottom.Frame.Top.Text == LocalPlayer.DisplayName.."'s Booth!" then
                LocalPlayer.Character.HumanoidRootPart.CFrame = Booth.Table.CFrame * CFrame.new(5, 0, 0)
                print("✅ Found existing booth")
                return true
            end
        end

        -- Claim new booth
        local spawn = BoothSpawns:FindFirstChildWhichIsA("Model")
        if spawn then
            LocalPlayer.Character.HumanoidRootPart.CFrame = spawn.Table.CFrame * CFrame.new(5, 0, 0)
            
            boothClaimAttempts = boothClaimAttempts + 1
            if boothClaimAttempts > MAX_ATTEMPTS then
                warn("⌛ Too many booth claim attempts, waiting...")
                task.wait(RETRY_DELAY * 2)
                boothClaimAttempts = 0
            end
            
            local success, err = pcall(function()
                Network.Invoke("Booths_ClaimBooth", tostring(spawn:GetAttribute("ID")))
            end)
            
            if success then
                print("✅ Successfully claimed booth")
                return true
            else
                warn("⚠️ Booth claim failed:", err)
            end
        end
        
        task.wait(RETRY_DELAY)
    end
    
    error("❌ Failed to claim booth after 60 seconds")
    return false
end

-- ========== ANTI-AFK SYSTEM ==========
local function SetupAntiAFK()
    if not Config.AntiAFK then return end
    
    -- Disable existing idle connections
    for _, v in pairs(getconnections(LocalPlayer.Idled)) do 
        v:Disable() 
    end
    
    -- Set up new idle connection
    LocalPlayer.Idled:Connect(function()
        VirtualUser:ClickButton2(Vector2.new(math.random(0, 1000), math.random(0, 1000)))
    end)
    
    -- Prevent server tracking
    local oldNamecall
    oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
        local method = getnamecallmethod()
        if not checkcaller() then
            local Name = tostring(self)
            if table.find({"Server Closing", "Idle Tracking: Update Timer", "Move Server"}, Name) then
                return nil
            end
        end
        return oldNamecall(self, ...)
    end)
    
    Network.Fire("Idle Tracking: Stop Timer")
    print("✅ Anti-AFK system activated")
end

-- ========== MAIN SELLING LOOP ==========
local function StartSelling()
    print("🔄 Starting auto-sell system...")
    
    while true do
        local inventory = Savemod.Get().Inventory
        local playerData = Savemod.Get()
        local diamonds = playerData.Diamonds or 0
        local playerName = LocalPlayer.Name
        local itemsToSell = {}
        local totalListed = 0
        local exclusiveListed = 0
        
        -- Collect matching items
        for _, configItem in ipairs(Config.Items) do
            local classItems = inventory[configItem.Class]
            if classItems then
                for uuid, itemData in pairs(classItems) do
                    if IsMatchingItem(itemData, itemData.id, configItem) then
                        local isExclusive = configItem.IsExclusive or IsExclusivePet(configItem.item)
                        local maxAmount = isExclusive and 1 or math.min(itemData._am or 1, MAX_REGULAR_ITEMS)
                        
                        table.insert(itemsToSell, {
                            uuid = uuid,
                            itemData = itemData,
                            configItem = configItem,
                            isExclusive = isExclusive,
                            maxAmount = maxAmount
                        })
                    end
                end
            end
        end
        
        -- Sort items (exclusives first, then by amount)
        table.sort(itemsToSell, function(a, b)
            if a.isExclusive ~= b.isExclusive then
                return a.isExclusive
            else
                return (a.itemData._am or 1) < (b.itemData._am or 1)
            end
        end)
        
        -- Sell items
        for _, item in ipairs(itemsToSell) do
            if totalListed >= MAX_BOOTH_SLOTS then break end
            
            local itemName = item.configItem.item
            local price = math.min(item.configItem.MaxPrice, GetRap(item.configItem.Class, item.itemData))
            local amount = item.maxAmount
            local remaining = (item.itemData._am or 1) - amount
            local itemId = item.itemData.id
            
            if item.isExclusive and exclusiveListed < 1 then
                local success, err = pcall(function()
                    Network.Invoke("Booths_CreateListing", item.uuid, price, amount)
                end)
                
                if success then
                    SendWebhook(itemName, price, amount, remaining, playerName, diamonds, itemId)
                    exclusiveListed = exclusiveListed + 1
                    totalListed = totalListed + 1
                    print(string.format("✅ Listed exclusive: %s x%d for %d", itemName, amount, price))
                else
                    warn("⚠️ Failed to list exclusive item:", err)
                end
                
                task.wait(1)
            elseif not item.isExclusive then
                local success, err = pcall(function()
                    Network.Invoke("Booths_CreateListing", item.uuid, price, amount)
                end)
                
                if success then
                    if amount >= 10000 then
                        SendWebhook(itemName, price, amount, remaining, playerName, diamonds, itemId)
                    end
                    totalListed = totalListed + 1
                    print(string.format("✅ Listed: %s x%d for %d", itemName, amount, price))
                else
                    warn("⚠️ Failed to list item:", err)
                end
                
                task.wait(1)
            end
        end
        
        print(string.format("🔄 Waiting %d seconds before next update...", Config.SellInterval))
        task.wait(Config.SellInterval)
    end
end

-- ========== MAIN EXECUTION ==========
local function Main()
    print("🚀 Initializing PS99 Auto Seller v3.0")
    
    -- Step 1: Travel to plaza if needed
    if not TravelToPlaza() then
        error("❌ Initialization failed - Could not travel to plaza")
        return
    end
    
    -- Step 2: Claim a booth
    if not ClaimBooth() then
        error("❌ Initialization failed - Could not claim booth")
        return
    end
    
    -- Step 3: Set up anti-AFK
    SetupAntiAFK()
    
    -- Step 4: Start selling
    StartSelling()
end

-- Start the script
local success, err = pcall(Main)
if not success then
    warn("❌ Critical error:", err)
end
