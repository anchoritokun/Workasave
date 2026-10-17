local HttpService = game:GetService("HttpService")
local SerializationService = game:GetService("SerializationService")
local EncodingService = game:GetService("EncodingService")
local ReflectionService = game:GetService("ReflectionService")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local FORMAT_VERSION = 2
local CHUNK_SIZE_BYTES = 512 * 1024
local INDEX_SETTING_KEY = "Workasave_Index"
local MAX_AUTOMATIC_BACKUPS = 3
local COMPRESSION_LEVEL = 6
local NUMBER_TOLERANCE = 1e-5

local SERVICE_NAMES = {
	"Workspace", "Lighting", "MaterialService", "ReplicatedFirst", "ReplicatedStorage",
	"ServerScriptService", "ServerStorage", "StarterGui", "StarterPack", "StarterPlayer",
	"SoundService", "Teams", "TextChatService", "Chat", "LocalizationService", "Players", "TestService",
}
local PROPERTIES_ONLY_SERVICES = { Players = true }

local IGNORED_PROPERTY_NAMES = {
	Parent = true, Archivable = true, Name = true, UniqueId = true,
	ScriptGuid = true, SourceAssetId = true, Source = true,
}

local Core = {}
Core.ServiceNames = SERVICE_NAMES
Core.PropertiesOnlyServices = PROPERTIES_ONLY_SERVICES

local settingsStore = nil

function Core.init(store)
	settingsStore = store
end

local lastYieldClock = os.clock()
local function yieldIfBusy()
	if os.clock() - lastYieldClock > 0.05 then
		task.wait()
		lastYieldClock = os.clock()
	end
end

function Core.formatBytes(byteCount)
	if byteCount >= 1024 * 1024 then
		return ("%.1f MB"):format(byteCount / 1024 / 1024)
	elseif byteCount >= 1024 then
		return ("%.0f KB"):format(byteCount / 1024)
	end
	return byteCount .. " B"
end

local function encodePropertyValue(value)
	local valueType = typeof(value)
	if valueType == "boolean" then
		return { "bool", value }
	elseif valueType == "number" then
		if value ~= value then
			return { "number", "nan" }
		elseif value == math.huge then
			return { "number", "inf" }
		elseif value == -math.huge then
			return { "number", "-inf" }
		end
		return { "number", value }
	elseif valueType == "string" then
		return { "string", value }
	elseif valueType == "EnumItem" then
		return { "enum", tostring(value.EnumType), value.Name }
	elseif valueType == "Color3" then
		return { "color3", value.R, value.G, value.B }
	elseif valueType == "Vector2" then
		return { "vector2", value.X, value.Y }
	elseif valueType == "Vector3" then
		return { "vector3", value.X, value.Y, value.Z }
	elseif valueType == "UDim" then
		return { "udim", value.Scale, value.Offset }
	elseif valueType == "UDim2" then
		return { "udim2", value.X.Scale, value.X.Offset, value.Y.Scale, value.Y.Offset }
	elseif valueType == "Rect" then
		return { "rect", value.Min.X, value.Min.Y, value.Max.X, value.Max.Y }
	elseif valueType == "NumberRange" then
		return { "numberRange", value.Min, value.Max }
	elseif valueType == "BrickColor" then
		return { "brickColor", value.Name }
	elseif valueType == "CFrame" then
		return { "cframe", unpack({ value:GetComponents() }) }
	elseif valueType == "Font" then
		return { "font", value.Family, value.Weight.Name, value.Style.Name }
	elseif valueType == "NumberSequence" then
		local encoded = { "numberSequence" }
		for _, keypoint in value.Keypoints do
			table.insert(encoded, { keypoint.Time, keypoint.Value, keypoint.Envelope })
		end
		return encoded
	elseif valueType == "ColorSequence" then
		local encoded = { "colorSequence" }
		for _, keypoint in value.Keypoints do
			table.insert(encoded, { keypoint.Time, keypoint.Value.R, keypoint.Value.G, keypoint.Value.B })
		end
		return encoded
	end
	return nil
end

