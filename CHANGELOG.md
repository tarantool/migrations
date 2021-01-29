# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](http://keepachangelog.com/en/1.0.0/)
and this project adheres to [Semantic Versioning](http://semver.org/spec/v2.0.0.html).

## [Unreleased]
### Fixed: 
- Fix crash during init when instance http server disabled 
## [0.3.1]
### Fixed:
- Fix "fiber name is too long" for long instance names

## [0.3.0]
### Added
- config-loader to load migrations from Cartridge clusterwide config

## [0.2.0]
### Fixed:
- Fix bug in "second" migrations run, that would lead to each migration applying again and again

## [0.1.0]
### Added:
- Basic functionality
