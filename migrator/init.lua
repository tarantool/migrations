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
local changing_applied_migrations = require('migrator.changing-applied-migrations')

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

local function create_space_for_storing_applied_migrations()
    box.schema.sequence.create('_migrations_id_seq', { if_not_exists = true })
    box.schema.create_space('_migrations', {
        if_not_exists = true,
    })

    box.space._migrations:format({
        {'id', type='unsigned', is_nullable=false},
        {'name', type='string', is_nullable=false},
        {'hash', type='string', is_nullable=true},
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

    box.atomic(changing_applied_migrations.create_hashes_for_migrations)
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

--- Get list of applied migration names in cluster.
-- Throws an exception in case of any problems
-- @function get_applied
-- @return table of applied migrations in cluster grouped by leader aliases.
local function get_applied()
    local leaders = rpc.get_candidates('migrator',{ leader_only = true })
    log.info('Preparing getting applied migrations from %s', json.encode(leaders))
    local result, errmap = pool.map_call('_G.__cluster_rpc_call_local',
        {'migrator', 'get_applied_local'}, {
            uri_list = leaders,
            timeout = get_storage_timeout(),
        })
    if errmap ~= nil then
        for uri, err in pairs(errmap) do
            log.error('Cannot get migrations state from %s: %s',
                uri, json.encode(err))
        end
        error("Failed to get migrations state: " .. json.encode(errmap))
    end

    local migrations_by_alias = {}
    for uri, migrations in pairs(result) do
        migrations_by_alias[get_server_alias(uri)] = migrations
    end

    return migrations_by_alias
end

-- Append migration names to the _migrations space.
local function append_migrations_to_local_space(migrations)
    local copied_migrations = {}
    local local_migrations = get_applied_local()
    local hashes_by_name = vars.loader:hashes_by_name()
    for i, migration in ipairs(migrations) do
        if i <= #local_migrations then
            if local_migrations[i] ~= migration then
                local err_msg = string.format('Inconsistency between cluster-wide and local ' ..
                'applied migrations list: migration #%d in config: %s, in local space: %s',
                    i, migration, local_migrations[i])
                log.error(err_msg)
                error(err_msg)
            end
        else
            box.space._migrations:insert{box.NULL, migration, hashes_by_name[migration]}
            table.insert(copied_migrations, migration)
        end
    end
    log.info("Migration names copied: %s", json.encode(copied_migrations))
    return copied_migrations
end

--- Run applied migrations list copying from from cluster-wide config to local space on each storage.
-- Throws an exception in case of any problems
-- @function move_migrations_state
-- @return table of instance uris with migration names copied.
local function move_migrations_state(current_server_only)
    local config = confapplier.get_readonly('migrations')

    if config == nil or config.applied == nil or #config.applied == 0 then
        log.info('There are no applied migrations in cluster config. Skip moving state.')
        return {}
    end

    if current_server_only then
        return append_migrations_to_local_space(config.applied)
    end

    -- Copy state on all leaders.
    local leaders = rpc.get_candidates('migrator',{leader_only = true })
    log.info('Preparing copying migrations on %s', json.encode(leaders))
    local result, errmap = pool.map_call('_G.__cluster_rpc_call_local',
        {'migrator', 'move_migrations_state', {true}}, {
            uri_list = leaders,
            timeout = get_storage_timeout(),
        })
    if errmap ~= nil then
        for uri, err in pairs(errmap) do
            log.error('Failed to copy migrations state from cluster config on %s: %s',
                uri, json.encode(err))
        end
        error("Failed to copy migrations state: " .. json.encode(errmap))
    end

    -- Remove applied migrations from cluster-wide configuration.
    local patch = {
        ['migrations'] = {
            ['applied'] = box.NULL
        }
    }
    log.info('Migrations are copied on all storages, removing them from clusterwide configuration...')
    log.verbose('Changing cluster-wide configuration with a patch: %s', json.encode(patch))

    local _, err = cartridge.config_patch_clusterwide(patch)
    if err ~= nil then
        log.error(err)
        error(err)
    end
    log.info('Applied migrations are moved successfully: %s', json.encode(leaders))

    local migrations_by_alias = {}
    for uri, migrations in pairs(result) do
        migrations_by_alias[get_server_alias(uri)] = migrations
    end

    return migrations_by_alias
end

local function init()
    local httpd = cartridge.service_get('httpd')
    if not httpd then return true end

    httpd:route({ path = '/migrations/up', method = 'POST' }, function(req)
        local resp = req:render({ json = { applied = up() }})
        resp.status = 200
        return resp
    end)

    httpd:route({ path = '/migrations/move_migrations_state', method = 'POST' }, function(req)
        local resp = req:render({ json = { migrations_moved = move_migrations_state() }})
        resp.status = 200
        return resp
    end)

    httpd:route({ path = '/migrations/applied', method = 'GET' }, function(req)
        local resp = req:render({ json = { applied = get_applied() }})
        resp.status = 200
        return resp
    end)
end

local function upgrade()
    check_no_migrations_in_config()
    changing_applied_migrations.check_applied_migrations_not_changed()

    local migrations = {applied_now = {}, applied = get_applied_local()}
    local to_apply, migrations_map = get_diff(migrations.applied)
    local hashes_by_name = vars.loader:hashes_by_name()
    for _, name in ipairs(to_apply) do
        local _, err = migrator_error:pcall(migrations_map[name].up)
        if err ~= nil then
            log.error('Migration %s not applied: %s', name, err)
            error(err)
        end
        box.space._migrations:insert{box.NULL, name, hashes_by_name[name]}
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

    if options.is_applied_migrations_writable ~= nil then
        assert(
            type(options.is_applied_migrations_writable) == 'boolean',
            ("'options.is_applied_migrations_writable' must be a boolean, %s provided"):format(type(options.is_applied_migrations_writable))
        )
    end

    -- box.cfg was not called yet
    if type(box.cfg) == 'table' then
        changing_applied_migrations.check_applied_migrations_not_changed(conf_new)
    end
    return true
end

local function should_update_hashes(conf_new, conf_old)
    -- if is_applied_migrations_writable changes from true to false we should update_applied_migrations_hashes
    -- it will allow to pass check_applied_migrations_not_changed, if user changed them.
    local new_is_writable = ((conf_new['migrations'] or {}).options or {}).is_applied_migrations_writable
    local old_is_writable =
        ((conf_old['migrations'] or {}).options or {}).is_applied_migrations_writable or
        changing_applied_migrations.DEFAULT_IS_APPLIED_MIGRATIONS_WRITABLE

    if new_is_writable == false and old_is_writable == true then
        return true
    end
    return false
end

local function apply_config(conf_new, conf_old)
    if not box.info().ro then
        create_space_for_storing_applied_migrations()
    end

    if should_update_hashes(conf_new, conf_old) then
        changing_applied_migrations.update_applied_migrations_hashes()
        log.info("Update hashes for applied migrations")
    end

    return true
end

return {
    init = init,

    validate_config = validate_config,
    apply_config = apply_config,

    permanent = true,

    upgrade = upgrade,
    up = up,

    set_loader = set_loader,
    set_use_cartridge_ddl = set_use_cartridge_ddl,

    get_schema = get_schema,

    move_migrations_state = move_migrations_state,
    get_applied = get_applied,
    get_applied_local = get_applied_local,

    _VERSION = require('migrator.version'),
}