local function decodePropertyValue(encoded)
	local kind = encoded[1]
	if kind == "bool" or kind == "string" then
		return encoded[2]
	elseif kind == "number" then
		local raw = encoded[2]
		if raw == "nan" then
			return 0 / 0
		elseif raw == "inf" then
			return math.huge
		elseif raw == "-inf" then
			return -math.huge
		end
		return raw
	elseif kind == "enum" then
		return Enum[encoded[2]][encoded[3]]
	elseif kind == "color3" then
		return Color3.new(encoded[2], encoded[3], encoded[4])
	elseif kind == "vector2" then
		return Vector2.new(encoded[2], encoded[3])
	elseif kind == "vector3" then
		return Vector3.new(encoded[2], encoded[3], encoded[4])
	elseif kind == "udim" then
		return UDim.new(encoded[2], encoded[3])
	elseif kind == "udim2" then
		return UDim2.new(encoded[2], encoded[3], encoded[4], encoded[5])
	elseif kind == "rect" then
		return Rect.new(encoded[2], encoded[3], encoded[4], encoded[5])
	elseif kind == "numberRange" then
		return NumberRange.new(encoded[2], encoded[3])
	elseif kind == "brickColor" then
		return BrickColor.new(encoded[2])
	elseif kind == "cframe" then
		return CFrame.new(unpack(encoded, 2))
	elseif kind == "font" then
		return Font.new(encoded[2], Enum.FontWeight[encoded[3]], Enum.FontStyle[encoded[4]])
	elseif kind == "numberSequence" then
		local keypoints = {}
		for i = 2, #encoded do
			table.insert(keypoints, NumberSequenceKeypoint.new(encoded[i][1], encoded[i][2], encoded[i][3]))
		end
		return NumberSequence.new(keypoints)
	elseif kind == "colorSequence" then
		local keypoints = {}
		for i = 2, #encoded do
			local point = encoded[i]
			table.insert(keypoints, ColorSequenceKeypoint.new(point[1], Color3.new(point[2], point[3], point[4])))
		end
		return ColorSequence.new(keypoints)
	end
	error("unknown value type " .. tostring(kind))
end

local function encodedValuesEqual(first, second)
	if type(first) ~= type(second) then
		return false
	end
	if type(first) == "number" then
		local scale = math.max(1, math.abs(first), math.abs(second))
		return math.abs(first - second) <= NUMBER_TOLERANCE * scale
	elseif type(first) == "table" then
		if #first ~= #second then
			return false
		end
		for i = 1, #first do
			if not encodedValuesEqual(first[i], second[i]) then
				return false
			end
		end
		return true
	end
	return first == second
end

local function isJsonSafe(encoded)
	return pcall(HttpService.JSONEncode, HttpService, encoded)
end

local function isReservedAttribute(attributeName)
	return attributeName:sub(1, 3):upper() == "RBX"
end

local function classifyChild(serviceName, child)
	if not child.Archivable then
		return "ignore"
	end
	if serviceName == "Workspace" then
		if child:IsA("PVInstance") or child:IsA("Camera") then
			return "ignore"
		end
		if child:FindFirstChildWhichIsA("PVInstance", true) then
			return "skipContainer"
		end
	end
	return "save"
end

local function collectSavableChildren(serviceName, service)
	local savable, skippedContainers = {}, {}
	if PROPERTIES_ONLY_SERVICES[serviceName] then
		return savable, skippedContainers
	end
	for _, child in service:GetChildren() do
		local verdict = classifyChild(serviceName, child)
		if verdict == "save" then
			table.insert(savable, child)
		elseif verdict == "skipContainer" then
			table.insert(skippedContainers, child.Name)
		end
	end
	return savable, skippedContainers
end

function Core.describe()
	local result = {}
	for _, serviceName in SERVICE_NAMES do
		local service = game:FindService(serviceName)
		if service then
			local savable, skippedContainers = collectSavableChildren(serviceName, service)
			local items = {}
			for _, instance in savable do
				table.insert(items, { name = instance.Name, class = instance.ClassName })
			end
			table.insert(result, {
				name = serviceName,
				items = items,
				skipped = skippedContainers,
				propertiesOnly = PROPERTIES_ONLY_SERVICES[serviceName] == true,
			})
		end
	end
	return result
end

local propertyNameCache = {}

