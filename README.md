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

## FAT framework decryption

For a FAT framework containing armv7/arm64 or multiple CPU subtypes, the output
contains only the slice loaded by the target process. Its header and load commands
must match the on-disk slice. Segment VM offsets are used to read decrypted pages;
the encryption flag is cleared only after every read succeeds and the data differs
from ciphertext and is nonzero. Failed attempts retain the previous output file.

Run `sh Tests/run.sh` on macOS for FAT32/FAT64, byte-order, CPU subtype/UUID,
VM-offset, Mach task read and failed-output regressions. Actual FairPlay decryption
requires an installed app on a supported physical device.

## Credits / Thanks
- [wh1te4ever](https://github.com/wh1te4ever) for TrollDecryptor
- [opa334](https://github.com/opa334) for some pieces of code
- [super.user](https://superuser.carrd.co) for the original app icon