Api = Api or {}

local net <const> = playdate.network

-- writes the response to disk in chunks
-- buffering the and decoding it in one callback trips the 10s loop watchdog.
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
