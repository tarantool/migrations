-- This module is used to verify that the user does not modify the code of already applied migrations.
-- To detect changes in the migration code, an MD5 hash of the migration code is used.

local log = require('log')
local confapplier = require('cartridge.confapplier')

local M = {}

M.DEFAULT_IS_APPLIED_MIGRATIONS_WRITABLE = false

function M.__is_applied_migrations_writable()
    local config = confapplier.get_readonly('migrations') or {}
    local options = config['options'] or {}
    return options.is_applied_migrations_writable or M.DEFAULT_IS_APPLIED_MIGRATIONS_WRITABLE
end

local function is_applied_migration_code_changed(applied_hash, current_hash)
    -- Ideally, there should never be a 'nil', but if it occurs, it's better to ignore it.
    -- This is mainly for user's convenience and shouldn't critically affect anything else.
    if current_hash == nil then
        return false
    end
    return applied_hash ~= current_hash
end

local function check_migrations(current_hashes_by_name)
    for _, migration in box.space._migrations:pairs() do
        local current_hash = current_hashes_by_name[migration.name]
        if is_applied_migration_code_changed(migration.hash, current_hash) then
            log.error(
                "Hashes mismatch for applied migration %s, applied %s, current %s",
                migration.name,
                migration.hash,
                current_hash
            )
            error(
                "Modifying already applied migrations is not allowed. " ..
                "To enable changes, set the is_applied_migrations_writable option. " ..
                "Keep in mind that already applied migrations will not be reapplied. " ..
                "If you wish to make changes, add new migrations."
            )
        end
    end
end

function M.is_migration_space_has_hash_field()
    return #box.space._migrations:format() > 2
end

function M.check_applied_migrations_not_changed(conf_new)
    local vars = require('cartridge.vars').new('migrator')
    local current_hashes_by_name = vars.loader:hashes_by_name(conf_new)
    if (not M.__is_applied_migrations_writable()) and M.is_migration_space_has_hash_field() then
        check_migrations(current_hashes_by_name)
    end
end

-- we may not have 'hash' field in format, so have to access by number
local hash_filed_num = 3
function M.update_applied_migrations_hashes()
    local vars = require('cartridge.vars').new('migrator')
    local hashes_by_name = vars.loader:hashes_by_name()

    for _, t in box.space._migrations:pairs() do
        -- Ideally, there should never be a nil, but if it occurs, it's better to ignore it.
        -- This is mainly for user's convenience and shouldn't critically affect anything else.
        if hashes_by_name[t.name] == nil then
            log.error(
                "Failed to get hash for migration %s. Check migrations source code. They might be inconsistent.",
                t.name
            )
        else
            if t[hash_filed_num] ~= box.NULL then
                log.info("Update hash for migration %s from %s to %s", t.name, t[hash_filed_num], hashes_by_name[t.name])
            else
                log.info("Create hash for migration %s:%s", t.name, hashes_by_name[t.name])
            end
            box.space._migrations:update(t.id,{{'=', hash_filed_num,  hashes_by_name[t.name]}})
        end
    end
end

function M.create_hashes_for_migrations()
    local vars = require('cartridge.vars').new('migrator')
    local hashes_by_name = vars.loader:hashes_by_name()
    for _, t in box.space._migrations:pairs() do
        -- create only is was not set
        if t[hash_filed_num] == box.NULL then
            -- Ideally, there should never be a nil, but if it occurs, it's better to ignore it.
            -- This is mainly for user's convenience and shouldn't critically affect anything else.
            if hashes_by_name[t.name] == nil then
                log.error(
                    "Failed to get hash for migration %s. Check migrations source code. They might be inconsistent.",
                    t.name
                )
            else
                box.space._migrations:update(t.id,{{'=', hash_filed_num,  hashes_by_name[t.name]}})
                log.info("Create hash for migration %s:%s", t.name, hashes_by_name[t.name])
            end
        end
    end
end

return M
