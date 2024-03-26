local rpc = require('cartridge.rpc')
local pool = require('cartridge.pool')
local cartridge = require('cartridge')
local confapplier = require('cartridge.confapplier')
local get_topology_api = require('cartridge.lua-api.get-topology')

local log = require('log')
local fiber = require('fiber')
local json = require('json')
local checks = require('checks')
local fun = require('fun')

local ddl = require('ddl')

local module_name = 'migrator'
local vars = require('cartridge.vars').new(module_name)
local migrator_error = require('errors').new_class(module_name)

local utils = require('migrator.utils')
vars:new('loader', require('migrator.directory-loader').new())
vars:new('use_cartridge_ddl', true)


local function get_diff(applied)
    local to_apply = {}
    local migrations_map = {}
    for _, migration in ipairs(vars.loader:list()) do
        if utils.value_in(migration.name, applied) then
            log.verbose('%s migration is already applied', migration.name)
        else
            table.insert(to_apply, migration.name)
            migrations_map[migration.name] = migration
        end
    end
    return to_apply, migrations_map
end

local function get_schema()
    return ddl.get_schema()
end

-- since migrations might be triggered on a replica, we should fetch ddl schema from actual master
-- see https://github.com/tarantool/migrations/issues/56 for details
local function fetch_schema()
    if vars.use_cartridge_ddl ~= true then return nil end
    local schema, err = rpc.call('migrator', 'get_schema', nil, {prefer_local = true, leader_only = true})
        if err ~= nil then
        log.error(err)
        error(err)
    end
    return schema
end

local DEFAULT_STORAGE_TIMEOUT = 3600

local function get_storage_timeout()
    local config = confapplier.get_readonly('migrations') or {}
    local options = config['options'] or {}
    if options.storage_timeout ~= nil then
        return options.storage_timeout
    end
    return DEFAULT_STORAGE_TIMEOUT
end

-- Makes sure that the passed migrations match the list from the local reader.
local function check_migrations_consistency(migrations_per_instance)
    local names = fun.iter(vars.loader:list()):map(function(m) return m.name end):totable()
    for host, applied in pairs(migrations_per_instance) do
        if utils.compare(names, applied) == false then
            local err_msg = string.format('Inconsistent migrations in cluster: ' ..
            'expected: %s, applied on %s: %s', json.encode(names), host, json.encode(applied))
            log.error(err_msg)
            error(err_msg)
        end
    end
end

-- Makes sure there is no migrations list in cluster config.
local function check_no_migrations_in_config()
    local config = confapplier.get_readonly('migrations')
    if config ~= nil and config.applied ~= nil and #config.applied > 0 then
        error('Cannot perform an upgrade. A list of applied migrations is found in cluster ' ..
            'config. Current migrator version works only with local list of applied migrations. ' ..
            'Run "move_migrations_state" to move cluster-wide migrations state to local ' ..
            'storage before up invocation.')
    end
end

-- Returns server alias by URI.
local function get_server_alias(instance_uri)
    local servers = get_topology_api.get_servers(function(server)
        return server.uri == instance_uri
    end)
    if not servers or #servers == 0 or #servers > 1 or not servers[1].alias then
        return instance_uri
    end
    return servers[1].alias
end

