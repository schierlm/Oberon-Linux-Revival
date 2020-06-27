	2016-11-29	ARM legacy: OLR.OBC.Mod faster load/store for global variables
	2017-02-25	Files.ReadBytes: initialize unread bytes with zero

ZipDocs.Mod missing not used?? Chech UnZip.Mod!
	2017-02-11	MOPL: fixed Load const with ODD(bit 15)
	2017-02-11	VOPL: fixed Div; changed Load const to MOPL version
	2017-04-16	FileDir: removed adding "/" in Enumerate	
	2017-04-16	Input: using enumerate in InitMouseFB

OLR.mature.Make.Tool

---------------------------- ARMv7 ------------------------------- 
RCompiler.CompileA \d	OLR.ARM.Linux0.Mod	OLR.Kernel.Mod	OLR.Modules.Mod 
	OLR.Files.Mod	OLR.FileDir.Mod	OLR.Objects.Mod	OLR.Display.Mod	OLR.Input.Mod	
	OLR.Fonts.Mod	ARM.Reals.Mod	OLR.Texts.Mod  Viewers.Mod	Oberon.Mod
	MenuViewers.Mod	OLR.TextFrames.Mod	OLR.System.Mod	OLR.Bitmaps.Mod	
	Out.Mod	Pictures.Mod	OLR.Centronics.Mod	OLR.V24.Mod	Printer.Mod	
	Edit.Mod	Styles.Mod		ScriptFrames.Mod	Script.Mod		OLR.Compiler.Mod	OLR.FileTools.Mod	Dates.Mod
	ROPM.Mod	ROPS.Mod	ROPT.Mod	ROPB.Mod	ROPP.Mod	AOPL.Mod	AOPC.Mod	AOPV.Mod
	ROP2.Mod	OLR.RBootLinker.Mod	A32Decoder.Mod	OLR.Browser.Mod ../Hennessy3.pm.Mod Test14.Mod ~
RBootLinker.Link   ola3\ea := Linux0 Kernel Modules  ~	

-------------------------- RISC-V ---------------------------------------------
RCompiler.CompileV	OLR.RISCV.Linux0.Mod	OLR.Kernel.Mod	OLR.Modules.Mod	
	OLR.Files.Mod	OLR.FileDir.Mod	OLR.Objects.Mod	OLR.Display.Mod	OLR.Input.Mod	
	OLR.Fonts.Mod	ARM.Reals.Mod	OLR.Texts.Mod  Viewers.Mod	Oberon.Mod
	MenuViewers.Mod	OLR.TextFrames.Mod	OLR.System.Mod	OLR.Bitmaps.Mod	
	Out.Mod	Pictures.Mod	OLR.Centronics.Mod	OLR.V24.Mod	Printer.Mod	
	Edit.Mod	Styles.Mod	ScriptFrames.Mod	Script.Mod	OLR.Compiler.Mod	OLR.FileTools.Mod
	ROPM.Mod	ROPS.Mod	ROPT.Mod	ROPB.Mod	ROPP.Mod	VOPL.Mod	VOPC.Mod	VOPV.Mod
	ROP2.Mod	OLR.RBootLinker.Mod	VDecoder.Mod	OLR.Browser.Mod ../Hennessy3.pm.Mod~
RBootLinker.Link   olv2\ev :=  Linux0 Kernel Modules  ~ 	get	"https://github.com/arsv/riscv-qemu"	run "qemu-riscv32 ./olv"

-------------------------- MIPS64 ---------------------------------------------
run with "qemu-mips64el  -s 190000  ./olm2"

-------------------------- MIPS   ------------------
RCompiler.CompileM	OLR.MIPS.Linux0.Mod	OLR.Kernel.Mod	OLR.Modules.Mod	
	OLR.Files.Mod	OLR.FileDir.Mod	OLR.Objects.Mod	OLR.Display.Mod	OLR.Input.Mod	
	OLR.Fonts.Mod	ARM.Reals.Mod	OLR.Texts.Mod  Viewers.Mod	Oberon.Mod
	MenuViewers.Mod	OLR.TextFrames.Mod	OLR.System.Mod	OLR.Bitmaps.Mod	
	Out.Mod	Pictures.Mod	OLR.Centronics.Mod	OLR.V24.Mod	Printer.Mod	
	Edit.Mod	Styles.Mod	ScriptFrames.Mod	Script.Mod	OLR.Compiler.Mod	OLR.FileTools.Mod
	ROPM.Mod	ROPS.Mod	ROPT.Mod	ROPB.Mod	ROPP.Mod	MOPL.Mod	MOPC.Mod	MOPV.Mod
	ROP2.Mod	OLR.RBootLinker.Mod	M2Decoder.Mod	OLR.Browser.Mod ../Hennessy3.pm.Mod~
