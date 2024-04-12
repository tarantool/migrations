local t = require('luatest')
local luatest_utils = require('luatest.utils')

local function set_sections(g, sections)
    return g.cluster.main_server:graphql({ query = [[
        mutation($sections: [ConfigSectionInput!]) {
            cluster {
                config(sections: $sections) {
                    filename
                    content
                }
            }
        }]],
        variables = { sections = sections }
    }).data.cluster.config
end

local function cleanup(g)
    local sections = g.cluster.main_server.net_box:eval([[
        return require('fun').iter(
            require('migrator.config-loader').new():list()
        ):map(function(x) return x.name end):totable()
    ]])
    for _, name in pairs(sections) do
        set_sections(g, { { filename = 'migrations/source/' .. name, content = box.NULL } })
    end
    set_sections(g, { { filename = 'schema.yml', content = box.NULL } })

    g.cluster.main_server.net_box:eval([[require('cartridge').config_patch_clusterwide({migrations = {applied = box.NULL }})]])
    local spaces_to_remove = { "first", "sharded" }
    for _, server in ipairs(g.cluster.servers) do
        for _, space in pairs(spaces_to_remove) do
            g.cluster:retrying({ timeout = 10 }, function()
                t.assert(server.net_box:eval([[
                    return (function(space)
                        if box.cfg.read_only then
                            return true
                        end

                        if box.space[space] ~= nil then
                            return box.space[space]:drop() == nil
                        end

                        return true
                    end)(...)
                ]], { space }))
            end)
        end

        -- Cleanup _migrations space.
        g.cluster:retrying({ timeout = 5 }, function()
            t.assert(server:eval([[
                if box.info.ro then
                    return true
                end
                if box.sequence._migrations_id_seq ~= nil then
                    box.sequence._migrations_id_seq:reset()
                    box.sequence._migrations_id_seq:set(0)
                end
                if box.space._migrations ~= nil and box.space._migrations:truncate() ~= nil then
                    return false
                end
                return true
            ]]))
        end)
        g.cluster:retrying({ timeout = 5 }, function()
            t.assert(server:eval([[
                return box.space._migrations:len() == 0
            ]]))
        end)
    end

    -- Reset loader to default.
    for _, server in pairs(g.cluster.servers) do
        server:eval([[require('migrator').set_loader(
            require('migrator.directory-loader').new('test/integration/migrations'))
        ]])
    end

    g.cluster:retrying({ timeout = 1 }, function()
        for _, server in pairs(g.cluster.servers) do
            t.assert(server.net_box:eval('return box.space.first == nil'))
        end
    end)
end

local function parse_module_version(str)
    -- https://github.com/tarantool/luatest/blob/f37b353b77be50a1f1ce87c1ff2edf0c1b96d5d1/luatest/utils.lua#L166-L173
    local splitstr = str:split('.')
    local major = tonumber(splitstr[1]:match('%d+'))
    local minor = tonumber(splitstr[2]:match('%d+'))
    local patch = tonumber(splitstr[3]:match('%d+'))
    return luatest_utils.version(major, minor, patch)
end

local function is_ddl_supports_sequences()
    local ddl = require('ddl')

    if ddl._VERSION == nil then
        return false
    end

    local parsed_ddl_version = parse_module_version(ddl._VERSION)
    local are_sequences_supported = luatest_utils.version_ge(
        parsed_ddl_version,
        luatest_utils.version(1, 7, 0)
    )

    return are_sequences_supported
end

local function downgrade_ddl_schema_if_required(ddl_schema)
    if not is_ddl_supports_sequences then
        for _, space in pairs(ddl_schema.spaces) do
            for _, index in ipairs(space.indexes) do
                index.sequence = nil
            end
        end

        ddl_schema.sequences = nil
    end

    return ddl_schema
end

return {
    set_sections = set_sections,
    cleanup = cleanup,
    downgrade_ddl_schema_if_required = downgrade_ddl_schema_if_required,
}
