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

In `/etc/apache2/sites-available/alexbeals.com-le-ssl.conf` add in this port forwarding:

```
  # Proxying for OwlCam
  ProxyPass /projects/owl-cam/stream http://127.0.0.1:16146/stream timeout=300
  ProxyPassReverse /projects/owl-cam/stream http://127.0.0.1:16146/stream
  ProxyPass /projects/owl-cam/status http://127.0.0.1:16146/status
  ProxyPassReverse /projects/owl-cam/status http://127.0.0.1:16146/status
```

and restart with `service apache2 restart`.