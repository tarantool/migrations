package = 'migrations-ee'
version = 'scm-1'
source  = {
    url = 'git+https://github.com/tarantool/migrations-ee.git';
    branch = 'master';
}
-- Put any modules your app depends on here
dependencies = {
    'tarantool',
    'lua >= 5.1',
    'checks >= 3.0.1-1, <4.0.0',
    'cartridge >= 2.12.1-1, <3.0.0',
    'ddl-ee',
}
build = {
    type = 'make',
	build_target = 'all',
    install = {
        lua = {
            ['migrator-ee'] = 'migrator-ee/init.lua',
            ['migrator-ee.version'] = 'migrator-ee/version.lua',
            ['migrator-ee.utils'] = 'migrator-ee/utils.lua',
            ['migrator-ee.directory-loader'] = 'migrator-ee/directory-loader.lua',
            ['migrator-ee.config-loader'] = 'migrator-ee/config-loader.lua',
        },
    },
    build_variables = {
        version = 'scm-1',
    },
    install_pass = false,
}
