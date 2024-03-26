local t = require('luatest')

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

return {
    set_sections = set_sections,
    cleanup = cleanup,
}
