include $(THEOS)/makefiles/common.mk

FRAMEWORK_NAME = SSZipArchive

SSZipArchive_FILES = $(shell find . -path "*/.theos/*" -prune -o \( -name "*.m" -o -name "*.c" \) -print)

SSZipArchive_PUBLIC_HEADERS = SSZipCommon.h SSZipArchive.h
SSZipArchive_INSTALL_PATH = /Library/Frameworks

SSZipArchive_CFLAGS = -fobjc-arc
SSZipArchive_CFLAGS += -DHAVE_INTTYPES_H -DHAVE_PKCRYPT -DHAVE_STDINT_H -DHAVE_WZAES -DHAVE_ZLIB -DZLIB_COMPAT # SSZipArchive
SSZipArchive_CFLAGS += -Wno-unused-but-set-variable

include $(THEOS_MAKE_PATH)/framework.mk
