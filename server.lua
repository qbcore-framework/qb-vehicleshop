-- Variables
local QBCore = exports['qb-core']:GetCoreObject()
local financetimer = {}

-- Handlers
RegisterNetEvent('vehicleshop:server:alert', function(message)
    print(message)
end)
-- Store game time for player when they load
RegisterNetEvent('qb-vehicleshop:server:addPlayer', function(citizenid)
    financetimer[citizenid] = os.time()
end)

-- Deduct stored game time from player on logout
RegisterNetEvent('qb-vehicleshop:server:removePlayer', function(citizenid)
    if financetimer[citizenid] then
        local playTime = financetimer[citizenid]
        local financetime = MySQL.query.await('SELECT * FROM player_vehicles WHERE citizenid = ?', {citizenid})
        for _, v in pairs(financetime) do
            if v.balance >= 1 then
                local newTime = (v.financetime-((os.time()-playTime)/60))
                if newTime < 0 then newTime = 0 end
                MySQL.update('UPDATE player_vehicles SET financetime = ? WHERE plate = ?', {math.ceil(newTime), v.plate})
            end
        end
    end
    financetimer[citizenid] = nil
end)

-- Deduct stored game time from player on quit because we can't get citizenid
AddEventHandler('playerDropped', function()
    local src = source
    local license
    for _, v in pairs(GetPlayerIdentifiers(src)) do
        if string.sub(v, 1, string.len("license:")) == "license:" then
            license = v
        end
    end
    if license then
        local vehicles = MySQL.query.await('SELECT * FROM player_vehicles WHERE license = ?', {license})
        if vehicles then
            for _, v in pairs(vehicles) do
                local playTime = financetimer[v.citizenid]
                if v.balance >= 1 and playTime then
                    local newTime = (v.financetime-((os.time()-playTime)/60))
                    if newTime < 0 then newTime = 0 end
                    MySQL.update('UPDATE player_vehicles SET financetime = ? WHERE plate = ?', {math.ceil(newTime), v.plate})
                end
            end
            if vehicles[1] and financetimer[vehicles[1].citizenid] then financetimer[vehicles[1].citizenid] = nil end
        end
    end
end)

-- Functions
local function round(x)
    return x >= 0 and math.floor(x + 0.5) or math.ceil(x - 0.5)
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
    local result = MySQL.scalar.await('SELECT plate FROM player_vehicles WHERE plate = ?', {plate})
    if result then
        return GeneratePlate()
    else
        return plate:upper()
    end
end

local function JobsPlateGen(res)
    local plate = res.platePrefix .. tostring(math.random(1000, 9999))
    local dbRes = MySQL.scalar.await('SELECT plate FROM player_vehicles WHERE plate = ?', {plate})
    if res.selGar == "ownGarage" then
        if res.vehTrack and res.vehTrack[res.plate] and DoesEntityExist(res.vehTrack[res.plate].veh) then
            TriggerClientEvent('QBCore:Notify', res.source, Lang:t('error.vehexists'), 'error')
            return false
        end
        plate = res.plate
    elseif dbRes and res.vehTrack and DoesEntityExist(res.vehTrack[plate].veh) then
        return JobsPlateGen()
    end
    QBCore.Debug("here " .. plate:upper())
    return plate:upper()
end
exports("JobsPlateGen", JobsPlateGen)

local function comma_value(amount)
    local formatted = amount
    local k
    while true do
        formatted, k = string.gsub(formatted, '^(-?%d+)(%d%d%d)', '%1,%2')
        if (k == 0) then
            break
        end
    end
    return formatted
end

