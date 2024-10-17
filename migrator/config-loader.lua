local fio = require('fio')
local digest = require('digest')
local checks = require('checks')
local log = require('log')

local Loader = {}
Loader.__index = Loader

local function __must_sort(m)
    table.sort(m, function(a, b) return a.name < b.name end)
end

local function assert_migration(migration)
    checks({
        name = 'string',
        up = 'function',
    })
    return migration
end

function Loader:list()
    local ca = require("cartridge.confapplier")
    local cfg = ca.get_active_config():get_plaintext()
    if cfg == nil then
        return {}
    end

    local result = {}

    for k, v in pairs(cfg) do
        if k:startswith(self.config_section_name) then
            local migration, err = loadstring(v)
            if migration ~= nil then
                local m = migration()
                m.name = fio.basename(k)
                assert_migration(m)
                table.insert(result, m)
            else
                log.warn('Cannot load %s: %s', v, err)
            end
        end
    end

    __must_sort(result)

    return result
end

function Loader:hashes_by_name(cfg)
    -- cfg might be a new config from validate_config
    -- if nil uses current active config
    local ca = require("cartridge.confapplier")
    cfg = cfg or ca.get_active_config():get_plaintext()
    if cfg == nil then
        return {}
    end

    local result = {}

    for k, text in pairs(cfg) do
        if k:startswith(self.config_section_name) then
            local name = k:match("([^/]+)$")
            if name ~= nil then
                result[name] = digest.md5(text)
            else
                log.warn('Cannot load %s', k)
            end
        end
    end

    return result
end

local function new()
    local loader = {
        config_section_name = 'migrations/source',
    }
    setmetatable(loader, Loader)
    return loader
end

return {
    __must_sort = __must_sort,
    new = new,
}
