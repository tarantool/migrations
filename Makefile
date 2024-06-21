version := scm-1

.PHONY: all doc test schema install

AWS_S3_ENDPOINT_URL= https://hb.vkcs.cloud
DOWNLOAD_PATH = download.tarantool.io/enterprise/release/linux/x86_64/2.11
TARANTOOL_VERSION = gc64-2.11.3-0-r636.linux.x86_64
COMMIT_TAG = $(shell git describe)

all: doc
	mkdir -p doc

centos-packages:
	yum -y install epel-release && yum -y update && yum -y install wget git cmake make unzip

sdk: Makefile
	curl -O -L https://${DOWNLOAD_TOKEN}@${DOWNLOAD_PATH}/tarantool-enterprise-sdk-${TARANTOOL_VERSION}.tar.gz
	tar -xzf tarantool-enterprise-sdk-$(TARANTOOL_VERSION).tar.gz
	rm tarantool-enterprise-sdk-$(TARANTOOL_VERSION).tar.gz
	mv tarantool-enterprise sdk

.rocks: migrations-ee-scm-1.rockspec
	$(shell) ./deps.sh

lint:
	.rocks/bin/luacheck .

test: lint
	rm -f luacov*
	.rocks/bin/luatest --verbose
