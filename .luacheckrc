std = 'luajit'
globals = {'box', '_TARANTOOL', 'tonumber64'}
ignore = {
    -- Unused argument <self>.
    '212/self',
    -- Shadowing a local variable.
    '421',
    -- Shadowing an upvalue.
    '431',
    -- Shadowing an upvalue argument.
    '432',
}

include_files = {
    'avro/**/*.lua',
    'test/**/*_test.lua',
}

exclude_files = {
    'test/var/*',
    '.rocks/*',
}
