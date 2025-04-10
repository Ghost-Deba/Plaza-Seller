--======= [الوظائف المساعدة] =======--
local function FormatNumber(n)
    return tostring(n):reverse():gsub("%d%d%d", "%1,"):reverse():gsub("^,", "")
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
        title = "💰 عملية بيع ناجحة!",
        description = string.format(
            "**اسم العنصر:** `%s`\n"..
            "**السعر:** %s 💎\n"..
            "**تم بيع:** %sx\n"..
            "**المتبقي:** %sx\n\n"..
            "**رصيد الدايموند:** %s 💎",
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
    
    local data = {
        content = Config.Webhook.PingOnSale and ("<@&"..Config.Webhook.PingRoleID..">") or nil,
        embeds = {embed},
        username = "Ghosty Seller Bot",
        avatar_url = "https://i.imgur.com/xyz789.png"
    }
    
    pcall(function()
        syn.request({
            Url = Config.Webhook.URL,
            Method = "POST",
            Headers = {["Content-Type"] = "application/json"},
            Body = game:GetService("HttpService"):JSONEncode(data)
        })
    end)
end

--======= [تهيئة اللعبة] =======--
repeat task.wait() until game:IsLoaded()
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local Library = game:GetService("ReplicatedStorage").Library
local Network = require(Library.Client.Network)
local Savemod = require(Library.Client.Save)

--======= [منع AFK] =======--
if Config.AntiAFK then
    local VirtualUser = game:GetService("VirtualUser")
    LocalPlayer.Idled:Connect(function()
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new())
    end)
end

--======= [الانتقال للساحة] =======--
if Config.AutoTravelToPlaza then
    while true do
        Network.Invoke("Travel to Trading Plaza")
        task.wait(3)
    end
end

--======= [حجز الكشك] =======--
local function ClaimBooth()
    local BoothSpawns = workspace.TradingPlaza.BoothSpawns:GetChildren()[1]
    LocalPlayer.Character.HumanoidRootPart.CFrame = BoothSpawns.Table.CFrame * CFrame.new(0, 5, 0)
    Network.Invoke("Booths_ClaimBooth", tostring(BoothSpawns:GetAttribute("ID")))
end

repeat ClaimBooth() task.wait(1) until workspace.__THINGS.Booths:FindFirstChild(LocalPlayer.Name)

--======= [نظام البيع الرئيسي] =======--
while task.wait(Config.SellInterval) do
    local Inventory = Savemod.Get().Inventory
    local Diamonds = Savemod.Get().Diamonds
    
    local itemsToSell = {}
    for _, config in ipairs(Config.Items) do
        for uuid, itemData in pairs(Inventory[config.Class] or {}) do
            local ItemClass = require(Library.Items[config.Class.."Item"])
            local Item = ItemClass.new(itemData.id)
            
            -- فلترة العناصر
            if Item.name == config.item then
                if config.PowerType and itemData.pt ~= config.PowerType then continue end
                if config.Shiny and not itemData.sh then continue end
                
                table.insert(itemsToSell, {
                    uuid = uuid,
                    data = itemData,
                    config = config
                })
            end
        end
    end
    
    -- فرز العناصر حسب القيمة
    table.sort(itemsToSell, function(a,b)
        return RAPCmds.Get(a.Item) > RAPCmds.Get(b.Item)
    end)
    
    -- بدء البيع
    for _, item in ipairs(itemsToSell) do
        local MaxPrice = item.config.MaxPrice
        local RAP = RAPCmds.Get(Item)
        local Price = type(MaxPrice) == "string" and (RAP * tonumber(MaxPrice:gsub("%%",""))/100) or math.min(MaxPrice, RAP * 2)
        local MaxAmount = math.min(item.data._am or 1, math.floor(25e9 / Price))
        
        if MaxAmount > 0 then
            Network.Invoke("Booths_CreateListing", item.uuid, Price, MaxAmount)
            SendWebhook(
                item.config.item,
                Price,
                MaxAmount,
                (item.data._am or 1) - MaxAmount,
                Diamonds,
                item.data.id
            )
            task.wait(1)
        end
    end
end
