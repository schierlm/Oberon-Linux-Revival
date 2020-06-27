The Zip tool allows you to compress multiple files into the same zip-archive using the Zlib Deflate compression technique. Zip-archives are portable among all Oberon (and many other) platforms.


ZipTool.Directory Zipfile.Zip ~	Display a list of all entries in  ZipTool.Directory \d Zipfile.Zip ~	an archive. If option "d" is 
ZipTool.Directory ^	used additional information 
ZipTool.Directory \d ^	on contents is given.

ZipTool.Add [\level [\strategy]] Zipfile.Zip file ... ~	Add files to an archive, if the 
ZipTool.Add [\level [\strategy]] Zipfile.Zip ^	archive not already exists, 
ZipTool.Add [\level [\strategy]] ^	create a new one. Options "level" (number
	from 0 (no compression) - 9 (best
	compression)) and "strategy" (number
	from 0 - 2) influence compression degree.


ZipTool.Extract [\o] Zipfile.Zip file1 file2 ... ~	Unpack selected files from an archive.
ZipTool.Extract [\o] Zipfile.Zip ^	If option "o" is used already existing 
ZipTool.Extract [\o] ^	files with the same name are overwritten,
	otherwise they are renamed to filex.Bak

ZipTool.ExtractAll [\o] Zipfile1.Zip ... ~	Unpack all files from a list of archives.
ZipTool.ExtractAll [\o] ^	If option "o" is used already existing 
	files with the same name are renamed 		to filex.Bak


ZipTool.Delete Zipfile.Zip file1 file2 ... ~	Delete selected files from an archive.
ZipTool.Delete Zipfile.Zip ^
ZipTool.Delete ^
