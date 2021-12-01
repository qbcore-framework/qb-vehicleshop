-- Variables
local QBCore = exports['qb-core']:GetCoreObject()
local financetimer = {}
local paymentDue = false

-- Handlers

-- Store game time for player when they load
RegisterNetEvent('qb-vehicleshop:server:addPlayer', function(citizenid, gameTime)
    financetimer[citizenid] = gameTime
end)

-- Deduct stored game time from player on logout
RegisterNetEvent('qb-vehicleshop:server:removePlayer', function(citizenid)
    if financetimer[citizenid] then
        local playTime = financetimer[citizenid]
        local financetime = exports.oxmysql:executeSync('SELECT * FROM player_vehicles WHERE citizenid = ?', {citizenid})
        for k,v in pairs(financetime) do
            if v.balance >= 1 then
                local newTime = math.floor(v.financetime - (((GetGameTimer() - playTime) / 1000) / 60))
                if newTime < 0 then newTime = 0 end
                exports.oxmysql:update('UPDATE player_vehicles SET financetime = ? WHERE plate = ?', {newTime, v.plate})
            end
        end
    end
    financetimer[citizenid] = {}
end)

-- Deduct stored game time from player on quit because we can't get citizenid
AddEventHandler('playerDropped', function()
    local src = source
    for k,v in pairs(GetPlayerIdentifiers(src)) do
        if string.sub(v, 1, string.len("license:")) == "license:" then
            license = v
        end
    end
    if license then
        local vehicles = exports.oxmysql:executeSync('SELECT * FROM player_vehicles WHERE license = ?', {license})
        if vehicles then
            for k,v in pairs(vehicles) do
                if financetimer[v.citizenid] then
                    local playTime = financetimer[v.citizenid]
                    if v.balance >= 1 then
                        local newTime = math.floor(v.financetime - (((GetGameTimer() - playTime) / 1000) / 60))
                        if newTime < 0 then newTime = 0 end
                        exports.oxmysql:update('UPDATE player_vehicles SET financetime = ? WHERE plate = ?', {newTime, v.plate})
                        financetimer[v.citizenid] = {}
                    end
                end
            end
        end
    end
end)

-- Functions

local function round(x)
    return x>=0 and math.floor(x+0.5) or math.ceil(x-0.5)
end

local function calculateFinance(vehiclePrice, downPayment, paymentamount)
    local balance = vehiclePrice - downPayment
    local vehPaymentAmount = balance / paymentamount
    return round(balance), round(vehPaymentAmount)
end

local function calculateNewFinance(paymentAmount, vehData)
    local newBalance = tonumber(vehData.balance - paymentAmount)
    local minusPayment = vehData.paymentsLeft - 1
    local newPaymentsLeft = newBalance / minusPayment
    local newPayment = newBalance / newPaymentsLeft
    return round(newBalance), round(newPayment), newPaymentsLeft
end

local function GeneratePlate()
    local plate = QBCore.Shared.RandomInt(1) .. QBCore.Shared.RandomStr(2) .. QBCore.Shared.RandomInt(3) .. QBCore.Shared.RandomStr(2)
    local result = exports.oxmysql:scalarSync('SELECT plate FROM player_vehicles WHERE plate = ?', {plate})
    if result then
        return GeneratePlate()
    else
        return plate:upper()
    end
end

local function comma_value(amount)
    local formatted = amount
    while true do
      formatted, k = string.gsub(formatted, '^(-?%d+)(%d%d%d)', '%1,%2')
      if (k==0) then
        break
      end
    end
    return formatted
end

-- Callbacks

QBCore.Functions.CreateCallback('qb-vehicleshop:server:getVehicles', function(source, cb)
    local src = source
    local player = QBCore.Functions.GetPlayer(src)
    if player then
        local vehicles = exports.oxmysql:executeSync('SELECT * FROM player_vehicles WHERE citizenid = ?', {player.PlayerData.citizenid})
        if vehicles[1] then
            cb(vehicles)
        end
    end
end)

-- Events

