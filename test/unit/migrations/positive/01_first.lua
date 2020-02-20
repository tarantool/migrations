return {
    up = function()
        local f = box.schema.create_space('first', {
            format = {
                { name = 'key', type = 'string' },
                { name = 'value', type = 'string', is_nullable = true }
            },
            if_not_exists = true,
        })
        f:create_index('primary', {
            parts = { 'key' },
            if_not_exists = true,
        })
        return true
    end
}
