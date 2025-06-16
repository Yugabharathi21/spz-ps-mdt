local Framework = Config.GetFramework()

function GetPlayerData(source)
    if Config.Framework == "qb" then
        local Player = Framework.Functions.GetPlayer(source)
        if Player == nil then return end
        return Player.PlayerData
    elseif Config.Framework == "esx" then
        local xPlayer = Framework.GetPlayerFromId(source)
        if xPlayer == nil then return end
        return {
            citizenid = xPlayer.identifier,
            charinfo = {
                firstname = xPlayer.get('firstName') or "",
                lastname = xPlayer.get('lastName') or "",
                birthdate = xPlayer.get('dateofbirth') or "",
            },
            job = xPlayer.getJob(),
            metadata = {
                callsign = xPlayer.get('callsign') or "NO CALLSIGN"
            }
        }
    end
end

function UnpackJob(data)
    if Config.Framework == "qb" then
        local job = {
            name = data.name,
            label = data.label
        }
        local grade = {
            name = data.grade.name,
        }
        return job, grade
    elseif Config.Framework == "esx" then
        local job = {
            name = data.name,
            label = data.label
        }
        local grade = {
            name = data.grade_name,
        }
        return job, grade
    end
end

function PermCheck(src, PlayerData)
	local result = true

	if not Config.AllowedJobs[PlayerData.job.name] then
		print(("UserId: %s(%d) tried to access the mdt even though they are not authorised (server direct)"):format(GetPlayerName(src), src))
		result = false
	end

	return result
end

function ProfPic(gender, profilepic)
	if profilepic then return profilepic end;
	if gender == "f" then return "img/female.png" end;
	return "img/male.png"
end

function IsJobAllowedToMDT(job)
	if Config.PoliceJobs[job] then
		return true
	elseif Config.AmbulanceJobs[job] then
		return true
	elseif Config.DojJobs[job] then
		return true
	else
		return false
	end
end

function GetNameFromPlayerData(PlayerData)
	return ('%s %s'):format(PlayerData.charinfo.firstname, PlayerData.charinfo.lastname)
end
