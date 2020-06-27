	2016-11-29	ARM mature compiler: OLR.OBC.Mod faster load/store for global variables
	2017-02-13	make DIV and MOD for all non x86 targets OBERON compatible

ZipDocs.Mod missing not used?? Chech UnZip.Mod!
	2017-02-11	MOPL: fixed Load const with ODD(bit 15)
	2017-02-11	VOPL: changed Load const to MOPL version
	2017-02-13	make DIV and MOD for all non x86 targets OBERON compatible

-------------------------- X86 EOP2-compiler---------------------------------------------
XCompiler.Compile	OLR.X86.Linux0.Mod\s	OLR.X86.Kernel.Mod	OLR.Files.Mod	OLR.X86.Modules.Mod
	OLR.FileDir.Mod	OLR.Objects.Mod	OLR.Display.Mod	OLR.Input.Mod	
	OLR.Fonts.Mod	ARM.Reals.Mod	OLR.Texts.Mod  Viewers.Mod	Oberon.Mod
	MenuViewers.Mod	OLR.TextFrames.Mod	OLR.System.Mod	Bitmaps.Mod	
	Out.Mod	Pictures.Mod	OLR.Centronics.Mod	OLR.V24.Mod	Printer.Mod	
	Edit.Mod	Styles.Mod	ScriptFrames.Mod	Script.Mod	OLR.Compiler.Mod	OLR.FileTools.Mod
	OLR.OPM.Mod	OLR.OPS.Mod	OLR.OPT.Mod	OLR.OPB.Mod	OPA.Mod	OLR.OPP.Mod	OLR.OPO.Mod	OLR.OPL.Mod	OLR.OPC.Mod
	OLR.OPV.Mod	OLR.XCompiler.Mod	OLR.XBootLinker.Mod	OLR.XDecoder.Mod	OLR.X86.Browser.Mod~
XBootLinker.Link	olx2 \refs \integrate 8049000H x86/Linux0 x86/Kernel x86/Files x86/Modules ~

----------------------------ARM Ceres-based-compiler------------------------------- 
ACompiler.Compile \s	OLR.ARMl.Linux0.Mod	OLR.ARMl.Kernel.Mod\x	OLR.ARMl.Modules.Mod	
	OLR.Files.Mod	OLR.FileDir.Mod	OLR.Objects.Mod	OLR.Display.Mod\x	OLR.Input.Mod	
	OLR.Fonts.Mod	ARM.Reals.Mod	OLR.Texts.Mod  Viewers.Mod	Oberon.Mod
	MenuViewers.Mod	OLR.TextFrames.Mod	OLR.System.Mod	OLR.Bitmaps.Mod	
	Out.Mod	Pictures.Mod	OLR.Centronics.Mod	OLR.V24.Mod	Printer.Mod	
	Edit.Mod	Styles.Mod	ScriptFrames.Mod	Script.Mod	OLR.Compiler.Mod	OLR.FileTools.Mod
 	ARM.OBM.Mod	ARM.OBS.Mod	ARM.OBT.Mod	OLR.OBC.Mod	OLR.OBE.Mod	OLR.OBH.Mod 	OLR.OBA.Mod	ARM.ACompiler.Mod
	OLR.ABootLinker.Mod	OLR.ADecoder.Mod	OLR.ARMl.Browser.Mod Dates.Mod Strings.Mod ~ used in OBA.Mod