-- Sync vehicle for other players
RegisterNetEvent('qb-vehicleshop:server:swapVehicle', function(data)
    local src = source
    TriggerClientEvent('qb-vehicleshop:client:swapVehicle', -1, data)
    Wait(1500) -- let new car spawn
    TriggerClientEvent('qb-vehicleshop:client:homeMenu', src) -- reopen main menu
end)

-- Send customer for test drive
RegisterNetEvent('qb-vehicleshop:server:customTestDrive', function(data)
    local src = source
    local PlayerPed = GetPlayerPed(src)
    local pCoords = GetEntityCoords(PlayerPed)
    for k, v in pairs(QBCore.Functions.GetPlayers()) do
        local TargetPed = GetPlayerPed(v)
        local tCoords = GetEntityCoords(TargetPed)
        local dist = #(pCoords - tCoords)
        if PlayerPed ~= TargetPed and dist < 3.0 then
            testDrivePlayer = QBCore.Functions.GetPlayer(v)
        end
    end
    if not testDrivePlayer then return TriggerClientEvent('QBCore:Notify', src, 'No one nearby', 'error') end
    TriggerClientEvent('qb-vehicleshop:client:customTestDrive', testDrivePlayer.PlayerData.source, data)
end)

-- Make a finance payment
RegisterNetEvent('qb-vehicleshop:server:financePayment', function(paymentAmount, vehData)
    local src = source
    local player = QBCore.Functions.GetPlayer(src)
    local cash = player.PlayerData.money['cash']
    local bank = player.PlayerData.money['bank']
    local plate = vehData.vehiclePlate
    local paymentAmount = tonumber(paymentAmount)
    local minPayment = tonumber(vehData.paymentAmount)
    local timer = (Config.PaymentInterval * 60)
    local newBalance, newPaymentsLeft, newPayment = calculateNewFinance(paymentAmount, vehData)
    if newBalance > 0 then
        if player and paymentAmount >= minPayment then
            if cash >= paymentAmount then
                player.Functions.RemoveMoney('cash', paymentAmount)
                exports.oxmysql:execute('UPDATE player_vehicles SET balance = ?, paymentamount = ?, paymentsleft = ?, financetime = ? WHERE plate = ?', {newBalance, newPayment, newPaymentsLeft, timer, plate})
            elseif bank >= paymentAmount then
                player.Functions.RemoveMoney('bank', paymentAmount)
                exports.oxmysql:execute('UPDATE player_vehicles SET balance = ?, paymentamount = ?, paymentsleft = ?, financetime = ? WHERE plate = ?', {newBalance, newPayment, newPaymentsLeft, timer, plate})
            else
                TriggerClientEvent('QBCore:Notify', src, 'Not enough money', 'error')
            end
        else
            TriggerClientEvent('QBCore:Notify', src, 'Minimum payment allowed is $' ..comma_value(minPayment), 'error')
        end
    else
        TriggerClientEvent('QBCore:Notify', src, 'You overpaid', 'error')
    end
end)


-- Pay off vehice in full
RegisterNetEvent('qb-vehicleshop:server:financePaymentFull', function(data)
    local src = source
    local player = QBCore.Functions.GetPlayer(src)
    local cash = player.PlayerData.money['cash']
    local bank = player.PlayerData.money['bank']
    local vehBalance = data.vehBalance
    local vehPlate = data.vehPlate
    if player and vehBalance ~= 0 then
        if cash >= vehBalance then
            player.Functions.RemoveMoney('cash', vehBalance)
            exports.oxmysql:update('UPDATE player_vehicles SET balance = ?, paymentamount = ?, paymentsleft = ?, financetime = ? WHERE plate = ?', {0, 0, 0, 0, vehPlate})
        elseif bank >= vehBalance then
            player.Functions.RemoveMoney('bank', vehBalance)
            exports.oxmysql:update('UPDATE player_vehicles SET balance = ?, paymentamount = ?, paymentsleft = ?, financetime = ? WHERE plate = ?', {0, 0, 0, 0, vehPlate})
        else
            TriggerClientEvent('QBCore:Notify', src, 'Not enough money', 'error')
        end
    else
        TriggerClientEvent('QBCore:Notify', src, 'Vehicle is already paid off', 'error')
    end
end)

