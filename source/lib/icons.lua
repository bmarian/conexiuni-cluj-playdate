Icons = Icons or {}

local cache = {}

function Icons.get(name, size)
    local key = name .. "-" .. size
    local cached = cache[key]
    if cached ~= nil then return cached end

    local image = Graphics.image.new("images/icons/" .. key)
    cache[key] = image
    return image
end

function Icons.draw(name, size, x, y, flip)
    local image = Icons.get(name, size)
    if image ~= nil then image:draw(x, y, flip or Graphics.kImageUnflipped) end
end

function Icons.drawCentered(name, size, x, y, flip)
    local image = Icons.get(name, size)
    if image ~= nil then
        image:draw(x - size // 2, y - size // 2, flip or Graphics.kImageUnflipped)
    end
end