ABootLinker.Link   \q \Parm/	Modules  ~	Fixup errors in Linux0 during Linking can be ignored (missing SysHalt not used since unconditional RETURN used

------------------------------ system ------------------------------
=> in /tmp , untar system030105d.tgz

FileTools.CopyTo	/tmp/olr/x86/	./x86/	Linux0.Obj Kernel.Obj Modules.Obj  Files.Obj FileDir.Obj Objects.Obj Display.Obj Input.Obj Viewers.Obj Fonts.Obj
	Reals.Obj Texts.Obj Oberon.Obj MenuViewers.Obj TextFrames.Obj System.Obj Bitmaps.Obj Out.Obj Pictures.Obj Centronics.Obj V24.Obj Printer.Obj
	Edit.Obj Styles.Obj ScriptFrames.Obj Script.Obj	XBootLinker.Obj
	OPM.Obj OPS.Obj OPT.Obj OPB.Obj OPA.Obj OPP.Obj OPO.Obj OPL.Obj OPC.Obj OPV.Obj XCompiler.Obj Compiler.Obj Browser.Obj~

FileTools.CopyTo	/tmp/olr/arm/	./arm/	Files.Obj FileDir.Obj Objects.Obj Display.Obj Input.Obj Viewers.Obj Fonts.Obj
	Reals.Obj Texts.Obj Oberon.Obj MenuViewers.Obj TextFrames.Obj System.Obj Bitmaps.Obj Out.Obj Pictures.Obj Centronics.Obj V24.Obj 
	Printer.Obj Edit.Obj Styles.Obj ScriptFrames.Obj Script.Obj Dates.Obj Strings.Obj 
	OBM.Obj OBS.Obj OBT.Obj OBC.Obj OBE.Obj OBH.Obj OBA.Obj ACompiler.Obj Compiler.Obj	Browser.Obj	
	Linux0.Sym Kernel.Sym Modules.Sym Files.Sym FileDir.Sym Objects.Sym Display.Sym Input.Sym Viewers.Sym Fonts.Sym
	Reals.Sym Texts.Sym Oberon.Sym MenuViewers.Sym TextFrames.Sym System.Sym Bitmaps.Sym Out.Sym Pictures.Sym Centronics.Sym V24.Sym 
	Printer.Sym Edit.Sym Styles.Sym ScriptFrames.Sym Script.Sym Dates.Sym Strings.Sym 
	OBM.Sym OBS.Sym OBT.Sym OBC.Sym OBE.Sym OBH.Sym OBA.Sym ACompiler.Sym Compiler.Sym Browser.Sym	~

FileTools.CopyTo	/tmp/olr/ "" OLR.X86.Linux0.Mod OLR.X86.Kernel.Mod OLR.X86.Modules.Mod  
	OLR.MIPS.Linux0.Mod	OLR.RISCV.Linux0.Mod OLR.ARM.Linux0.Mod OLR.Kernel.Mod OLR.Modules.Mod 
	OLR.ARMl.Linux0.Mod	OLR.ARMl.Kernel.Mod OLR.ARMl.Modules.Mod OLR.ARM.SoftFloat.Mod OLR.ARM.HardFloat.Mod	
	OLR.ARMl.Browser.Mod	OLR.System.Mod OLR.Files.Mod OLR.FileDir.Mod OLR.Objects.Mod OLR.Display.Mod OLR.Input.Mod Viewers.Mod
	OLR.Fonts.Mod ARM.Reals.Mod OLR.Texts.Mod OLR.TextFrames.Mod OLR.Bitmaps.Mod	OLR.FileTools.Mod	OLR.Compiler.Mod

	OLR.Centronics.Mod OLR.V24.Mod  OLR.OPM.Mod	OLR.OPS.Mod	OLR.OPT.Mod	OLR.OPB.Mod	OLR.OPP.Mod	OLR.OPO.Mod	OLR.OPL.Mod
	OLR.OPC.Mod	OLR.XCompiler.Mod OLR.XBootLinker.Mod   OLR.OPV.Mod	OLR.XDecoder.Mod	OLR.X86.Browser.Mod

	ROPM.Mod	ROPS.Mod	ROPT.Mod	ROPB.Mod	ROPP.Mod
	MOPL.Mod	MOPC.Mod	MOPV.Mod	ROP2.Mod	M2Decoder.Mod	OLR.RBootLinker.Mod OLR.MPeephole.Mod
	VOPL.Mod	VOPC.Mod	VOPV.Mod	VDecoder.Mod	AOPL.Mod	AOPC.Mod	AOPV.Mod	A32Decoder.Mod

	ARM.OBM.Mod ARM.OBS.Mod ARM.OBT.Mod OLR.OBC.Mod OLR.OBE.Mod OLR.OBH.Mod OLR.OBA.Mod
	ARM.ACompiler.Mod OLR.ADecoder.Mod OLR.ABootLinker.Mod	

	OLR.System.Tool => System.Tool Files.Tool OLR.mature.Make.Tool	OROP2Errors.Text
	OLR.Oberon.Text => Oberon.Text	OLR.System.Text => System.Text	ARM.OberonErrors.Text 
	ola => ola\x  olx2 => olx\x oberon => oberon\x

	OLR.Gadgets.Tool	OLR.BIT.Mod	ARM.Math.Mod	ARM.MathL.Mod	OLR.HPLaserPrinter.Mod	OLR.HPPCL.Mod
	OLR.ZlibBuffers.Mod	OLR.ZlibDeflate.Mod	OLR.ZlibWriters.Mod	OLR.ZlibInflate.Mod	OLR.ZlibReaders.Mod	OLR.Zip.Mod
	OLR.GZReaders.Mod OLR.GZWriters.Mod	OLR.Types.Mod	OLR.Lists.Mod	OLR.Directories.Mod	OLR.Desktops.Mod	
	OLR.EditTools.Mod	OLR.XPM.Mod	OLR.PPM.Mod	OLR.Displays.Colors.Mod	OLR.Images.Mod	OLR.JPEGImages.Mod	OLR.MIME.Mod	
	OLR.Builder.Mod	OLR.Watson0.Mod	OLR.Watson.Mod	ARM.NetTools.Mod	OLR.LeoTools.Mod

	OLR.GfxFonts0.Mod	OLR.GfxPS.Mod	OLR.GfxPKFonts.Mod	OLR.LeoPanels.Mod	OLR.LeoLists.Mod	OLR.LeoTools.Mod	OLR.Scheme.Mod
	OLR.Vinci.Mod	OLR.Snapshot.Mod	OLR.Find.Mod	

	OLR.Layouts.Mod	OLR.Dim3Engine.Mod	OLR.Find.Mod	OLR.FontEditor.Mod	UnZip.Mod
	OLR.Asteroids.Mod	../Hennessy3.pm.Mod => Hennessy3.pm.Mod  ../BENCH.pm.Mod => BENCH.pm.Mod	
~
=> tar czf olr.mature.170113.tgz olr/*

