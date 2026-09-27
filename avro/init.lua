--- Apache Avro for Tarantool, in pure Lua.
--
--     local avro = require('avro')
--
--     local sc = avro.schema.parse('{"type":"record","name":"P","fields":[...]}')
--     local bytes = avro.encode(sc, {...})
--     local value = avro.decode(sc, bytes)
--
--     local w = avro.ocf.open('graph.avro', {mode = 'w', schema = sc})
--     w:append({...}); w:close()
--     for record in avro.ocf.open('graph.avro'):records() do ... end
--
-- The pieces are usable on their own: `avro.schema` parses and
-- fingerprints schemas, `avro.codec` does the binary encoding,
-- `avro.resolve` reads data written with one schema through another,
-- `avro.ocf` the container format and `avro.deflate` the raw
-- DEFLATE its `deflate` codec needs. The compression itself comes from
-- `avro.compress`, which is Enterprise's module or an FFI stand-in for it.
--
-- This module only re-exports; every function it names is documented where it
-- is defined.
--
-- @module avro

local schema  = require('avro.schema')
local codec   = require('avro.codec')
local ocf     = require('avro.ocf')
local deflate = require('avro.deflate')
local resolve = require('avro.resolve')

local M = {
    schema   = schema,
    codec    = codec,
    ocf      = ocf,
    deflate  = deflate,
    resolve  = resolve,
    -- A reusable decoder for one (writer schema, reader schema) pair.
    resolver = resolve.resolver,
    skip     = codec.skip,
    -- Whether a container-file codec works in this build, and what backs it.
    -- Worth having at the top level because it is the one thing about Avro
    -- here that differs between two Tarantool binaries.
    codec_available = ocf.codec_available,
    -- A stand-in for a JSON null, so that a null value keeps its key in a
    -- record, array or map where a Lua nil would vanish.
    NULL     = schema.NULL,
    parse    = schema.parse,
    encode   = codec.encode,
    decode   = codec.decode,
    validate = codec.validate,
}

return M
