TARGET := iphone:clang:latest:16.0
ARCHS = arm64 arm64e
#INSTALL_TARGET_PROCESSES = SpringBoard
#THEOS_PACKAGE_SCHEME = rootless


include $(THEOS)/makefiles/common.mk

TWEAK_NAME = VolumeBoostYT

VolumeBoostYT_FILES = Tweak.x YTVolumeHUD.m
VolumeBoostYT_CFLAGS = -fobjc-arc
VolumeBoostYT_FRAMEWORKS = UIKit AVFoundation AudioToolbox
VolumeBoostYT_LOGOSFLAGS = -c generator=internal

include $(THEOS_MAKE_PATH)/tweak.mk