-- DB Insertion Function
local function vehDBInsert(res)
    local dbCheck
    local msg = {}
    if res.vehOption == "purchase" then
        dbCheck = MySQL.insert.await('INSERT INTO player_vehicles (license, citizenid, vehicle, hash, mods, plate, garage, state) VALUES (?,?,?,?,?,?,?,?)', {
            res.veh.license,
            res.veh.cid,
            res.veh.vehicle,
            GetHashKey(res.veh.vehicle),
            '{}',
            res.veh.plate,
            'pillboxgarage',
            0
        })
        msg[1] = "purchased"
    elseif res.vehOption == "finance" then
        dbCheck = MySQL.insert.await('INSERT INTO player_vehicles (license, citizenid, vehicle, hash, mods, plate, garage, state, balance, paymentamount, paymentsleft, financetime) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)', {
            res.veh.license,
            res.veh.cid,
            res.veh.vehicle,
            GetHashKey(res.veh.vehicle),
            '{}',
            res.veh.plate,
            'pillboxgarage',
            0,
            res.veh.balance,
            res.veh.vehPaymentAmount,
            res.veh.paymentAmount,
            res.veh.timer
        })
        msg[1] = "financed"
    elseif res.vehOption == "jobs" then
        dbCheck = MySQL.insert.await('INSERT INTO player_vehicles (license, citizenid, vehicle, hash, mods, plate, garage, state, job) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)', {
            res.veh.license,
            res.veh.cid,
            res.veh.vehicle,
            GetHashKey(res.veh.vehicle),
            '{}',
            res.veh.plate,
            'pillboxgarage',
            0,
            res.veh.jobName
        })
        msg[1] = "purchased"
    end
    msg[2] = res.veh.cid .. " has " .. msg[1] .. " a " .. res.veh.vehicle .. " with plate " .. res.veh.plate
    TriggerEvent('qb-log:server:CreateLog', 'vehicleshop', 'Vehicle '..msg[1], 'green', msg[2])
    if dbCheck then return dbCheck end
    return dbCheck
end

-- Buy QB-Jobs Vehicle Outright
local function BuyJobsVehicle(res)
    local player = res.player
    local PlayerJob = player.PlayerData.job
    local cid = player.PlayerData.citizenid
    local approved
    local vehList
    local data = {veh = {}}
    if QBCore.Shared.Jobs[PlayerJob.name].Vehicles then
        vehList = QBCore.Shared.Jobs[PlayerJob.name].Vehicles
    else
        vehList = exports['qb-jobs']:AddJobs()
    end

    if vehList then
        local cash = player.PlayerData.money['cash']
        local bank = player.PlayerData.money['bank']
        local vehiclePrice = vehList[res.vehicle].purchasePrice
        local plate = JobsPlateGen(res)
        if cash > tonumber(vehiclePrice) then
            approved = "cash"
        elseif bank > tonumber(vehiclePrice) then
            approved = "bank"
        else
            TriggerClientEvent('QBCore:Notify', res.source, Lang:t('error.notenoughmoney'), 'error')
            return false
        end
        data.vehOption = "jobs"
        data.veh.license = player.PlayerData.license
        data.veh.cid = cid
        data.veh.vehicle = res.vehicle
        data.veh.plate = plate
        data.veh.jobName = PlayerJob.name
        QBCore.Debug(PlayerJob)
        local dbCheck = vehDBInsert(data)
        if dbCheck and approved then
            player.Functions.RemoveMoney(approved, vehiclePrice, 'vehicle-bought-from-job')
            exports['qb-management']:AddMoney(PlayerJob.name, vehiclePrice)
            TriggerClientEvent('QBCore:Notify', res.source, Lang:t('success.purchased'), 'success')
            return true
        end
    end
end
exports("BuyJobsVehicle",BuyJobsVehicle)

-- Callbacks
QBCore.Functions.CreateCallback('qb-vehicleshop:server:getVehicles', function(source, cb)
    local src = source
    local player = QBCore.Functions.GetPlayer(src)
    if player then
        local vehicles = MySQL.query.await('SELECT * FROM player_vehicles WHERE citizenid = ?', {player.PlayerData.citizenid})
        if vehicles[1] then
            cb(vehicles)
        end
    end
end)

-- Events
RegisterNetEvent('QBCore:Server:UpdateObject', function()
	if source ~= '' then return false end
	QBCore = exports['qb-core']:GetCoreObject()
end)
-- Brute force vehicle deletion
RegisterNetEvent('qb-vehicleshop:server:deleteVehicle', function (netId)
    local vehicle = NetworkGetEntityFromNetworkId(netId)
    DeleteEntity(vehicle)
end)

-- Sync vehicle for other players
RegisterNetEvent('qb-vehicleshop:server:swapVehicle', function(data)
    local src = source
    TriggerClientEvent('qb-vehicleshop:client:swapVehicle', -1, data)
    Wait(1500)-- let new car spawn
    TriggerClientEvent('qb-vehicleshop:client:homeMenu', src)-- reopen main menu
end)

