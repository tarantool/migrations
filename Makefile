version := scm-1

.PHONY: all doc test schema install

BUNDLE_VERSION=1.10.5-14-gb44cfa1

all: webui/build/bundle.lua
	mkdir -p doc

sdk: Makefile
	yum -y install epel-release && yum -y update && yum -y install wget git cmake make unzip
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
