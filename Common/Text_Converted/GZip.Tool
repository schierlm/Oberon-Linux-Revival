The GZip tool allows you to compress a file into a GZip file using the Zlib Deflate compression technique. GZip files are portable among all Oberon (and many other) platforms.


GZip.Unzip [\o] GZipfile1.gz GZipfile2.gz ... ~	Unpack selected files. If option "o" is used GZip.Unzip [\o] ^	already existing files with the same name 
	are overwritten, otherwise they are
	renamed to file.gz

GZip.Zip [\level [\strategy]] file1 file1.gz ... ~	Compress selected files into *.gz files. 
GZip.Zip [\level [\strategy]] file1 file2 ... ~	If no filename with suffix ".gz" is 
GZip.Zip [\level [\strategy]] ^	specified after the old filename, the
	filename extension ".gz" is appended 
	automatically to the original filename. 
	Options "level" (number from 0 (no
	compression) - 9 (best compression))
	and "strategy" (number from 0 - 2)
	influence compression degree.