-- Send customer for test drive
RegisterNetEvent('qb-vehicleshop:server:customTestDrive', function(vehicle, playerid)
    local src = source
    local target = tonumber(playerid)
    if not QBCore.Functions.GetPlayer(target) then
        TriggerClientEvent('QBCore:Notify', src, Lang:t('error.Invalid_ID'), 'error')
        return
    end
    if #(GetEntityCoords(GetPlayerPed(src)) - GetEntityCoords(GetPlayerPed(target))) < 3 then
        TriggerClientEvent('qb-vehicleshop:client:customTestDrive', target, vehicle)
    else
        TriggerClientEvent('QBCore:Notify', src, Lang:t('error.playertoofar'), 'error')
    end
end)

-- Make a finance payment (Send to QB-Bank)
RegisterNetEvent('qb-vehicleshop:server:financePayment', function(paymentAmount, vehData)
    local src = source
    local player = QBCore.Functions.GetPlayer(src)
    local cash = player.PlayerData.money['cash']
    local bank = player.PlayerData.money['bank']
    local plate = vehData.vehiclePlate
    paymentAmount = tonumber(paymentAmount)
    local minPayment = tonumber(vehData.paymentAmount)
    local timer = (Config.PaymentInterval * 60)
    local newBalance, newPaymentsLeft, newPayment = calculateNewFinance(paymentAmount, vehData)
    local approved
    if newBalance > 0 then
        if player and paymentAmount >= minPayment then
            if cash >= paymentAmount then approved = "cash"
            elseif bank >= paymentAmount then approved = "bank"
            else
                TriggerClientEvent('QBCore:Notify', src, Lang:t('error.notenoughmoney'), 'error')
                return false
            end
                player.Functions.RemoveMoney(approved, paymentAmount)
                MySQL.update('UPDATE player_vehicles SET balance = ?, paymentamount = ?, paymentsleft = ?, financetime = ? WHERE plate = ?', {newBalance, newPayment, newPaymentsLeft, timer, plate})
        end
    else
        TriggerClientEvent('QBCore:Notify', src, Lang:t('error.overpaid'), 'error')
    end
end)

-- Pay off vehice in full (Send to QB-Bank)
RegisterNetEvent('qb-vehicleshop:server:financePaymentFull', function(data)
    local src = source
    local player = QBCore.Functions.GetPlayer(src)
    local cash = player.PlayerData.money['cash']
    local bank = player.PlayerData.money['bank']
    local vehBalance = data.vehBalance
    local vehPlate = data.vehPlate
    local amount
    if player and vehBalance ~= 0 then
        if cash >= vehBalance then amount = "cash"
        elseif bank >= vehBalance then amount = "bank"
        else
            TriggerClientEvent('QBCore:Notify', src, Lang:t('error.notenoughmoney'), 'error')
            return false
        end
            player.Functions.RemoveMoney(amount, vehBalance)
            player.Functions.RemoveMoney(amount, vehBalance)
            MySQL.update('UPDATE player_vehicles SET balance = ?, paymentamount = ?, paymentsleft = ?, financetime = ? WHERE plate = ?', {0, 0, 0, 0, vehPlate})
    else
        TriggerClientEvent('QBCore:Notify', src, Lang:t('error.alreadypaid'), 'error')
    end
end)

-- Buy public vehicle outright
RegisterNetEvent('qb-vehicleshop:server:buyShowroomVehicle', function(vehicle)
    local src = source
    vehicle = vehicle.buyVehicle
    local player = QBCore.Functions.GetPlayer(src)
    if not player.PlayerData.license then
        TriggerClientEvent('QBCore:Notify', source, Lang:t('error.missingLicense'), 'error')
        return
    end
    local cid = player.PlayerData.citizenid
    local cash = player.PlayerData.money['cash']
    local bank = player.PlayerData.money['bank']
    local vehiclePrice = QBCore.Shared.Vehicles[vehicle]['price']
    local plate = GeneratePlate()
    local approved
    local data = {veh = {}}
    if cash > tonumber(vehiclePrice) then approved = "cash"
    elseif bank > tonumber(vehiclePrice) then approved = "bank" end
    if approved then
        data.vehOption = "purchase"
        data.veh.license = player.PlayerData.license
        data.veh.cid = cid
        data.veh.vehicle = vehicle
        data.veh.plate = plate
        local dbCheck = vehDBInsert(data)
        if dbCheck then
            TriggerClientEvent('QBCore:Notify', src, Lang:t('success.purchased'), 'success')
            TriggerClientEvent('qb-vehicleshop:client:buyShowroomVehicle', src, vehicle, plate)
            player.Functions.RemoveMoney(approved, vehiclePrice, 'vehicle-bought-in-showroom')
        end
    else
        TriggerClientEvent('QBCore:Notify', src, Lang:t('error.notenoughmoney'), 'error')
    end
end)

