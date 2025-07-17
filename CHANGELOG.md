# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](http://keepachangelog.com/en/1.0.0/)
and this project adheres to [Semantic Versioning](http://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- A check for user modifications to applied migrations.

## [1.0.2]

### Fixed

- State space bootstrap on cluster rolling upgrade (gh-77)

## [1.0.1]

### Added

- BSD License.

## [1.0.0]

### Fixed

- Migrations do not apply to newly added replica sets in the cluster (gh-65)
  Applied migration names are moved from the cluster-wide configuration to
  the space on each node.

### Added

- An API for moving existing migration names from the cluster configuration to
  a space.
- API for getting applied migrations list for the cluster.

## [0.7.0]

### Added

- `utils.check_roles_enabled` helper function
  to check whether roles are enabled on the instance (gh-68)

## [0.6.0]

### Added

- Configurable timeout for storage migrations (gh-66)
### Fixed

- Running tests with Tarantool 2.11+
- Running tests with tarantool/http 1.2.0+ (gh-63)

## [0.5.0]

### Added

- Versioning support

## [0.4.2]

### Fixed

- Fetch schema from a replicaset leader to apply on the clusterwide config even
  when `migrations.up()` is called on a replica (gh-56). The local schema on
  the replica may be not the most actual due to replication lag.
- Issue a warning into log when `register_sharding_key()` is called with
  `{'bucket_id'}` key (gh-49). It is likely a mistake: sharding key is a set of
  fields, which are used to calculate `bucket_id`, not the `bucket_id` itself.

## [0.4.1]

### Fixed

- Unclear error output in some cases

## [0.4.0]

### Fixed

- Fix crash during init when instance http server disabled

### Added

- Lua API to trigger migrations from console

## [0.3.1]

### Fixed

- Fix "fiber name is too long" for long instance names

## [0.3.0]

### Added

- config-loader to load migrations from Cartridge clusterwide config

## [0.2.0]

### Fixed

- Fix bug in "second" migrations run, that would lead to each migration applying again and again

## [0.1.0]

### Added

- Basic functionality
