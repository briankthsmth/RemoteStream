# RemoteStream

Framework for MacOS and iOS to view a RTSP stream. This uses GStreamer, https://gstreamer.freedesktop.org/, for 
receiving a RTSP stream. The project settings are setup such that the framework 
will compile with the GStreamer frameworks installed from their package installers.

I last used GStreamer 1.22.1 for MacOs, and 1.20.5 for iOS.

Any system running an RTSP server can be used. This has been tested
with a Raspberry Pi and a NVIDIA Jetson Nano. 