-- Finance public vehicle (Send to QB-Bank)
RegisterNetEvent('qb-vehicleshop:server:financeVehicle', function(downPayment, paymentAmount, vehicle)
    local src = source
    downPayment = tonumber(downPayment)
    paymentAmount = tonumber(paymentAmount)
    local player = QBCore.Functions.GetPlayer(src)
    local approved
    local data = {veh = {}}
    local cid = player.PlayerData.citizenid
    local cash = player.PlayerData.money['cash']
    local bank = player.PlayerData.money['bank']
    local vehiclePrice = QBCore.Shared.Vehicles[vehicle]['price']
    local timer = (Config.PaymentInterval * 60)
    local minDown = tonumber(round((Config.MinimumDown / 100) * vehiclePrice))
    if downPayment > vehiclePrice then return TriggerClientEvent('QBCore:Notify', src, Lang:t('error.notworth'), 'error') end
    if downPayment < minDown then return TriggerClientEvent('QBCore:Notify', src, Lang:t('error.downtoosmall'), 'error') end
    if paymentAmount > Config.MaximumPayments then return TriggerClientEvent('QBCore:Notify', src, Lang:t('error.exceededmax'), 'error') end
    local plate = GeneratePlate()
    local balance, vehPaymentAmount = calculateFinance(vehiclePrice, downPayment, paymentAmount)
    if cash >= downPayment then approved = "cash"
    elseif bank >= downPayment then approved = "bank"
    else
        TriggerClientEvent('QBCore:Notify', src, Lang:t('error.notenoughmoney'), 'error')
        return false
    end
    data.vehOption = "finance"
    data.veh.license = player.PlayerData.license
    data.veh.cid = cid
    data.veh.vehicle = vehicle
    data.veh.plate = plate
    data.veh.balance = balance
    data.veh.vehPaymentAmount = vehPaymentAmount
    data.veh.paymentAmount = paymentAmount
    data.veh.timer = timer
    local dbCheck = vehDBInsert(data)
    if dbCheck then
        TriggerClientEvent('QBCore:Notify', src, Lang:t('success.purchased'), 'success')
        TriggerClientEvent('qb-vehicleshop:client:buyShowroomVehicle', src, vehicle, plate)
        player.Functions.RemoveMoney(approved, downPayment, 'vehicle-bought-in-showroom')
    end
end)

-- Sell vehicle to customer
RegisterNetEvent('qb-vehicleshop:server:sellShowroomVehicle', function(vehicle, playerid)
    local src = source
    local player = QBCore.Functions.GetPlayer(src)
    local target = QBCore.Functions.GetPlayer(tonumber(playerid))
    local approved
    local data = {veh = {}}
    if not target then
        TriggerClientEvent('QBCore:Notify', src, Lang:t('error.Invalid_ID'), 'error')
        return
    end
    if #(GetEntityCoords(GetPlayerPed(src)) - GetEntityCoords(GetPlayerPed(target.PlayerData.source))) < 3 then
        local cid = target.PlayerData.citizenid
        local cash = target.PlayerData.money['cash']
        local bank = target.PlayerData.money['bank']
        local vehiclePrice = QBCore.Shared.Vehicles[vehicle]['price']
        local commission = round(vehiclePrice * Config.Commission)
        local netvehPrice = vehiclePrice - commission
        local plate = GeneratePlate()
        if cash >= tonumber(vehiclePrice) then approved = "cash"
        elseif bank >= tonumber(vehiclePrice) then approved = "bank"
        else
            TriggerClientEvent('QBCore:Notify', src, Lang:t('error.notenoughmoney'), 'error')
            return false
        end
        data.vehOption = "purchase"
        data.veh.license = player.PlayerData.license
        data.veh.cid = cid
        data.veh.vehicle = vehicle
        data.veh.plate = plate
        local dbCheck = vehDBInsert(data)
        if dbCheck then
            TriggerClientEvent('qb-vehicleshop:client:buyShowroomVehicle', target.PlayerData.source, vehicle, plate)
            target.Functions.RemoveMoney(approved, vehiclePrice, 'vehicle-bought-in-showroom')
            player.Functions.AddMoney('bank', commission)
            TriggerClientEvent('QBCore:Notify', src, Lang:t('success.earned_commission', {amount = comma_value(commission)}), 'success')
            exports['qb-management']:AddMoney(player.PlayerData.job.name, netvehPrice)
            TriggerClientEvent('QBCore:Notify', target.PlayerData.source, Lang:t('success.purchased'), 'success')
        end
    else
        TriggerClientEvent('QBCore:Notify', src, Lang:t('error.playertoofar'), 'error')
    end
end)

