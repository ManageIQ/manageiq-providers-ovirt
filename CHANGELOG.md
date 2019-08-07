# Change Log

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](http://keepachangelog.com/en/1.0.0/)


## Ivanchuk-Beta2

### Fixed
- Fix potential bug for graph refresh [(#390)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/390)

## Ivanchuk-Beta1 - Released 2019-07-29

### Added
- Add ConversionHost and ServiceTemplateTransformationPlan subclasses [(#339)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/339)

### Fixed
- Fixes for host_switches [(#338)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/338)
- Fix bug in vm targeted refresh [(#331)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/331)
- Fix parse_targeted_inventory to call inv.parse [(#328)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/328)
- Fix targeted host refresh [(#316)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/316)
- EMS validation with maintenance zone specs fix [(#311)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/311)
- mapping from "powering_up" to "on" [(#346)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/346)
- Skip VMs missing a cluster when saving relats [(#343)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/343)

## Hammer-8 - Released 2019-07-02

### Fixed
- Implement provisioning independent thin VM [(#372)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/372)
- Add skeletal provisioning to V4 [(#379)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/379)

## Hammer-7 - Released 2019-06-10

### Fixed
- Don't collect security groups in rhev refresh [(#365)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/365)
- Fix refreshing vm ips - multiple reported devices [(#371)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/371)

## Hammer-6 - Released 2019-05-22

### Added
- Add supports_conversion_host to Host [(#315)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/315)

### Fixed
- Fix refreshing ipmi from host [(#359)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/359)

## Hammer-5 - Released 2019-04-23

### Fixed
- Fix removing a disk from a Vm [(#353)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/353)

## Hammer-4 - Released 2019-03-29

### Fixed
- Fix deleting a disk from VM [(#348)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/348)

## Hammer-3 - Released 2019-03-06

### Fixed
- Host targeted refresh deleting and re-creating storage, switch, and lan records [(#336)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/336)

## Hammer-1 - Released 2019-01-15

### Added
- Add sysprep support for ovirt [(#275)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/275)
- Add plugin display name [(#279)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/279)
- Persister: optimized InventoryCollection definitions [(#268)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/268)
- Performance improvements for graph refresh [(#237)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/237)
- Don't use interpolations in gettext strings [(#297)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/297)
- Add support for CA for Ansible role [(#313)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/313)
- No need to override disconnect_inv from core [(#310)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/310)

### Fixed
- Fix targeted host refresh [(#316)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/316)
- Scope EmsFolder and ResourcePool queries by ems_id [(#322)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/322)
- Fix attach_floppy to pass "floppy" type [(#298)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/298)
- Fix pxe provisioning [(#300)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/300)
- Fix provisioning independent VM [(#277)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/277)
- Fix disk_type attribute [(#276)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/276)
- Use the same assoc for targeted and full refresh [(#265)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/265)
- Fix vm targeted refresh on removal [(#264)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/264)
- Fix refresh failing on guest device lan collection [(#262)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/262)
- Use Graph refresh by default [(#259)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/259)
- Fix logging oVirt event in debug level [(#255)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/255)
- Set EMS api_version to a variable for readability [(#250)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/250)
- Don't call Gem::Version.new() with a nil version [(#247)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/247)
- Fix graph targeted host refresh spec [(#213)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/213)
- Add safe operator for bz 1633540 to protect against empty source_vms [(#292)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/292)
- Fix PXE provisioning [(#294)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/294)
- Fix ISO provisioning with kickstart [(#296)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/296)

## Gaprindashvili-3 released 2018-05-15

### Added
- Support Unregister VM [(#223)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/223)
- Update client to use renamed NetworkDiscovery [(#208)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/208)
- Discovery namespace change [(#209)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/209)
- Make graph refresh enabled by default [(#219)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/219)

### Fixed
- Add fix and add specs for graph targeted refresh [(#203)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/203)
- Provide max memory on VM reconfigure [(#224)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/224)
- Use correct refresh for older providers [(#207)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/207)
- Fix graph refresh fetching custom attributes [(#211)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/211)
- Get mac addr if the selected profile is '<Empty>' or '<Template>' [(#227)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/227)
- Fix provider discovery [(#232)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/232)
- Use old refresh as default [(#233)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/233)

## Gaprindashvili-2 released 2018-03-06

### Fixed
- Fix target host [(#155)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/155)
- Move refresh settings for the Network Manager [(#198)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/198)
- Fix adding vm_location to vm event hash [(#205)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/205)
- Fix updating catalog item when provider missing [(#206)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/206)

## Gaprindashvili-1 - Released 2018-01-31

### Added
- Reload provider when api_version available [(#157)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/157)
- Check metrics details from `raw_connect` [(#134)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/134)
- Set default tag category in 'Transform VM' dialog [(#135)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/135)
- Save host 'maintenance' value [(#147)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/147)
- Add admin_ui feature support to InfraManager [(#133)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/133)
- Update Engine version check for admin_ui feature [(#148)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/148)
- oVirt network provider support routers, security groups and floating ips [(#144)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/144)
- Introducing OVN as oVirt's network provider [(#90)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/90)
- Honour `open_timeout` when using V4 [(#126)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/126)
- Handle partial vm entity during creation [(#129)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/129)

### Changed
- Change "Empty" to "No Profile" in profile list [(#151)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/151)

### Fixed
- Raise Miq exceptions on connect [(#162)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/162)
- Update ems version during graph refresh [(#164)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/164)
- Fix Seal option of publish VM [(#167)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/167)
- Implement template targeted refresh [(#165)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/165)
- Handle console events [(#173)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/173)
- Targeting host fails [(#171)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/171)
- Added supported_catalog_types [(#174)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/174)
- Use supports_vm_import? instead of validate_import_vm [(#154)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/154)
- Fix credential validation if no metrics given [(#140)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/140)
- Vm provisioning do not run reconnect_events [(#138)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/138)
- Fix remote console for v4 [(#145)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/145)
- Fix version check in supports_admin_ui method [(#156)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/156)
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
- Fix location of `pipeline` and `connections` settings [(#176)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/176)
- Unrecognized events during import from glance [(#179)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/179)
- Store ipv4/ipv6 of guest devices aligned to vmware implementaion [(#170)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/170)
- Provide missing events [(#180)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/180)
- Credential verification errors for new provider [(#188)](https://github.com/ManageIQ/manageiq-providers-ovirt/pull/188)

## Initial changelog added
