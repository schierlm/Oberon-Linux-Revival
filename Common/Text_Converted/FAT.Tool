The FAT tool allows you to access the extended capabilities of the FAT file system that Oberon does not support, i.e. directories, file attributes, aso.

Directory Handling
OFSFATTools.CreateDir "[prefix':']name" ~	create a directory
OFSFATTools.ChangeDir "[prefix':']name" ~	change the current directory
OFSFATTools.RemoveDir "[prefix':']name" [\r] ~	remove a directory.
	\r: recursively delete subdirectories and files
OFSFATTools.CurrentDir prefix ~	get the name of the current directory

Cache Settings
OFSFATTools.EnableLazyWriting prefix ("E"|"D") ~	enables/disables lazy writing
OFSFATTools.PrintCacheStatistics prefix ~	writes cache statistics to the system's log

Volume Maintenance
OFSFATFiles.ShowHiddenFiles	lists hidden files in directory listings
OFSFATFiles.HideHiddenFiles	hides hidden files in directory listings
OFSFATTools.FileInfo "[prefix':']name" ~	prints information on a file handle
OFSFATTools.DirectoryInfo "[prefix':']name" ~	prints information on a directory handle
OFSFATTools.PrintInformation prefix ~	prints information on mounted FAT volume

OFSFATTools.Scandisk prefix ~	scan the volume for invalid directory entries,
	cross-linked files and lost cluster chains
!OFSFATTools.QuickFormat prefix ~	format the volume.
	WARNING: all data will be lost !
	
Examples
OFSFATTools.CreateDir "FAT:/NativeOberon/Work" ~
OFSFATTools.ChangeDir "FAT:/Native Oberon/Work/" ~
OFSFATTools.ChangeDir "FAT:.." ~
OFSFATTools.CurrentDir FAT ~
OFSFATTools.FileInfo "FAT:G.TXT" ~
OFSFATTools.DirectoryInfo "FAT:/Native Oberon" ~
OFSFATTools.PrintCacheStatistics FAT ~
OFSFATTools.PrintInformation FAT ~
OFSFATTools.Scandisk FAT ~