local function getSavedPropertyNames(className)
	local cached = propertyNameCache[className]
	if cached then
		return cached
	end
	local names = {}
	local ok, descriptors = pcall(function()
		return ReflectionService:GetPropertiesOfClass(className)
	end)
	if ok then
		for _, descriptor in descriptors do
			if descriptor.Serialized and descriptor.Owner ~= "Instance" and not IGNORED_PROPERTY_NAMES[descriptor.Name] then
				table.insert(names, descriptor.Name)
			end
		end
	end
	propertyNameCache[className] = names
	return names
end

local function readPropertyMap(instance)
	local propertyMap = {}
	for _, propertyName in getSavedPropertyNames(instance.ClassName) do
		local readable, value = pcall(function()
			return instance[propertyName]
		end)
		if readable then
			local encoded = encodePropertyValue(value)
			if encoded ~= nil then
				propertyMap[propertyName] = encoded
			end
		end
	end
	if instance:IsA("LuaSourceContainer") then
		local readable, sourceText = pcall(function()
			return instance.Source
		end)
		if readable then
			propertyMap.Source = { "string", sourceText }
		end
	end
	return propertyMap
end

local function readAttributeMap(instance)
	local attributeMap = {}
	for attributeName, value in instance:GetAttributes() do
		if not isReservedAttribute(attributeName) then
			local encoded = encodePropertyValue(value)
			if encoded ~= nil then
				attributeMap[attributeName] = encoded
			end
		end
	end
	return attributeMap
end

local function sortedTagList(instance)
	local tags = instance:GetTags()
	table.sort(tags)
	return tags
end

local function captureServiceData(service)
	local data = { properties = {}, attributes = {}, tags = service:GetTags() }
	for propertyName, encoded in readPropertyMap(service) do
		if isJsonSafe(encoded) then
			data.properties[propertyName] = encoded
		end
	end
	for attributeName, encoded in readAttributeMap(service) do
		if isJsonSafe(encoded) then
			data.attributes[attributeName] = encoded
		end
	end
	return data
end

local function clearAttributes(instance)
	for attributeName in instance:GetAttributes() do
		if not isReservedAttribute(attributeName) then
			pcall(instance.SetAttribute, instance, attributeName, nil)
		end
	end
end

local function applyServiceData(service, data, onlyChanges)
	local setCount, failedNames = 0, {}
	local currentProperties = onlyChanges and readPropertyMap(service) or nil
	for propertyName, encoded in data.properties do
		local alreadyMatches = currentProperties
			and currentProperties[propertyName] ~= nil
			and encodedValuesEqual(currentProperties[propertyName], encoded)
		if not alreadyMatches then
			local ok = pcall(function()
				service[propertyName] = decodePropertyValue(encoded)
			end)
			if ok then
				setCount += 1
			else
				table.insert(failedNames, propertyName)
			end
		end
	end
	clearAttributes(service)
	for attributeName, encoded in data.attributes do
		pcall(function()
			service:SetAttribute(attributeName, decodePropertyValue(encoded))
		end)
	end
	for _, tag in service:GetTags() do
		service:RemoveTag(tag)
	end
	for _, tag in data.tags do
		service:AddTag(tag)
	end
	table.sort(failedNames)
	return setCount, failedNames
end

