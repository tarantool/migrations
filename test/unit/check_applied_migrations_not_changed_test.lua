local t = require('luatest')
local changing_applied_migrations = require('migrator.changing-applied-migrations')
local vars = require('cartridge.vars').new('migrator')


local function create_migration_space_1_3_0()
    -- after release 1_3_0 added field 'hash' in _migrations space
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

    if box.space._migrations.index.primary ~= nil
    and box.space._migrations.index.primary.sequence_id == nil then
        box.space._migrations.index.primary:alter({sequence = '_migrations_id_seq'})
    end
end

local function create_migration_space_1_2_0()
    -- before release 1_3_0 there were only id and name fields
    box.schema.sequence.create('_migrations_id_seq', { if_not_exists = true })
    box.schema.create_space('_migrations', {
        if_not_exists = true,
    })

    box.space._migrations:format({
        {'id', type='unsigned', is_nullable=false},
        {'name', type='string', is_nullable=false},
    })

    box.space._migrations:create_index('primary', {
        sequence = '_migrations_id_seq',
        if_not_exists = true,
    })

    if box.space._migrations.index.primary ~= nil
    and box.space._migrations.index.primary.sequence_id == nil then
        box.space._migrations.index.primary:alter({sequence = '_migrations_id_seq'})
    end
end

local g = t.group()

g.before_all(function()
    vars.loader = {
        hashes_by_name = function()
            return {
                ["001.lua"] = 'HASH',
            }
        end
    }
end)

g.after_all(function()
    vars.loader = nil
end)

g.after_each(function()
    if box.space._migrations ~= nil then
        box.space._migrations:drop()
    end
end)

g.test_empty_ok_1_2_0 = function()
    create_migration_space_1_2_0()
    changing_applied_migrations.check_applied_migrations_not_changed()
end

g.test_empty_ok_1_3_0 = function()
    create_migration_space_1_3_0()
    changing_applied_migrations.check_applied_migrations_not_changed()
end

g.test_error = function()
    create_migration_space_1_3_0()
    box.space._migrations:replace({
        1, '001.lua', 'NOT EQUAL HASH'
    })
    t.assert_error_msg_contains(
        'Modifying already applied migrations is not allowed',
        changing_applied_migrations.check_applied_migrations_not_changed
    )
end

g.test_ok_no_hash_field = function()
    create_migration_space_1_2_0()
    box.space._migrations:replace({
        1, '001.lua'
    })
    changing_applied_migrations.check_applied_migrations_not_changed()
end

g.test_skip_is_applied_migrations_writable = function()
    create_migration_space_1_3_0()
    box.space._migrations:replace({
        1, '001.lua', 'NOT EQUAL HASH'
    })

    local orig = changing_applied_migrations.__is_applied_migrations_writable
    changing_applied_migrations.__is_applied_migrations_writable = function ()
        return true
    end
    changing_applied_migrations.check_applied_migrations_not_changed()
    changing_applied_migrations.__is_applied_migrations_writable = orig
end
