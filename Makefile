TARGET := iphone:clang:latest:14.0
INSTALL_TARGET_PROCESSES = TrollDecrypt

GO_EASY_ON_ME = 1
PACKAGE_FORMAT = ipa

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = TrollDecrypt

TrollDecrypt_FILES = SSZipArchive/minizip/unzip.c SSZipArchive/minizip/crypt.c SSZipArchive/minizip/ioapi_buf.c SSZipArchive/minizip/ioapi_mem.c SSZipArchive/minizip/ioapi.c SSZipArchive/minizip/minishared.c SSZipArchive/minizip/zip.c SSZipArchive/minizip/aes/aes_ni.c SSZipArchive/minizip/aes/aescrypt.c SSZipArchive/minizip/aes/aeskey.c SSZipArchive/minizip/aes/aestab.c SSZipArchive/minizip/aes/fileenc.c SSZipArchive/minizip/aes/hmac.c SSZipArchive/minizip/aes/prng.c SSZipArchive/minizip/aes/pwd2key.c SSZipArchive/minizip/aes/sha1.c SSZipArchive/SSZipArchive.m
TrollDecrypt_FILES += main.m TDAppDelegate.m TDRootViewController.m TDDumpDecrypted.m TDUtils.m TDFileManagerViewController.m LSApplicationProxy+AltList.m
TrollDecrypt_FRAMEWORKS = UIKit CoreGraphics MobileCoreServices
TrollDecrypt_CFLAGS = -fobjc-arc
TrollDecrypt_CODESIGN_FLAGS = -Sentitlements.plist

include $(THEOS_MAKE_PATH)/application.mk

after-stage::
	rm -rf Payload
	mkdir -p $(THEOS_STAGING_DIR)/Payload
	ldid -Sentitlements.plist $(THEOS_STAGING_DIR)/Applications/TrollDecrypt.app/TrollDecrypt
	cp -a $(THEOS_STAGING_DIR)/Applications/* $(THEOS_STAGING_DIR)/Payload
	mv $(THEOS_STAGING_DIR)/Payload .
	zip -q -r TrollDecrypt.tipa Payload
