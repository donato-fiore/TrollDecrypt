# TrollDecrypt
iOS IPA Decrypter for TrollStore

## How do I install TrollDecrypt?
In order to install TrollDecrypt you can either:
* Get it on [Havoc](https://havoc.app/package/trolldecrypt)!
* Download the latest release [here](https://github.com/donato-fiore/TrollDecrypt/releases)
* Build from source

## How to build
1. Install [theos](https://theos.dev/docs/installation)
2. Run the commands below
```
git clone https://github.com/donato-fiore/TrollDecrypt.git
cd TrollDecrypt
make package
```

For a TrollStore package, run `make package FINALPACKAGE=1 PACKAGE_TIPA=1`.

## Extension decryption in this fork

Extensions are discovered from both `PlugIns/*.appex` and `Extensions/*.appex`,
including extensions that are not registered with PlugInKit on the current OS.
Their executables are launched suspended through launchd, and decrypted pages
are read before dyld loads dependencies. This supports dumping extensions that
require newer system frameworks, such as WidgetKit and App Intents extensions.
It does not make those extensions runnable on an older iOS version.

The installed App Store copy and its FairPlay metadata must remain available.
A short-lived helper uses the `com.apple.private.persona-mgmt` entitlement to
temporarily enable execution when the installer removed execute bits. The helper
restores the original mode after launch and on handled failures or termination,
and does not change the installed executable's bytes. Only verified, nonzero
decrypted data is published to the output copy. The suspended path currently
requires one arm64 slice; unsupported binaries are retained unchanged in the IPA.

Apps without embedded frameworks also use suspended decryption for their main
executable. Otherwise, the same path is a fallback if the main executable cannot
be dumped after a normal launch. Framework dumping still depends on the normal app process.
IPA export is best-effort: a failed main executable, framework, or extension does
not stop the remaining work. Every attempt writes to a separate file, so failures
retain the original bytes and encryption flag rather than a truncated or partially
patched executable. FairPlay metadata is retained for bundles that still contain
encrypted or unverified files. The final scan records remaining encryption and the
success dialog indicates when some files were kept unchanged, but the IPA is still
created. Bundle-copy and packaging failures remain fatal. Binary-only mode still
reports failure if it cannot decrypt the requested executable.

Run `sh Tests/run.sh` on macOS for extension discovery, Mach-O bounds checks,
FAT inspection, retained-original output transactions, and invalid launch PID regressions.
Actual FairPlay decryption requires an on-device test with an installed app.

## Credits / Thanks
- [wh1te4ever](https://github.com/wh1te4ever) for TrollDecryptor
- [opa334](https://github.com/opa334) for some pieces of code
- [super.user](https://superuser.carrd.co) for the original app icon
