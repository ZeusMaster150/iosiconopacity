export ARCHS = arm64
TARGET := iphone:clang:latest:12.0

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = IconOpacityPrefs

IconOpacityPrefs_FILES = IOPRootListController.m IOPPreviewCell.m
IconOpacityPrefs_FRAMEWORKS = UIKit
IconOpacityPrefs_LDFLAGS = -undefined dynamic_lookup
IconOpacityPrefs_INSTALL_PATH = /Library/PreferenceBundles
IconOpacityPrefs_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/bundle.mk
