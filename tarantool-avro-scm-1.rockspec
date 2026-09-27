package = 'tarantool-avro'
version = 'scm-1'
source = {
    url    = 'git+https://github.com/tarantool-contrib/tarantool-avro.git',
    branch = 'master',
}
description = {
    summary  = 'Apache Avro for Tarantool, in pure Lua',
    detailed = [[
Schema parsing with the Parsing Canonical Form and CRC-64-AVRO fingerprints,
binary encoding and decoding of every Avro type, object container files with
the null, deflate and zstandard codecs, and schema resolution. No C code.
]],
    homepage = 'https://github.com/tarantool-contrib/tarantool-avro',
    license  = 'BSD-2-Clause',
}
dependencies = {
    'lua ~> 5.1',
}
build = {
    type = 'builtin',
    modules = {
        ['avro']               = 'avro/init.lua',
        ['avro.schema']        = 'avro/schema.lua',
        ['avro.codec']         = 'avro/codec.lua',
        ['avro.resolve']       = 'avro/resolve.lua',
        ['avro.ocf']           = 'avro/ocf.lua',
        ['avro.deflate']       = 'avro/deflate.lua',
        ['avro.compress']      = 'avro/compress/init.lua',
        ['avro.compress.lib']  = 'avro/compress/lib.lua',
        ['avro.compress.zlib'] = 'avro/compress/zlib.lua',
        ['avro.compress.zstd'] = 'avro/compress/zstd.lua',
        ['avro.compress.lz4']  = 'avro/compress/lz4.lua',
    },
}