RBootLinker.Link   olm2\em := Linux0 Kernel Modules  ~

------------------------------ system ------------------------------
=> in /tmp , untar system030105d.tgz

FileTools.CopyTo	/tmp/olr/mips/	./mips/	Files.Obj FileDir.Obj Objects.Obj Display.Obj Input.Obj Viewers.Obj Fonts.Obj
	Reals.Obj Texts.Obj Oberon.Obj MenuViewers.Obj TextFrames.Obj System.Obj Bitmaps.Obj Out.Obj Pictures.Obj Centronics.Obj V24.Obj 
	Printer.Obj Edit.Obj Styles.Obj ScriptFrames.Obj Script.Obj Dates.Obj	Browser.Obj	Hennessy.Obj	Hennessy.Sym
	ROPM.Obj ROPS.Obj ROPT.Obj ROPB.Obj ROPP.Obj MOPL.Obj MOPC.Obj MOPV.Obj RCompiler.Obj Compiler.Obj	M2Decoder.Obj
	Linux0.Sym Kernel.Sym Modules.Sym Files.Sym FileDir.Sym Objects.Sym Display.Sym Input.Sym Viewers.Sym Fonts.Sym
	Reals.Sym Texts.Sym Oberon.Sym MenuViewers.Sym TextFrames.Sym System.Sym Bitmaps.Sym Out.Sym Pictures.Sym Centronics.Sym V24.Sym 
	Printer.Sym Edit.Sym Styles.Sym ScriptFrames.Sym Script.Sym Dates.Sym	Browser.Sym	
	ROPM.Sym ROPS.Sym ROPT.Sym ROPB.Sym ROPP.Sym MOPL.Sym MOPC.Sym MOPV.Sym RCompiler.Sym Compiler.Sym	M2Decoder.Sym~

FileTools.CopyTo	/tmp/olr/riscv/	./riscv/	Files.Obj FileDir.Obj Objects.Obj Display.Obj Input.Obj Viewers.Obj Fonts.Obj
	Reals.Obj Texts.Obj Oberon.Obj MenuViewers.Obj TextFrames.Obj System.Obj Bitmaps.Obj Out.Obj Pictures.Obj Centronics.Obj V24.Obj 
	Printer.Obj Edit.Obj Styles.Obj ScriptFrames.Obj Script.Obj Dates.Obj	Browser.Obj	Hennessy.Obj	Hennessy.Sym
	ROPM.Obj ROPS.Obj ROPT.Obj ROPB.Obj ROPP.Obj VOPL.Obj VOPC.Obj VOPV.Obj RCompiler.Obj Compiler.Obj	VDecoder.Obj
	Linux0.Sym Kernel.Sym Modules.Sym Files.Sym FileDir.Sym Objects.Sym Display.Sym Input.Sym Viewers.Sym Fonts.Sym
	Reals.Sym Texts.Sym Oberon.Sym MenuViewers.Sym TextFrames.Sym System.Sym Bitmaps.Sym Out.Sym Pictures.Sym Centronics.Sym V24.Sym 
	Printer.Sym Edit.Sym Styles.Sym ScriptFrames.Sym Script.Sym Dates.Sym	Browser.Sym
	ROPM.Sym ROPS.Sym ROPT.Sym ROPB.Sym ROPP.Sym VOPL.Sym VOPC.Sym VOPV.Sym RCompiler.Sym Compiler.Sym	VDecoder.Sym~

