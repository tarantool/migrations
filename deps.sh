#!/bin/sh
# Call this scripts to install test dependencies

set -e

TTCTL=tt
if ! [ -x "$(command -v tt)" ];
then
    echo "tt not found"
    exit 1
fi

# Test dependencies:
${TTCTL} rocks install luatest 1.0.1
${TTCTL} rocks install luacov 0.13.0
${TTCTL} rocks install luacheck 0.26.0

VSHARD_EE_VERSION="${VSHARD_EE_VERSION:-0.1.27}"
DDL_EE_VERSION="${DDL_EE_VERSION:-1.7.1}"
CARTRIDGE_VERSION="${CARTRIDGE_VERSION:-2.12.1}"

# Workaround until SDK with ee modules is released.
ENDPOINT="https://hb.vkcs.cloud"
aws --endpoint-url "${ENDPOINT}" s3 cp "s3://packages/rocks/vshard-ee-${VSHARD_EE_VERSION}-1.all.rock" .
${TTCTL} rocks install ./vshard-ee-${VSHARD_EE_VERSION}-1.all.rock

aws --endpoint-url "${ENDPOINT}" s3 cp "s3://packages/rocks/ddl-ee-${DDL_EE_VERSION}-1.all.rock" .
${TTCTL} rocks install ./ddl-ee-${DDL_EE_VERSION}-1.all.rock

${TTCTL} rocks install cartridge ${CARTRIDGE_VERSION}
# Workaround for cartridge rockspec vshard and ddl dependencies
${TTCTL} rocks remove vshard --force-fast
${TTCTL} rocks remove ddl --force-fast

${TTCTL} rocks make
