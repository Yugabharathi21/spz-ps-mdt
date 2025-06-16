-- Framework Detection
local Framework = nil
local QBCore, ESX = nil, nil

if Config.Framework == "qb" then
    QBCore = exports['qb-core']:GetCoreObject()
    Framework = QBCore
elseif Config.Framework == "esx" then
    ESX = exports['es_extended']:getSharedObject()
    Framework = ESX
end

-- Variables
local incidents = {}
local convictions = {}
local bolos = {}
local MugShots = {}
local activeUnits = {}
local impound = {}
local dispatchMessages = {}
local isDispatchRunning = false
local antiSpam = false
local calls = {}

--------------------------------
-- API Configuration
--------------------------------
-- Fivemerr API (Recommended)
local FivemerrMugShot = 'https://api.fivemerr.com/v1/media/images'
local FivemerrApiKey = 'YOUR API KEY HERE'

-- Webhooks
local MugShotWebhook = ''  -- For mugshot images (not recommended, use Fivemerr instead)
local ClockinWebhook = ''  -- For duty notifications and /mdtleaderboard
local IncidentWebhook = '' -- For incident notifications

--------------------------------
-- Helper Functions
--------------------------------
local function RegisterCallback(name, cb)
    if Config.Framework == "qb" then
        QBCore.Functions.CreateCallback(name, cb)
    elseif Config.Framework == "esx" then
        ESX.RegisterServerCallback(name, cb)
    end
end

local function GetPlayer(source)
    if Config.Framework == "qb" then
        return QBCore.Functions.GetPlayer(source)
    elseif Config.Framework == "esx" then
        return ESX.GetPlayerFromId(source)
    end
end

local function GetPlayerByCitizenId(citizenid)
    if Config.Framework == "qb" then
        return QBCore.Functions.GetPlayerByCitizenId(citizenid)
    elseif Config.Framework == "esx" then
        return ESX.GetPlayerFromIdentifier(citizenid)
    end
end

local function GetPlayerName(player)
    if Config.Framework == "qb" then
        return player.PlayerData.charinfo.firstname .. ' ' .. player.PlayerData.charinfo.lastname
    elseif Config.Framework == "esx" then
        return player.get('firstName') .. ' ' .. player.get('lastName')
    end
end

local function GetPlayerJob(player)
    if Config.Framework == "qb" then
        return player.PlayerData.job
    elseif Config.Framework == "esx" then
        return player.getJob()
    end
end

local function IsPolice(player)
    if Config.Framework == "qb" then
        return player.PlayerData.job.name == "police"
    elseif Config.Framework == "esx" then
        return player.job.name == "police"
    end
end

-- Time Formatting
function format_time(time)
    local days = math.floor(time / 86400)
    time = time % 86400
    local hours = math.floor(time / 3600)
    time = time % 3600
    local minutes = math.floor(time / 60)
    local seconds = time % 60
    
    if days > 0 then
        return string.format("%dd %dh %dm %ds", days, hours, minutes, seconds)
    elseif hours > 0 then
        return string.format("%dh %dm %ds", hours, minutes, seconds)
    elseif minutes > 0 then
        return string.format("%dm %ds", minutes, seconds)
    else
        return string.format("%ds", seconds)
    end
end

-- Discord Webhook Functions
function sendToDiscord(webhook, name, message, color, footer)
    if webhook == '' then return end
    
    local embed = {
        {
            ["color"] = color,
            ["title"] = "**".. name .."**",
            ["description"] = message,
            ["footer"] = {
                ["text"] = footer,
            },
        }
    }
    
    PerformHttpRequest(webhook, function(err, text, headers) end, 'POST', json.encode({username = name, embeds = embed}), { ['Content-Type'] = 'application/json' })
end

function sendIncidentToDiscord(color, name, message, footer, associatedData)
    if IncidentWebhook == '' then return end
    local pingMessage = ""
    
    if associatedData then
        if associatedData.charges and #associatedData.charges > 0 then
            local chargesTable = {}
            for _, charge in ipairs(associatedData.charges) do
                table.insert(chargesTable, "- " .. charge)
            end
            local chargeList = table.concat(chargesTable, "\n")
            message = message .. "\n**Charges:** \n" .. chargeList
        else
            message = message .. "\n**Charges: No Charges**"
        end

        if associatedData.guilty == false then
            pingMessage = "**Guilty: Not Guilty - Need Court Case**"
            message = message .. "\n" .. pingMessage
        end
    end

    local embed = {
        {
            color = color,
            title = "**".. name .."**",
            description = message,
            footer = {
                text = footer,
            },
        }
    }

    PerformHttpRequest(IncidentWebhook, function(err, text, headers) end, 'POST', json.encode({content = pingMessage ~= "" and pingMessage or nil, username = name, embeds = embed}), { ['Content-Type'] = 'application/json' })
end

-- MDT Callbacks
RegisterCallback('ps-mdt:server:MugShotWebhook', function(source, cb)
    if Config.MugShotWebhook then
        if MugShotWebhook == '' then
            print("\27[31mA webhook is missing in: MugShotWebhook (server > main.lua)\27[0m")
            cb('', '')
        else
            cb(MugShotWebhook, '')
        end
    elseif Config.FivemerrMugShot then
        if FivemerrApiKey == 'YOUR API KEY HERE' then
            print("\27[31mPlease add your Fivemerr API key in: FivemerrApiKey (server > main.lua)\27[0m")
            cb('', '')
        else
            cb(FivemerrMugShot, FivemerrApiKey)
        end
    end
end)

-- Profile Search
RegisterCallback('mdt:server:SearchProfile', function(source, cb, sentData)
    local src = source
    local Player = GetPlayer(src)
    if not Player then return cb({}) end
    
    local JobType = GetPlayerJob(Player)
    if not IsPolice(Player) then return cb({}) end
    
    local query
    local queryParams = {}
    
    if Config.Framework == "qb" then
        query = "SELECT p.*, json_extract(charinfo, '$.firstname') as firstname, json_extract(charinfo, '$.lastname') as lastname FROM players p"
        if sentData.query then
            query = query .. " WHERE LOWER(json_extract(charinfo, '$.firstname')) LIKE ? OR LOWER(json_extract(charinfo, '$.lastname')) LIKE ? OR LOWER(citizenid) LIKE ?"
            local searchTerm = string.lower('%'..sentData.query..'%')
            queryParams = {searchTerm, searchTerm, searchTerm}
        end
    else
        query = "SELECT identifier as citizenid, firstname, lastname, job, metadata FROM users"
        if sentData.query then
            query = query .. " WHERE LOWER(firstname) LIKE ? OR LOWER(lastname) LIKE ? OR LOWER(identifier) LIKE ?"
            local searchTerm = string.lower('%'..sentData.query..'%')
            queryParams = {searchTerm, searchTerm, searchTerm}
        end
    end
    
    local results = MySQL.query.await(query, queryParams)
    if not results then return cb({}) end
    
    local profiles = {}
    for _, v in ipairs(results) do
        local fingerprint = json.decode(v.metadata or '{}').fingerprint
        local pfp = MugShots[v.citizenid] or ""
        
        local profile = {
            citizenid = v.citizenid,
            firstname = v.firstname,
            lastname = v.lastname,
            fingerprint = fingerprint,
            pfp = pfp,
            mdtinfo = v.mdtinfo,
            job = Config.Framework == "qb" and json.decode(v.job or '{}') or v.job,
            convictions = convictions[v.citizenid] or 0
        }
        table.insert(profiles, profile)
    end
    
    cb(profiles)
end)

-- Vehicle Search
RegisterCallback('mdt:server:SearchVehicles', function(source, cb, sentData)
    local src = source
    local Player = GetPlayer(src)
    if not Player then return cb({}) end
    
    if not IsPolice(Player) then return cb({}) end
    
    local vehicles = {}
    local query, queryParams
    
    if Config.Framework == "qb" then
        query = [[
            SELECT v.*, p.charinfo
            FROM player_vehicles v
            LEFT JOIN players p ON p.citizenid = v.citizenid
            WHERE LOWER(plate) LIKE ? OR LOWER(v.citizenid) LIKE ?
        ]]
    else
        query = [[
            SELECT v.*, u.firstname, u.lastname
            FROM owned_vehicles v
            LEFT JOIN users u ON u.identifier = v.owner
            WHERE LOWER(plate) LIKE ? OR LOWER(v.owner) LIKE ?
        ]]
    end
    
    local searchTerm = string.lower('%'..sentData.query..'%')
    local results = MySQL.query.await(query, {searchTerm, searchTerm})
    
    if results then
        for _, vehicle in pairs(results) do
            local ownerName
            if Config.Framework == "qb" then
                local charinfo = json.decode(vehicle.charinfo or '{}')
                ownerName = charinfo.firstname .. ' ' .. charinfo.lastname
            else
                ownerName = vehicle.firstname .. ' ' .. vehicle.lastname
            end
            
            local vehicleData = {
                plate = vehicle.plate,
                citizenid = Config.Framework == "qb" and vehicle.citizenid or vehicle.owner,
                model = vehicle.vehicle,
                owner = ownerName,
                stolen = vehicle.stolen or false,
                code = vehicle.code or 'None',
                image = vehicle.image or '',
                info = vehicle.info or ''
            }
            table.insert(vehicles, vehicleData)
        end
    end
    
    cb(vehicles)
end)

