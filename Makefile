TARGET := iphone:clang:latest:16.0
INSTALL_TARGET_PROCESSES = SpringBoard


include $(THEOS)/makefiles/common.mk

TWEAK_NAME = VolumeBoostYT

VolumeBoostYT_FILES = Tweak.x YTVolumeHUD.m
VolumeBoostYT_CFLAGS = -fobjc-arc
VolumeBoostYT_FRAMEWORKS = UIKit AVFoundation AudioToolbox

include $(THEOS_MAKE_PATH)/tweak.mk

VolumeBoostYT_LOGOSFLAGS = -c generator=internal
