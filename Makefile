version := scm-1

.PHONY: all doc test schema install

BUNDLE_VERSION=2.8.4-0-g47e6bd362-r508
COMMIT_TAG = $(shell git describe)

all: doc
	mkdir -p doc

centos-packages:
	yum -y install epel-release && yum -y update && yum -y install wget git cmake make unzip

sdk: Makefile
	wget https://$(DOWNLOAD_TOKEN)@download.tarantool.io/enterprise/tarantool-enterprise-bundle-$(BUNDLE_VERSION).tar.gz
	tar -xzf tarantool-enterprise-bundle-$(BUNDLE_VERSION).tar.gz
	rm tarantool-enterprise-bundle-$(BUNDLE_VERSION).tar.gz
	mv tarantool-enterprise sdk

.rocks: migrations-ee-scm-1.rockspec
	$(shell) ./deps.sh

lint:
	.rocks/bin/luacheck .

test: lint
	rm -f luacov*
	.rocks/bin/luatest --verbose --coverage
	.rocks/bin/luacov . && grep -A999 '^Summary' tmp/luacov.report.out

push-scm-1:
	curl --fail -X PUT -F "rockspec=@migrations-ee-scm-1.rockspec" https://${ROCKS_USERNAME}:${ROCKS_PASSWORD}@rocks.tarantool.org

push-release:
	cd release/ \
    && curl --fail -X PUT -F "rockspec=@migrations-ee-${COMMIT_TAG}-1.rockspec" https://${ROCKS_USERNAME}:${ROCKS_PASSWORD}@rocks.tarantool.org \
    && curl --fail -X PUT -F "rockspec=@migrations-ee-${COMMIT_TAG}-1.all.rock" https://${ROCKS_USERNAME}:${ROCKS_PASSWORD}@rocks.tarantool.org
