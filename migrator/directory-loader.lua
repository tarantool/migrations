local fio = require('fio')
local checks = require('checks')
local log = require('log') -- luacheck: ignore

local Loader = {}
Loader.__index = Loader

local function assert_migration(migration)
    checks({
        name = 'string',
        up = 'function'
    })
    return migration
end

function Loader:list()
    local result = {}
    local files = fio.listdir(self.dir_name)
    table.sort(files)
    for _, v in ipairs(files) do
        local migration = dofile(fio.pathjoin(self.dir_name, v))
        migration.name = v
        assert_migration(migration)
        table.insert(result, migration)
    end
    return result
end

local function new(dir_name)
    checks('?string')
    dir_name = dir_name or 'migrations'
    local loader = {
        dir_name = dir_name
    }
    setmetatable(loader, Loader)
    return loader
end

return {
    new = new
}

