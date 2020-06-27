Overview
The Images package provides support for bitmap images of up to 32 bit pixel depths. Its main features include:
- model for raster images of various depths and formats
- basic image processing (format conversions, optimized palettes, dithering, compositing)
- support for different file formats (fully extensible)
- gadgets and documents for viewing images
- color objects and gadgets for manipulating them (see Colors.Tool)


Commands

	ImageDocs.Open ^	open selected file as image document


Documentation
	Compress.Extract Images103.Arc Images.Text ~
	Desktops.OpenDoc Images.Text


Installation
	Compress.Extract Images103.Arc
		Colors.Mod Images.Mod ImageGadgets.Mod ImageDocs.Mod
		PictImages.Mod BMPImages.Mod JPEGImages.Mod GIFImages.Mod ~
	Compiler.Compile \s
		Colors.Mod Images.Mod\N ImageGadgets.Mod ImageDocs.Mod
		PictImages.Mod\N BMPImages.Mod JPEGImages.Mod
		GIFImages.Mod\N ~

Register known file extensions in Oberon.Text
	ImageFormats = {
		Pict = PictImages.Install
		bmp = BMPImages.Install
		jpg = JPEGImages.Install
		gif = GIFImages.Install
	}

Oberon for Windows users should execute the following commands
	System.Set ImageFormats Pict := PictImages.Install ~
	System.Set ImageFormats bmp := BMPImages.Install ~
	System.Set ImageFormats jpg := JPEGImages.Install ~
	System.Set ImageFormats gif := GIFImages.Install ~


Currently supported file formats
- read and write Oberon .Pict files
- read .bmp files (hi-color and true-color supported)
- read .jpg files (experimental, done by Edgar Schwarz)
- read .gif files (reads only first frame in animated GIFs)


Wish list
- support for more file formats, esp. PNG
- an application combining features of Rembrandt and Christian Kurmann's TrueMontage package for editing images (Photoshop/GIMP light)


Bug Reports
Please send bug reports and comments to oswald@inf.ethz.ch


History
22.06.2000/1.03
 o Images
	- fixed bug in AnyToBGR888 and BGR888ToAny (didn't use bit
	  address for "any" format)
	- added AnyOverBGRA8888 (bug in Bind)
 o ImageGadgets.RestoreRuns: fixed infinite loop with transparent
   images; improved transparency handling
10.05.2000/1.02
 o ColorGadgets: avoid losing hue value when tracking wedge
    (suggested by pjm)
26.04.2000/1.01
 o bugfix in ImageGadgets.PrintRect: didn't handle transparency
23.11.1999/1.00
 o fixed missing alpha component in computed palettes
 o don't dither when storing as .Pict
 o fixed overflow in PictImages RLE
17.11.1999
 o introduced Colors.Mod, ColorGadgets.Mod, and Colors.Panel
 o adapted Images to use Colors instead of fixed palette
9.9.1999
 o fixed usage of wrong pixel size in Images.AnyToBGRA8888
6.9.1999
 o fixed Images.Same (didn't compare palette pointers for {index, alpha} format)
 o new GIFImages.Mod
2.9.1999
 o fixed problem with empty images in ImageGadgets causing traps
 o fixed several transfer procedures in Images which didn't set alpha correctly
31.8.1999
 o fixed BMPImages, palette read from file didn't set alpha to max
30.8.1999
 o initial release