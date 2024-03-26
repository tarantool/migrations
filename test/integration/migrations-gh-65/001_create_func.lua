return {
    up = function()
        box.schema.func.create('sum', {
            body = [[ function(a, b) return a + b end ]]
        })
        return true
    end
}
