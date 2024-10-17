local fio = require('fio')
local digest = require('digest')
local checks = require('checks')
local log = require('log') -- luacheck: ignore

local Loader = {}
Loader.__index = Loader

local function assert_migration(migration)
    checks({
        name = 'string',
        up = 'function',
    })
    return migration
end

function Loader:list()
    local result = {}
    local search_folder = fio.pathjoin(package.searchroot(), self.dir_name)
    if not fio.path.is_dir(search_folder) then error(('Path %s is not valid'):format(search_folder)) end
    local files = fio.listdir(search_folder) or {}
    table.sort(files)
    for _, v in ipairs(files) do
        local migration, err = dofile(fio.pathjoin(search_folder, v))
        if migration ~= nil then
            migration.name = v
            assert_migration(migration)
            table.insert(result, migration)
        else
            log.warn('Cannot load %s: %s', v, err)
        end
    end
    return result
end

function Loader:hashes_by_name()
    local result = {}

    local search_folder = fio.pathjoin(package.searchroot(), self.dir_name)
    if not fio.path.is_dir(search_folder) then error(('Path %s is not valid'):format(search_folder)) end
    local files = fio.listdir(search_folder) or {}
    for _, file_name in ipairs(files) do
        local fh, err_open = fio.open(fio.pathjoin(search_folder, file_name), {'O_RDONLY'})
        if err_open ~= nil then
            log.warn('Cannot open file %s: %s', file_name, err_open)
        else
            local lua_code, err_read = fh:read()
            if err_read ~= nil then
                log.warn('Cannot read file %s: %s', file_name, err_read)
            else
                result[file_name] = digest.md5(lua_code)
            end
        end
    end

    return result
end

local function new(dir_name)
    checks('?string')
    dir_name = dir_name or 'migrations'
    local loader = {
        dir_name = dir_name,
    }
    setmetatable(loader, Loader)
    return loader
end

return {
    new = new
}


