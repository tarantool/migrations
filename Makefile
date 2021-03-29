version := scm-1

.PHONY: all doc test schema install

BUNDLE_VERSION=1.10.9-0-g720ffdd23-r391
COMMIT_TAG = $(shell git describe)

all: doc
	mkdir -p doc

centos-packages:
	yum -y install epel-release && yum -y update && yum -y install wget git cmake make unzip

sdk: Makefile
	wget https://tarantool:$(DOWNLOAD_TOKEN)@download.tarantool.io/enterprise/tarantool-enterprise-bundle-$(BUNDLE_VERSION).tar.gz
	tar -xzf tarantool-enterprise-bundle-$(BUNDLE_VERSION).tar.gz
	rm tarantool-enterprise-bundle-$(BUNDLE_VERSION).tar.gz
	mv tarantool-enterprise sdk

.rocks: migrations-scm-1.rockspec
	$(shell) ./deps.sh

lint:
	.rocks/bin/luacheck .

test: lint
	rm -f luacov*
	.rocks/bin/luatest --verbose --shuffle all --coverage
	.rocks/bin/luacov . && grep -A999 '^Summary' tmp/luacov.report.out

push-scm-1:
	curl --fail -X PUT -F "rockspec=@migrations-scm-1.rockspec" https://${ROCKS_USERNAME}:${ROCKS_PASSWORD}@rocks.tarantool.org

push-release:
	cd release/ \
    && curl --fail -X PUT -F "rockspec=@migrations-${COMMIT_TAG}-1.rockspec" https://${ROCKS_USERNAME}:${ROCKS_PASSWORD}@rocks.tarantool.org \
    && curl --fail -X PUT -F "rockspec=@migrations-${COMMIT_TAG}-1.all.rock" https://${ROCKS_USERNAME}:${ROCKS_PASSWORD}@rocks.tarantool.org
