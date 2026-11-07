export ARCHS = arm64
TARGET := iphone:clang:latest:12.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = IconOpacity
IconOpacity_FILES = Tweak.x
IconOpacity_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk

after-install::
	install.exec "killall -9 SpringBoard"
