local environment = getgenv() or getfenv() or {}

local HttpService = game:GetService("HttpService")

local Discord = {}
Discord.__index = Discord

local RPC_PORT_START = 6454
local RPC_PORT_END = 6467
local RPC_TIMEOUT = 3

local function requestFunction()
	return environment.request or environment.http_request or (environment.syn and environment.syn.request) or (environment.http and environment.http.request) or (environment.fluxus and environment.fluxus.request)
end

local function extractInviteCode(value)
	value = tostring(value or "")
	return value:match("discord%%.gg/([%w_-]+)") or value:match("discord%%.com/invite/([%w_-]+)") or value:match("^([%w_-]+)$") or ""
end

local function isSuccessfulResponse(response)
	local statusCode = tonumber(response and response.StatusCode)
	if statusCode == nil then
		return response ~= nil
	end

	return statusCode >= 200 and statusCode < 300
end

function Discord.new(options)
	options = options or {}
	return setmetatable({
		file = options.file,
		http = options.http,
		logger = options.logger,
		statePath = options.statePath or "configs/discord.json",
		invite = options.invite or "",
	}, Discord)
end

function Discord:_readState()
	if not self.file then
		return {}
	end

	local state = self.file:ReadJson(self.statePath, {})
	if type(state) ~= "table" then
		return {}
	end

	return state
end

function Discord:_writeState(state)
	if not self.file then
		return false, "file api unavailable"
	end

	return self.file:WriteJson(self.statePath, state, { force = true })
end

function Discord:IsInvited(invite)
	local code = extractInviteCode(invite or self.invite)
	if code == "" then
		return false
	end

	local state = self:_readState()
	local invites = type(state.invites) == "table" and state.invites or {}
	return invites[code] == true
end

function Discord:MarkInvited(invite)
	local code = extractInviteCode(invite or self.invite)
	if code == "" then
		return false, "missing invite code"
	end

	local state = self:_readState()
	state.invites = type(state.invites) == "table" and state.invites or {}
	state.invites[code] = true
	state.lastInvite = code
	state.updatedAt = os.time()

	return self:_writeState(state)
end

function Discord:_requestRpc(port, body)
	local url = string.format("http://127.0.0.1:%d/rpc?v=1", port)
	local req = requestFunction()

	if req then
		local ok, response = pcall(req, {
			Method = "POST",
			Url = url,
			Headers = {
				["Content-Type"] = "application/json",
				Origin = "https://discord.com",
			},
			Body = body,
		})

		if ok and isSuccessfulResponse(response) then
			return true, response and response.Body, response
		end

		return false, response and response.Body or response, response
	end

	if self.http and type(self.http.Request) == "function" then
		return self.http:Request({
			url = url,
			method = "POST",
			headers = {
				["Content-Type"] = "application/json",
				Origin = "https://discord.com",
			},
			body = body,
		})
	end

	return false, "request function unavailable"
end

function Discord:Invite(invite)
	local code = extractInviteCode(invite or self.invite)
	if code == "" then
		return false, "missing invite code"
	end

	local body = HttpService:JSONEncode({
		nonce = HttpService:GenerateGUID(false),
		args = {
			invite = {
				code = code,
			},
			code = code,
		},
		cmd = "INVITE_BROWSER",
	})
	local totalRequests = (RPC_PORT_END - RPC_PORT_START) + 1
	local completed = 0
	local success = false
	local responseBody
	local responseData
	local lastErr = "discord rpc unavailable"

	for port = RPC_PORT_START, RPC_PORT_END do
		task.spawn(function()
			local ok, currentBody, currentResponse = self:_requestRpc(port, body)
			if ok and not success then
				success = true
				responseBody = currentBody
				responseData = currentResponse
			elseif not ok and currentBody and currentBody ~= "" then
				lastErr = currentBody
			end

			completed = completed + 1
		end)
	end

	local startedAt = os.clock()
	while completed < totalRequests and not success do
		if (os.clock() - startedAt) >= RPC_TIMEOUT then
			break
		end
		task.wait()
	end

	if success then
		local saved, saveErr = self:MarkInvited(code)
		if not saved then
			return false, saveErr
		end
		return true, responseBody, responseData
	end

	if self.logger then
		self.logger:Warn("discord invite failed", code, lastErr)
	end

	return false, lastErr
end

function Discord:EnsureInvite(invite)
	local code = extractInviteCode(invite or self.invite)
	if code == "" then
		return false, "missing invite code", false
	end

	if self:IsInvited(code) then
		return true, "already invited", true
	end

	local ok, result = self:Invite(code)
	return ok, result, false
end

return Discord