-- Buy public vehicle outright
RegisterNetEvent('qb-vehicleshop:server:buyShowroomVehicle', function(vehicle)
    local src = source
    local vehicle = vehicle.buyVehicle
    local pData = QBCore.Functions.GetPlayer(src)
    local cid = pData.PlayerData.citizenid
    local cash = pData.PlayerData.money['cash']
    local bank = pData.PlayerData.money['bank']
    local vehiclePrice = QBCore.Shared.Vehicles[vehicle]['price']
    local plate = GeneratePlate()
    if cash > vehiclePrice then
        exports.oxmysql:insert('INSERT INTO player_vehicles (license, citizenid, vehicle, hash, mods, plate, state) VALUES (?, ?, ?, ?, ?, ?, ?)', {
            pData.PlayerData.license,
            cid,
            vehicle,
            GetHashKey(vehicle),
            '{}',
            plate,
            0
        })
        TriggerClientEvent('QBCore:Notify', src, 'Congratulations on your purchase!', 'success')
        TriggerClientEvent('qb-vehicleshop:client:buyShowroomVehicle', src, vehicle, plate)
        pData.Functions.RemoveMoney('cash', vehiclePrice, 'vehicle-bought-in-showroom')
    elseif bank > vehiclePrice then
        exports.oxmysql:insert('INSERT INTO player_vehicles (license, citizenid, vehicle, hash, mods, plate, state) VALUES (?, ?, ?, ?, ?, ?, ?)', {
            pData.PlayerData.license,
            cid,
            vehicle,
            GetHashKey(vehicle),
            '{}',
            plate,
            0
        })
        TriggerClientEvent('QBCore:Notify', src, 'Congratulations on your purchase!', 'success')
        TriggerClientEvent('qb-vehicleshop:client:buyShowroomVehicle', src, vehicle, plate)
        pData.Functions.RemoveMoney('bank', vehiclePrice, 'vehicle-bought-in-showroom')
    else
        TriggerClientEvent('QBCore:Notify', src, 'Not enough money', 'error')
    end
end)

-- Finance public vehicle
RegisterNetEvent('qb-vehicleshop:server:financeVehicle', function(downPayment, paymentAmount, vehicle)
    local src = source
    local downPayment = tonumber(downPayment)
    local paymentAmount = tonumber(paymentAmount)
    local pData = QBCore.Functions.GetPlayer(src)
    local cid = pData.PlayerData.citizenid
    local cash = pData.PlayerData.money['cash']
    local bank = pData.PlayerData.money['bank']
    local vehiclePrice = QBCore.Shared.Vehicles[vehicle]['price']
    local timer = (Config.PaymentInterval * 60)
    local minDown = tonumber(round(vehiclePrice / Config.MinimumDown))
    if downPayment > vehiclePrice then return TriggerClientEvent('QBCore:Notify', src, 'Vehicle is not worth that much', 'error') end
    if downPayment < minDown then return TriggerClientEvent('QBCore:Notify', src, 'Down payment too small', 'error') end
    if paymentAmount > Config.MaximumPayments then return TriggerClientEvent('QBCore:Notify', src, 'Exceeded maximum payment amount', 'error') end
    local plate = GeneratePlate()
    local balance, vehPaymentAmount = calculateFinance(vehiclePrice, downPayment, paymentAmount)
    if cash >= downPayment then
        exports.oxmysql:insert('INSERT INTO player_vehicles (license, citizenid, vehicle, hash, mods, plate, state, balance, paymentamount, paymentsleft, financetime) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)', {
            pData.PlayerData.license,
            cid,
            vehicle,
            GetHashKey(vehicle),
            '{}',
            plate,
            0,
            balance,
            vehPaymentAmount,
            paymentAmount,
            timer
        })
        TriggerClientEvent('QBCore:Notify', src, 'Congratulations on your purchase!', 'success')
        TriggerClientEvent('qb-vehicleshop:client:buyShowroomVehicle', src, vehicle, plate)
        pData.Functions.RemoveMoney('cash', downPayment, 'vehicle-bought-in-showroom')
    elseif bank >= downPayment then
        exports.oxmysql:insert('INSERT INTO player_vehicles (license, citizenid, vehicle, hash, mods, plate, state, balance, paymentamount, paymentsleft, financetime) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)', {
            pData.PlayerData.license,
            cid,
            vehicle,
            GetHashKey(vehicle),
            '{}',
            plate,
            0,
            balance,
            vehPaymentAmount,
            paymentAmount,
            timer
        })
        TriggerClientEvent('QBCore:Notify', src, 'Congratulations on your purchase!', 'success')
        TriggerClientEvent('qb-vehicleshop:client:buyShowroomVehicle', src, vehicle, plate)
        pData.Functions.RemoveMoney('bank', downPayment, 'vehicle-bought-in-showroom')
    else
        TriggerClientEvent('QBCore:Notify', src, 'Not enough money', 'error')
    end
end)