-- Finance vehicle to customer (Send to QB-Bank)
RegisterNetEvent('qb-vehicleshop:server:sellfinanceVehicle', function(downPayment, paymentAmount, vehicle, playerid)
    local src = source
    local player = QBCore.Functions.GetPlayer(src)
    local target = QBCore.Functions.GetPlayer(tonumber(playerid))

    if not target then
        TriggerClientEvent('QBCore:Notify', src, Lang:t('error.Invalid_ID'), 'error')
        return
    end

    if #(GetEntityCoords(GetPlayerPed(src)) - GetEntityCoords(GetPlayerPed(target.PlayerData.source))) < 3 then
        downPayment = tonumber(downPayment)
        paymentAmount = tonumber(paymentAmount)
        local approved
        local data = {veh = {}}
        local cid = target.PlayerData.citizenid
        local cash = target.PlayerData.money['cash']
        local bank = target.PlayerData.money['bank']
        local vehiclePrice = QBCore.Shared.Vehicles[vehicle]['price']
        local timer = (Config.PaymentInterval * 60)
        local minDown = tonumber(round((Config.MinimumDown / 100) * vehiclePrice))
        if downPayment > vehiclePrice then return TriggerClientEvent('QBCore:Notify', src, Lang:t('error.notworth'), 'error') end
        if downPayment < minDown then return TriggerClientEvent('QBCore:Notify', src, Lang:t('error.downtoosmall'), 'error') end
        if paymentAmount > Config.MaximumPayments then return TriggerClientEvent('QBCore:Notify', src, Lang:t('error.exceededmax'), 'error') end
        local commission = round(vehiclePrice * Config.Commission)
        local netvehPrice = vehiclePrice - commission
        local plate = GeneratePlate()
        local balance, vehPaymentAmount = calculateFinance(vehiclePrice, downPayment, paymentAmount)
        if cash >= downPayment then approved = "cash"
        elseif bank >= downPayment then approved = "bank"
        else
            TriggerClientEvent('QBCore:Notify', src, Lang:t('error.notenoughmoney'), 'error')
            return false
        end
        data.vehOption = "finance"
        data.veh.license = player.PlayerData.license
        data.veh.cid = cid
        data.veh.vehicle = vehicle
        data.veh.plate = plate
        data.veh.balance = balance
        data.veh.vehPaymentAmount = vehPaymentAmount
        data.veh.paymentAmount = paymentAmount
        data.veh.timer = timer
        local dbCheck = vehDBInsert(data)
        if dbCheck then
            TriggerClientEvent('qb-vehicleshop:client:buyShowroomVehicle', target.PlayerData.source, vehicle, plate)
            target.Functions.RemoveMoney(approved, downPayment, 'vehicle-bought-in-showroom')
            player.Functions.AddMoney(approved, commission)
            TriggerClientEvent('QBCore:Notify', src, Lang:t('success.earned_commission', {amount = comma_value(commission)}), 'success')
            exports['qb-management']:AddMoney(player.PlayerData.job.name, netvehPrice)
            TriggerClientEvent('QBCore:Notify', target.PlayerData.source, Lang:t('success.purchased'), 'success')
        end
    else
        TriggerClientEvent('QBCore:Notify', src, Lang:t('error.playertoofar'), 'error')
    end
end)

-- Check if payment is due (Send to QB-Bank)
RegisterNetEvent('qb-vehicleshop:server:checkFinance', function()
    local src = source
    local player = QBCore.Functions.GetPlayer(src)
    local msg = {}
    local query = 'SELECT * FROM player_vehicles WHERE citizenid = ? AND balance > 0 AND financetime < 1'
    local result = MySQL.query.await(query, {player.PlayerData.citizenid})
    if result[1] then
        TriggerClientEvent('QBCore:Notify', src, Lang:t('general.paymentduein', {time = Config.PaymentWarning}))
        Wait(Config.PaymentWarning * 60000)
        local vehicles = MySQL.query.await(query, {player.PlayerData.citizenid})
        for _, v in pairs(vehicles) do
            local plate = v.plate
            if Config.repoDelete then
                MySQL.query('DELETE FROM player_vehicles WHERE plate = @plate', {['@plate'] = plate})
            else
               MySQL.update('UPDATE player_vehicles SET citizenid = ? WHERE plate = ?', {'REPO-'..v.citizenid, plate}) -- Use this if you don't want them to be deleted
            end
            TriggerClientEvent('QBCore:Notify', src, Lang:t('error.repossessed', {plate = plate}), 'error')
            msg[1] = "vehicle " .. v.plate .." has been reposessed for non-payment from " .. player.PlayerData.citizenid
            TriggerEvent('qb-log:server:CreateLog', 'vehicleshop', 'Vehicle Reposessed', 'green', msg[1])
        end
    end
end)

