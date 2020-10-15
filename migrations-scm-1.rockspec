package = 'migrations'
version = 'scm-1'
source  = {
    url = 'git+https://github.com/tarantool/migrations.git';
    branch = 'master';
}
-- Put any modules your app depends on here
dependencies = {
    'tarantool',
    'lua >= 5.1',
    'checks >= 3.0.1-1, <4.0.0',
    'cartridge >= 2.0.1-1, <3.0.0',
}
build = {
    type = 'make',
	build_target = 'all',
    install = {
        lua = {
            ['migrator'] = 'migrator/init.lua',
            ['migrator.utils'] = 'migrator/utils.lua',
            ['migrator.directory-loader'] = 'migrator/directory-loader.lua',
            ['migrator.config-loader'] = 'migrator/config-loader.lua',
        },
    },
    build_variables = {
        version = 'scm-1',
    },
    install_pass = false,
}
