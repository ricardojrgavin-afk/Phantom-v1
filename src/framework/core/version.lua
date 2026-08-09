local Version = {}

local function numberOrDefault(value, defaultValue)
	local asNumber = tonumber(value)
	if asNumber == nil then
		return defaultValue
	end
	return asNumber
end

function Version.Read(fileApi)
	local versionData = fileApi:ReadJson("version.json", {
		name = "Phantom",
		channel = "stable",
		major = 0,
		minor = 0,
		patch = 0,
	})

	versionData.major = numberOrDefault(versionData.major, 0)
	versionData.minor = numberOrDefault(versionData.minor, 0)
	versionData.patch = numberOrDefault(versionData.patch, 0)
	versionData.base = string.format("%d.%d.%d", versionData.major, versionData.minor, versionData.patch)

	local cachedManifest = fileApi:ReadJson("cache/release-manifest.json", nil)
	versionData.full = cachedManifest and cachedManifest.version or versionData.base
	versionData.releaseTag = cachedManifest and cachedManifest.releaseTag or "local"

	return versionData
end

return Version
