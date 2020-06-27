VNC-Viewer by Jrg Kreienbhl 
(see http://www.uk.research.att.com/vnc/ for servers and other clients)

NetSystem.SetUser vnc:<user>@<host> ~

Desktops.OpenDoc  "<host>:<5900 + Disp>" (VNCViewerDocs.NewDoc) ~
VNC.OpenGadget ^

VNCTask.UnInstallAll

To start a Unix VNC/X-Window server:
  vncserver -geometry 620x730 -depth 24

System.Free VNCViewerDocs VNC VNCViewers VNCTask ~

Compiler.Compile \s  
	DES.Mod VNCTask.Mod VNCViewers.Mod 
	VNC.Mod VNCViewerDocs.Mod ~
	
System.DeleteFiles VNC.Arc ~
Compress.Add VNC.Arc VNC.Tool DES.Mod VNCTask.Mod 
	VNCViewers.Mod VNC.Mod VNCViewerDocs.Mod ~