-- Framework-specific Events
RegisterNetEvent("ps-mdt:dispatchStatus", function(bool)
	isDispatchRunning = bool
end)

if Config.UseWolfknightRadar == true then
	RegisterNetEvent("wk:onPlateScanned")
	AddEventHandler("wk:onPlateScanned", function(cam, plate, index)
		local src = source
		local Player = QBCore.Functions.GetPlayer(src)
		local PlayerData = GetPlayerData(src)
		local vehicleOwner = GetVehicleOwner(plate)
		local bolo, title, boloId = GetBoloStatus(plate)
		local warrant, owner, incidentId = GetWarrantStatus(plate)
		local driversLicense = PlayerData.metadata['licences'].driver

		if bolo == true then
			TriggerClientEvent('QBCore:Notify', src, 'BOLO ID: '..boloId..' | Title: '..title..' | Registered Owner: '..vehicleOwner..' | Plate: '..plate, 'error', Config.WolfknightNotifyTime)
		end
		if warrant == true then
			TriggerClientEvent('QBCore:Notify', src, 'WANTED - INCIDENT ID: '..incidentId..' | Registered Owner: '..owner..' | Plate: '..plate, 'error', Config.WolfknightNotifyTime)
		end

		if Config.PlateScanForDriversLicense and driversLicense == false and vehicleOwner then
			TriggerClientEvent('QBCore:Notify', src, 'NO DRIVERS LICENCE | Registered Owner: '..vehicleOwner..' | Plate: '..plate, 'error', Config.WolfknightNotifyTime)
		end

		if bolo or warrant or (Config.PlateScanForDriversLicense and not driversLicense) and vehicleOwner then
			TriggerClientEvent("wk:togglePlateLock", src, cam, true, 1)
		end
	end)
end

AddEventHandler('onResourceStart', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    Wait(3000)
    if Config.MugShotWebhook and MugShotWebhook == '' then
        print("\27[31mA webhook is missing in: MugShotWebhook (server > main.lua > line 16)\27[0m")
    end
    if Config.FivemerrMugShot and FivemerrMugShot == '' then
        print("\27[31mFivemerr setup is missing in: FivemerrMugShot (server > main.lua > line 19)\27[0m")
    end
    if ClockinWebhook == '' then
        print("\27[31mA webhook is missing in: ClockinWebhook (server > main.lua > line 24)\27[0m")
    end
    if GetResourceState('ps-dispatch') == 'started' then
        local calls = exports['ps-dispatch']:GetDispatchCalls()
        return calls
    end
end)

RegisterNetEvent("ps-mdt:server:OnPlayerUnload", function()
	--// Delete player from the MDT on logout
	local src = source
	local player = QBCore.Functions.GetPlayer(src)
	if GetActiveData(player.PlayerData.citizenid) then
		activeUnits[player.PlayerData.citizenid] = nil
	end
end)

AddEventHandler('playerDropped', function(reason)
    local src = source
    local PlayerData = GetPlayerData(src)
	if PlayerData == nil then return end -- Player not loaded in correctly and dropped early

    local time = os.date("%Y-%m-%d %H:%M:%S")
    local job = PlayerData.job.name
    local firstName = PlayerData.charinfo.firstname:sub(1,1):upper()..PlayerData.charinfo.firstname:sub(2)
    local lastName = PlayerData.charinfo.lastname:sub(1,1):upper()..PlayerData.charinfo.lastname:sub(2)

    -- Auto clock out if the player is off duty
     if IsPoliceOrEms(job) and PlayerData.job.onduty then
		MySQL.query.await('UPDATE mdt_clocking SET clock_out_time = NOW(), total_time = TIMESTAMPDIFF(SECOND, clock_in_time, NOW()) WHERE user_id = @user_id ORDER BY id DESC LIMIT 1', {
			['@user_id'] = PlayerData.citizenid
		})

		local result = MySQL.scalar.await('SELECT total_time FROM mdt_clocking WHERE user_id = @user_id', {
			['@user_id'] = PlayerData.citizenid
		})
		if result then
			local time_formatted = format_time(tonumber(result))
			sendToDiscord(16711680, "MDT Clock-Out", 'Player: **' ..  firstName .. " ".. lastName .. '**\n\nJob: **' .. PlayerData.job.name .. '**\n\nRank: **' .. PlayerData.job.grade.name .. '**\n\nStatus: **Off Duty**\n Total time:' .. time_formatted, "ps-mdt | Made by Project Sloth")
		end
	end

    -- Delete player from the MDT on logout
    if PlayerData ~= nil then
        if GetActiveData(PlayerData.citizenid) then
            activeUnits[PlayerData.citizenid] = nil
        end
    else
        local license = QBCore.Functions.GetIdentifier(src, "license")
        local citizenids = GetCitizenID(license)

        for _, v in pairs(citizenids) do
            if GetActiveData(v.citizenid) then
                activeUnits[v.citizenid] = nil
            end
        end
    end
end)

RegisterNetEvent("ps-mdt:server:ToggleDuty", function()
    local src = source
    local player = QBCore.Functions.GetPlayer(src)
    if not player.PlayerData.job.onduty then
	--// Remove from MDT
	if GetActiveData(player.PlayerData.citizenid) then
		activeUnits[player.PlayerData.citizenid] = nil
	end
    end
end)

QBCore.Commands.Add("mdtleaderboard", "Show MDT leaderboard", {}, false, function(source, args)
    local PlayerData = GetPlayerData(source)
    local job = PlayerData.job.name

    if not IsPoliceOrEms(job) then
        TriggerClientEvent('QBCore:Notify', source, "You don't have permission to use this command.", 'error')
        return
    end

	local result = MySQL.Sync.fetchAll('SELECT firstname, lastname, total_time FROM mdt_clocking ORDER BY total_time DESC')

    local leaderboard_message = '**MDT Leaderboard**\n\n'

    for i, record in ipairs(result) do
		local firstName = record.firstname:sub(1,1):upper()..record.firstname:sub(2)
		local lastName = record.lastname:sub(1,1):upper()..record.lastname:sub(2)
		local total_time = format_time(record.total_time)

		leaderboard_message = leaderboard_message .. i .. '. **' .. firstName .. ' ' .. lastName .. '** - ' .. total_time .. '\n'
	end

    sendToDiscord(16753920, "MDT Leaderboard", leaderboard_message, "ps-mdt | Made by Project Sloth")
    TriggerClientEvent('QBCore:Notify', source, "MDT leaderboard sent to Discord!", 'success')
end)

RegisterNetEvent("ps-mdt:server:ClockSystem", function()
    local src = source
    local PlayerData = GetPlayerData(src)
    local time = os.date("%Y-%m-%d %H:%M:%S")
    local firstName = PlayerData.charinfo.firstname:sub(1,1):upper()..PlayerData.charinfo.firstname:sub(2)
    local lastName = PlayerData.charinfo.lastname:sub(1,1):upper()..PlayerData.charinfo.lastname:sub(2)
    if PlayerData.job.onduty then

        TriggerClientEvent('QBCore:Notify', source, "You're clocked-in", 'success')
		MySQL.Async.insert('INSERT INTO mdt_clocking (user_id, firstname, lastname, clock_in_time) VALUES (:user_id, :firstname, :lastname, :clock_in_time) ON DUPLICATE KEY UPDATE user_id = :user_id, firstname = :firstname, lastname = :lastname, clock_in_time = :clock_in_time', {
			user_id = PlayerData.citizenid,
			firstname = firstName,
			lastname = lastName,
			clock_in_time = time
		}, function()
		end)
		sendToDiscord(65280, "MDT Clock-In", 'Player: **' ..  firstName .. " ".. lastName .. '**\n\nJob: **' .. PlayerData.job.name .. '**\n\nRank: **' .. PlayerData.job.grade.name .. '**\n\nStatus: **On Duty**', "ps-mdt | Made by Project Sloth")
    else
		TriggerClientEvent('QBCore:Notify', source, "You're clocked-out", 'success')
		MySQL.query.await('UPDATE mdt_clocking SET clock_out_time = NOW(), total_time = TIMESTAMPDIFF(SECOND, clock_in_time, NOW()) WHERE user_id = @user_id ORDER BY id DESC LIMIT 1', {
			['@user_id'] = PlayerData.citizenid
		})

		local result = MySQL.scalar.await('SELECT total_time FROM mdt_clocking WHERE user_id = @user_id', {
			['@user_id'] = PlayerData.citizenid
		})
		local time_formatted = format_time(tonumber(result))

		sendToDiscord(16711680, "MDT Clock-Out", 'Player: **' ..  firstName .. " ".. lastName .. '**\n\nJob: **' .. PlayerData.job.name .. '**\n\nRank: **' .. PlayerData.job.grade.name .. '**\n\nStatus: **Off Duty**\n Total time:' .. time_formatted, "ps-mdt | Made by Project Sloth")
    end
end)

