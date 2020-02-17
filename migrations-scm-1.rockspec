package = 'migrations'
version = 'scm-1'
source  = {
    url = '/dev/null',
}
-- Put any modules your app depends on here
dependencies = {
    'tarantool',
    'lua >= 5.1',
    'checks >= 3.0.1-1, <4.0.0',
    'cartridge >= 2.0.1-1, <3.0.0',
}
build = {
    type = 'none';
}
