# Migrations manager for Tarantool Cartridge

@lookup README.md

Migrations module allows you to run cluster-wide migrations for your data.

It stores the list of applied migrations in cluster-wide config and applies resulting schema to cartridge `ddl`.

## Usage

1)  Add `migrations` dependency:
    ```lua
    -- <project-name>-scm-1.rockspec
        dependencies = {
            ...
            'migrations == <the-latest-tag>-1',
            ...
        }
    ```

2) Add `migrator` to the list of cartridge roles in `init.lua`:
    ```lua
    -- init.lua
    ....
    cartridge.cfg({
      roles = {
        'migrator',
        ....
      }
    })
    ```

3) Put migrations code to `./migrations` folder in your app. By default, migrator loads all files from it using lexicographical order.
Every migration (e. g. `0001_create_my_sharded_space_DATETIME.lua`) should expose a single parameter-less function `up`:
    ```lua
    return {
        up = function()
        local utils = require('migrator.utils')
        local f = box.schema.create_space('my_sharded_space', {
            format = {
                { name = 'key', type = 'string' },
                { name = 'bucket_id', type = 'unsigned' },
                { name = 'value', type = 'any', is_nullable = true }
            },
            if_not_exists = true,
        })
        f:create_index('primary', {
            parts = { 'key' },
            if_not_exists = true,
        })
        f:create_index('bucket_id', {
            parts = { 'bucket_id' },
            if_not_exists = true,
            unique = false
        })
        utils.register_sharding_key('my_sharded_space', {'key'})
        return true
        end
    }
    ```

4) Call `curl -X POST http://<your_tarantool_ip>:<http_port>/migrations/up` once you are ready to migrate or connect to any instance of cluster and call `require('migrator').up()`.

5) What will happen then:
    * coordinator node (the one you curled upon) will trigger migrations execution on all replicaset leaders;
    * each replicaset leader will apply all available migrations and reply to coordinator;
    * each replicaset leader stores a list of applied migrations in a space;
    * if all replies are successful, coordinator will apply changes to the resulting cluster ddl-schema.

6) That's it!

## Advanced usage

IMPORTANT: code snippets below should be embedded to `init.lua`, so they would take effect on all nodes of the cluster.

1) Change directory where migrations are located: embed the following to init.lua

    ```lua
    local migrator = require('migrator')
    local my_directory_loader = require('migrator.directory-loader').new('test/integration/migrations')
    migrator.set_loader(my_directory_loader)
    ```

2) ... or use `migrator.config-loader` to load migrations from Tarantool Cartridge clusterwide config.

    Configure `migrator` to use `config-loader`:

    ```lua
    local migrator = require('migrator')
    local config_loader = require('migrator.config-loader').new()
    migrator.set_loader(config_loader)
    ```

    Navigate to Cartridge webui "Code" to write your migrations.
    Migrations must be stored in *.lua files under "migrations/source" key:

    ![config-loader example](doc/assets/config-loader.png)

3) ... or use your own loader - it should expose a single function `list(self)` which returns a similar-looking array:

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

4) Disable `cartridge.ddl` usage:

    ```lua
    migrator.set_use_cartridge_ddl(false)
    ```

    In this case, resulting schema will not be registered via `cartridge_set_schema`

## Utils, helpers, tips and tricks
* Specify a sharding key for `cartridge.ddl` (if you use it) using `utils.register_sharding_key`:
  ```lua
      up = function()
          local utils = require('migrator.utils')
          local f = box.schema.create_space('my_sharded_space', {
              format = {
                  { name = 'key', type = 'string' },
                  { name = 'bucket_id', type = 'unsigned' },
                  { name = 'value', type = 'any', is_nullable = true }
              },
              if_not_exists = true,
          })
          f:create_index('primary', {
              parts = { 'key' },
              if_not_exists = true,
          })
          f:create_index('bucket_id', {
              parts = { 'bucket_id' },
              if_not_exists = true,
              unique = false
          })
          utils.register_sharding_key('my_sharded_space', {'key'})
          return true
      end
  ```
  Warning! It's not correct to specify 'bucket_id' as a 'key' parameter for register_sharding_key().
  The 'bucket_id' field is a place where the output of sharding function is saved to.

* Before 0.6.0, each storage migration run time was limited to 3600 seconds (#66).
  If your migrations run longer than this limit, it will result in timeout error.

  Starting with 0.6.0, you may configure this value with clusterwide config to
  allow longer migrations. Default is 3600 seconds.
  ```yaml
  migrations:
    options:
      storage_timeout: 43200 # in seconds
  ```

* By default, modifying already applied migrations is not permitted.
    The module will throw an error: "Modifying already applied migrations is not allowed. To enable changes, set the is_applied_migrations_writable option. Keep in mind that already applied migrations will not be reapplied.
    If you wish to make changes, add new migrations."

    However, if you still need to make changes in applied migrations, you can use the `options.is_applied_migrations_writable`
    flag by setting it to `true` (by default `false`).
  ```yaml
  migrations:
    options:
      is_applied_migrations_writable: true
  ```

* **To "correct" the effects of incorrect migrations, write new ones. Modifying old migrations will not help.**

* To run migrations code on a specific roles use `utils.check_roles_enabled`:
    ```lua
        up = function()
            local utils = require('migrator.utils')
            if utils.check_roles_enabled({'vshard-storage'}) then
                local f = box.schema.create_space('my_sharded_space', {
                    format = {
                        { name = 'key', type = 'string' },
                        { name = 'bucket_id', type = 'unsigned' },
                        { name = 'value', type = 'any', is_nullable = true }
                    },
                    if_not_exists = true,
                })
                f:create_index('primary', {
                    parts = { 'key' },
                    if_not_exists = true,
                })
                f:create_index('bucket_id', {
                    parts = { 'bucket_id' },
                    if_not_exists = true,
                    unique = false
                })
                utils.register_sharding_key('my_sharded_space', {'key'})
                return true
            elseif utils.check_roles_enabled({'my-role'}) then
                my_specific_role_logic()
            end
        end
    ```

* To get a list of applied migrations make a GET request to
  `http://<your_tarantool_ip>:<http_port>/migrations/applied` or call
  `require('migrator').get_applied()` on any cluster instance. This method will return a list of
  applied migrations grouped by a leader node.

## Upgrade from 0.* versions.

Applied migrations names storage method has been changed in `1.*` version: applied migrations list
is stored on each cluster node separately in `_migrations` space. An additional step is required
before applying migrations after update from `0.*`: call
`curl -X POST http://<your_tarantool_ip>:<http_port>/migrations/move_migrations_state` or connect
to any instance of cluster and call `require('migrator').move_migrations_state()`. This method
does the following:

- copies applied migrations names from cluster-wide configuration to the `_migrations` space on
  leader nodes.
- if copying is succeeded on all leaders, removes the list from the cluster-wide configuration.

## Rolling back to 0.* versions.

To perform a downgrade from `1.*` to `0.*` version do the following:

- get a list of the applied migrations using the `get_applied` API.
- set list of migrations in cluster-wide config:
```yaml
    migrations:
      applied:
      - 01_migration.lua
      - 02_migration.lua
      . . .
```
- remove `_migrations` space and `_migrations_id_seq` on all nodes if necessary.
- perform downgrade of the `migrations`.

## Limitations
- all migrations will be run on all cluster nodes (no partial migrations);
- no pre-validation for migrations code (yet), so you should test them beforehands;
- no support to run a single migration (yet);
- no dry-run (yet);
- no rolling back unsuccessful migrations (yet);
- no migrating `down` (yet).
