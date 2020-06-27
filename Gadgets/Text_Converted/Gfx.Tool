Get a quick start with Gfx:

What is Gfx?
A set of modules for rendering two-dimensional graphics using
high-level operations.

Note: This release of Gfx (1.74) will only compile on Oberon System 3
release 2.3.4 or later and requires that the Images package is
installed, which is available at
  ftp://ftp.inf.ethz.ch/pub/software/Oberon/System3/Contrib/Images/

Documentation
	Compress.Extract Gfx174.Arc GfxHowto.html GfxOverview.html ~

Installation
	Compress.Extract Gfx174.Arc
		GfxMatrix.Mod GfxImages.Mod GfxPaths.Mod
		GfxRegions.Mod GfxFonts0.Mod GfxFonts.Mod Gfx.Mod
		GfxRaster.Mod GfxPrinter.Mod GfxBuffer.Mod GfxDisplay.Mod
		GfxPS.Mod GfxProlog.ps
	~
	Native -> Builder.Compile GfxFonts0.Mod\s ~
	Windows -> Builder.Compile \D=WIN GfxFonts0.Mod\s ~
	All -> Builder.Compile \s
		GfxMatrix.Mod GfxImages.Mod\N GfxPaths.Mod
		GfxRegions.Mod GfxFonts.Mod\N Gfx.Mod GfxRaster.Mod
		GfxPrinter.Mod GfxBuffer.Mod GfxDisplay.Mod\N GfxPS.Mod
	~

Sample Code
	Compress.Extract Gfx174.Arc GfxTest.Mod GfxDemo.Mod ~
	Builder.Compile GfxTest.Mod\s GfxDemo.Mod\s ~