RegisterNetEvent('mdt:server:openMDT', function()
	local src = source
	local PlayerData = GetPlayerData(src)
	if not PermCheck(src, PlayerData) then return end
	local Radio = Player(src).state.radioChannel or 0

	if GetResourceState('ps-dispatch') == 'started' then
		calls = exports['ps-dispatch']:GetDispatchCalls()
	end

	activeUnits[PlayerData.citizenid] = {
		cid = PlayerData.citizenid,
		callSign = PlayerData.metadata['callsign'],
		firstName = PlayerData.charinfo.firstname:sub(1,1):upper()..PlayerData.charinfo.firstname:sub(2),
		lastName = PlayerData.charinfo.lastname:sub(1,1):upper()..PlayerData.charinfo.lastname:sub(2),
		radio = Radio,
		unitType = PlayerData.job.name,
		duty = PlayerData.job.onduty
	}

	local JobType = GetJobType(PlayerData.job.name)
	local bulletin = GetBulletins(JobType)
	TriggerClientEvent('mdt:client:open', src, bulletin, activeUnits, calls, PlayerData.citizenid)
end)

RegisterNetEvent("ps-mdt:server:OnPlayerUnload", function()
	--// Delete player from the MDT on logout
	local src = source
	local player = QBCore.Functions.GetPlayer(src)
	if GetActiveData(player.PlayerData.citizenid) then
		activeUnits[player.PlayerData.citizenid] = nil
	end
end)

AddEventHandler('playerDropped', function(reason)
    local src = source
    local PlayerData = GetPlayerData(src)
	if PlayerData == nil then return end -- Player not loaded in correctly and dropped early

    local time = os.date("%Y-%m-%d %H:%M:%S")
    local job = PlayerData.job.name
    local firstName = PlayerData.charinfo.firstname:sub(1,1):upper()..PlayerData.charinfo.firstname:sub(2)
    local lastName = PlayerData.charinfo.lastname:sub(1,1):upper()..PlayerData.charinfo.lastname:sub(2)

    -- Auto clock out if the player is off duty
     if IsPoliceOrEms(job) and PlayerData.job.onduty then
		MySQL.query.await('UPDATE mdt_clocking SET clock_out_time = NOW(), total_time = TIMESTAMPDIFF(SECOND, clock_in_time, NOW()) WHERE user_id = @user_id ORDER BY id DESC LIMIT 1', {
			['@user_id'] = PlayerData.citizenid
		})

		local result = MySQL.scalar.await('SELECT total_time FROM mdt_clocking WHERE user_id = @user_id', {
			['@user_id'] = PlayerData.citizenid
		})
		if result then
			local time_formatted = format_time(tonumber(result))
			sendToDiscord(16711680, "MDT Clock-Out", 'Player: **' ..  firstName .. " ".. lastName .. '**\n\nJob: **' .. PlayerData.job.name .. '**\n\nRank: **' .. PlayerData.job.grade.name .. '**\n\nStatus: **Off Duty**\n Total time:' .. time_formatted, "ps-mdt | Made by Project Sloth")
		end
	end

    -- Delete player from the MDT on logout
    if PlayerData ~= nil then
        if GetActiveData(PlayerData.citizenid) then
            activeUnits[PlayerData.citizenid] = nil
        end
    else
        local license = QBCore.Functions.GetIdentifier(src, "license")
        local citizenids = GetCitizenID(license)

        for _, v in pairs(citizenids) do
            if GetActiveData(v.citizenid) then
                activeUnits[v.citizenid] = nil
            end
        end
    end
end)

RegisterNetEvent("ps-mdt:server:ToggleDuty", function()
    local src = source
    local player = QBCore.Functions.GetPlayer(src)
    if not player.PlayerData.job.onduty then
	--// Remove from MDT
	if GetActiveData(player.PlayerData.citizenid) then
		activeUnits[player.PlayerData.citizenid] = nil
	end
    end
end)

QBCore.Commands.Add("mdtleaderboard", "Show MDT leaderboard", {}, false, function(source, args)
    local PlayerData = GetPlayerData(source)
    local job = PlayerData.job.name

    if not IsPoliceOrEms(job) then
        TriggerClientEvent('QBCore:Notify', source, "You don't have permission to use this command.", 'error')
        return
    end

	local result = MySQL.Sync.fetchAll('SELECT firstname, lastname, total_time FROM mdt_clocking ORDER BY total_time DESC')

    local leaderboard_message = '**MDT Leaderboard**\n\n'

    for i, record in ipairs(result) do
		local firstName = record.firstname:sub(1,1):upper()..record.firstname:sub(2)
		local lastName = record.lastname:sub(1,1):upper()..record.lastname:sub(2)
		local total_time = format_time(record.total_time)

		leaderboard_message = leaderboard_message .. i .. '. **' .. firstName .. ' ' .. lastName .. '** - ' .. total_time .. '\n'
	end

    sendToDiscord(16753920, "MDT Leaderboard", leaderboard_message, "ps-mdt | Made by Project Sloth")
    TriggerClientEvent('QBCore:Notify', source, "MDT leaderboard sent to Discord!", 'success')
end)

RegisterNetEvent("ps-mdt:server:ClockSystem", function()
    local src = source
    local PlayerData = GetPlayerData(src)
    local time = os.date("%Y-%m-%d %H:%M:%S")
    local firstName = PlayerData.charinfo.firstname:sub(1,1):upper()..PlayerData.charinfo.firstname:sub(2)
    local lastName = PlayerData.charinfo.lastname:sub(1,1):upper()..PlayerData.charinfo.lastname:sub(2)
    if PlayerData.job.onduty then

        TriggerClientEvent('QBCore:Notify', source, "You're clocked-in", 'success')
		MySQL.Async.insert('INSERT INTO mdt_clocking (user_id, firstname, lastname, clock_in_time) VALUES (:user_id, :firstname, :lastname, :clock_in_time) ON DUPLICATE KEY UPDATE user_id = :user_id, firstname = :firstname, lastname = :lastname, clock_in_time = :clock_in_time', {
			user_id = PlayerData.citizenid,
			firstname = firstName,
			lastname = lastName,
			clock_in_time = time
		}, function()
		end)
		sendToDiscord(65280, "MDT Clock-In", 'Player: **' ..  firstName .. " ".. lastName .. '**\n\nJob: **' .. PlayerData.job.name .. '**\n\nRank: **' .. PlayerData.job.grade.name .. '**\n\nStatus: **On Duty**', "ps-mdt | Made by Project Sloth")
    else
		TriggerClientEvent('QBCore:Notify', source, "You're clocked-out", 'success')
		MySQL.query.await('UPDATE mdt_clocking SET clock_out_time = NOW(), total_time = TIMESTAMPDIFF(SECOND, clock_in_time, NOW()) WHERE user_id = @user_id ORDER BY id DESC LIMIT 1', {
			['@user_id'] = PlayerData.citizenid
		})

		local result = MySQL.scalar.await('SELECT total_time FROM mdt_clocking WHERE user_id = @user_id', {
			['@user_id'] = PlayerData.citizenid
		})
		local time_formatted = format_time(tonumber(result))

		sendToDiscord(16711680, "MDT Clock-Out", 'Player: **' ..  firstName .. " ".. lastName .. '**\n\nJob: **' .. PlayerData.job.name .. '**\n\nRank: **' .. PlayerData.job.grade.name .. '**\n\nStatus: **Off Duty**\n Total time:' .. time_formatted, "ps-mdt | Made by Project Sloth")
    end
end)

RegisterNetEvent('mdt:server:openMDT', function()
	local src = source
	local PlayerData = GetPlayerData(src)
	if not PermCheck(src, PlayerData) then return end
	local Radio = Player(src).state.radioChannel or 0

	if GetResourceState('ps-dispatch') == 'started' then
		calls = exports['ps-dispatch']:GetDispatchCalls()
	end

	activeUnits[PlayerData.citizenid] = {
		cid = PlayerData.citizenid,
		callSign = PlayerData.metadata['callsign'],
		firstName = PlayerData.charinfo.firstname:sub(1,1):upper()..PlayerData.charinfo.firstname:sub(2),
		lastName = PlayerData.charinfo.lastname:sub(1,1):upper()..PlayerData.charinfo.lastname:sub(2),
		radio = Radio,
		unitType = PlayerData.job.name,
		duty = PlayerData.job.onduty
	}

	local JobType = GetJobType(PlayerData.job.name)
	local bulletin = GetBulletins(JobType)
	TriggerClientEvent('mdt:client:open', src, bulletin, activeUnits, calls, PlayerData.citizenid)
end)

