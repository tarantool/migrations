#!/bin/sh
# Call this scripts to install test dependencies

set -e

# Test dependencies:
tarantoolctl rocks install luatest 1.0.1
tarantoolctl rocks install luacov 0.13.0
tarantoolctl rocks install luacheck 0.26.0
tarantoolctl rocks make migrations-scm-1.rockspec
