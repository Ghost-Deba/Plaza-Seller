-- Wait for game to load
repeat task.wait() until game:IsLoaded()
local LocalPlayer = game:GetService("Players").LocalPlayer
repeat task.wait() until not LocalPlayer.PlayerGui:FindFirstChild("__INTRO")

-- Verify configuration exists
if not getgenv().Config then
    error("Configuration not found! Please load your config file first.")
    return
end

-- ========== CONSTANT SETTINGS ==========
local CUSTOM_USERNAME = "Seller"
local CUSTOM_AVATAR = "https://cdn.discordapp.com/attachments/905256599906558012/1356371225714102324/IMG_1773.jpg"
local FOOTER_ICON = "https://cdn.discordapp.com/attachments/905256599906558012/1356371225714102324/IMG_1773.jpg"
local DEFAULT_IMAGE = "https://cdn.discordapp.com/attachments/905256599906558012/1356371225714102324/IMG_1773.jpg"

-- ========== REQUIRED LIBRARIES ==========
local Library = game.ReplicatedStorage.Library
local Client = Library.Client
local RAPCmds = require(Client.RAPCmds)
local Network = require(Client.Network)
local Savemod = require(Client.Save)

-- ========== HELPER FUNCTIONS ==========
local function GetItemImage(itemId)
    local thumbnailUrl = string.format("https://www.roblox.com/Thumbs/Asset.ashx?width=420&height=420&assetId=%d", itemId)
    
    local success = pcall(function()
        return game:GetService("HttpService"):GetAsync(string.format(
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
    
    local data = {
        ["username"] = CUSTOM_USERNAME,
        ["avatar_url"] = CUSTOM_AVATAR,
        ["content"] = ping,
        ["embeds"] = {{
            ["title"] = "New Item Sold 🥳",
            ["description"] = string.format(
                "**Item Sold Info**\n"..
                "> Item = %s\n"..
                "> Value = %s\n"..
                "> Amount = %d\n"..
                "> In Inventory = %d\n\n"..
                "**User Info**\n"..
                "> Diamond = %s\n"..
                "> Account = ||%s||",
                itemName,
                tostring(price),
                amount,
                remaining,
                tostring(diamonds),
                playerName
            ),
            ["color"] = 65280, -- Green color
            ["thumbnail"] = {
                ["url"] = thumbnailUrl
            },
            ["footer"] = {
                ["text"] = "Ｇんｏｓｔ • Seller",
                ["icon_url"] = FOOTER_ICON
            },
            ["timestamp"] = DateTime.now():ToIsoDate()
        }}
    }
    
    local success, response = pcall(function()
        return game:GetService("HttpService"):PostAsync(
            Config.Webhook.URL,
            game:GetService("HttpService"):JSONEncode(data),
            {["Content-Type"] = "application/json"}
        )
    end)
    
    if not success then
        warn("Failed to send webhook:", response)
    end
end

local function IsExclusivePet(itemName)
    return itemName:find("Huge") or itemName:find("Titanic")
end

local function IsMatchingItem(itemData, itemId, configItem)
    local Item = require(Library.Items[configItem.Class .. "Item"])(itemId)
    
    if Item.name ~= configItem.item then
        return false
    end
    
    if configItem.PowerType ~= nil and itemData.pt ~= configItem.PowerType then
        return false
    end
    
    if configItem.Shiny ~= nil and (itemData.sh or false) ~= configItem.Shiny then
        return false
    end
    
    return true
end

local function GetRap(Class, ItemTable)
    local Item = require(Library.Items[Class .. "Item"])(ItemTable.id)

    if ItemTable.sh then Item:SetShiny(true) end
    if ItemTable.pt == 1 then Item:SetGolden() end
    if ItemTable.pt == 2 then Item:SetRainbow() end
    if ItemTable.tn then Item:SetTier(ItemTable.tn) end

    return RAPCmds.Get(Item) or 0
end

-- ========== TRAVEL TO TRADING PLAZA ==========
if Config.AutoTravelToPlaza and (game.PlaceId == 8737899170 or game.PlaceId == 16498369169) then
    while true do 
        Network.Invoke("Travel to Trading Plaza") 
        task.wait(1) 
    end
end

-- ========== CLAIM BOOTH ==========
local HaveBooth = false
while not HaveBooth do 
    local BoothSpawns = game.workspace.TradingPlaza.BoothSpawns:FindFirstChildWhichIsA("Model")
    for _, Booth in ipairs(workspace.__THINGS.Booths:GetChildren()) do
        if Booth:IsA("Model") and Booth.Info.BoothBottom.Frame.Top.Text == LocalPlayer.DisplayName .. "'s Booth!" then
            HaveBooth = true
            LocalPlayer.Character.HumanoidRootPart.CFrame = Booth.Table.CFrame * CFrame.new(5, 0, 0)
            break
        end
    end
    if not HaveBooth then
        LocalPlayer.Character.HumanoidRootPart.CFrame = BoothSpawns.Table.CFrame * CFrame.new(5, 0, 0)
        Network.Invoke("Booths_ClaimBooth", tostring(BoothSpawns:GetAttribute("ID")))
    end
end

-- ========== ANTI-AFK SYSTEM ==========
if Config.AntiAFK then
    local VirtualUser = game:GetService("VirtualUser")
    for _, v in pairs(getconnections(LocalPlayer.Idled)) do v:Disable() end
    LocalPlayer.Idled:Connect(function()
        VirtualUser:ClickButton2(Vector2.new(math.random(0, 1000), math.random(0, 1000))) 
    end)
    
    old = hookmetamethod(game, "__namecall", function(self, ...)
        local method = getnamecallmethod()
        if not checkcaller() then
            local Name = tostring(self)
            if table.find({"Server Closing", "Idle Tracking: Update Timer", "Move Server"}, Name) then
                return nil
            end
        end
        return old(self, ...)
    end)
    Network.Fire("Idle Tracking: Stop Timer")
end

-- ========== MAIN SELLING SYSTEM ==========
while task.wait(Config.SellInterval) do 
    local inventory = Savemod.Get().Inventory
    local playerData = Savemod.Get()
    local diamonds = playerData.Diamonds or 0
    local playerName = LocalPlayer.Name
    local itemsToSell = {}
    
    -- Collect matching items
    for _, configItem in ipairs(Config.Items) do
        local classItems = inventory[configItem.Class]
        if classItems then
            for uuid, itemData in pairs(classItems) do
                if IsMatchingItem(itemData, itemData.id, configItem) then
                    local isExclusive = configItem.IsExclusive or IsExclusivePet(configItem.item)
                    local maxAmount = isExclusive and 1 or math.min(itemData._am or 1, 50000)
                    
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
    
    -- Priority sorting (exclusives first)
    table.sort(itemsToSell, function(a, b)
        if a.isExclusive ~= b.isExclusive then
            return a.isExclusive
        else
            return (a.itemData._am or 1) < (b.itemData._am or 1)
        end
    end)
    
    -- Sell items with limits
    local totalListed = 0
    local exclusiveListed = 0
    
    for _, item in ipairs(itemsToSell) do
        if totalListed >= 25 then break end
        
        local itemName = item.configItem.item
        local price = math.min(item.configItem.MaxPrice, GetRap(item.configItem.Class, item.itemData))
        local amount = item.maxAmount
        local remaining = (item.itemData._am or 1) - amount
        local itemId = item.itemData.id
        
        if item.isExclusive and exclusiveListed < 1 then
            Network.Invoke("Booths_CreateListing", item.uuid, price, amount)
            SendWebhook(itemName, price, amount, remaining, playerName, diamonds, itemId)
            exclusiveListed = exclusiveListed + 1
            totalListed = totalListed + 1
            task.wait(1)
        elseif not item.isExclusive then
            Network.Invoke("Booths_CreateListing", item.uuid, price, amount)
            if amount >= 10000 then
                SendWebhook(itemName, price, amount, remaining, playerName, diamonds, itemId)
            end
            totalListed = totalListed + 1
            task.wait(1)
        end
    end
end
