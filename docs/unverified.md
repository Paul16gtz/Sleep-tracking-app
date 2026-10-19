# Unverified API and tooling assumptions

No Swift compiler, Xcode or XcodeGen is available in the authoring environment. Every item below could only be checked statically and must be confirmed on the Mac or in CI.

- `project.yml`: XcodeGen is expected to exclude the `Info.plist` referenced by `INFOPLIST_FILE` from the target's resources automatically. To verify: after `xcodegen generate`, check that `SleepTracker/Info.plist` does not appear under "Copy Bundle Resources". If it does, add `excludes: ["Info.plist"]` to the `SleepTracker` source entry.
