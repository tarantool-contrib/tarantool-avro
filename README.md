# tarantool-avro

[![Status: maintained](https://img.shields.io/badge/status-maintained-brightgreen)](https://github.com/tarantool-contrib/rfcs/blob/main/text/0002-governance.md#module-status)
[![Test](https://github.com/tarantool-contrib/tarantool-avro/actions/workflows/test.yml/badge.svg)](https://github.com/tarantool-contrib/tarantool-avro/actions/workflows/test.yml)

[Apache Avro](https://avro.apache.org/docs/1.12.0/specification/) for
Tarantool, in pure Lua: schema parsing with the Parsing Canonical Form and
CRC-64-AVRO fingerprints, binary encoding and decoding of every type, object
container files with the `null`, `deflate` and `zstandard` codecs, and schema
resolution. It is for Tarantool applications that exchange Avro data with the
rest of a data platform — reading files produced by Spark, Kafka Connect or
fastavro, or writing files those tools read.

There is no C code and no Lua dependency. Compression comes from whatever is at
hand: Tarantool Enterprise's `compress` module, or the system libz and libzstd
through the FFI, or — for reading `deflate` — a pure-Lua inflater that works
everywhere.

The byte format is checked against [fastavro](https://fastavro.readthedocs.io/)
fixtures in both directions: every expectation in the cross-implementation
tests comes from the other implementation, not from this one.

## Requirements and installation

Tarantool 3.8, Community or Enterprise Edition. Other versions are not tested.

```
tt rocks install --server=... tarantool-avro   # once the rock is published
tt rocks make                                  # from a checkout
```

The module is `require('avro')`. The unrelated C bindings to the Avro C library
published on luarocks.org (`lua-avro`, `kong-lua-avro`, `avro`) use the same
module name, so do not install one of them into the same rocks tree.

## Quick start

```lua
local avro = require('avro')

local sc = avro.schema.parse([[{
    "type": "record", "name": "Vertex",
    "fields": [{"name": "name", "type": "string"},
               {"name": "value", "type": "long"}]
}]])

local bytes = avro.encode(sc, {name = 'v001', value = 7})
local value = avro.decode(sc, bytes)          --> {name = 'v001', value = 7}

avro.ocf.write_all('/tmp/graph.avro', sc, {value, {name = 'v002', value = 9}})
for record in avro.ocf.open('/tmp/graph.avro'):records() do
    print(record.name, record.value)
end
```

## Schemas

`avro.schema.parse(spec [, opts])` (also `avro.parse`) takes JSON text, a
decoded Lua table or an already parsed schema.

```lua
sc.kind              --> 'record'
sc.fullname          --> 'Vertex'
sc:canonical()       --> {"name":"Vertex","type":"record","fields":[...]}
sc:tojson()          --> the full schema, with docs, aliases and defaults
sc:fingerprint()     --> CRC-64-AVRO of the canonical form, as int64 cdata
sc:fingerprint_hex() --> '547b814b11775a54'
```

`canonical()` is the Parsing Canonical Form, which strips everything not
needed to read the data. `tojson()` keeps it all, which is why it — and not the
canonical form — is what goes into a container file's header: a reader needs
the defaults.

## Values

```lua
local bytes = avro.encode(sc, {name = 'v001', value = 7})  --> 6 bytes
local value = avro.decode(sc, bytes)                       --> {name=, value=}
avro.validate(sc, {name = 'v001', value = 7})              --> true
avro.validate(sc, {name = 'v001'})                         --> false
```

`avro.decode(sc, data [, pos [, reader_schema]])` returns the value and the
position after it, so a concatenation of records can be walked; `avro.skip`
walks past one without building it. Lua maps onto Avro the obvious way, with
one wrinkle: a `null` nested in a record, array or map decodes to `box.NULL`
(exported as `avro.NULL`), because a Lua `nil` would take the key with it.
Ranges are enforced: an `int` outside 32 bits or a `long` outside 64 bits is
refused by `encode` and `validate` rather than wrapped, and a union such as
`["long", "double"]` picks the branch that can actually hold the value.

## Object container files

```lua
local w = avro.ocf.open('/tmp/graph.avro', {
    mode = 'w', schema = sc, codec = 'deflate', block_size = 64 * 1024,
})
w:append({name = 'v001', value = 7})
w:append_all({{name = 'v002', value = 9}})
w:close()

local r = avro.ocf.open('/tmp/graph.avro')
for record in r:records() do
    -- ...
end
r:close()
```

`open` takes `mode = 'r'` (the default) or `'w'`. A reader accepts `data`
instead of a path, to read a file already in memory, and `schema` — a *reader*
schema the records are resolved into. A writer takes `schema` (required),
`codec`, `block_size`, `metadata` and `sync`. Both stream, so a file larger
than memory costs one block; both do blocking file I/O through `fio` and must
run in a fiber that may yield.

Three shorthands cover the common cases: `avro.ocf.read_all(path)` returns
every record plus the file's schema, `avro.ocf.write_all(path, sc, records)`
writes an array in one call, and `avro.ocf.schema_of(path)` returns the schema
and the metadata map without reading any records.

Codecs, and what each build does with them. What varies is not whether a file
can be read — every row of the `deflate` column produces and consumes ordinary
RFC 1951 — but whether it is compressed and by what.

| | CE, system libraries present | CE, no libraries | Enterprise |
| --- | --- | --- | --- |
| `null` | yes | yes | yes |
| `deflate`, writing | zlib through the FFI | stored blocks, uncompressed | Enterprise `compress.zlib` |
| `deflate`, reading | zlib through the FFI | the pure-Lua inflater | zlib through the FFI |
| `zstandard` | libzstd through the FFI | unavailable | Enterprise `compress.zstd` |

Reading `deflate` goes through the FFI binding under Enterprise as well, and
not through Enterprise's own module. That module honours `window_bits` when
compressing and ignores it when decompressing, so the raw deflate an Avro file
stores is write-only there; the FFI binding honours it both ways. Where no
libz can be loaded at all, the pure-Lua inflater takes over — which is what
makes a `deflate` file readable on any build whatsoever.

`avro.codec_available(name)` (also `avro.ocf.codec_available`) answers for the
running build and names the implementation as a second value:

```lua
avro.codec_available('null')       --> true, 'none'
avro.codec_available('deflate')    --> true, 'ffi/ffi'      -- writer/reader
avro.codec_available('zstandard')  --> true, 'ffi'
avro.codec_available('snappy')     --> false
```

The `deflate` value is `'<writer>/<reader>'`: `'enterprise/ffi'` under
Enterprise, `'ffi/ffi'` on a Community build with a system libz,
`'stored/pure-lua'` with neither. `avro.deflate.has_zlib` says whether writing
actually compresses, and `avro.deflate.has_raw_inflate` whether reading uses
zlib rather than Lua.

Setting `AVRO_PURE_LUA=1` in the environment — or
`avro.deflate.force_pure = true` at run time — selects the pure-Lua inflater
whatever else is available. The test suite uses it to exercise both readers in
one process; it is also the way to rule the FFI out when diagnosing something.

## Schema resolution

Data written with one schema can be read through another, following the
specification's Schema Resolution rules: the numeric promotions, string and
bytes either way, record fields matched by name or by a reader alias, a
reader field the writer never wrote filled from its default, an unknown enum
symbol falling back to the reader's `default`.

```lua
local reader = avro.schema.parse([[{
    "type": "record", "name": "Vertex",
    "fields": [{"name": "name", "type": "string"},
               {"name": "value", "type": "double"},
               {"name": "colour", "type": "string", "default": "none"}]
}]])

avro.decode(sc, bytes, 1, reader)  --> {name='v001', value=7, colour='none'}
```

`avro.resolver(writer, reader)` compiles the pair once and returns a decoder to
call per record, which is the cheaper form in a loop.
`avro.resolve.compatible(writer, reader)` is the shallow test the resolver uses
to pick a branch when only the reader is a union: matching kinds, matching
names for the named types, and the promotions. It is not a full answer to
whether the pair resolves — building the resolver is.

## avro.compress

Tarantool Enterprise ships a `compress` module; Community Edition does not, and
that was the only reason the Avro codecs would behave differently on the two.
`avro.compress` is that module where it exists and an FFI binding to the
system libraries where it does not, with the same API either way. The codecs
use it internally; it is usable on its own.

```lua
local compress = require('avro.compress')

compress.implementation           --> 'enterprise' or 'ffi'
compress.available('zstd')        --> true / false

local z = compress.zlib.new({level = 6})
z:decompress(z:compress(s)) == s
```

The three codecs and their options, matching Enterprise's:

```lua
compress.zlib.new({level = 6, mem_level = 8, strategy = 'default',
                   window_bits = 15})
compress.zstd.new({level = 3})
compress.lz4.new({acceleration = 1, decompress_buffer_size = 1048576})
```

`strategy` is one of `default`, `filtered`, `huffman_only`, `rle`, `fixed`.
`level` is 0..9 for zlib and, for zstd, whatever range the linked libzstd
reports (-131072..22 on a current one). `decompress_buffer_size` is a real
limit and not a hint: an LZ4 block records neither its decompressed size nor a
checksum, so this is the largest output `lz4:decompress` will produce, and
Enterprise enforces the same 1 MiB default.

The output is Enterprise's byte for byte where the linked library versions
agree, which the test suite checks in both directions on `make test-ee`.

### window_bits, the one deliberate difference

`window_bits` — 15 for zlib framing, -15 for raw RFC 1951 deflate, 31 for gzip
— is a superset. Enterprise honours it when compressing and ignores it when
decompressing: its `decompress` always expects the zlib frame and always
verifies the trailing adler32, so raw deflate is write-only there. (Re-framing
a raw block for it is not possible either: the adler32 is computed over the
decompressed bytes, which is what is not known yet.) Here the option reaches
`inflateInit2_` as well, which is what the Avro `deflate` codec needs.

`compress.ffi.zlib` is the FFI binding under every build, Enterprise included,
for exactly that reason. `compress.zlib` is the drop-in; reach for
`compress.ffi` only when the difference is the point.

### Finding the libraries

`ffi.load` is tried against, in order:

1. the running process, when it already exports the library's version symbol —
   Community Edition links zlib and zstd statically and exports them, and
   Enterprise 3.7 does the same for liblz4. Preferred because it needs no file
   and cannot skew against what the binary itself compresses with;
2. the plain soname (`z`, `zstd`, `lz4`) and the versioned ones (`libz.so.1`,
   `libz.1.dylib`, …);
3. `/opt/homebrew/lib`, `/opt/homebrew/opt/<name>/lib`, `/usr/local/lib`,
   `/usr/local/opt/<name>/lib`, `/usr/lib` and the Linux multiarch directories;
4. the directory named by `AVRO_COMPRESS_LIBDIR`, as a last resort for a
   library none of the above reaches.

A candidate is accepted only once its version symbol resolves, so a file that
merely has the right name fails the lookup rather than the first real call. The
handle is cached per library. When nothing works the error names every path
tried:

```
avro.compress: cannot load libzstd (tried: ffi.C (the process exports no
ZSTD_versionNumber), zstd, libzstd.so.1, /opt/homebrew/lib/libzstd.1.dylib, …)
```

`require('avro.compress.lib').version('zstd')` reports what was bound.

## Testing and development

```
make deps     # tt rocks install luatest; tt rocks install luacheck
make lint     # luacheck over the whole tree
make test     # the suite, under the luatest wrapper's own tarantool
make test-ee  # the suite, under $(TARANTOOL_EE)
```

Under Community Edition the seven tests that compare against the Enterprise
`compress` module skip themselves; everything else runs on both binaries.
`test-ee` is `test-under` with `TARANTOOL` pointed at `TARANTOOL_EE` —
`make test-ee TARANTOOL_EE=/path/to/ee/tarantool`, or set it in the
environment. `make test-under TARANTOOL=...` runs the suite under any binary.

The fixtures under `test/fixtures/avro` are generated by fastavro 1.12.2:

```
uv run --with fastavro python3 test/fixtures/avro/gen.py
```

Their schemas live in the `pregel.test` namespace, because the module grew up
inside [pregel](https://github.com/tarantool-contrib/pregel) and the namespace
is part of every fixture's bytes and fingerprint.

## License

BSD-2-Clause, see [LICENSE](LICENSE).
