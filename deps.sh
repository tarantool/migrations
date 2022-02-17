#!/bin/sh
# Call this scripts to install test dependencies

set -e

# Test dependencies:
tarantoolctl rocks install luatest 0.5.7
tarantoolctl rocks install luacov 0.13.0
tarantoolctl rocks install luacheck 0.26.0
tarantoolctl rocks make migrations-scm-1.rockspec
