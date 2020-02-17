# Migrations manager for Tarantool Cartridge

@lookup README.md

Migrations module allows you to run cluster-wide migrations for your data.

It stores the list of applied migraions in cluster-wide config and applies resulting schema to cartridge `ddl`. 

## Usage

1) Add `migrator` to you list of cartridge roles:
```lua
...
...
cartridge.cfg({
   roles = {'migrator', ...}
})
```

2) By default, it will try to load migrations from `./migrations` directory from your app, using lexicographical order.
Every migration should expose a single parameter-less function `up`:
```lua
return {
    up = function()
        box.schema.create_space('test')    
    end
}
```

3) Once you are ready to migrate your data - call `curl -X POST http://your_tarantool:port/migrations/up`

4) That's it!

## Advanced usage

1) Change directory where migrations are located: embed the following to init.lua
```lua
local migrator = require('migrator')
local my_directory_loader = require('migrator.directory-loader').new('test/integration/migrations') 
migrator.set_loader(my_directory_loader)
```

2) ... or use your own loader - it should expose a single function `list(self)` which returns a similar-looking array:
```lua
local my_loader = {
    list = function(_)
        return {
            {
                name  = '01_first',
                up = function() ... end
            },
        }
    end
}
migrator.set_loader(my_loader)
```

## Limitations
- All migrations will be run on all cluster nodes, and migrator expects that resulting schema is the same on all nodes.
- Migrations are not pre-validated, so you should test them beforehands
- Running a single migration is not supported at the moment
- Dry-run is not supported at the moment
- Rolling back unsuccessful migrations is not supported at the moment
- Migrating `down` is not supported at the moment
