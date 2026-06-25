local t = require('luatest')
local g = t.group('sharding_utils_unit')

local utils = require('migrator.utils')

g.after_each(function()
    if box.space._ddl_sharding_key ~= nil then
        box.space._ddl_sharding_key:drop()
    end
    if box.space._ddl_sharding_func ~= nil then
        box.space._ddl_sharding_func:drop()
    end
    if box.space.sample ~= nil then
        box.space.sample:drop()
    end
end)

local function create_sample_space()
    box.schema.space.create('sample', {
        format = { { name = 'id', type = 'unsigned' } },
    })
    box.space.sample:create_index('primary', { parts = { 'id' } })
end

-- register_sharding_key

g.test_register_sharding_key_creates_ddl_space = function()
    t.assert_equals(box.space._ddl_sharding_key, nil)
    utils.register_sharding_key('myspace', { 'key' })

    local sp = box.space._ddl_sharding_key
    t.assert_not_equals(sp, nil)

    local fmt = sp:format()
    t.assert_equals(fmt[1].name, 'space_name')
    t.assert_equals(fmt[1].type, 'string')
    t.assert_equals(fmt[1].is_nullable, false)
    t.assert_equals(fmt[2].name, 'sharding_key')
    t.assert_equals(fmt[2].type, 'array')
    t.assert_equals(fmt[2].is_nullable, false)

    local idx = sp.index.space_name
    t.assert_not_equals(idx, nil)
    t.assert_equals(idx.type, 'TREE')
    t.assert_equals(idx.unique, true)
end

g.test_register_sharding_key_stores_key = function()
    utils.register_sharding_key('myspace', { 'field_a', 'field_b' })

    local row = box.space._ddl_sharding_key:get('myspace')
    t.assert_not_equals(row, nil)
    t.assert_equals(row.space_name, 'myspace')
    t.assert_equals(row.sharding_key, { 'field_a', 'field_b' })
end

g.test_register_sharding_key_replaces_existing = function()
    utils.register_sharding_key('myspace', { 'old' })
    utils.register_sharding_key('myspace', { 'new' })

    t.assert_equals(box.space._ddl_sharding_key:count(), 1)
    local row = box.space._ddl_sharding_key:get('myspace')
    t.assert_equals(row.sharding_key, { 'new' })
end

g.test_register_sharding_key_multiple_spaces = function()
    utils.register_sharding_key('space1', { 'k1' })
    utils.register_sharding_key('space2', { 'k2' })

    t.assert_equals(box.space._ddl_sharding_key:count(), 2)
    t.assert_equals(box.space._ddl_sharding_key:get('space1').sharding_key, { 'k1' })
    t.assert_equals(box.space._ddl_sharding_key:get('space2').sharding_key, { 'k2' })
end

g.test_register_sharding_key_bucket_id_still_registers = function()
    utils.register_sharding_key('myspace', { 'bucket_id' })

    local row = box.space._ddl_sharding_key:get('myspace')
    t.assert_not_equals(row, nil)
    t.assert_equals(row.sharding_key, { 'bucket_id' })
end

g.test_register_sharding_key_space_preexists = function()
    box.schema.space.create('_ddl_sharding_key', {
        format = {
            { name = 'space_name', type = 'string', is_nullable = false },
            { name = 'sharding_key', type = 'array', is_nullable = false },
        },
        if_not_exists = true,
    })
    box.space._ddl_sharding_key:create_index('space_name', {
        type = 'TREE',
        unique = true,
        parts = { { 'space_name', 'string', is_nullable = false } },
        if_not_exists = true,
    })

    utils.register_sharding_key('myspace', { 'key' })

    local row = box.space._ddl_sharding_key:get('myspace')
    t.assert_not_equals(row, nil)
    t.assert_equals(row.sharding_key, { 'key' })
end

-- drop_sharding_key

g.test_drop_sharding_key_deletes_row = function()
    utils.register_sharding_key('myspace', { 'key' })
    t.assert_not_equals(box.space._ddl_sharding_key:get('myspace'), nil)

    utils.drop_sharding_key('myspace')

    t.assert_equals(box.space._ddl_sharding_key:get('myspace'), nil)
end

g.test_drop_sharding_key_noop_when_ddl_space_absent = function()
    t.assert_equals(box.space._ddl_sharding_key, nil)
    utils.drop_sharding_key('whatever')
    t.assert_equals(box.space._ddl_sharding_key, nil)
end

g.test_drop_sharding_key_still_deletes_when_space_exists = function()
    create_sample_space()
    utils.register_sharding_key('sample', { 'id' })

    utils.drop_sharding_key('sample')

    t.assert_equals(box.space._ddl_sharding_key:get('sample'), nil)