FileTools.CopyTo	/tmp/olr/armv7/	./armv7/	Files.Obj FileDir.Obj Objects.Obj Display.Obj Input.Obj Viewers.Obj Fonts.Obj
	Reals.Obj Texts.Obj Oberon.Obj MenuViewers.Obj TextFrames.Obj System.Obj Bitmaps.Obj Out.Obj Pictures.Obj Centronics.Obj V24.Obj 
	Printer.Obj Edit.Obj Styles.Obj ScriptFrames.Obj Script.Obj Dates.Obj	Browser.Obj	Hennessy.Obj	Hennessy.Sym
	ROPM.Obj ROPS.Obj ROPT.Obj ROPB.Obj ROPP.Obj AOPL.Obj AOPC.Obj AOPV.Obj RCompiler.Obj Compiler.Obj	A32Decoder.Obj
	Linux0.Sym Kernel.Sym Modules.Sym Files.Sym FileDir.Sym Objects.Sym Display.Sym Input.Sym Viewers.Sym Fonts.Sym
	Reals.Sym Texts.Sym Oberon.Sym MenuViewers.Sym TextFrames.Sym System.Sym Bitmaps.Sym Out.Sym Pictures.Sym Centronics.Sym V24.Sym 
	Printer.Sym Edit.Sym Styles.Sym ScriptFrames.Sym Script.Sym Dates.Sym 
	ROPM.Sym ROPS.Sym ROPT.Sym ROPB.Sym ROPP.Sym AOPL.Sym AOPC.Sym AOPV.Sym RCompiler.Sym Compiler.Sym	A32Decoder.Sym~

FileTools.CopyTo	/tmp/olr/ ""   
	OLR.MIPS.Linux0.Mod OLR.RISCV.Linux0.Mod OLR.ARM.Linux0.Mod OLR.Kernel.Mod OLR.Modules.Mod 
	OLR.Browser.Mod	OLR.System.Mod OLR.Files.Mod OLR.FileDir.Mod OLR.Objects.Mod OLR.Display.Mod OLR.Input.Mod Viewers.Mod
	OLR.Fonts.Mod ARM.Reals.Mod OLR.Texts.Mod OLR.TextFrames.Mod OLR.Bitmaps.Mod	OLR.FileTools.Mod	OLR.Compiler.Mod

	OLR.Centronics.Mod OLR.V24.Mod

	ROPM.Mod	ROPS.Mod	ROPT.Mod	ROPB.Mod	ROPP.Mod	ROP2.Mod	OLR.RBootLinker.Mod
	MOPL.Mod	MOPC.Mod	MOPV.Mod	M2Decoder.Mod	OLR.MPeephole.Mod
	VOPL.Mod	VOPC.Mod	VOPV.Mod	VDecoder.Mod
	AOPL.Mod	AOPC.Mod	AOPV.Mod	A32Decoder.Mod

	OLR.ROP2.System.Tool => System.Tool Files.Tool OLR.Make.Tool	ROP2Errors.Text
	OLR.Oberon.Text => Oberon.Text	OLR.System.Text => System.Text 
	ola3 => ola3\x olm2 => olm\x olv2 => olv\x oberon => oberon\x 

	OLR.Gadgets.Tool	OLR.BIT.Mod	ARM.Math.Mod	ARM.MathL.Mod	OLR.HPLaserPrinter.Mod	OLR.HPPCL.Mod
	OLR.ZlibBuffers.Mod	OLR.ZlibDeflate.Mod	OLR.ZlibWriters.Mod	OLR.ZlibInflate.Mod	OLR.ZlibReaders.Mod	OLR.Zip.Mod
	OLR.GZReaders.Mod OLR.GZWriters.Mod	OLR.Types.Mod	OLR.Lists.Mod	OLR.Directories.Mod	OLR.Desktops.Mod	
	OLR.EditTools.Mod	OLR.XPM.Mod	OLR.PPM.Mod	OLR.Displays.Colors.Mod	OLR.Images.Mod	OLR.JPEGImages.Mod	OLR.MIME.Mod	
	OLR.XBrowser.Mod	OLR.Builder.Mod	OLR.Watson0.Mod	OLR.Watson.Mod	ARM.NetTools.Mod	OLR.LeoTools.Mod

	OLR.GfxFonts0.Mod	OLR.GfxPS.Mod	OLR.GfxPKFonts.Mod	OLR.LeoPanels.Mod	OLR.LeoLists.Mod	OLR.LeoTools.Mod	OLR.Scheme.Mod
	OLR.Vinci.Mod	OLR.Snapshot.Mod	OLR.Find.Mod	

	OLR.Layouts.Mod	OLR.Dim3Engine.Mod	OLR.Find.Mod	OLR.FontEditor.Mod	UnZip.Mod
	OLR.Asteroids.Mod	../Hennessy3.pm.Mod => Hennessy3.pm.Mod  ../BENCH.pm.Mod => BENCH.pm.Mod	
~

=> tar czf olr.ROP2.170213.tgz olr/*

