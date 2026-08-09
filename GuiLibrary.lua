--!nocheck

local executorReadFile = getfenv and getfenv().readfile or nil

if not executorReadFile then
	error("[phantom] readfile is not available in this executor")
end

local source = executorReadFile("Phantom/src/framework/core/LegacyGuiLibrary.lua")
local chunk, err = loadstring(source, "@Phantom/src/framework/core/LegacyGuiLibrary.lua")
if not chunk then
	error("[phantom] failed to compile legacy gui: " .. tostring(err))
end

return chunk()