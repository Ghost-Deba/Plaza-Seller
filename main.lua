--======= [الوظائف المساعدة] =======--
local function FormatNumber(n)
    n = tonumber(n) or 0 -- الإصلاح هنا
    return tostring(math.floor(n)):reverse():gsub("%d%d%d", "%1,", 0):reverse():gsub("^,", "")
end

local function GetItemImage(itemId)
    local success, response = pcall(function()
        return game:HttpGet("https://thumbnails.roblox.com/v1/assets?assetIds="..itemId.."&size=420x420&format=Png")
    end)
    return success and game:GetService("HttpService"):JSONDecode(response).data[1].imageUrl or "https://i.imgur.com/JW6QZ9y.png"
end

local function SendWebhook(itemName, price, sold, remaining, diamonds, itemId)
    if not Config.Webhook.Enable or not Config.Webhook.URL then return end
    
    local embed = {
        title = "💰 تم البيع بنجاح!",
        description = string.format(
            "**الاسم:** %s\n"..
            "**السعر:** %s 💎\n"..
            "**المباع:** %sx\n"..
            "**المتبقي:** %sx\n"..
            "**الدايموند:** %s 💎",
            itemName,
            FormatNumber(price),
            FormatNumber(sold),
            FormatNumber(remaining),
            FormatNumber(diamonds)
        ),
        color = 65280,
        thumbnail = {url = GetItemImage(itemId)},
        footer = {
            text = "الساعة "..os.date("%X"),
            icon_url = Config.Webhook.FooterIcon
        }
    }
    
    pcall(function()
        syn.request({
            Url = Config.Webhook.URL,
            Method = "POST",
            Headers = {["Content-Type"] = "application/json"},
            Body = game:GetService("HttpService"):JSONEncode({
                content = Config.Webhook.PingOnSale and ("<@&"..Config.Webhook.PingRoleID..">") or nil,
                embeds = {embed},
                username = "Ghosty Seller"
            })
        })
    end)
end

--======= [التهيئة] =======--
repeat task.wait() until game:IsLoaded()
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
repeat task.wait() until LocalPlayer.PlayerGui:FindFirstChild("__INVENTORY")

local Library = game:GetService("ReplicatedStorage").Library
local Network = require(Library.Client.Network)
local Savemod = require(Library.Client.Save)
local RAPCmds = require(Library.Client.RAPCmds)

--======= [منع AFK] =======--
if Config.AntiAFK then
    local VirtualUser = game:GetService("VirtualUser")
    LocalPlayer.Idled:Connect(function()
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new())
    end)
end

--======= [نظام السفر الذكي] =======--
local function CheckLocation()
    local AllowedPlaces = {8737899170, 16498369169}
    return table.find(AllowedPlaces, game.PlaceId)
end

local function SmartTravel()
    if CheckLocation() and game.PlaceId == 8737899170 then
        for i = 1, 3 do -- 3 محاولات كحد أقصى
            local success = pcall(Network.Invoke, "Travel to Trading Plaza")
            if success then
                repeat task.wait(1) until game.PlaceId == 16498369169
                return true
            end
            task.wait(math.random(2,4))
        end
    end
    return false
end

--======= [حجز الكشك] =======--
local function ClaimBooth()
    local BoothSpawns = workspace.TradingPlaza.BoothSpawns:GetChildren()
    if #BoothSpawns > 0 then
        LocalPlayer.Character.HumanoidRootPart.CFrame = BoothSpawns[1].Table.CFrame * CFrame.new(0, 5, 0)
        Network.Invoke("Booths_ClaimBooth", tostring(BoothSpawns[1]:GetAttribute("ID")))
    end
end

--======= [النظام الرئيسي] =======--
task.spawn(function()
    while true do
        if Config.AutoTravelToPlaza and game.PlaceId ~= 16498369169 then
            SmartTravel()
        end
        
        if game.PlaceId == 16498369169 then
            if not workspace.__THINGS.Booths:FindFirstChild(LocalPlayer.Name) then
                ClaimBooth()
            else
                break
            end
        end
        
        task.wait(5)
    end
end)

--======= [نظام البيع] =======--
while task.wait(Config.SellInterval) do
    local Inventory = Savemod.Get().Inventory
    local Diamonds = Savemod.Get().Diamonds or 0
    
    local itemsToSell = {}
    for _, config in ipairs(Config.Items) do
        local classItems = Inventory[config.Class] or {}
        for uuid, itemData in pairs(classItems) do
            local Item = require(Library.Items[config.Class.."Item"])(itemData.id)
            local isMatch = true
            
            -- الفلترة
            if Item.name ~= config.item then continue end
            if config.PowerType and itemData.pt ~= config.PowerType then continue end
            if config.Shiny and not itemData.sh then continue end
            
            table.insert(itemsToSell, {
                uuid = uuid,
                data = itemData,
                config = config,
                rap = RAPCmds.Get(Item)
            })
        end
    end
    
    -- الفرز حسب القيمة
    table.sort(itemsToSell, function(a,b)
        return a.rap > b.rap
    end)
    
    -- البيع
    for _, item in ipairs(itemsToSell) do
        local price = item.config.MaxPrice
        if type(price) == "string" then
            price = item.rap * (tonumber(price:gsub("%%",""))/100
        end
        price = math.floor(math.min(price, item.rap * 1.5))
        
        local maxAmount = math.min(item.data._am or 1, math.floor(25e9 / price))
        
        if maxAmount > 0 then
            Network.Invoke("Booths_CreateListing", item.uuid, price, maxAmount)
            SendWebhook(
                item.config.item,
                price,
                maxAmount,
                (item.data._am or 1) - maxAmount,
                Diamonds,
                item.data.id
            )
            task.wait(1)
        end
    end
    end
