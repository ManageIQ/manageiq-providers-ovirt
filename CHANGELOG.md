# Change Log

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](http://keepachangelog.com/en/1.0.0/)


## Gaprindashvili RC

### Added
- Reload provider when api_version available [(#157)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/157)

### Fixed
- Raise Miq exceptions on connect [(#162)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/162)
- Update ems version during graph refresh [(#164)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/164)
- Fix Seal option of publish VM [(#167)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/167)
- Implement template targeted refresh [(#165)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/165)
- Handle console events [(#173)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/173)
- Targeting host fails [(#171)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/171)
- Added supported_catalog_types [(#174)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/174)
- Use supports_vm_import? instead of validate_import_vm [(#154)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/154)

## Gaprindashvili Beta2

### Added
- Check metrics details from `raw_connect` [(#134)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/134)
- Set default tag category in 'Transform VM' dialog [(#135)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/135)
- Save host 'maintenance' value [(#147)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/147)
- Add admin_ui feature support to InfraManager [(#133)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/133)
- Update Engine version check for admin_ui feature [(#148)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/148)
- oVirt network provider support routers, security groups and floating ips [(#144)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/144)

### Changed
- Change "Empty" to "No Profile" in profile list [(#151)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/151)

### Fixed
- Fix credential validation if no metrics given [(#140)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/140)
- Vm provisioning do not run reconnect_events [(#138)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/138)
- Fix remote console for v4 [(#145)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/145)
- Fix version check in supports_admin_ui method [(#156)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/156)

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
