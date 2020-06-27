Oberon File System Tools

FileSystem.Watch
FileSystem.SetDefault ^
FileSystem.Unmount ^
FileSystem.Mount prefix [hashSize] [cachesize] alias (params ~ | ^ )
FileSystem.InstallCache prefix hashSize cacheSize ~
FileSystem.RemoveCache prefix

FileSystem.GenCopyFiles rem add ( "mask" | &file | { file [=> file] } )
FileSystem.CopyTo dst src ( &file | { file [=> file]} ) ~

Examples:
Partitions.Show ~ (list available partitions)
FileSystem.Mount AOS AosFS IDE2#5 ~
FileSystem.Mount RAM RamFS 2000 2048 ~
FileSystem.Mount A NatFS Diskette0 ~ (execute Diskettes.Install first)
FileSystem.Mount CD ISOFS IDE1 ~
FileSystem.Mount C FatFS IDE0#1 ~
FileSystem.Mount Linux LinuxFS /home/user/LNO/ ~ (LNO only)
FileSystem.Mount DFS FileFS Oberon.Dsk ~ (mount DOS-based volume copied to Native)
FileSystem.Mount DOS DosBasedFS c:/oberon.dsk ~ (mount DOS-based volume)
FileSystem.Mount OB0 NatFS SYS:Oberon0.Dsk ~
FileSystem.InstallCache SYS 500 1000
FileSystem.RemoveCache SYS

With removable media: insert the media, execute Mount, use the mounted 
drive, and execute Unmount before removing the media again.

Drivers:
ATADisks.Install Diskettes.Install ~
FileDisks.Open SYS:Oberon0.Dsk ~  FileDisks.Close ^

Aos only:
FileSystem.Mount <prefix> FatFS <disk#part>[",R"][",X"][",C:"<cache size>]["|"<root directory>] ~
options: 
	R: mount read-only
	X: force mount read/write even if volume was not properly unmounted
	C: override default data cache settings
	"|"<root directory>: allows to mount a different directory as the root directory

