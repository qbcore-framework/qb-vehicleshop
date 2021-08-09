local NumberCharset = {}
local Charset = {}

for i = 48,  57 do table.insert(NumberCharset, string.char(i)) end
for i = 65,  90 do table.insert(Charset, string.char(i)) end
for i = 97, 122 do table.insert(Charset, string.char(i)) end

-- code

RegisterNetEvent('qb-vehicleshop:server:buyVehicle')
AddEventHandler('qb-vehicleshop:server:buyVehicle', function(vehicleData, garage)
    local src = source
    local pData = QBCore.Functions.GetPlayer(src)
    local cid = pData.PlayerData.citizenid
    local vData = QBCore.Shared.Vehicles[vehicleData["model"]]
    local balance = pData.PlayerData.money["bank"]
    
    if (balance - vData["price"]) >= 0 then
        local plate = GeneratePlate()
        exports.ghmattimysql:execute('INSERT INTO player_vehicles (license, citizenid, vehicle, hash, mods, plate, garage) VALUES (@license, @citizenid, @vehicle, @hash, @mods, @plate, @garage)', {
            ['@license'] = pData.PlayerData.license,
            ['@citizenid'] = cid,
            ['@vehicle'] = vData["model"],
            ['@hash'] = GetHashKey(vData["model"]),
            ['@mods'] = '{}',
            ['@plate'] = plate,
            ['@garage'] = garage
        })
        TriggerClientEvent("QBCore:Notify", src, "Success! Your vehicle has been delivered to "..QB.GarageLabel[garage], "success", 5000)
        pData.Functions.RemoveMoney('bank', vData["price"], "vehicle-bought-in-shop")
        TriggerEvent("qb-log:server:sendLog", cid, "vehiclebought", {model=vData["model"], name=vData["name"], from="garage", location=QB.GarageLabel[garage], moneyType="bank", price=vData["price"], plate=plate})
        TriggerEvent("qb-log:server:CreateLog", "vehicleshop", "Vehicle purchased (garage)", "green", "**"..GetPlayerName(src) .. "** bought a " .. vData["name"] .. " for $" .. vData["price"])
    else
		TriggerClientEvent("QBCore:Notify", src, "You don't have enough money, you're missing $"..format_thousand(vData["price"] - balance), "error", 5000)
    end
end)

RegisterNetEvent('qb-vehicleshop:server:buyShowroomVehicle')
AddEventHandler('qb-vehicleshop:server:buyShowroomVehicle', function(vehicle, class)
    local src = source
    local pData = QBCore.Functions.GetPlayer(src)
    local cid = pData.PlayerData.citizenid
    local cash = pData.PlayerData.money["cash"]
    local bank = pData.PlayerData.money["bank"]
    local vehiclePrice = QBCore.Shared.Vehicles[vehicle]["price"]
    local plate = GeneratePlate()

    if (cash - vehiclePrice) >= 0 then
        exports.ghmattimysql:execute('INSERT INTO player_vehicles (license, citizenid, vehicle, hash, mods, plate, state) VALUES (@license, @citizenid, @vehicle, @hash, @mods, @plate, @state)', {
            ['@license'] = pData.PlayerData.license,
            ['@citizenid'] = cid,
            ['@vehicle'] = vehicle,
            ['@hash'] = GetHashKey(vehicle),
            ['@mods'] = '{}',
            ['@plate'] = plate,
            ['@state'] = 0
        })
        TriggerClientEvent("QBCore:Notify", src, "Success! Your vehicle will be waiting for you outside", "success", 5000)
        TriggerClientEvent('qb-vehicleshop:client:buyShowroomVehicle', src, vehicle, plate)
        pData.Functions.RemoveMoney('cash', vehiclePrice, "vehicle-bought-in-showroom")
        TriggerEvent("qb-log:server:CreateLog", "vehicleshop", "Vehicle purchased (showroom)", "green", "**"..GetPlayerName(src) .. "** bought a " .. QBCore.Shared.Vehicles[vehicle]["name"] .. " for $" .. vehiclePrice .. " with cash")
    elseif (bank - vehiclePrice) >= 0 then
        exports.ghmattimysql:execute('INSERT INTO player_vehicles (license, citizenid, vehicle, hash, mods, plate, state) VALUES (@license, @citizenid, @vehicle, @hash, @mods, @plate, @state)', {
            ['@license'] = pData.PlayerData.license,
            ['@citizenid'] = cid,
            ['@vehicle'] = vehicle,
            ['@hash'] = GetHashKey(vehicle),
            ['@mods'] = '{}',
            ['@plate'] = plate,
            ['@state'] = 0
        })
        TriggerClientEvent("QBCore:Notify", src, "Success! Your vehicle will be waiting for you outside", "success", 5000)
        TriggerClientEvent('qb-vehicleshop:client:buyShowroomVehicle', src, vehicle, plate)
        pData.Functions.RemoveMoney('bank', vehiclePrice, "vehicle-bought-in-showroom")
        TriggerEvent("qb-log:server:CreateLog", "vehicleshop", "Vehicle purchased (showroom)", "green", "**"..GetPlayerName(src) .. "** bought a " .. QBCore.Shared.Vehicles[vehicle]["name"] .. " for $" .. vehiclePrice .. " from the bank")
    else
        TriggerClientEvent("QBCore:Notify", src, "You don't have enough money, you're missing $"..format_thousand(vehiclePrice - balance), "error", 5000)
    end
end)

