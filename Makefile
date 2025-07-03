TARGET := iphone:clang:latest:14.0
INSTALL_TARGET_PROCESSES = TrollDecrypt

GO_EASY_ON_ME = 1
PACKAGE_FORMAT = ipa

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = TrollDecrypt

TrollDecrypt_FILES = $(wildcard SSZipArchive/minizip/*.c) $(wildcard SSZipArchive/minizip/aes/*.c) SSZipArchive/SSZipArchive.m
TrollDecrypt_FILES += $(wildcard src/*.m) $(wildcard src/*.mm)
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