end

g.test_drop_sharding_key_unknown_name_is_noop = function()
    utils.register_sharding_key('real', { 'key' })
    utils.drop_sharding_key('nonexistent')

    t.assert_not_equals(box.space._ddl_sharding_key:get('real'), nil)
end

-- register_sharding_func

g.test_register_sharding_func_creates_ddl_space = function()
    t.assert_equals(box.space._ddl_sharding_func, nil)
    utils.register_sharding_func('myspace', 'myfunc', nil)

    local sp = box.space._ddl_sharding_func
    t.assert_not_equals(sp, nil)

    local fmt = sp:format()
    t.assert_equals(fmt[1].name, 'space_name')
    t.assert_equals(fmt[1].type, 'string')
    t.assert_equals(fmt[1].is_nullable, false)
    t.assert_equals(fmt[2].name, 'sharding_func_name')
    t.assert_equals(fmt[2].type, 'string')
    t.assert_equals(fmt[2].is_nullable, true)
    t.assert_equals(fmt[3].name, 'sharding_func_body')
    t.assert_equals(fmt[3].type, 'string')
    t.assert_equals(fmt[3].is_nullable, true)

    local idx = sp.index.space_name
    t.assert_not_equals(idx, nil)
    t.assert_equals(idx.type, 'TREE')
    t.assert_equals(idx.unique, true)
end

g.test_register_sharding_func_by_name = function()
    utils.register_sharding_func('myspace', 'myfunc', nil)

    local row = box.space._ddl_sharding_func:get('myspace')
    t.assert_not_equals(row, nil)
    t.assert_equals(row.space_name, 'myspace')
    t.assert_equals(row.sharding_func_name, 'myfunc')
    t.assert_equals(row.sharding_func_body, nil)
end

g.test_register_sharding_func_by_body = function()
    utils.register_sharding_func('myspace', nil, 'function(key) return 1 end')

    local row = box.space._ddl_sharding_func:get('myspace')
    t.assert_not_equals(row, nil)
    t.assert_equals(row.sharding_func_name, nil)
    t.assert_equals(row.sharding_func_body, 'function(key) return 1 end')
end

g.test_register_sharding_func_both_name_and_body = function()
    utils.register_sharding_func('myspace', 'myfunc', 'return 1')

    local row = box.space._ddl_sharding_func:get('myspace')
    t.assert_equals(row.sharding_func_name, 'myfunc')
    t.assert_equals(row.sharding_func_body, 'return 1')
end

g.test_register_sharding_func_replaces_existing = function()
    utils.register_sharding_func('myspace', 'f1', nil)
    utils.register_sharding_func('myspace', 'f2', 'return 2')

    t.assert_equals(box.space._ddl_sharding_func:count(), 1)
    local row = box.space._ddl_sharding_func:get('myspace')
    t.assert_equals(row.sharding_func_name, 'f2')
    t.assert_equals(row.sharding_func_body, 'return 2')
end

g.test_register_sharding_func_multiple_spaces = function()
    utils.register_sharding_func('space1', 'f1', nil)
    utils.register_sharding_func('space2', nil, 'return 2')

    t.assert_equals(box.space._ddl_sharding_func:count(), 2)
    t.assert_equals(box.space._ddl_sharding_func:get('space1').sharding_func_name, 'f1')
    t.assert_equals(box.space._ddl_sharding_func:get('space2').sharding_func_body, 'return 2')
end

-- drop_sharding_func

g.test_drop_sharding_func_deletes_row = function()
    utils.register_sharding_func('myspace', 'myfunc', nil)
    t.assert_not_equals(box.space._ddl_sharding_func:get('myspace'), nil)

    utils.drop_sharding_func('myspace')

    t.assert_equals(box.space._ddl_sharding_func:get('myspace'), nil)
end

g.test_drop_sharding_func_noop_when_ddl_space_absent = function()
    t.assert_equals(box.space._ddl_sharding_func, nil)
    utils.drop_sharding_func('whatever')
    t.assert_equals(box.space._ddl_sharding_func, nil)
end

g.test_drop_sharding_func_still_deletes_when_space_exists = function()
    create_sample_space()
    utils.register_sharding_func('sample', 'myfunc', nil)

    utils.drop_sharding_func('sample')

    t.assert_equals(box.space._ddl_sharding_func:get('sample'), nil)
end

g.test_drop_sharding_func_unknown_name_is_noop = function()
    utils.register_sharding_func('real', 'f1', nil)
    utils.drop_sharding_func('nonexistent')

    t.assert_not_equals(box.space._ddl_sharding_func:get('real'), nil)
end