-- Transfer vehicle to player in passenger seat
QBCore.Commands.Add('transfervehicle', Lang:t('general.command_transfervehicle'), {{name = 'ID', help = Lang:t('general.command_transfervehicle_help')}, {name = 'amount', help = Lang:t('general.command_transfervehicle_amount')}}, false, function(source, args)
    local src = source
    local approved
    local msg = {}
    local buyerId = tonumber(args[1])
    local sellAmount = tonumber(args[2])
    if buyerId == 0 then return TriggerClientEvent('QBCore:Notify', src, Lang:t('error.Invalid_ID'), 'error') end
    local ped = GetPlayerPed(src)
    local targetPed = GetPlayerPed(buyerId)
    if targetPed == 0 then return TriggerClientEvent('QBCore:Notify', src, Lang:t('error.buyerinfo'), 'error') end
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 then return TriggerClientEvent('QBCore:Notify', src, Lang:t('error.notinveh'), 'error') end
    local plate = QBCore.Shared.Trim(GetVehicleNumberPlateText(vehicle))
    if not plate then return TriggerClientEvent('QBCore:Notify', src, Lang:t('error.vehinfo'), 'error') end
    local player = QBCore.Functions.GetPlayer(src)
    local target = QBCore.Functions.GetPlayer(buyerId)
    local row = MySQL.single.await('SELECT * FROM player_vehicles WHERE plate = ?', {plate})
    if Config.PreventFinanceSelling then
        if row.balance > 0 then return TriggerClientEvent('QBCore:Notify', src, Lang:t('error.financed'), 'error') end
    end
    if row.citizenid ~= player.PlayerData.citizenid then return TriggerClientEvent('QBCore:Notify', src, Lang:t('error.notown'), 'error') end
    if #(GetEntityCoords(ped) - GetEntityCoords(targetPed)) > 5.0 then return TriggerClientEvent('QBCore:Notify', src, Lang:t('error.playertoofar'), 'error') end
    local targetcid = target.PlayerData.citizenid
    local targetlicense = QBCore.Functions.GetIdentifier(target.PlayerData.source, 'license')
    if not target then return TriggerClientEvent('QBCore:Notify', src, Lang:t('error.buyerinfo'), 'error') end
    if not sellAmount then
        TriggerClientEvent('QBCore:Notify', src, Lang:t('success.gifted'), 'success')
        TriggerClientEvent('vehiclekeys:client:SetOwner', buyerId, plate)
        TriggerClientEvent('QBCore:Notify', buyerId, Lang:t('success.received_gift'), 'success')
    elseif target.Functions.GetMoney('cash') > sellAmount then
        approved = "cash"
    elseif target.Functions.GetMoney('bank') > sellAmount then
        approved = "bank"
    else
        TriggerClientEvent('QBCore:Notify', src, Lang:t('error.buyertoopoor'), 'error')
        return false
    end
    TriggerClientEvent('QBCore:Notify', src, Lang:t('success.soldfor') .. comma_value(sellAmount), 'success')
    TriggerClientEvent('vehiclekeys:client:SetOwner', buyerId, plate)
    TriggerClientEvent('QBCore:Notify', buyerId, Lang:t('success.boughtfor') .. comma_value(sellAmount), 'success')
    msg[1] = player.PlayerData.citizenid .. " transferred vehicle to " .. target.PlayerData.citizenid
    TriggerEvent('qb-log:server:CreateLog', 'vehicleshop', 'Vehicle Transferred', 'green', msg[1])
    player.Functions.AddMoney(approved, sellAmount)
    target.Functions.RemoveMoney(approved, sellAmount)
    MySQL.update.await('UPDATE player_vehicles SET citizenid = ?, license = ? WHERE plate = ?', {targetcid, targetlicense, plate})
end)
