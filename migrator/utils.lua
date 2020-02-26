
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
local function register_sharding_key(space_name, key)
    if box.space._ddl_sharding_key == nil then
            local sharding_space = box.schema.space.create('_ddl_sharding_key', {
        format = {
            {name = 'space_name', type = 'string', is_nullable = false},
            {name = 'sharding_key', type = 'array', is_nullable = false}
        },
        if_not_exists = true
    })
    sharding_space:create_index(
        'space_name', {
            type = 'TREE',
            unique = true,
            parts = {{'space_name', 'string', is_nullable = false}},
            if_not_exists = true
        }
    )
    end
    box.space._ddl_sharding_key:replace{space_name, key}
end

return {
    value_in = value_in,
    compare = compare,

    register_sharding_key = register_sharding_key
}
