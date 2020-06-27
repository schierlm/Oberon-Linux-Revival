MODULE Compiler;

IMPORT Linux0, Modules;

PROCEDURE CompileA*;
VAR c: Modules.Command;
BEGIN
	c:= Modules.ThisCommand(Modules.ThisMod("ACompiler"), "Compile");
	IF c#NIL THEN c END;
END CompileA;

PROCEDURE CompileX*;
VAR c: Modules.Command;
BEGIN
	c:= Modules.ThisCommand(Modules.ThisMod("XCompiler"), "Compile");
	IF c#NIL THEN c END;
END CompileX;

PROCEDURE CompileM*;
VAR c: Modules.Command;
BEGIN
	c:= Modules.ThisCommand(Modules.ThisMod("RCompiler"), "CompileM");
	IF c#NIL THEN c END;
END CompileM;

PROCEDURE CompileV*;
VAR c: Modules.Command;
BEGIN
	c:= Modules.ThisCommand(Modules.ThisMod("RCompiler"), "CompileV");
	IF c#NIL THEN c END;
END CompileV;

PROCEDURE Compile*;
BEGIN
	IF Linux0.ARCH="ARM" THEN CompileA;
	ELSIF Linux0.ARCH="X86" THEN CompileX;
	ELSIF Linux0.ARCH="MIPS" THEN CompileM; 
	ELSIF Linux0.ARCH="RISC-V" THEN CompileV;
	END;
END Compile;

PROCEDURE CompileAll*;
BEGIN
	CompileA;
	CompileX;
	CompileM;
	CompileV;
END CompileAll;
	
END Compiler.

Compiler.CompileAll Test.Mod ~
Compiler.Compile Test.Mod\s ~
Compiler.Compile Test.Mod\sX.Obx ~
Compiler.Compile *
Compiler.Compile *\s
Compiler.Compile \.Obx Test.Mod Test.Mod\.Obf Test.Mod ~
Compiler.Compile @