-- Sell vehicle to customer
RegisterNetEvent('qb-vehicleshop:server:sellShowroomVehicle', function(data)
    local src = source
    local PlayerPed = GetPlayerPed(src)
    local pCoords = GetEntityCoords(PlayerPed)
    local player = QBCore.Functions.GetPlayer(src)
    for k, v in pairs(QBCore.Functions.GetPlayers()) do
        local TargetPed = GetPlayerPed(v)
        local tCoords = GetEntityCoords(TargetPed)
        local dist = #(pCoords - tCoords)
        if PlayerPed ~= TargetPed and dist < 1.0 then
            targetPlayer = QBCore.Functions.GetPlayer(v)
        end
    end
    if not targetPlayer then return TriggerClientEvent('QBCore:Notify', src, 'No one nearby', 'error') end
    local cid = targetPlayer.PlayerData.citizenid
    local cash = targetPlayer.PlayerData.money['cash']
    local bank = targetPlayer.PlayerData.money['bank']
    local vehicle = data.buyVehicle
    local vehiclePrice = QBCore.Shared.Vehicles[vehicle]['price']
    local plate = GeneratePlate()
    local commission = round(vehiclePrice * Config.Commission)
    if cash >= vehiclePrice then
        exports.oxmysql:insert('INSERT INTO player_vehicles (license, citizenid, vehicle, hash, mods, plate, state) VALUES (?, ?, ?, ?, ?, ?, ?)', {
            targetPlayer.PlayerData.license,
            cid,
            vehicle,
            GetHashKey(vehicle),
            '{}',
            plate,
            0
        })
        TriggerClientEvent('qb-vehicleshop:client:buyShowroomVehicle', targetPlayer.PlayerData.source, vehicle, plate)
        targetPlayer.Functions.RemoveMoney('cash', vehiclePrice, 'vehicle-bought-in-showroom')
        player.Functions.AddMoney('bank', commission)
        TriggerEvent('qb-bossmenu:server:addAccountMoney', player.PlayerData.job.name, vehiclePrice)
        TriggerClientEvent('QBCore:Notify', targetPlayer.PlayerData.source, 'Congratulations on your purchase!', 'success')
        TriggerClientEvent('QBCore:Notify', src, 'You earned $'..comma_value(commission)..' in commission', 'success')
    elseif bank >= vehiclePrice then
        exports.oxmysql:insert('INSERT INTO player_vehicles (license, citizenid, vehicle, hash, mods, plate, state) VALUES (?, ?, ?, ?, ?, ?, ?)', {
            targetPlayer.PlayerData.license,
            cid,
            vehicle,
            GetHashKey(vehicle),
            '{}',
            plate,
            0
        })
        TriggerClientEvent('qb-vehicleshop:client:buyShowroomVehicle', targetPlayer.PlayerData.source, vehicle, plate)
        targetPlayer.Functions.RemoveMoney('bank', vehiclePrice, 'vehicle-bought-in-showroom')
        player.Functions.AddMoney('bank', commission)
        TriggerEvent('qb-bossmenu:server:addAccountMoney', player.PlayerData.job.name, vehiclePrice)
        TriggerClientEvent('QBCore:Notify', targetPlayer.PlayerData.source, 'Congratulations on your purchase!', 'success')
        TriggerClientEvent('QBCore:Notify', src, 'You earned $'..comma_value(commission)..' in commission', 'success')
    else
        TriggerClientEvent('QBCore:Notify', src, 'Not enough money', 'error')
    end
end)

