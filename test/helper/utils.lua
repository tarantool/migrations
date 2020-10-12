local t = require('luatest')

local function set_sections(g, sections)
    return g.cluster.main_server:graphql({query = [[
        mutation($sections: [ConfigSectionInput!]) {
            cluster {
                config(sections: $sections) {
                    filename
                    content
                }
            }
        }]],
        variables = {sections = sections}
    }).data.cluster.config
end

local function cleanup(g)
    set_sections(g, {{filename = 'migrations', content = nil}})

    local spaces_to_remove = {"first", "sharded"}
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
                ]], {space}))
            end)
        end
    end
end

return {
    set_sections = set_sections,
    cleanup = cleanup,
}