--- Run migrations on all nodes in the cluster
-- Throws an exception in case of any problems
-- @function up
-- @return table of applied migration names grouped by host, e. g. {
    -- [router] = {"01_first.lua", "02_second.lua", "03_sharded.lua"}
    -- [s1-master] = {"03_sharded.lua"}
-- }
-- If no migrations applied, the table is empty.
local function up()
    check_no_migrations_in_config()

    local result = {}
    local all_migrations = {}
    local fibers = {}
    for _, instance_uri in pairs(rpc.get_candidates('migrator', { leader_only = true })) do
        log.info('Preparing to run migrations on %s', instance_uri)
        local f = fiber.new(function()
            local conn = pool.connect(instance_uri)
            local applied_migrations, err = conn:call(
                '__cluster_rpc_call_local',
                { 'migrator', 'upgrade' },
                {timeout = get_storage_timeout()})
            if err ~= nil then
                log.warn('Cannot apply migrations on %s: %s', instance_uri, json.encode(err))
                error(json.encode(err))
            end
            local server_alias = get_server_alias(instance_uri)
            log.verbose('Instance %s applied migrations: %s',
                server_alias, json.encode(applied_migrations.applied_now))
            if #applied_migrations.applied_now > 0 then
                result[server_alias] = applied_migrations.applied_now
            end
            all_migrations[instance_uri] = applied_migrations.applied
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
        local err_msg = string.format('Errors happened during migrations: %s', json.encode(errors))
        log.error(err_msg)
        error(err_msg)
    end

    log.verbose('All fibers joined, results are: %s', json.encode(result))
    check_migrations_consistency(all_migrations)

    local patch = {
        ['schema.yml'] = fetch_schema()
    }
    log.info('Migrations applied on all storages, changing clusterwide configuration...')
    log.verbose('All migrations applied successfully, changing cluster-wide configuration with a patch: %s', json.encode(patch))

    local _, err = cartridge.config_patch_clusterwide(patch)
    if err ~= nil then
        log.error(err)
        error(err)
    end
    log.info('Migrations applied successfully!')

    return result
end

--- Get list of applied migration names on local server.
-- @function get_applied_local
-- @return table of applied migration names on local server.
local function get_applied_local()
    local result = {}
    local counter = 0
    for _, migration in box.space._migrations:pairs() do
        table.insert(result, migration['name'])
        counter = counter + 1
        if counter >= 1000 then
            fiber.yield()
            counter = 0
        end
    end
    return result
end

local function init(opts)
    -- Create space for storing applied migrations.
    if opts.is_master then
        box.schema.sequence.create('_migrations_id_seq', { if_not_exists = true })
        box.schema.create_space('_migrations', {
            format = {
                {'id', type='unsigned', is_nullable=false},
                {'name', type='string', is_nullable=false},
            },
            if_not_exists = true,
        })
        box.space._migrations:create_index('primary', {
            sequence = '_migrations_id_seq',
            if_not_exists = true,
        })
        -- Workaround for https://github.com/tarantool/ddl/issues/122
        -- If index is created by ddl, sequence is not set. Check and update is required.
        if box.space._migrations.index.primary ~= nil
        and box.space._migrations.index.primary.sequence_id == nil then
            box.space._migrations.index.primary:alter({sequence = '_migrations_id_seq'})
        end
    end

    local httpd = cartridge.service_get('httpd')
    if not httpd then return true end

    httpd:route({ path = '/migrations/up', method = 'POST' }, function(req)
        local resp = req:render({ json = { applied = up() }})
        resp.status = 200
        return resp
    end)
end

local function upgrade()
    check_no_migrations_in_config()

    local migrations = {applied_now = {}, applied = get_applied_local()}
    local to_apply, migrations_map = get_diff(migrations.applied)
    for _, name in ipairs(to_apply) do
        local _, err = migrator_error:pcall(migrations_map[name].up)
        if err ~= nil then
            log.error('Migration %s not applied: %s', name, err)
            error(err)
        end
        box.space._migrations:insert{box.NULL, name}
        table.insert(migrations.applied_now, name)
        table.insert(migrations.applied, name)
        log.verbose('Migration %s applied successfully', name)
    end
    return migrations
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

local function validate_config(conf_new)
    local migrations_conf = conf_new['migrations'] or {}
    local options = migrations_conf['options'] or {}

    if options.storage_timeout ~= nil then
        assert(
            type(options.storage_timeout) == 'number',
            ("'options.storage_timeout' must be a number, %s provided"):format(type(options.storage_timeout)))
        assert(
            options.storage_timeout >= 0,
            "'options.storage_timeout' must be a non-negative number")
    end

    return true
end

return {
    init = init,

    validate_config = validate_config,

    permanent = true,

    upgrade = upgrade,
    up = up,

    set_loader = set_loader,
    set_use_cartridge_ddl = set_use_cartridge_ddl,

    get_schema = get_schema,

    _VERSION = require('migrator.version'),
}
