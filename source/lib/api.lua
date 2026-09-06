-- Thin wrapper around playdate.network.http. Used only by the sync screen;
-- every other screen reads from Store (local data), never the network.
-- Defined as a global (not `local M = {}; return M`) because Playdate's
-- `import` only returns a value the FIRST time a file is imported anywhere
-- in the compiled bundle -- a second import from elsewhere silently gets
-- nil. A global avoids depending on import order entirely.

Api = Api or {}

local net <const> = playdate.network

--- Streams a GET response straight to a file, a chunk per read callback.
---
--- It deliberately never builds the body as a Lua string and never decodes
--- it. The export is ~1MB of JSON; holding that as a string and decoding it
--- inside one callback blocks the update loop long enough for the device to
--- report "loop stalled for more than 10s", and re-encoding it afterwards
--- (which is what playdate.datastore.write does) costs as much again. Going
--- to disk in chunks spreads the work over the frames the download takes
--- anyway, and leaves exactly one decode, at load time.
---
--- request: { host, port, useSSL, path, reason, destination,
---            onProgress(read, total), onSuccess(bytes), onError(message) }
function Api.download(request)
	local connection = net.http.new(request.host, request.port, request.useSSL, request.reason)
	if not connection then
		request.onError("network access denied")
		return
	end

	local file, fileError = playdate.file.open(request.destination, playdate.file.kFileWrite)
	if not file then
		connection:close()
		request.onError("could not open " .. request.destination .. ": " .. tostring(fileError))
		return
	end

	local written = 0
	local done = false

	-- Both callbacks can plausibly fire on the same failure; the file and the
	-- connection must only be closed once.
	local function finish(ok, message)
		if done then return end
		done = true
		file:close()
		connection:close()
		if ok then
			request.onSuccess(written)
		else
			playdate.file.delete(request.destination)
			request.onError(message)
		end
	end

	connection:setHeadersReadCallback(function()
		local status = connection:getResponseStatus()
		-- Without this an error page gets written to disk and only fails much
		-- later, as an unreadable snapshot.
		if status ~= nil and status ~= 200 then
			finish(false, "server returned " .. status)
		end
	end)

	connection:setRequestCallback(function()
		if done then return end
		local available = connection:getBytesAvailable()
		if available > 0 then
			local chunk = connection:read(available)
			if chunk ~= nil then
				file:write(chunk)
				written = written + #chunk
			end
		end
		if request.onProgress then
			request.onProgress(connection:getProgress())
		end
	end)

	connection:setRequestCompleteCallback(function()
		local err = connection:getError()
		if err ~= nil and err ~= "Connection closed" then
			finish(false, tostring(err))
			return
		end
		if written == 0 then
			finish(false, "empty response")
			return
		end
		finish(true)
	end)

	connection:setConnectTimeout(10)
	local ok, err = connection:get(request.path)
	if not ok then
		finish(false, tostring(err))
	end
end
