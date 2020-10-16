local rpc = require('cartridge.rpc')
local pool = require('cartridge.pool')
local cartridge = require('cartridge')
local confapplier = require('cartridge.confapplier')

local log = require('log')
local fiber = require('fiber')
local json = require('json')
local checks = require('checks')

local ddl = require('ddl')

local module_name = 'migrator'
local vars = require('cartridge.vars').new(module_name)
local migrator_error = require('errors').new_class(module_name)

local utils = require('migrator.utils')
vars:new('loader', require('migrator.directory-loader').new())
vars:new('use_cartridge_ddl', true)


local function get_diff()
    local names = {}
    local migrations_map = {}
    local config = confapplier.get_readonly('migrations') or {}
    config.applied = config.applied or {}
    for _, migration in ipairs(vars.loader:list()) do
        if not utils.value_in(migration.name, config.applied) then
            table.insert(names, migration.name)
            migrations_map[migration.name] = migration
        end
    end
    return names, migrations_map
end

local function init()
    local httpd = cartridge.service_get('httpd')
    httpd:route({ path = '/migrations/up', method = 'POST' }, function(req)
        local target_names = get_diff()

        if #target_names == 0 then
            log.info('No migrations to apply!')
            local resp = req:render({ json = { applied = {} }})
            resp.status = 200
            return resp
        end

        log.info('Migrations to be applied: %s', json.encode(target_names))

        local result = {}
        local fibers = {}
        for _, instance_uri in pairs(rpc.get_candidates('migrator', { leader_only = true })) do
            log.info('Preparing to run migrations on %s', instance_uri)
            local f = fiber.new(function()
                local conn = pool.connect(instance_uri)
                -- migrations might take long time, so net.box timeout should be disabled
                local applied_migrations, err = conn:call('__cluster_rpc_call_local', { 'migrator', 'upgrade' }, {timeout = 3600})
                if err ~= nil then
                    log.warn('Cannot apply migrations on %s: %s', instance_uri, json.encode(err))
                    error(json.encode(err))
                end
                log.verbose('Instance %s applied migrations: %s', instance_uri, json.encode(applied_migrations))
                result[instance_uri] = applied_migrations
                return true
            end)
            f:set_joinable(true)
            f:name(instance_uri, {truncate=true})
            table.insert(fibers, f)
        end

        local errors = {}
        for _, f in pairs(fibers) do
            local ok, join_result = f:join()
            if not ok then table.insert(errors, join_result) end
        end
        if #errors > 0 then
            log.error('Errors happened during migrations, gods help you now: %s', json.encode(errors))
            error(errors[1])
        end

        log.verbose('All fibers joined, results are: %s', json.encode(result))

        for instance_uri, applied in pairs(result) do
            if not utils.compare(applied, target_names) then
                error('Not all migrations applied on %s. Actual list: %s', instance_uri, json.encode(applied))
            end
        end

        local config = confapplier.get_deepcopy('migrations') or {}
        config.applied = config.applied or {}
        for _, name in ipairs(target_names) do
            table.insert(config.applied, name)
        end

        local patch = {
            migrations = config,
            ['schema.yml'] = vars.use_cartridge_ddl and ddl.get_schema() or nil
        }
        log.verbose('All migrations applied successfully, changing cluster-wide configuration with a patch: %s', json.encode(patch))

        local _, err = cartridge.config_patch_clusterwide(patch)
        if err ~= nil then error(err) end
        log.info('Migrations applied successfully!')

        local resp = req:render({ json = { applied = target_names }})
        resp.status = 200
        return resp
    end)
end

local function upgrade()
    local result = {}
    local names, migrations_map = get_diff()
    for _, name in ipairs(names) do
        local _, err = migrator_error:pcall(migrations_map[name].up)
        if err ~= nil then
            log.error('Migration %s not applied: %s', name, err)
            error(err)
        end
        table.insert(result, name)
        log.verbose('Migration %s applied successfully', name)
    end
    return result
end

local function set_loader(loader)
    checks('table')
    assert(type(loader.list) == 'function')
    vars.loader = loader
end

local function set_use_cartridge_ddl(use_cartridge_ddl)
    checks('boolean')
    vars.use_cartridge_ddl = use_cartridge_ddl
end

return {
    init = init,

    permanent = true,

    upgrade = upgrade,

    set_loader = set_loader,
    set_use_cartridge_ddl = set_use_cartridge_ddl
}
