# Verification

Local checks use Xcode 27 and the installed Swift compiler. iOS UI workflows run on an iPhone Simulator; the macOS workflow runs on this Mac. Debug and Release Swift Package tests exercise domain behaviour; CI also compiles a Release app and runs the native workflow. UI tests namespace their data rather than removing normal app state.

The deployment target is a source/API compatibility target. The oldest supported OS has not been run locally. Validate it and physical-device lifecycle behaviour before distributing a build. Platform capabilities that need an owner’s signing team, container, domain, or provider key are described in the README and remain separate device verification steps.

Screenshots are captured from running native apps or retained Xcode UI test attachments; they are not mockups.
