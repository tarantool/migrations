version := scm-1

.PHONY: all doc test

SHELL := /bin/bash

AWS_S3_ENDPOINT_URL= https://hb.vkcs.cloud
TARANTOOL_BUNDLE_PATH := enterprise/release/linux/x86_64/2.11/tarantool-enterprise-sdk-gc64-2.11.5-0-r662.linux.x86_64.tar.gz

all: doc
	mkdir -p doc

centos-packages:
	yum -y install epel-release && yum -y update && yum -y install wget git cmake make unzip

sdk:
	aws --endpoint-url "$(AWS_S3_ENDPOINT_URL)" s3 cp "s3://packages/$(TARANTOOL_BUNDLE_PATH)" ./sdk.tar.gz
	mkdir -p sdk && tar -xzvf ./sdk.tar.gz -C sdk --strip 1
	rm sdk.tar.gz

1_2_0_upgrade_rocks:
	source sdk/env.sh \
	&& cd test/1_2_0_upgrade/ \
	&& tt rocks install migrations-ee-1.2.0-1.all.rock

.rocks: sdk
	source sdk/env.sh \
	&& tt rocks install luatest 1.0.1 --only-server=sdk/rocks \
	&& tt rocks install luacov 0.13.0 --only-server=sdk/rocks \
	&& tt rocks install luacheck 0.26.0 --only-server=sdk/rocks \
	&& tt rocks make

lint:
	.rocks/bin/luacheck .

test: lint 1_2_0_upgrade_rocks
	rm -f luacov*
	source sdk/env.sh && .rocks/bin/luatest --verbose