-- Finance vehicle to customer
RegisterNetEvent('qb-vehicleshop:server:sellfinanceVehicle', function(downPayment, paymentAmount, vehicle)
    local src = source
    local PlayerPed = GetPlayerPed(src)
    local pCoords = GetEntityCoords(PlayerPed)
    local player = QBCore.Functions.GetPlayer(src)
    for k, v in pairs(QBCore.Functions.GetPlayers()) do
        local TargetPed = GetPlayerPed(v)
        local tCoords = GetEntityCoords(TargetPed)
        local dist = #(pCoords - tCoords)
        if PlayerPed ~= TargetPed and dist < 1.0 then
            targetplayer = QBCore.Functions.GetPlayer(v)
        end
    end
    if not targetplayer then return TriggerClientEvent('QBCore:Notify', src, 'No one nearby', 'error') end
    local downPayment = tonumber(downPayment)
    local paymentAmount = tonumber(paymentAmount)
    local cid = targetplayer.PlayerData.citizenid
    local cash = targetplayer.PlayerData.money['cash']
    local bank = targetplayer.PlayerData.money['bank']
    local vehiclePrice = QBCore.Shared.Vehicles[vehicle]['price']
    local commission = round(vehiclePrice * Config.FinanceCommission)
    local timer = (Config.PaymentInterval * 60)
    local minDown = tonumber(round(vehiclePrice / Config.MinimumDown))
    if downPayment > vehiclePrice then return TriggerClientEvent('QBCore:Notify', src, 'Vehicle is not worth that much', 'error') end
    if downPayment < minDown then return TriggerClientEvent('QBCore:Notify', src, 'Down payment too small', 'error') end
    if paymentAmount > Config.MaximumPayments then return TriggerClientEvent('QBCore:Notify', src, 'Exceeded maximum payment amount', 'error') end
    local plate = GeneratePlate()
    local balance, vehPaymentAmount = calculateFinance(vehiclePrice, downPayment, paymentAmount)
    if cash >= downPayment then
        exports.oxmysql:insert('INSERT INTO player_vehicles (license, citizenid, vehicle, hash, mods, plate, state, balance, paymentamount, paymentsleft, financetime) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)', {
            targetplayer.PlayerData.license,
            cid,
            vehicle,
            GetHashKey(vehicle),
            '{}',
            plate,
            0,
            balance,
            vehPaymentAmount,
            paymentAmount,
            timer
        })
        TriggerClientEvent('qb-vehicleshop:client:buyShowroomVehicle', targetplayer.PlayerData.source, vehicle, plate)
        targetplayer.Functions.RemoveMoney('cash', downPayment, 'vehicle-bought-in-showroom')
        player.Functions.AddMoney('bank', commission)
        TriggerEvent('qb-bossmenu:server:addAccountMoney', player.PlayerData.job.name, vehiclePrice)
        TriggerClientEvent('QBCore:Notify', targetplayer.PlayerData.source, 'Congratulations on your purchase!', 'success')
        TriggerClientEvent('QBCore:Notify', src, 'You earned $'..comma_value(commission)..' in commission', 'success')
    elseif bank >= downPayment then
        exports.oxmysql:insert('INSERT INTO player_vehicles (license, citizenid, vehicle, hash, mods, plate, state, balance, paymentamount, paymentsleft, financetime) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)', {
            targetplayer.PlayerData.license,
            cid,
            vehicle,
            GetHashKey(vehicle),
            '{}',
            plate,
            0,
            balance,
            vehPaymentAmount,
            paymentAmount,
            timer
        })
        TriggerClientEvent('qb-vehicleshop:client:buyShowroomVehicle', targetplayer.PlayerData.source, vehicle, plate)
        targetplayer.Functions.RemoveMoney('bank', downPayment, 'vehicle-bought-in-showroom')
        player.Functions.AddMoney('bank', commission)
        TriggerEvent('qb-bossmenu:server:addAccountMoney', player.PlayerData.job.name, vehiclePrice)
        TriggerClientEvent('QBCore:Notify', targetplayer.PlayerData.source, 'Congratulations on your purchase!', 'success')
        TriggerClientEvent('QBCore:Notify', src, 'You earned $'..comma_value(commission)..' in commission', 'success')
    else
        TriggerClientEvent('QBCore:Notify', src, 'Not enough money', 'error')
    end
end)

