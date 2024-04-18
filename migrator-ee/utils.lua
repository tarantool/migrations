local log = require('log')

local function value_in(val, arr)
    for i, elem in ipairs(arr) do
        if val == elem then
            return true, i
        end
    end
    return false
end

local function compare(a, b)
    if #a ~= #b then return false end
    for i, v in ipairs(a) do
        if b[i] ~= v then return false end
    end
    return true
end


-- TODO: remove this ugly hack
---
--- Set fields that are used for sharding key calculation for a specified space.
---
--- @param space_name string name of sharded space
--- @param key table array of field names that will be used as input of sharding function
---
local function register_sharding_key(space_name, key)

    if value_in('bucket_id', key) then
        log.error("Wrong sharding key: 'bucket_id' is used as input of sharding function for space '"
            .. space_name .. "'")
    end

    if box.space._ddl_sharding_key == nil then
            local sharding_space = box.schema.space.create('_ddl_sharding_key', {
        format = {
            {name = 'space_name', type = 'string', is_nullable = false},
            {name = 'sharding_key', type = 'array', is_nullable = false}
        },
        if_not_exists = true,
    })
    sharding_space:create_index(
        'space_name', {
            type = 'TREE',
            unique = true,
            parts = {{'space_name', 'string', is_nullable = false}},
            if_not_exists = true,
        }
    )
    end
    box.space._ddl_sharding_key:replace{space_name, key}
end


-- Check whether expected cartridge roles are enabled on a server.
--- @param roles_list table array of role names
---
local function check_roles_enabled(roles_list)
    local topology = require('cartridge.confapplier').get_readonly('topology')
    local cur_roles = topology.replicasets[box.info.cluster.uuid].roles

    for _, rname in pairs(roles_list) do
        if cur_roles[rname] == nil then
            return false
        end
    end

    return true
end

return {
    value_in = value_in,
    compare = compare,

    register_sharding_key = register_sharding_key,
    check_roles_enabled = check_roles_enabled,
}
