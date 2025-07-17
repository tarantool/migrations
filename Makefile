version := scm-1

.PHONY: all doc test schema install

ARCHIVE_NAME=tarantool-enterprise-sdk-gc64-2.11.7-0-r691.linux.x86_64.tar.gz
COMMIT_TAG = $(shell git describe)

all: doc
	mkdir -p doc

sdk: Makefile
	wget https://tarantool:$(DOWNLOAD_TOKEN)@download.tarantool.io/enterprise/release/linux/x86_64/2.11/${ARCHIVE_NAME}
	tar -xzf ${ARCHIVE_NAME}
	rm ${ARCHIVE_NAME}
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
