ARCHS = arm64
THEOS_PACKAGE_SCHEME = rootless
TARGET = iphone:clang:16.5:15.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = OwlCam

OwlCam_FILES = Tweak.xm
OwlCam_FRAMEWORKS = UIKit CoreGraphics CoreVideo ImageIO Foundation
OwlCam_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk

clean::
	rm -rf packages/

# Hardcoded IP
PHONE = mobile@192.168.0.247

inst::
	scp packages/*.deb $(PHONE):/tmp/owlcam.deb
	ssh -t $(PHONE) "sudo dpkg -i /tmp/owlcam.deb && sudo killall -9 SpringBoard"

deploy: clean package inst