-- Check if payment is due
RegisterNetEvent('qb-vehicleshop:server:checkFinance', function()
    local src = source
    local player = QBCore.Functions.GetPlayer(src)
    local result = exports.oxmysql:executeSync('SELECT * FROM player_vehicles WHERE citizenid = ?', {player.PlayerData.citizenid})
    for k,v in pairs(result) do
        if v.balance >= 1 and v.financetime < 1 then
            paymentDue = true
        end
    end
    if paymentDue then
        TriggerClientEvent('QBCore:Notify', src, 'Your vehicle payment is due within '..Config.PaymentWarning..' minutes')
        Wait(Config.PaymentWarning * 60000)
        exports.oxmysql:execute('SELECT * FROM player_vehicles WHERE citizenid = ?', {player.PlayerData.citizenid}, function(vehicles)
            for k,v in pairs(vehicles) do
                if v.balance >= 1 and v.financetime < 1 then
                    local plate = v.plate
                    exports.oxmysql:execute('DELETE FROM player_vehicles WHERE plate = @plate', {['@plate'] = plate})
                    TriggerClientEvent('QBCore:Notify', src, 'Your vehicle with plate '..plate..' has been repossessed', 'error')
                end
            end
        end)
    end
end)

-- Enter the persons Player ID to transfer them the vehicle (Must be close(5))
QBCore.Commands.Add('transfervehicle', 'Transfer Vehicle Ownership', {{name = 'id', help = 'Player ID'}}, true, function(source, args)
    local src = source
    local targetId = tonumber(args[1])
    local ped = GetPlayerPed(src)
    local target = GetPlayerPed(targetId)
    local sendingPlayer = QBCore.Functions.GetPlayer(src)
    local targetPlayer = QBCore.Functions.GetPlayer(targetId)
    local vehicle = GetVehiclePedIsIn(ped, false)
    local plate = GetVehicleNumberPlateText(vehicle)
    if targetId ~= nil then
        if vehicle ~= 0 then
            if target ~= 0 then
                local pedCoords = GetEntityCoords(ped)
                local targetCoords = GetEntityCoords(target)
                if #(pedCoords - targetCoords) < 5 then
                    local result = exports.oxmysql:scalarSync('SELECT citizenid from player_vehicles WHERE plate = :plate', {['plate'] = plate})
                    if result == sendingPlayer.PlayerData.citizenid then
                        exports.oxmysql:execute('UPDATE player_vehicles SET citizenid = :citizenid WHERE plate = :plate', {['citizenid'] = targetPlayer.PlayerData.citizenid, ['plate'] = plate})
                        TriggerClientEvent('QBCore:Notify', src, 'You Transferred Vehicle With Plate ' ..plate, 'success')
                        TriggerClientEvent('QBCore:Notify', targetId, 'You Received Vehicle With Plate ' ..plate, 'success')
                    else
                        TriggerClientEvent('QBCore:Notify', src, 'You Don\'t Own This Vehicle', 'error')
                    end
                else
                    TriggerClientEvent('QBCore:Notify', src, 'Player Too Far Away', 'error')
                end
            else
                TriggerClientEvent('QBCore:Notify', src, 'Player Not Online', 'error')
            end
        else
            TriggerClientEvent('QBCore:Notify', src, 'You Are Not In A Vehicle', 'error')
        end
    else
        TriggerClientEvent('QBCore:Notify', src, 'Must Specify ID', 'error')
    end
end)