local function writeBlob(blobKey, data)
	local compressed = EncodingService:CompressBuffer(data, Enum.CompressionAlgorithm.Zstd, COMPRESSION_LEVEL)
	local text = buffer.tostring(EncodingService:Base64Encode(compressed))
	local chunkCount = math.max(1, math.ceil(#text / CHUNK_SIZE_BYTES))
	for chunkNumber = 1, chunkCount do
		local firstByte = (chunkNumber - 1) * CHUNK_SIZE_BYTES + 1
		settingsStore.set(blobKey .. "_" .. chunkNumber, text:sub(firstByte, firstByte + CHUNK_SIZE_BYTES - 1))
		yieldIfBusy()
	end
	return { key = blobKey, chunks = chunkCount, rawBytes = buffer.len(data), storedBytes = #text }
end

local function readBlob(blobInfo)
	local pieces = table.create(blobInfo.chunks)
	for chunkNumber = 1, blobInfo.chunks do
		local piece = settingsStore.get(blobInfo.key .. "_" .. chunkNumber)
		if type(piece) ~= "string" then
			error("Saved data is missing (part " .. chunkNumber .. " of " .. blobInfo.key .. ").", 0)
		end
		pieces[chunkNumber] = piece
		yieldIfBusy()
	end
	local compressed = EncodingService:Base64Decode(buffer.fromstring(table.concat(pieces)))
	return EncodingService:DecompressBuffer(compressed, Enum.CompressionAlgorithm.Zstd)
end

local function deleteBlob(blobInfo)
	for chunkNumber = 1, blobInfo.chunks do
		settingsStore.set(blobInfo.key .. "_" .. chunkNumber, nil)
	end
end

local function deleteServiceBlobs(serviceInfo)
	if serviceInfo.instances then
		deleteBlob(serviceInfo.instances)
	end
	if serviceInfo.properties then
		deleteBlob(serviceInfo.properties)
	end
end

local function readIndex()
	local rawText = settingsStore.get(INDEX_SETTING_KEY)
	if type(rawText) == "string" then
		local ok, index = pcall(HttpService.JSONDecode, HttpService, rawText)
		if ok and type(index) == "table" and type(index.saves) == "table" then
			return index
		end
	end
	return { saves = {} }
end

local function writeIndex(index)
	settingsStore.set(INDEX_SETTING_KEY, HttpService:JSONEncode(index))
end

function Core.list()
	local entries = {}
	for _, entry in readIndex().saves do
		table.insert(entries, entry)
	end
	table.sort(entries, function(left, right)
		return left.created > right.created
	end)
	return entries
end

function Core.find(saveId)
	return saveId and readIndex().saves[saveId] or nil
end

function Core.delete(saveId)
	local index = readIndex()
	local entry = index.saves[saveId]
	if entry then
		for _, serviceInfo in entry.services do
			deleteServiceBlobs(serviceInfo)
		end
		index.saves[saveId] = nil
		writeIndex(index)
	end
end

local function pruneAutomaticBackups()
	local backups = {}
	for _, entry in Core.list() do
		if entry.auto then
			table.insert(backups, entry)
		end
	end
	for i = MAX_AUTOMATIC_BACKUPS + 1, #backups do
		Core.delete(backups[i].id)
	end
end

local function serializeInstances(instances)
	local ok, data = pcall(function()
		return SerializationService:SerializeInstancesAsync(instances)
	end)
	if ok then
		return data, {}
	end
	local good, badNames = {}, {}
	for _, instance in instances do
		local serializable = pcall(function()
			SerializationService:SerializeInstancesAsync({ instance })
		end)
		if serializable then
			table.insert(good, instance)
		else
			table.insert(badNames, instance.Name)
		end
		yieldIfBusy()
	end
	if #good == 0 then
		return nil, badNames
	end
	return SerializationService:SerializeInstancesAsync(good), badNames
end

function Core.save(saveName, serviceNames, onProgress, isAutomaticBackup, overwriteId)
	onProgress = onProgress or function() end
	local index = readIndex()
	local existing = overwriteId and index.saves[overwriteId] or nil
	if overwriteId and not existing then
		error("The save you chose to overwrite no longer exists.", 0)
	end

	local saveId = existing and existing.id or ("%d%04d"):format(os.time(), math.random(0, 9999))
	local writeStamp = ("%d%04d"):format(os.time(), math.random(0, 9999))
	local newServices = {}
	local warnings = {}

	local ok, errorMessage = pcall(function()
		for position, serviceName in serviceNames do
			onProgress("Saving " .. serviceName .. "...", (position - 1) / #serviceNames)
			local service = game:FindService(serviceName)
			if service then
				local keyPrefix = saveId .. "_" .. serviceName .. "_" .. writeStamp
				local serviceInfo = { itemCount = 0, propertyCount = 0 }
				local savable, skippedContainers = collectSavableChildren(serviceName, service)
				for _, containerName in skippedContainers do
					table.insert(warnings, serviceName .. "." .. containerName .. " contains parts, so it was not saved")
				end
				if #savable > 0 then
					local data, unsavableNames = serializeInstances(savable)
					for _, unsavableName in unsavableNames do
						table.insert(warnings, serviceName .. "." .. unsavableName .. " could not be saved")
					end
					if data then
						serviceInfo.itemCount = #savable - #unsavableNames
						serviceInfo.instances = writeBlob(keyPrefix .. "_i", data)
					end
				end
				local serviceData = captureServiceData(service)
				for _ in serviceData.properties do
					serviceInfo.propertyCount += 1
				end
				serviceInfo.properties = writeBlob(keyPrefix .. "_p", buffer.fromstring(HttpService:JSONEncode(serviceData)))
				newServices[serviceName] = serviceInfo
			end
			yieldIfBusy()
		end
	end)
	if not ok then
		for _, serviceInfo in newServices do
			pcall(deleteServiceBlobs, serviceInfo)
		end
		error(errorMessage, 0)
	end

	local entry = existing or { id = saveId, services = {} }
	entry.name = saveName
	entry.created = os.time()
	entry.auto = isAutomaticBackup or nil
	entry.placeId = game.PlaceId
	entry.placeName = game.Name
	entry.version = FORMAT_VERSION
	for serviceName, serviceInfo in newServices do
		local previous = entry.services[serviceName]
		if previous then
			pcall(deleteServiceBlobs, previous)
		end
		entry.services[serviceName] = serviceInfo
	end
	entry.rawBytes, entry.storedBytes = 0, 0
	for _, serviceInfo in entry.services do
		for _, blob in { serviceInfo.instances, serviceInfo.properties } do
			entry.rawBytes += blob.rawBytes
			entry.storedBytes += blob.storedBytes
		end
	end
	index.saves[saveId] = entry
	writeIndex(index)
	if isAutomaticBackup then
		pruneAutomaticBackups()
	end
	onProgress("Saved", 1)
	return entry, warnings
end

local function findDifferences(currentInstance, savedInstance)
	local differences = { properties = {}, attributes = false, tags = false }

	local currentProperties = readPropertyMap(currentInstance)
	for propertyName, savedValue in readPropertyMap(savedInstance) do
		local currentValue = currentProperties[propertyName]
		if currentValue ~= nil and not encodedValuesEqual(currentValue, savedValue) then
			table.insert(differences.properties, propertyName)
		end
	end

	local currentAttributes, savedAttributes = readAttributeMap(currentInstance), readAttributeMap(savedInstance)
	for attributeName, savedValue in savedAttributes do
		local currentValue = currentAttributes[attributeName]
		if currentValue == nil or not encodedValuesEqual(currentValue, savedValue) then
			differences.attributes = true
		end
	end
	for attributeName in currentAttributes do
		if savedAttributes[attributeName] == nil then
			differences.attributes = true
		end
	end

	local currentTags, savedTags = sortedTagList(currentInstance), sortedTagList(savedInstance)
	differences.tags = table.concat(currentTags, "\0") ~= table.concat(savedTags, "\0")

	differences.any = #differences.properties > 0 or differences.attributes or differences.tags
	return differences
end

local function applyDifferences(currentInstance, savedInstance, differences)
	for _, propertyName in differences.properties do
		local ok = pcall(function()
			currentInstance[propertyName] = savedInstance[propertyName]
		end)
		if not ok then
			return false
		end
	end
	if differences.attributes then
		clearAttributes(currentInstance)
		for attributeName, value in savedInstance:GetAttributes() do
			if not isReservedAttribute(attributeName) then
				pcall(currentInstance.SetAttribute, currentInstance, attributeName, value)
			end
		end
	end
	if differences.tags then
		for _, tag in currentInstance:GetTags() do
			currentInstance:RemoveTag(tag)
		end
		for _, tag in savedInstance:GetTags() do
			currentInstance:AddTag(tag)
		end
	end
	return true
end

local function matchKey(instance)
	return instance.Name .. "\0" .. instance.ClassName
end

local function mergeChildren(currentParent, savedChildren, stats, isMatchCandidate)
	local candidates = {}
	for _, existingChild in currentParent:GetChildren() do
		if isMatchCandidate(existingChild) then
			local key = matchKey(existingChild)
			candidates[key] = candidates[key] or {}
			table.insert(candidates[key], existingChild)
		end
	end

	for _, savedChild in savedChildren do
		local bucket = candidates[matchKey(savedChild)]
		local currentChild = bucket and table.remove(bucket, 1) or nil
		if currentChild == nil then
			savedChild.Parent = currentParent
			stats.added += 1
		else
			local differences = findDifferences(currentChild, savedChild)
			local replacedWholeItem = false
			if differences.any then
				stats.updated += 1
				if not applyDifferences(currentChild, savedChild, differences) then
					currentChild:Destroy()
					savedChild.Parent = currentParent
					replacedWholeItem = true
				end
			else
				stats.unchanged += 1
			end
			if not replacedWholeItem then
				mergeChildren(currentChild, savedChild:GetChildren(), stats, function()
					return true
				end)
				savedChild:Destroy()
			end
		end
		yieldIfBusy()
	end
end

function Core.load(saveId, serviceNames, mode, onProgress)
	onProgress = onProgress or function() end
	local entry = Core.find(saveId)
	if not entry then
		error("That save no longer exists.", 0)
	end
	local isMerge = mode == "merge"

	local loadedServices = {}
	for position, serviceName in serviceNames do
		local serviceInfo = entry.services[serviceName]
		if serviceInfo then
			onProgress("Reading " .. serviceName .. "...", 0.4 * (position - 1) / #serviceNames)
			local loaded = { instances = {}, data = nil }
			if serviceInfo.instances then
				loaded.instances = SerializationService:DeserializeInstancesAsync(readBlob(serviceInfo.instances))
			end
			if serviceInfo.properties then
				loaded.data = HttpService:JSONDecode(buffer.tostring(readBlob(serviceInfo.properties)))
			end
			loadedServices[serviceName] = loaded
		end
		yieldIfBusy()
	end

	onProgress("Backing up current state...", 0.4)
	local backedUpServices = {}
	for _, serviceName in serviceNames do
		if loadedServices[serviceName] and game:FindService(serviceName) then
			table.insert(backedUpServices, serviceName)
		end
	end
	local backupName = 'Backup before loading "' .. entry.name .. '"'
	if #backedUpServices > 0 then
		Core.save(backupName, backedUpServices, nil, true)
	end

	local report = { mode = isMerge and "merge" or "replace", services = {}, warnings = {}, backupName = backupName }
	local recordingId = ChangeHistoryService:TryBeginRecording("Workasave: Load")
	local ok, errorMessage = pcall(function()
		for position, serviceName in serviceNames do
			local loaded = loadedServices[serviceName]
			if loaded then
				onProgress("Loading " .. serviceName .. "...", 0.4 + 0.6 * (position - 1) / #serviceNames)
				local service = game:GetService(serviceName)
				local stats = { added = 0, updated = 0, unchanged = 0, removed = 0, properties = 0, failedProperties = {} }

				if not PROPERTIES_ONLY_SERVICES[serviceName] then
					if isMerge then
						mergeChildren(service, loaded.instances, stats, function(child)
							return classifyChild(serviceName, child) == "save"
						end)
					else
						for _, child in service:GetChildren() do
							if classifyChild(serviceName, child) == "save" and pcall(child.Destroy, child) then
								stats.removed += 1
							end
							yieldIfBusy()
						end
						for number, instance in loaded.instances do
							if pcall(function()
								instance.Parent = service
							end) then
								stats.added += 1
							else
								table.insert(report.warnings, serviceName .. "." .. instance.Name .. " could not be placed")
							end
							if number % 10 == 0 then
								task.wait()
							end
						end
					end
				end
				if loaded.data then
					stats.properties, stats.failedProperties = applyServiceData(service, loaded.data, isMerge)
				end
				report.services[serviceName] = stats
			end
		end
	end)
	if recordingId then
		ChangeHistoryService:FinishRecording(recordingId, Enum.FinishRecordingOperation.Commit)
	end
	if not ok then
		error(errorMessage, 0)
	end
	for _, loaded in loadedServices do
		for _, instance in loaded.instances do
			if instance.Parent == nil then
				instance:Destroy()
			end
		end
	end
	onProgress("Done", 1)
	return report
end