Font Extensions
Gfx features a plug-in mechanism for adding other font formats
than native Oberon bitmap and outline fonts. At the moment,
two extensions are supported: TrueType fonts and Metafont pk
bitmaps (used in Kaspar Fischer's DVI file viewer). TrueType
support requires that the OType package is already installed,
available at
  ftp://ftp.inf.ethz.ch/pub/software/Oberon/System3/Contrib/OpenType/

	Compress.Extract Gfx174.Arc GfxOType.Mod GfxPKFonts.Mod ~
	Native -> Builder.Compile GfxOType.Mod\s GfxPKFonts.Mod\s ~
	Windows -> Builder.Compile \D=WIN GfxOType.Mod\s GfxPKFonts.Mod\s ~

Font extensions must be registered in the FontFormats section
of Oberon.Text (or in the Windows registry). Font family prefixes
can directly be associated with the correct extension module.

	Native -> add the following lines to Oberon.Text (without green text):
		FontFormats = {
			Arial = GfxOType.Install
			... {add other TrueType family names here}
			cm = GfxPKFonts.Install
			... {add other TeX font family names here}
			GfxOType.Install = *	{try to open unregistered fonts as TrueType}
			GfxPKFonts.Install = *	{try to open unregistered fonts as pk fonts}
		}

	Windows -> equivalent to above example:
		System.Set FontFormats Arial := GfxOType.Install ~
		System.Set FontFormats cm := GfxPKFonts.Install ~
		System.Set FontFormats GfxOType.Install := "*"~
		System.Set FontFormats GfxPKFonts.Install := "*"~

	
Change History

1.74 (22.06.2000)
- GfxImages: fixed stupid bug in SkewRows/SkewCols that used
  wrong width/height for clipped rows/cols (found by pjm)
- GfxPaths: fixed bug in EnumBezier.draw: used xy11 as midpoint
  of Bezier curve instead of xy12
- GfxOType: fixed bug in Open (ignored style)
1.73 (10.05.2000)
- GfxBuffer.Rect now ignores empty rectangles
- GfxPaths.solve: one execution path never set number of solutions
  (noticed by Gnter Feldmann)
1.72 (26.04.2000)
- GfxMatrix: added Atan2 function
- GfxRaster.Arc: fixed u and v not being set when recording
- GfxPrinter.Show: use font as metric if printer metric is NIL
- GfxFonts0: fixed dimensionless fonts not being recognized (Elektra)
- GfxFonts.Open: accept "M.P=*" as wildcard in registry
- default flatness reduced to 0.5 pixels
1.71 (27.03.2000)
- GfxPS: fixed bug in run-length encoding: switch to equal mode
  failed if only first byte different
- GfxPS: fixed bug in ImageM: didn't take x and y into account
1.70 (24.03.2000)
- fixed arc code in GfxPaths for starting points that are off the ellipse
- added Gfx.DrawArc wrapper procedure
- allow font changes while Gfx is in path
- improved downscaling for pk fonts
- made name matching in GfxFonts0 and GfxPKFonts more robust
  (compatibility with device prefix of new file system)
- fine-grained font registering in GfxFonts
- fixed GfxMatrix.Scaled; now recognizes downscaling
- fixed typo in GfxRaster.HairCircle
- more robust Bezier rendering in GfxPaths
- included GfxPKFonts extension
- Gfx clip areas no longer treated as stacks
- Gfx.SaveState and Gfx.RestoreState replaced by Gfx.Save and
  Gfx.Restore (different semantics)
- wrong sense of rotation in GfxPS.Arc fixed
- GfxPS no longer clips to empty path
- improved code for resetting ctm, clip path, and context in GfxPS
  (calls to init* operators broke embedded graphics)

1.63 (7.12.1999)
- bugfix in GfxRaster (filled circles and ellipses)

1.62 (23.11.1999)
- switch to Colors.Mod

1.61 (26.10.1999)
- GfxFonts.WarpMap no longer creates empty images
- removed auto-close logic for regions in GfxRaster
  (breaks outliner pens)
- updated documentation

1.60 (8.10.1999)
- added Gfx.MoveTo and Gfx.Close for more natural path specification
  (removed Gfx.Enter0 and Gfx.Exit0 in turn)
- Gfx.Exit doesn't have to be called anymore for open ended paths

1.50 (9.9.1999)
- wrong exit direction in GfxPaths.Reverse fixed
- GfxPaths now approximates arc with line if radius is smaller than flatness
- GfxFonts.Open now tries to load raster font before calling extensions
- GfxDisplay.CopyMapBlk increases height of temporary buffer by one
  row to avoid heap corruption in Win32.Display.TransferBlock
- GfxMaps has been incorporated into new Images package
- new module GfxImages contains image transformations

1.40 (3.6.1999)
- eliminated Gfx.Erase
- cap and join styles are now constants
- GfxDemo frames do now print
- Gfx.GetStrokeOutline and Gfx.GetDashOutline not consuming
  GfxPaths.Exit after subpath fixed
- reset ctm and clipping path in GfxPS fixed
- ASCIIHexDecode bug in GfxProlog.ps fixed

1.30 (21.4.1999)
- GfxFonts.Open now expects point size in addition to matrix
- font matrix contains transform from default display coordinates
- unified GfxFonts0
- support for TrueColor and TransferBlock in GfxDisplay
- more optimized blend procedures in GfxMaps
- added GfxMaps.InitBuf
- bugfix in GfxMaps.Transform: incorrect overlay of temporary maps
- bugfix in GfxRaster.Rect: incorrect use of GfxRegions.AddPoint with Clip
- made GfxSetDashArray guarantee that (len=0) or (period#0)
- fix in GfxRaster.DashLineTo: didn't always start next dash
- bugfix in GfxFonts.WFGetWidth (dy = dx)

1.20 (10.3.1999)
- GfxPens no longer part of Gfx (has been integrated into LeoPens)
- dash pattern in Gfx separated in two arrays for on/off lengths

1.11 (8.3.1999)
- GfxMaps.Copy now handles overlapping rectangles
- GfxPens no longer part of Gfx release (incorporated into Leonardo)

1.1b (4.3.1999)
- handle Display.Depth() > 8 in GfxMaps.InitDisplayPalette
- fixed wrong matrix in GfxFonts.InitDefault
- Native.GfxFonts0 made more robust when dealing with metric only fonts
- addition of GfxPaths.Split
- GfxMaps are now derived from Objects.Object

1.02b (20.1.1999)
- bugfix in GfxPens.CopyRef (stamp not copied)
- bugfix in GfxRaster (wrong calculation of devWidth)

1.0b (15.12.1998)
- no further changes in design expected
