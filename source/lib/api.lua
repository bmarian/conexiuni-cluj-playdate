-- Thin wrapper around playdate.network.http. Used only by the sync screen;
-- every other screen reads from Store (local data), never the network.
-- Defined as a global (not `local M = {}; return M`) because Playdate's
-- `import` only returns a value the FIRST time a file is imported anywhere
-- in the compiled bundle -- a second import from elsewhere silently gets
-- nil. A global avoids depending on import order entirely.

Api = Api or {}

local net <const> = playdate.network

-- Api.get(host, port, useSSL, path, reason, onSuccess, onError)
-- onSuccess(decodedJson) / onError(message), called at most once.
function Api.get(host, port, useSSL, path, reason, onSuccess, onError)
	local chunks = {}
	local conn = net.http.new(host, port, useSSL, reason)
	if not conn then
		onError("network access denied")
		return
	end

	conn:setRequestCallback(function()
		local bytes = conn:getBytesAvailable()
		if bytes > 0 then
			local chunk = conn:read(bytes)
			table.insert(chunks, chunk)
		end
	end)

	conn:setRequestCompleteCallback(function()
		local err = conn:getError()
		conn:close()
		if err ~= nil and err ~= "Connection closed" then
			onError(tostring(err))
			return
		end

		local body = table.concat(chunks)
		local ok, decoded = pcall(json.decode, body)
		if not ok or decoded == nil then
			onError("could not parse response")
			return
		end
		onSuccess(decoded)
	end)

	conn:setConnectTimeout(10)
	local ok, err = conn:get(path)
	if not ok then
		onError(tostring(err))
	end
end
