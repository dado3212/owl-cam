# OwlCam Stream

Stream a NiView security camera to the web from a jailbroken iPhone.

## Installation on iPhone
Update Makefile with the correct `PHONE = mobile@192.168.0.247` and then run `make deploy`.

Then open NiView and open the camera.

The stream will be accessible from the EC2 instance IP if you're using the right port or locally:

`http://192.168.0.247:8080/stream` in a browser.

## Installation on Router

Port forward to :16146.

### Debug

You can see logs by filtering to "[OwlCam]" in Console.app with the iPhone physically attached.

## Installation on EC2