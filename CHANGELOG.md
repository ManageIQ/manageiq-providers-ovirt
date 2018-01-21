# Change Log

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](http://keepachangelog.com/en/1.0.0/)


## Unreleased as of Sprint 77 ending 2018-01-15

### Fixed
- Fix message for credentials validation [(#195)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/195)
- Fix wrong call to 'orchestrate_destroy' with no parameters [(#192)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/192)
- Reconnect host on provider add [(#189)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/189)
- Credential verification errors for new provider [(#188)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/188)
- Block migration call [(#182)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/182)
- Set '<Use template nics>' as the default vnic profile option [(#150)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/150)

## Unreleased as of Sprint 76 ending 2018-01-01

### Fixed
- Provide missing events [(#180)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/180)
- Unrecognized events during import from glance [(#179)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/179)
- Fix location of `pipeline` and `connections` settings [(#176)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/176)
- Handle console events [(#173)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/173)
- Store ipv4/ipv6 of guest devices aligned to vmware implementaion [(#170)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/170)

## Unreleased as of Sprint 75 ending 2017-12-11

### Fixed
- Added supported_catalog_types [(#174)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/174)
- Update ems version during graph refresh [(#164)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/164)

## Unreleased as of Sprint 74 ending 2017-11-27

### Added
- Use supports_vm_import? instead of validate_import_vm [(#154)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/154)
- Change "Empty" to "No Profile" in profile list [(#151)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/151)
- Update Engine version check for admin_ui feature [(#148)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/148)
- Save host 'maintenance' value [(#147)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/147)
- oVirt network provider support routers security groups and floating ips [(#144)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/144)
- Rename version_higher_than to version_at_least [(#143)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/143)

### Fixed
- Fix version check in supports_admin_ui method [(#156)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/156)
- Fix remote console for v4 [(#145)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/145)

## Unreleased as of Sprint 73 ending 2017-11-13

### Added
- Support sysprep for windows templates [(#91)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/91)

### Fixed
- Fill VmOrTemplate relation correctly [(#120)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/120)
- We need to use lazy_find_by for hash index [(#117)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/117)
- v2v: Extend 'VM Transform' dialog to select VMs by tag [(#115)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/115)
- Move detecting the api versions to database query [(#114)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/114)
- Running 'ensure_network provider' as a separate job [(#110)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/110)
- Assume 3 when can't determine API version [(#108)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/108)

## Unreleased as of Sprint 72 ending 2017-10-30

### Fixed
- ID's shouldn't be in the service dialog YML [(#119)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/119)

## Gaprindashvili Beta1

### Added
- Introducing OVN as oVirt's network provider [(#90)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/90)
- Honour `open_timeout` when using V4 [(#126)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/126)
- Handle partial vm entity during creation [(#129)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/129)

### Fixed
- Avoid NoMethod error in TemplatePreloadedAttributesDecorator.new [(#106)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/106)
- Propagate user validation errors [(#104)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/104)
- Parse the serial number during refresh [(#97)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/97)
- Identify the redhat events in the core settings [(#99)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/99)
- Target new template when using api v4 [(#96)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/96)
- Support publish VM [(#95)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/95)
- Add connection manager [(#92)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/92)
- v2v: Make "install drivers" checkbox dynamic [(#76)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/76)
- Refresh a host when removed [(#127)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/127)
- Don't close connection explicitly [(#128)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/128)
- Try both API versions in `raw_connect`[(#132)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/132)
- Fix vm removal for apiv4 [(#131)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/131)

## Initial changelog added