QBCore.Functions.CreateCallback('mdt:server:SearchProfile', function(source, cb, sentData)
    if not sentData then  return cb({}) end
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if Player then
        local JobType = GetJobType(Player.PlayerData.job.name)
        if JobType ~= nil then
            local people = MySQL.query.await("SELECT p.citizenid, p.charinfo, md.pfp, md.fingerprint FROM players p LEFT JOIN mdt_data md on p.citizenid = md.cid WHERE LOWER(CONCAT(JSON_VALUE(p.charinfo, '$.firstname'), ' ', JSON_VALUE(p.charinfo, '$.lastname'))) LIKE :query OR LOWER(`charinfo`) LIKE :query OR LOWER(`citizenid`) LIKE :query OR LOWER(md.fingerprint) LIKE :query AND jobtype = :jobtype LIMIT 20", { query = string.lower('%'..sentData..'%'), jobtype = JobType })
            local citizenIds = {}
            local citizenIdIndexMap = {}
            if not next(people) then cb({}) return end

            for index, data in pairs(people) do
                people[index]['warrant'] = false
                people[index]['convictions'] = 0
                people[index]['licences'] = GetPlayerLicenses(data.citizenid)
                people[index]['pp'] = ProfPic(data.gender, data.pfp)
				if data.fingerprint and data.fingerprint ~= "" then
					people[index]['fingerprint'] = data.fingerprint
				else
					people[index]['fingerprint'] = ""
				end
                citizenIds[#citizenIds+1] = data.citizenid
                citizenIdIndexMap[data.citizenid] = index
            end

            local convictions = GetConvictions(citizenIds)

            if next(convictions) then
                for _, conv in pairs(convictions) do
                    if conv.warrant == "1" then people[citizenIdIndexMap[conv.cid]].warrant = true end

                    local charges = json.decode(conv.charges)
                    people[citizenIdIndexMap[conv.cid]].convictions = people[citizenIdIndexMap[conv.cid]].convictions + #charges
                end
            end
			TriggerClientEvent('mdt:client:searchProfile', src, people, false)

            return cb(people)
        end
    end

    return cb({})
end)

QBCore.Functions.CreateCallback('ps-mdt:getDispatchCalls', function(source, cb)
    local calls = exports['ps-dispatch']:GetDispatchCalls()
    cb(calls)
end)

QBCore.Functions.CreateCallback("mdt:server:getWarrants", function(source, cb)
    local WarrantData = {}
    local data = MySQL.query.await("SELECT * FROM mdt_convictions WHERE warrant = 1", {})
    for _, value in pairs(data) do
	WarrantData[#WarrantData+1] = {
        	cid = value.cid,
        	linkedincident = value.linkedincident,
        	name = GetNameFromId(value.cid),
        	time = value.time
        }
    end
    cb(WarrantData)
end)

QBCore.Functions.CreateCallback('mdt:server:OpenDashboard', function(source, cb)
	local PlayerData = GetPlayerData(source)
	if not PermCheck(source, PlayerData) then return end
	local JobType = GetJobType(PlayerData.job.name)
	local bulletin = GetBulletins(JobType)
	cb(bulletin)
end)

RegisterNetEvent('mdt:server:NewBulletin', function(title, info, time)
	local src = source
	local PlayerData = GetPlayerData(src)
	if not PermCheck(src, PlayerData) then return end
	local JobType = GetJobType(PlayerData.job.name)
	local playerName = GetNameFromPlayerData(PlayerData)
	local newBulletin = MySQL.insert.await('INSERT INTO `mdt_bulletin` (`title`, `desc`, `author`, `time`, `jobtype`) VALUES (:title, :desc, :author, :time, :jt)', {
		title = title,
		desc = info,
		author = playerName,
		time = tostring(time),
		jt = JobType
	})

	AddLog(("A new bulletin was added by %s with the title: %s!"):format(playerName, title))
	TriggerClientEvent('mdt:client:newBulletin', -1, src, {id = newBulletin, title = title, info = info, time = time, author = PlayerData.CitizenId}, JobType)
end)

RegisterNetEvent('mdt:server:deleteBulletin', function(id, title)
	if not id then return false end
	local src = source
	local PlayerData = GetPlayerData(src)
	if not PermCheck(src, PlayerData) then return end
	local JobType = GetJobType(PlayerData.job.name)

	MySQL.query.await('DELETE FROM `mdt_bulletin` where id = ?', {id})
	AddLog("Bulletin with Title: "..title.." was deleted by " .. GetNameFromPlayerData(PlayerData) .. ".")
end)

QBCore.Functions.CreateCallback('mdt:server:GetProfileData', function(source, cb, sentId)
	if not sentId then return cb({}) end
	local src = source
	local PlayerData = GetPlayerData(src)
	if not PermCheck(src, PlayerData) then return cb({}) end
	local JobType = GetJobType(PlayerData.job.name)
	local target = GetPlayerDataById(sentId)
	local JobName = PlayerData.job.name

	local apartmentData

	if not target or not next(target) then return cb({}) end

	if type(target.job) == 'string' then target.job = json.decode(target.job) end
	if type(target.charinfo) == 'string' then target.charinfo = json.decode(target.charinfo) end
	if type(target.metadata) == 'string' then target.metadata = json.decode(target.metadata) end

	local licencesdata = target.metadata['licences'] or {
        ['driver'] = false,
        ['business'] = false,
        ['weapon'] = false,
		['pilot'] = false
	}

	local housingSystem

	if GetResourceState("ps-housing") == "started" then
        housingSystem = "ps-housing"
    elseif GetResourceState("qbx_properties") == "started" then
        housingSystem = "qbx_properties"
    elseif GetResourceState("qb-apartments") == "started" then
        housingSystem = "qb-apartments"
    else
        return print("^1[CONFIG ERROR]^0 No known housing resource is started.")
    end

	local job, grade = UnpackJob(target.job)

	if housingSystem == "ps-housing" then
		local propertyData = GetPlayerPropertiesByCitizenId(target.citizenid)
		if propertyData and next(propertyData) then
			local apartmentList = {}
			for i, property in ipairs(propertyData) do
				if property.apartment then
					table.insert(apartmentList, property.apartment .. ' Apt # (' .. property.property_id .. ')')
				end
			end
			if #apartmentList > 0 then
				apartmentData = table.concat(apartmentList, ', ')
			else
				TriggerClientEvent("QBCore:Notify", src, 'The citizen does not have an apartment.', 'error')
			end
		else
			TriggerClientEvent("QBCore:Notify", src, 'The citizen does not have a property.', 'error')
		end
	elseif housingSystem == "qbx_properties" then
		local propertyData = GetPlayerPropertiesByOwner(target.citizenid)
		if propertyData and next(propertyData) then
			local apartmentList = {}
			for i, property in ipairs(propertyData) do
				if property.property_name then
					table.insert(apartmentList, property.property_name .. ' Apt # (' .. property.id .. ')')
				end
			end
			if #apartmentList > 0 then
				apartmentData = table.concat(apartmentList, ', ')
			else
				TriggerClientEvent("QBCore:Notify", src, 'The citizen does not have an apartment.', 'error')
			end
		else
			TriggerClientEvent("QBCore:Notify", src, 'The citizen does not have a property.', 'error')
		end
	elseif housingSystem == "qb-apartments" then
        apartmentData = GetPlayerApartment(target.citizenid)
        if apartmentData then
            if apartmentData[1] then
                apartmentData = apartmentData[1].label .. ' (' ..apartmentData[1].name..')'
            else
                TriggerClientEvent("QBCore:Notify", src, 'The citizen does not have an apartment.', 'error')
            end
        else
            TriggerClientEvent("QBCore:Notify", src, 'The citizen does not have an apartment.', 'error')
		end
	else
		print("^1[CONFIG ERROR]^0 No known housing resource is started")
    end

	local person = {
		cid = target.citizenid,
		firstname = target.charinfo.firstname,
		lastname = target.charinfo.lastname,
		job = job.label,
		grade = grade.name,
		apartment = apartmentData,
		pp = ProfPic(target.charinfo.gender),
		licences = licencesdata,
		dob = target.charinfo.birthdate,
		fingerprint = target.metadata.fingerprint,
		phone = target.charinfo.phone,
		mdtinfo = '',
		tags = {},
		vehicles = {},
		properties = {},
		gallery = {},
		isLimited = false
	}

	if Config.PoliceJobs[JobName] or Config.DojJobs[JobName] then
		local convictions = GetConvictions({person.cid})
		local incidents = {}
		person.convictions2 = {}
		local convCount = 1
		if next(convictions) then
			for _, conv in pairs(convictions) do
				if conv.warrant == "1" then person.warrant = true end

				-- Get the incident details
				local id = conv.linkedincident
				local incident = GetIncidentName(id)

				if incident then
					incidents[#incidents + 1] = {
						id = id,
						title = incident.title,
						time = conv.time
					}
				end

				local charges = json.decode(conv.charges)
				for _, charge in pairs(charges) do
					person.convictions2[convCount] = charge
					convCount = convCount + 1
				end
			end
		end

		person.incidents = incidents

		local hash = {}
		person.convictions = {}

		for _,v in ipairs(person.convictions2) do
			if (not hash[v]) then
				person.convictions[#person.convictions+1] = v
				hash[v] = true
			end
		end

		local vehicles = GetPlayerVehicles(person.cid)

		if vehicles then
			person.vehicles = vehicles
		end

		if housingSystem == "ps-housing" then
    		local Coords = {}
    		local Houses = {}
			local propertyData = GetPlayerPropertiesByCitizenId(target.citizenid)
    		for k, v in pairs(propertyData) do
				if not v.apartment then
    		    	Coords[#Coords + 1] = {
    		    	    coords = json.decode(v["door_data"]),
    		    	    street = v["street"],
    		    	    propertyid = v["property_id"],
    		    	}
				end
    		end
    		for index = 1, #Coords do
    		    local coordsLocation, label
    		    local coords = Coords[index]["coords"]

    		    coordsLocation = tostring(coords.x .. "," .. coords.y .. "," .. coords.z)
    		    label = tostring(Coords[index].propertyid .. " " .. Coords[index].street)

    		    Houses[#Houses + 1] = {
    		        label = label,
    		        coords = coordsLocation,
    		    }
    		end
			person.properties = Houses
		elseif housingSystem == "qbx_properties" then
			local Coords = {}
			local Houses = {}
			local properties= GetPlayerPropertiesByOwner(person.cid)
			for k, v in pairs(properties) do
				Coords[#Coords+1] = {
					coords = json.decode(v["coords"]),
				}
			end
			for index = 1, #Coords, 1 do
				Houses[#Houses+1] = {
					label = properties[index]["property_name"],
					coords = tostring(Coords[index]["coords"]["x"]..",".. Coords[index]["coords"]["y"].. ",".. Coords[index]["coords"]["z"]),
				}
			end
			person.properties = Houses
		elseif housingSystem == "qb-apartments" then
			local Coords = {}
			local Houses = {}
			local properties= GetPlayerProperties(person.cid)
			for k, v in pairs(properties) do
				Coords[#Coords+1] = {
					coords = json.decode(v["coords"]),
				}
			end
			for index = 1, #Coords, 1 do
				Houses[#Houses+1] = {
					label = properties[index]["label"],
					coords = tostring(Coords[index]["coords"]["enter"]["x"]..",".. Coords[index]["coords"]["enter"]["y"].. ",".. Coords[index]["coords"]["enter"]["z"]),
				}
			end
			person.properties = Houses
		else
			print("^1[CONFIG ERROR]^0 No known housing resource is started")
		end
	end
	local mdtData = GetPersonInformation(sentId, JobType)
	if mdtData then
		person.mdtinfo = mdtData.information
		person.profilepic = mdtData.pfp
		person.tags = json.decode(mdtData.tags)
		person.gallery = json.decode(mdtData.gallery)
		person.fingerprint = mdtData.fingerprint
		print("Fetched fingerprint from mdt_data:", mdtData.fingerprint)
	end

	return cb(person)
end)

RegisterNetEvent("mdt:server:saveProfile", function(pfp, information, cid, fName, sName, tags, gallery, licenses, fingerprint)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    UpdateAllLicenses(cid, licenses)
    if Player then
        local JobType = GetJobType(Player.PlayerData.job.name)
        if JobType == 'doj' then JobType = 'police' end

        MySQL.Async.insert('INSERT INTO mdt_data (cid, information, pfp, jobtype, tags, gallery, fingerprint) VALUES (:cid, :information, :pfp, :jobtype, :tags, :gallery, :fingerprint) ON DUPLICATE KEY UPDATE cid = :cid, information = :information, pfp = :pfp, jobtype = :jobtype, tags = :tags, gallery = :gallery, fingerprint = :fingerprint', {
            cid = cid,
            information = information,
            pfp = pfp,
            jobtype = JobType,
            tags = json.encode(tags),
            gallery = json.encode(gallery),
            fingerprint = fingerprint,
        }, function()
        end)
    end
end)


-- Mugshotd
RegisterNetEvent('cqc-mugshot:server:triggerSuspect', function(suspect)
    TriggerClientEvent('cqc-mugshot:client:trigger', suspect, suspect)
end)

RegisterNetEvent('psmdt-mugshot:server:MDTupload', function(citizenid, MugShotURLs)
    MugShots[citizenid] = MugShotURLs
    local cid = citizenid
    MySQL.Async.insert('INSERT INTO mdt_data (cid, pfp, gallery, tags) VALUES (:cid, :pfp, :gallery, :tags) ON DUPLICATE KEY UPDATE cid = :cid,  pfp = :pfp, gallery = :gallery, tags = :tags', {
		cid = cid,
		pfp = MugShots[citizenid][1],
		gallery = json.encode(MugShots[citizenid]),
		tags = json.encode(tags),
	})
end)

RegisterNetEvent("mdt:server:updateLicense", function(cid, type, status)
	local src = source
	local Player = QBCore.Functions.GetPlayer(src)
	if Player then
		if GetJobType(Player.PlayerData.job.name) == 'police' then
			ManageLicense(cid, type, status)
		end
	end
end)

-- Incidents

RegisterNetEvent('mdt:server:getAllIncidents', function()
	local src = source
	local Player = QBCore.Functions.GetPlayer(src)
	if Player then
		local JobType = GetJobType(Player.PlayerData.job.name)
		if JobType == 'police' or JobType == 'doj' then
			local matches = MySQL.query.await("SELECT * FROM `mdt_incidents` ORDER BY `id` DESC LIMIT 30", {})

			TriggerClientEvent('mdt:client:getAllIncidents', src, matches)
		end
	end
end)

RegisterNetEvent('mdt:server:searchIncidents', function(query)
	if query then
		local src = source
		local Player = QBCore.Functions.GetPlayer(src)
		if Player then
			local JobType = GetJobType(Player.PlayerData.job.name)
			if JobType == 'police' or JobType == 'doj' then
				local matches = MySQL.query.await("SELECT * FROM `mdt_incidents` WHERE `id` LIKE :query OR LOWER(`title`) LIKE :query OR LOWER(`author`) LIKE :query OR LOWER(`details`) LIKE :query OR LOWER(`tags`) LIKE :query OR LOWER(`officersinvolved`) LIKE :query OR LOWER(`civsinvolved`) LIKE :query OR LOWER(`author`) LIKE :query ORDER BY `id` DESC LIMIT 50", {
					query = string.lower('%'..query..'%') -- % wildcard, needed to search for all alike results
				})

				TriggerClientEvent('mdt:client:getIncidents', src, matches)
			end
		end
	end
end)

RegisterNetEvent('mdt:server:getIncidentData', function(sentId)
	if sentId then
		local src = source
		local Player = QBCore.Functions.GetPlayer(src)
		if Player then
			local JobType = GetJobType(Player.PlayerData.job.name)
			if JobType == 'police' or JobType == 'doj' then
				local matches = MySQL.query.await("SELECT * FROM `mdt_incidents` WHERE `id` = :id", {
					id = sentId
				})
				local data = matches[1]
				data['tags'] = json.decode(data['tags'])
				data['officersinvolved'] = json.decode(data['officersinvolved'])
				data['civsinvolved'] = json.decode(data['civsinvolved'])
				data['evidence'] = json.decode(data['evidence'])


				local convictions = MySQL.query.await("SELECT * FROM `mdt_convictions` WHERE `linkedincident` = :id", {
					id = sentId
				})
				if convictions ~= nil then
					for i=1, #convictions do
						local res = GetNameFromId(convictions[i]['cid'])
						if res ~= nil then
							convictions[i]['name'] = res
						else
							convictions[i]['name'] = "Unknown"
						end
						convictions[i]['charges'] = json.decode(convictions[i]['charges'])
					end
				end
				TriggerClientEvent('mdt:client:getIncidentData', src, data, convictions)
			end
		end
	end
end)

RegisterNetEvent('mdt:server:getAllBolos', function()
	local src = source
	local Player = QBCore.Functions.GetPlayer(src)
	local JobType = GetJobType(Player.PlayerData.job.name)
	if JobType == 'police' or JobType == 'ambulance' then
		local matches = MySQL.query.await("SELECT * FROM `mdt_bolos` WHERE jobtype = :jobtype", {jobtype = JobType})
		TriggerClientEvent('mdt:client:getAllBolos', src, matches)
	end
end)

RegisterNetEvent('mdt:server:searchBolos', function(sentSearch)
	if sentSearch then
		local src = source
		local Player = QBCore.Functions.GetPlayer(src)
		local JobType = GetJobType(Player.PlayerData.job.name)
		if JobType == 'police' or JobType == 'ambulance' then
			local matches = MySQL.query.await("SELECT * FROM `mdt_bolos` WHERE `id` LIKE :query OR LOWER(`title`) LIKE :query OR `plate` LIKE :query OR LOWER(`owner`) LIKE :query OR LOWER(`individual`) LIKE :query OR LOWER(`detail`) LIKE :query OR LOWER(`officersinvolved`) LIKE :query OR LOWER(`tags`) LIKE :query OR LOWER(`author`) LIKE :query AND jobtype = :jobtype", {
				query = string.lower('%'..sentSearch..'%'), -- % wildcard, needed to search for all alike results
				jobtype = JobType
			})
			TriggerClientEvent('mdt:client:getBolos', src, matches)
		end
	end
end)

RegisterNetEvent('mdt:server:getBoloData', function(sentId)
	if sentId then
		local src = source
		local Player = QBCore.Functions.GetPlayer(src)
		local JobType = GetJobType(Player.PlayerData.job.name)
		if JobType == 'police' or JobType == 'ambulance' then
			local matches = MySQL.query.await("SELECT * FROM `mdt_bolos` WHERE `id` = :id AND jobtype = :jobtype LIMIT 1", {
				id = sentId,
				jobtype = JobType
			})

			local data = matches[1]
			data['tags'] = json.decode(data['tags'])
			data['officersinvolved'] = json.decode(data['officersinvolved'])
			data['gallery'] = json.decode(data['gallery'])
			TriggerClientEvent('mdt:client:getBoloData', src, data)
		end
	end
end)

RegisterNetEvent('mdt:server:newBolo', function(existing, id, title, plate, owner, individual, detail, tags, gallery, officersinvolved, time)
	if id then
		local src = source
		local Player = QBCore.Functions.GetPlayer(src)
		local JobType = GetJobType(Player.PlayerData.job.name)
		if JobType == 'police' or JobType == 'ambulance' then
			local fullname = Player.PlayerData.charinfo.firstname .. ' ' .. Player.PlayerData.charinfo.lastname

			local function InsertBolo()
				MySQL.insert('INSERT INTO `mdt_bolos` (`title`, `author`, `plate`, `owner`, `individual`, `detail`, `tags`, `gallery`, `officersinvolved`, `time`, `jobtype`) VALUES (:title, :author, :plate, :owner, :individual, :detail, :tags, :gallery, :officersinvolved, :time, :jobtype)', {
					title = title,
					author = fullname,
					plate = plate,
					owner = owner,
					individual = individual,
					detail = detail,
					tags = json.encode(tags),
					gallery = json.encode(gallery),
					officersinvolved = json.encode(officersinvolved),
					time = tostring(time),
					jobtype = JobType
				}, function(r)
					if r then
						TriggerClientEvent('mdt:client:boloComplete', src, r)
						TriggerEvent('mdt:server:AddLog', "A new BOLO was created by "..fullname.." with the title ("..title..") and ID ("..id..")")
					end
				end)
			end

			local function UpdateBolo()
				MySQL.update("UPDATE mdt_bolos SET `title`=:title, plate=:plate, owner=:owner, individual=:individual, detail=:detail, tags=:tags, gallery=:gallery, officersinvolved=:officersinvolved WHERE `id`=:id AND jobtype = :jobtype LIMIT 1", {
					title = title,
					plate = plate,
					owner = owner,
					individual = individual,
					detail = detail,
					tags = json.encode(tags),
					gallery = json.encode(gallery),
					officersinvolved = json.encode(officersinvolved),
					id = id,
					jobtype = JobType
				}, function(r)
					if r then
						TriggerClientEvent('mdt:client:boloComplete', src, id)
						TriggerEvent('mdt:server:AddLog', "A BOLO was updated by "..fullname.." with the title ("..title..") and ID ("..id..")")
					end
				end)
			end

			if existing then
				UpdateBolo()
			elseif not existing then
				InsertBolo()
			end
		end
	end
end)

RegisterNetEvent('mdt:server:deleteWeapons', function(id)
	if id then
		local src = source
		local Player = QBCore.Functions.GetPlayer(src)
		if Config.RemoveWeaponsPerms[Player.PlayerData.job.name] then
			if Config.RemoveWeaponsPerms[Player.PlayerData.job.name][Player.PlayerData.job.grade.level] then
				local fullName = Player.PlayerData.charinfo.firstname .. ' ' .. Player.PlayerData.charinfo.lastname
				MySQL.update("DELETE FROM `mdt_weaponinfo` WHERE id=:id", { id = id })
				TriggerEvent('mdt:server:AddLog', "A Weapon Info was deleted by "..fullName.." with the ID ("..id..")")
			else
				local fullname = Player.PlayerData.charinfo.firstname .. ' ' .. Player.PlayerData.charinfo.lastname
				TriggerClientEvent("QBCore:Notify", src, 'No Permissions to do that!', 'error')
				TriggerEvent('mdt:server:AddLog', fullname.." tryed to delete a Weapon Info with the ID ("..id..")")
			end
		end
	end
end)

RegisterNetEvent('mdt:server:deleteReports', function(id)
	if id then
		local src = source
		local Player = QBCore.Functions.GetPlayer(src)
		if Config.RemoveReportPerms[Player.PlayerData.job.name] then
			if Config.RemoveReportPerms[Player.PlayerData.job.name][Player.PlayerData.job.grade.level] then
				local fullName = Player.PlayerData.charinfo.firstname .. ' ' .. Player.PlayerData.charinfo.lastname
				MySQL.update("DELETE FROM `mdt_reports` WHERE id=:id", { id = id })
				TriggerEvent('mdt:server:AddLog', "A Report was deleted by "..fullName.." with the ID ("..id..")")
			else
				local fullname = Player.PlayerData.charinfo.firstname .. ' ' .. Player.PlayerData.charinfo.lastname
				TriggerClientEvent("QBCore:Notify", src, 'No Permissions to do that!', 'error')
				TriggerEvent('mdt:server:AddLog', fullname.." tryed to delete a Report with the ID ("..id..")")
			end
		end
	end
end)

RegisterNetEvent('mdt:server:deleteIncidents', function(id)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if Config.RemoveIncidentPerms[Player.PlayerData.job.name] then
        if Config.RemoveIncidentPerms[Player.PlayerData.job.name][Player.PlayerData.job.grade.level] then
            local fullName = Player.PlayerData.charinfo.firstname .. ' ' .. Player.PlayerData.charinfo.lastname
            MySQL.update("DELETE FROM `mdt_convictions` WHERE `linkedincident` = :id", {id = id})
            MySQL.update("UPDATE `mdt_convictions` SET `warrant` = '0' WHERE `linkedincident` = :id", {id = id}) -- Delete any outstanding warrants from incidents
            MySQL.update("DELETE FROM `mdt_incidents` WHERE id=:id", { id = id }, function(rowsChanged)
                if rowsChanged > 0 then
                    TriggerEvent('mdt:server:AddLog', "A Incident was deleted by "..fullName.." with the ID ("..id..")")
                end
            end)
        else
            local fullname = Player.PlayerData.charinfo.firstname .. ' ' .. Player.PlayerData.charinfo.lastname
            TriggerClientEvent("QBCore:Notify", src, 'No Permissions to do that!', 'error')
            TriggerEvent('mdt:server:AddLog', fullname.." tried to delete an Incident with the ID ("..id..")")
        end
    end
end)

RegisterNetEvent('mdt:server:deleteBolo', function(id)
	if id then
		local src = source
		local Player = QBCore.Functions.GetPlayer(src)
		local JobType = GetJobType(Player.PlayerData.job.name)
		if JobType == 'police' then
			local fullname = Player.PlayerData.charinfo.firstname .. ' ' .. Player.PlayerData.charinfo.lastname
			MySQL.update("DELETE FROM `mdt_bolos` WHERE id=:id", { id = id, jobtype = JobType })
			TriggerEvent('mdt:server:AddLog', "A BOLO was deleted by "..fullname.." with the ID ("..id..")")
		end
	end
end)

RegisterNetEvent('mdt:server:deleteICU', function(id)
	if id then
		local src = source
		local Player = QBCore.Functions.GetPlayer(src)
		local JobType = GetJobType(Player.PlayerData.job.name)
		if JobType == 'ambulance' then
			local fullname = Player.PlayerData.charinfo.firstname .. ' ' .. Player.PlayerData.charinfo.lastname
			MySQL.update("DELETE FROM `mdt_bolos` WHERE id=:id", { id = id, jobtype = JobType })
			TriggerEvent('mdt:server:AddLog', "A ICU Check-in was deleted by "..fullname.." with the ID ("..id..")")
		end
	end
end)

RegisterNetEvent('mdt:server:incidentSearchPerson', function(query)
    if query then
        local src = source
        local Player = QBCore.Functions.GetPlayer(src)
        if Player then
            local JobType = GetJobType(Player.PlayerData.job.name)
            if JobType == 'police' or JobType == 'doj' or JobType == 'ambulance' then
                local function ProfPic(gender, profilepic)
                    if profilepic then return profilepic end;
                    if gender == "f" then return "img/female.png" end;
                    return "img/male.png"
                end

                local result = MySQL.query.await("SELECT p.citizenid, p.charinfo, p.metadata, md.pfp from players p LEFT JOIN mdt_data md on p.citizenid = md.cid WHERE LOWER(CONCAT(JSON_VALUE(p.charinfo, '$.firstname'), ' ', JSON_VALUE(p.charinfo, '$.lastname'))) LIKE :query OR LOWER(`charinfo`) LIKE :query OR LOWER(`citizenid`) LIKE :query OR LOWER(md.fingerprint) LIKE :query AND jobtype = :jobtype LIMIT 30", {
					query = string.lower('%'..query..'%'),
                    jobtype = JobType
                })

                local data = {}
                for i=1, #result do
                    local charinfo = json.decode(result[i].charinfo)
                    local metadata = json.decode(result[i].metadata)
                    data[i] = {
                        id = result[i].citizenid,
                        firstname = charinfo.firstname,
                        lastname = charinfo.lastname,
                        profilepic = ProfPic(charinfo.gender, result[i].pfp),
                        callsign = metadata.callsign
                    }
                end
                TriggerClientEvent('mdt:client:incidentSearchPerson', src, data)
            end
        end
    end
end)

RegisterNetEvent('mdt:server:getAllReports', function()
	local src = source
	local Player = QBCore.Functions.GetPlayer(src)
	if Player then
		local JobType = GetJobType(Player.PlayerData.job.name)
		if JobType == 'police' or JobType == 'doj' or JobType == 'ambulance' then
			if JobType == 'doj' then JobType = 'police' end
			local matches = MySQL.query.await("SELECT * FROM `mdt_reports` WHERE jobtype = :jobtype ORDER BY `id` DESC LIMIT 30", {
				jobtype = JobType
			})
			TriggerClientEvent('mdt:client:getAllReports', src, matches)
		end
	end
end)

RegisterNetEvent('mdt:server:getReportData', function(sentId)
	if sentId then
		local src = source
		local Player = QBCore.Functions.GetPlayer(src)
		if Player then
			local JobType = GetJobType(Player.PlayerData.job.name)
			if JobType == 'police' or JobType == 'doj' or JobType == 'ambulance' then
				if JobType == 'doj' then JobType = 'police' end
				local matches = MySQL.query.await("SELECT * FROM `mdt_reports` WHERE `id` = :id AND `jobtype` = :jobtype LIMIT 1", {
					id = sentId,
					jobtype = JobType
				})
				local data = matches[1]
				data['tags'] = json.decode(data['tags'])
				data['officersinvolved'] = json.decode(data['officersinvolved'])
				data['civsinvolved'] = json.decode(data['civsinvolved'])
				data['gallery'] = json.decode(data['gallery'])
				TriggerClientEvent('mdt:client:getReportData', src, data)
			end
		end
	end
end)

RegisterNetEvent('mdt:server:searchReports', function(sentSearch)
	if sentSearch then
		local src = source
		local Player = QBCore.Functions.GetPlayer(src)
		if Player then
			local JobType = GetJobType(Player.PlayerData.job.name)
			if JobType == 'police' or JobType == 'doj' or JobType == 'ambulance' then
				if JobType == 'doj' then JobType = 'police' end
				local matches = MySQL.query.await("SELECT * FROM `mdt_reports` WHERE `id` LIKE :query OR LOWER(`author`) LIKE :query OR LOWER(`title`) LIKE :query OR LOWER(`type`) LIKE :query OR LOWER(`details`) LIKE :query OR LOWER(`tags`) LIKE :query AND `jobtype` = :jobtype ORDER BY `id` DESC LIMIT 50", {
					query = string.lower('%'..sentSearch..'%'), -- % wildcard, needed to search for all alike results
					jobtype = JobType
				})

				TriggerClientEvent('mdt:client:getAllReports', src, matches)
			end
		end
	end
end)

RegisterNetEvent('mdt:server:newReport', function(existing, id, title, reporttype, details, tags, gallery, officers, civilians, time)
	if id then
		local src = source
		local Player = QBCore.Functions.GetPlayer(src)
		if Player then
			local JobType = GetJobType(Player.PlayerData.job.name)
			if JobType ~= nil then
				local fullname = Player.PlayerData.charinfo.firstname .. ' ' .. Player.PlayerData.charinfo.lastname
				local function InsertReport()
					MySQL.insert('INSERT INTO `mdt_reports` (`title`, `author`, `type`, `details`, `tags`, `gallery`, `officersinvolved`, `civsinvolved`, `time`, `jobtype`) VALUES (:title, :author, :type, :details, :tags, :gallery, :officersinvolved, :civsinvolved, :time, :jobtype)', {
						title = title,
						author = fullname,
						type = reporttype,
						details = details,
						tags = json.encode(tags),
						gallery = json.encode(gallery),
						officersinvolved = json.encode(officers),
						civsinvolved = json.encode(civilians),
						time = tostring(time),
						jobtype = JobType,
					}, function(r)
						if r then
							TriggerClientEvent('mdt:client:reportComplete', src, r)
							TriggerEvent('mdt:server:AddLog', "A new report was created by "..fullname.." with the title ("..title..") and ID ("..id..")")
						end
					end)
				end

				local function UpdateReport()
					MySQL.update("UPDATE `mdt_reports` SET `title` = :title, type = :type, details = :details, tags = :tags, gallery = :gallery, officersinvolved = :officersinvolved, civsinvolved = :civsinvolved, jobtype = :jobtype WHERE `id` = :id LIMIT 1", {
						title = title,
						type = reporttype,
						details = details,
						tags = json.encode(tags),
						gallery = json.encode(gallery),
						officersinvolved = json.encode(officers),
						civsinvolved = json.encode(civilians),
						jobtype = JobType,
						id = id,
					}, function(affectedRows)
						if affectedRows > 0 then
							TriggerClientEvent('mdt:client:reportComplete', src, id)
							TriggerEvent('mdt:server:AddLog', "A report was updated by "..fullname.." with the title ("..title..") and ID ("..id..")")
						end
					end)
				end

				if existing then
					UpdateReport()
				elseif not existing then
					InsertReport()
				end
			end
		end
	end
end)

QBCore.Functions.CreateCallback('mdt:server:SearchVehicles', function(source, cb, sentData)
	if not sentData then  return cb({}) end
	local src = source
	local PlayerData = GetPlayerData(src)
	if not PermCheck(source, PlayerData) then return cb({}) end

	local src = source
	local Player = QBCore.Functions.GetPlayer(src)
	if Player then
		local JobType = GetJobType(Player.PlayerData.job.name)
		if JobType == 'police' or JobType == 'doj' then
			local vehicles = MySQL.query.await("SELECT pv.id, pv.citizenid, pv.plate, pv.vehicle, pv.mods, pv.state, p.charinfo FROM `player_vehicles` pv LEFT JOIN players p ON pv.citizenid = p.citizenid WHERE LOWER(`plate`) LIKE :query OR LOWER(`vehicle`) LIKE :query LIMIT 25", {
				query = string.lower('%'..sentData..'%')
			})

			if not next(vehicles) then cb({}) return end

			for _, value in ipairs(vehicles) do
				if value.state == 0 then
					value.state = "Out"
				elseif value.state == 1 then
					value.state = "Garaged"
				elseif value.state == 2 then
					value.state = "Impounded"
				end

				value.bolo = false
				local boloResult = GetBoloStatus(value.plate)
				if boloResult then
					value.bolo = true
				end

				value.code = false
				value.stolen = false
				value.image = "img/not-found.webp"
				local info = GetVehicleInformation(value.plate)
				if info then
					value.code = info['code5']
					value.stolen = info['stolen']
					value.image = info['image']
				end

				local ownerResult = json.decode(value.charinfo)

				value.owner = ownerResult['firstname'] .. " " .. ownerResult['lastname']
			end
			return cb(vehicles)
		end

		return cb({})
	end

end)

RegisterNetEvent('mdt:server:getVehicleData', function(plate)
	if plate then
		local src = source
		local Player = QBCore.Functions.GetPlayer(src)
		if Player then
			local JobType = GetJobType(Player.PlayerData.job.name)
			if JobType == 'police' or JobType == 'doj' then
				local vehicle = MySQL.query.await("select pv.*, p.charinfo from player_vehicles pv LEFT JOIN players p ON pv.citizenid = p.citizenid where pv.plate = :plate LIMIT 1", { plate = string.gsub(plate, "^%s*(.-)%s*$", "%1")})
				if vehicle and vehicle[1] then
					vehicle[1]['impound'] = false
					if vehicle[1].state == 2 then
						vehicle[1]['impound'] = true
					end

					vehicle[1]['bolo'] = GetBoloStatus(vehicle[1]['plate'])
					vehicle[1]['information'] = ""

					vehicle[1]['name'] = "Unknown Person"

					local ownerResult = json.decode(vehicle[1].charinfo)
					vehicle[1]['name'] = ownerResult['firstname'] .. " " .. ownerResult['lastname']

					local color1 = json.decode(vehicle[1].mods)
					vehicle[1]['color1'] = color1['color1']

					vehicle[1]['dbid'] = 0

					local info = GetVehicleInformation(vehicle[1]['plate'])
					if info then
						vehicle[1]['information'] = info['information']
						vehicle[1]['dbid'] = info['id']
						vehicle[1]['points'] = info['points']
						vehicle[1]['image'] = info['image']
						vehicle[1]['code'] = info['code5']
						vehicle[1]['stolen'] = info['stolen']
					end

					if vehicle[1]['image'] == nil then vehicle[1]['image'] = "img/not-found.webp" end
				end

				TriggerClientEvent('mdt:client:getVehicleData', src, vehicle)
			end
		end
	end
end)

RegisterNetEvent('mdt:server:saveVehicleInfo', function(dbid, plate, imageurl, notes, stolen, code5, impoundInfo, points)
	if plate then
		local src = source
		local Player = QBCore.Functions.GetPlayer(src)
		if Player then
			if GetJobType(Player.PlayerData.job.name) == 'police' then
				if dbid == nil then dbid = 0 end;
				local fullname = Player.PlayerData.charinfo.firstname .. ' ' .. Player.PlayerData.charinfo.lastname
				TriggerEvent('mdt:server:AddLog', "A vehicle with the plate ("..plate..") has a new image ("..imageurl..") edited by "..fullname)
				if tonumber(dbid) == 0 then
					MySQL.insert('INSERT INTO `mdt_vehicleinfo` (`plate`, `information`, `image`, `code5`, `stolen`, `points`) VALUES (:plate, :information, :image, :code5, :stolen, :points)', { plate = string.gsub(plate, "^%s*(.-)%s*$", "%1"), information = notes, image = imageurl, code5 = code5, stolen = stolen, points = tonumber(points) }, function(infoResult)
						if infoResult then
							TriggerClientEvent('mdt:client:updateVehicleDbId', src, infoResult)
							TriggerEvent('mdt:server:AddLog', "A vehicle with the plate ("..plate..") was added to the vehicle information database by "..fullname)
						end
					end)
				elseif tonumber(dbid) > 0 then
					MySQL.update("UPDATE mdt_vehicleinfo SET `information`= :information, `image`= :image, `code5`= :code5, `stolen`= :stolen, `points`= :points WHERE `plate`= :plate LIMIT 1", { plate = string.gsub(plate, "^%s*(.-)%s*$", "%1"), information = notes, image = imageurl, code5 = code5, stolen = stolen, points = tonumber(points) })
				end

				if impoundInfo.impoundChanged then
					local vehicle = MySQL.single.await("SELECT p.id, p.plate, i.vehicleid AS impoundid FROM `player_vehicles` p LEFT JOIN `mdt_impound` i ON i.vehicleid = p.id WHERE plate=:plate", { plate = string.gsub(plate, "^%s*(.-)%s*$", "%1") })
					if impoundInfo.impoundActive then
						local plate, linkedreport, fee, time = impoundInfo['plate'], impoundInfo['linkedreport'], impoundInfo['fee'], impoundInfo['time']
						if (plate and linkedreport and fee and time) then
							if vehicle.impoundid == nil then
								-- This section is copy pasted from request impound and needs some attention.
								-- sentVehicle doesnt exist.
								-- data is defined twice
								-- INSERT INTO will not work if it exists already (which it will)
								local data = vehicle
								MySQL.insert('INSERT INTO `mdt_impound` (`vehicleid`, `linkedreport`, `fee`, `time`) VALUES (:vehicleid, :linkedreport, :fee, :time)', {
									vehicleid = data['id'],
									linked
					text = footer,
				},
			}
		}

		PerformHttpRequest(ClockinWebhook, function(err, text, headers) end, 'POST', json.encode({username = name, embeds = embed}), { ['Content-Type'] = 'application/json' })
	end
end

function sendIncidentToDiscord(color, name, message, footer, associatedData)
    local rolePing = ""  -- Add your role ID here if needed
    local pingMessage = ""
    
    if associatedData and associatedData.guilty == false then
        pingMessage = "**Guilty: Not Guilty - Need Court Case**" .. (rolePing ~= "" and " " .. rolePing or "")
        message = message .. "\n" .. pingMessage
            else
                message = message .. "\nGuilty: " .. tostring(associatedData.guilty or "Not Found")
            end


            if associatedData.officersinvolved and #associatedData.officersinvolved > 0 then
                local officersList = table.concat(associatedData.officersinvolved, ", ")
                message = message .. "\nOfficers Involved: " .. officersList
            else
                message = message .. "\nOfficers Involved: None"
            end

            if associatedData.civsinvolved and #associatedData.civsinvolved > 0 then
                local civsList = table.concat(associatedData.civsinvolved, ", ")
                message = message .. "\nCivilians Involved: " .. civsList
            else
                message = message .. "\nCivilians Involved: None"
            end


            message = message .. "\nWarrant: " .. tostring(associatedData.warrant or "No Warrants")
            message = message .. "\nReceived Fine: $" .. tostring(associatedData.fine or "Not Found")
            message = message .. "\nReceived Sentence: " .. tostring(associatedData.sentence or "Not Found")
            message = message .. "\nRecommended Fine: $" .. tostring(associatedData.recfine or "Not Found")
            message = message .. "\nRecommended Sentence: " .. tostring(associatedData.recsentence or "Not Found")

            local chargesTable = json.decode(associatedData.charges)
            if chargesTable and #chargesTable > 0 then
                local chargeList = table.concat(chargesTable, "\n")
                message = message .. "\n**Charges:** \n" .. chargeList
            else
                message = message .. "\n**Charges: No Charges**"
            end
        end

        local embed = {
            {
                color = color,
                title = "**".. name .."**",
                description = message,
                footer = {
                    text = footer,
                },
            }
        }        PerformHttpRequest(IncidentWebhook, function(err, text, headers) end, 'POST', json.encode({content = pingMessage, username = name, embeds = embed}), { ['Content-Type'] = 'application/json' })
    end
end

function format_time(time)
    local days = math.floor(time / 86400)
    time = time % 86400
    local hours = math.floor(time / 3600)
    time = time % 3600
    local minutes = math.floor(time / 60)
    local seconds = time % 60

    local formattedTime = ""
    if days > 0 then
        formattedTime = string.format("%d day%s ", days, days == 1 and "" or "s")
    end
    if hours > 0 then
        formattedTime = formattedTime .. string.format("%d hour%s ", hours, hours == 1 and "" or "s")
    end
    if minutes > 0 then
        formattedTime = formattedTime .. string.format("%d minute%s ", minutes, minutes == 1 and "" or "s")
    end
    if seconds > 0 then
        formattedTime = formattedTime .. string.format("%d second%s", seconds, seconds == 1 and "" or "s")
    end
    return formattedTime
end

function GetPlayerPropertiesByCitizenId(citizenid)
    local properties = {}

    local result = MySQL.Sync.fetchAll("SELECT * FROM properties WHERE owner_citizenid = @citizenid", {
        ['@citizenid'] = citizenid
    })

    if result and #result > 0 then
        for i = 1, #result do
            table.insert(properties, result[i])
        end
    end

    return properties
end

function GetPlayerPropertiesByOwner(citizenid)
    local properties = {}

    local result = MySQL.Sync.fetchAll("SELECT * FROM properties WHERE owner = @citizenid", {
        ['@citizenid'] = citizenid
    })

    if result and #result > 0 then
        for i = 1, #result do
            table.insert(properties, result[i])
        end
    end

    return properties
end

function generateMessageFromResult(result)
    local author = result[1].author
    local title = result[1].title
    local details = result[1].details
    details = details:gsub("<[^>]+>", ""):gsub("&nbsp;", "")
    local message = "Author: " .. author .. "\n"
    message = message .. "Title: " .. title .. "\n"
    message = message .. "Details: " .. details
    return message
end

if Config.InventoryForWeaponsImages == "ox_inventory" and Config.RegisterWeaponsAutomatically then
	exports.ox_inventory:registerHook('buyItem', function(payload)
		if not string.find(payload.itemName, "WEAPON_") then return true end
		CreateThread(function()
			local owner = QBCore.Functions.GetPlayer(payload.source).PlayerData.citizenid
			if not owner or not payload.metadata.serial then return end
			local imageurl = ("https://cfx-nui-ox_inventory/web/images/%s.png"):format(payload.itemName)
			local notes = "Purchased from shop"
			local weapClass = "Class" --@TODO retrieve class better

			local success, result = pcall(function()
				return CreateWeaponInfo(payload.metadata.serial, imageurl, notes, owner, weapClass, payload.itemName)
			end)

			if not success then
				print("Error in creating weapon info in MDT: " .. result)
			end
		end)
		return true
	end, {
		typeFilter = { ['player'] = true }
	})
	-- This is for other shop resources that use the AddItem method.
	-- Only registers weapons with serial numbers, must specify a slot in ox_inventory:AddItem with metadata
	-- metadata = {
	--   registered = true
	-- }
	if Config.RegisterCreatedWeapons then
		exports.ox_inventory:registerHook('createItem', function(payload)
			if not string.find(payload.item.name, "WEAPON_") then return true end
			CreateThread(function()
				local owner = QBCore.Functions.GetPlayer(payload.inventoryId).PlayerData.citizenid
				if not owner or not payload.metadata.serial then return end
				local imageurl = ("https://cfx-nui-ox_inventory/web/images/%s.png"):format(payload.item.name)
				local notes = "Purchased from shop"
				local weapClass = "Class" --@TODO retrieve class better

				local success, result = pcall(function()
					return CreateWeaponInfo(payload.metadata.serial, imageurl, notes, owner, weapClass, payload.item.name)
				end)

				if not success then
					print("Error in creating weapon info in MDT: " .. result)
				end
			end)			return true
		end, {
			typeFilter = { ['player'] = true }
		})
	end
