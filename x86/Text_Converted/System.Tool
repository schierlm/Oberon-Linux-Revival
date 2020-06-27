See OLR.Gadgets.Tool to build Gadgets
Desktops.Open Oberon.Desk

See OLR.Make.Tool for instructions to build the system.

System.Open ^ OLR.Make.Tool
  Edit.Tool  Script.Tool  Miscellaneous.Tool
  Compiler.Tool  Oberon.Text

System.Recall previously closed viewer

Edit.Open ^  Edit.Show ^  
Edit.Recall previously deleted text

XCompiler.Compile *	(x86)
RCompiler.CompileM *	(MIPS)
ACompiler.Compile *\f  (ARM select PC in Trap)
Browser.ShowDef ^  

System.Directory  ^	OLR.*	ARM*	*.Mod
	*.Tool	*.Text	*.Pict	*.Graph  
	*.Obj	*.Bak	*.Arc	*.zip	*.Fnt

System.CopyFiles => ~
System.RenameFiles => ~
System.DeleteFiles  ~

System.ShowModules  System.Free ^
System.ShowCommands ^  System.State ^
System.ShowLibraries  System.FreeLibraries ^
System.ShowTasks  System.Watch  System.Collect
System.OpenKernelLog
System.Time ~ 25 12 95   13 10 0
! System.Quit
