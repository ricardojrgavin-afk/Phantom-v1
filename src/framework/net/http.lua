local environment = getgenv() or getfenv() or {}
local HttpService = game:GetService("HttpService")

local Http = {}
Http.__index = Http

local function getRequestFunction()
	return environment.request or environment.http_request or (environment.syn and environment.syn.request) or (environment.http and environment.http.request) or (environment.fluxus and environment.fluxus.request)
end

function Http.new(logger)
	return setmetatable({
		logger = logger,
	}, Http)
end

function Http:Request(options)
	local requestFunction = getRequestFunction()
	if not requestFunction then
		return false, "No request function available", { StatusCode = 0, Body = nil }
	end

	local ok, response = pcall(requestFunction, {
		Url = options.url,
		Method = options.method or "GET",
		Headers = options.headers or {},
		Body = options.body,
	})

	if ok and response and tonumber(response.StatusCode) then
		if response.StatusCode >= 200 and response.StatusCode < 300 then
			return true, response.Body, response
		end
		return false, response.Body, response
	end

	return false, response, { StatusCode = 0, Body = response }
end

function Http:Get(url, headers)
	return self:Request({
		url = url,
		method = "GET",
		headers = headers,
	})
end

function Http:GetJson(url, headers)
	local ok, body, response = self:Get(url, headers)
	if not ok then
		return false, body, response
	end

	local success, decoded = pcall(function()
		return HttpService:JSONDecode(body)
	end)

	if not success then
		if self.logger then
			self.logger:Warn("failed to decode http json", url, decoded)
		end
		return false, decoded, response
	end

	return true, decoded, response
end

return Http