function format_thousand(v)
    local s = string.format("%d", math.floor(v))
    local pos = string.len(s) % 3
    if pos == 0 then pos = 3 end
    return string.sub(s, 1, pos)
            .. string.gsub(string.sub(s, pos+1), "(...)", ".%1")
end

function GeneratePlate()
    local plate = tostring(GetRandomNumber(1)) .. GetRandomLetter(2) .. tostring(GetRandomNumber(3)) .. GetRandomLetter(2)
    local result = exports.ghmattimysql:scalarSync('SELECT plate FROM player_vehicles WHERE plate=@plate', {['@plate'] = plate})
    if result then
        plate = tostring(GetRandomNumber(1)) .. GetRandomLetter(2) .. tostring(GetRandomNumber(3)) .. GetRandomLetter(2)
    end
    return plate:upper()
end

function GetRandomNumber(length)
	Citizen.Wait(1)
	math.randomseed(GetGameTimer())
	if length > 0 then
		return GetRandomNumber(length - 1) .. NumberCharset[math.random(1, #NumberCharset)]
	else
		return ''
	end
end

function GetRandomLetter(length)
	Citizen.Wait(1)
	math.randomseed(GetGameTimer())
	if length > 0 then
		return GetRandomLetter(length - 1) .. Charset[math.random(1, #Charset)]
	else
		return ''
	end
end

RegisterServerEvent('qb-vehicleshop:server:setShowroomCarInUse')
AddEventHandler('qb-vehicleshop:server:setShowroomCarInUse', function(showroomVehicle, bool, currentindex)
    QB.VehicleShops[currentindex]["ShowroomVehicles"][showroomVehicle].inUse = bool
    TriggerClientEvent('qb-vehicleshop:client:setShowroomCarInUse', -1, showroomVehicle, bool)
end)

RegisterServerEvent('qb-vehicleshop:server:setShowroomVehicle')
AddEventHandler('qb-vehicleshop:server:setShowroomVehicle', function(vData, k, currentindex)
    QB.VehicleShops[currentindex]["ShowroomVehicles"][k].chosenVehicle = vData
    TriggerClientEvent('qb-vehicleshop:client:setShowroomVehicle', -1, vData, k)
end)

function CheckOwnedJob(source, grade)
    local ownedjob = false
    local Player = QBCore.Functions.GetPlayer(source)

    for k, v in pairs(QB.VehicleShops) do
        if v["OwnedJob"] then
            if v["OwnedJob"] == Player.PlayerData.job.name then
                if grade ~= nil and grade == Player.PlayerData.job.grade.level then
                    ownedjob = true
                elseif grade == nil then
                    ownedjob = true
                end
                break
            end
        end
    end

    return ownedjob
end

QBCore.Commands.Add("sell", "Sell Vehicle (Car Dealer Only)", {{name="ID", help="ID of Player to sell to"}}, true, function(source, args)
    local TargetId = tonumber(args[1])

    if CheckOwnedJob(source) then
        if TargetId ~= nil then
            if #(GetEntityCoords(GetPlayerPed(source)) - GetEntityCoords(GetPlayerPed(TargetId))) < 3.0 then
                TriggerClientEvent('qb-vehicleshop:client:SellCustomVehicle', source, TargetId)
            else
                TriggerClientEvent('QBCore:Notify', source, 'The provided Player with ID '..TargetId..' is not nearby', 'error')
            end
        else
            TriggerClientEvent('QBCore:Notify', source, 'You must provide a Player ID!', 'error')
        end
    else
        TriggerClientEvent('QBCore:Notify', source, "You don't have access to this command", 'error')
    end
end)

QBCore.Commands.Add("testdrive", "Test Drive Vehicle (Car Dealer Only)", {}, false, function(source, args)
    if CheckOwnedJob(source) then
        TriggerClientEvent('qb-vehicleshop:client:DoTestrit', source, GeneratePlate())
    else
        TriggerClientEvent('QBCore:Notify', source, "You don't have access to this command", 'error')
    end
end)

RegisterServerEvent('qb-vehicleshop:server:SellCustomVehicle')
AddEventHandler('qb-vehicleshop:server:SellCustomVehicle', function(TargetId, ShowroomSlot)
    TriggerClientEvent('qb-vehicleshop:client:SetVehicleBuying', TargetId, ShowroomSlot)
end)

RegisterServerEvent('qb-vehicleshop:server:ConfirmVehicle')
AddEventHandler('qb-vehicleshop:server:ConfirmVehicle', function(ShowroomVehicle)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    local VehPrice = QBCore.Shared.Vehicles[ShowroomVehicle.chosenVehicle].price
    local plate = GeneratePlate()

    if Player.PlayerData.money.cash >= VehPrice then
        Player.Functions.RemoveMoney('cash', VehPrice)
        TriggerClientEvent('qb-vehicleshop:client:ConfirmVehicle', src, ShowroomVehicle, plate)
        exports.ghmattimysql:execute('INSERT INTO player_vehicles (license, citizenid, vehicle, hash, mods, plate, state) VALUES (@license, @citizenid, @vehicle, @hash, @mods, @plate, @state)', {
            ['@license'] = Player.PlayerData.license,
            ['@citizenid'] = Player.PlayerData.citizenid,
            ['@vehicle'] = ShowroomVehicle.chosenVehicle,
            ['@hash'] = GetHashKey(ShowroomVehicle.chosenVehicle),
            ['@mods'] = '{}',
            ['@plate'] = plate,
            ['@state'] = 0
        })
    elseif Player.PlayerData.money.bank >= VehPrice then
        Player.Functions.RemoveMoney('bank', VehPrice)
        TriggerClientEvent('qb-vehicleshop:client:ConfirmVehicle', src, ShowroomVehicle, plate)
        exports.ghmattimysql:execute('INSERT INTO player_vehicles (license, citizenid, vehicle, hash, mods, plate, state) VALUES (@license, @citizenid, @vehicle, @hash, @mods, @plate, @state)', {
            ['@license'] = Player.PlayerData.license,
            ['@citizenid'] = Player.PlayerData.citizenid,
            ['@vehicle'] = ShowroomVehicle.chosenVehicle,
            ['@hash'] = GetHashKey(ShowroomVehicle.chosenVehicle),
            ['@mods'] = '{}',
            ['@plate'] = plate,
            ['@state'] = 0
        })
    else
        if Player.PlayerData.money.cash > Player.PlayerData.money.bank then
            TriggerClientEvent('QBCore:Notify', src, 'You don\'t have enough money.. You are missing ('..(Player.PlayerData.money.cash - VehPrice)..',-)')
        else
            TriggerClientEvent('QBCore:Notify', src, 'You don\'t have enough money.. You are missing ('..(Player.PlayerData.money.bank - VehPrice)..',-)')
        end
    end
end)
