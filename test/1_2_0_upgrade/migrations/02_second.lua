return {
    up = function()
        box.space.first:create_index('value', {
            parts = { 'value' },
            unique = false,
            if_not_exists = true,
        })
    end
}
