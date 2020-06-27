MODULE RCompiler;	(* RC 6.3.89 / 17.6.93 *)	(* object model 19.1.94 *)

(*
		Peter Matthias
		2016-03-18	made back end pluggable
		2016-11-11	output code directory OPM.Dir
		2017-05-09	added "d" option in OPM.opt for softdiv necessary for Cortex A8 and A9
		2017-06-12	added global options for RCompiler.CompileX \globaloptions  file ... ~
*)

	IMPORT
		Modules, Texts, TextFrames, Viewers, Oberon,
		OPM :=ROPM, OPT := ROPT, OPP := ROPP, Linux0;
	
	CONST
		mipstag=0F9X; mipsttag= 0FAX; armv7tag=0FBX; armv8tag=0FCX; riscvtag=0FDX;	(* same as in RBootLinker *)
		OptionChar = "\";
		SignOnMessage = "ROP2 Compiler  RC  10.2.94; p.m. 2016-11-22";

		(* compiler options: *)
		inxchk = 0;	(* index check on *)
		ovflchk = 1;	(* overflow check on *)
		ranchk = 2;	(* range check on *)
		typchk = 3;	(* type check on *)
		newsf = 4;	(* generation of new symbol file allowed *)
		ptrinit = 5;	(* pointer initialization *)
		intprinf = 6;	(* inter-procedural information about register allocation used *)
		assert = 7;	(* assert evaluation *)
		findpc = 8;	(* find text position of breakpc *)
		extsf = 9;	(* extension of old symbol file allowed *)
		defopt = {inxchk, typchk, ptrinit, assert};	(* default options *)
		softdiv= 10;

	VAR
		(* global because of the GC call on Ceres *)
		source: Texts.Text;
		sourceR: Texts.Reader;
		S: Texts.Scanner;
		v: Viewers.Viewer;
		W: Texts.Writer;
		OPV: Modules.Module;
		globopt: SET;

PROCEDURE SetOpt( VAR opt: SET; ch: CHAR);
BEGIN
	IF ch = "x" THEN opt :=opt / {inxchk}
	ELSIF ch = "v" THEN opt := opt / {ovflchk}
	ELSIF ch = "r" THEN opt := opt / {ranchk}
	ELSIF ch = "t" THEN opt := opt / {typchk}
	ELSIF ch = "s" THEN opt := opt / {newsf}
	ELSIF ch = "p" THEN opt := opt / {ptrinit}
	ELSIF ch = "i" THEN opt := opt / {intprinf}
	ELSIF ch = "a" THEN opt := opt / {assert}
	ELSIF ch = "f" THEN opt := opt / {findpc}
	ELSIF ch = "e" THEN opt := opt / {extsf}
	ELSIF ch = "d" THEN opt := opt / {softdiv}
	END
END SetOpt;

	PROCEDURE Module*(source: Texts.Reader; options: ARRAY OF CHAR; log: Texts.Text; VAR error: BOOLEAN);
		VAR ch: CHAR; i: INTEGER; ext, new: BOOLEAN; cmd: Modules.Command;
	BEGIN
		OPM.opt := globopt; i := 0;
		REPEAT
			ch:=options[i]; INC(i);
			SetOpt( OPM.opt, ch);
		UNTIL ch = 0X;
		OPM.Init( source, log);
		OPP.Module(OPT.prog, OPM.opt);
		IF OPM.noerr THEN
			cmd:=Modules.ThisCommand(OPV, "Init");
			IF cmd=NIL THEN Texts.WriteLn(W); Texts.WriteString(W, "OPV.Init not found"); Texts.Append(Oberon.Log, W.buf);
			ELSE
				cmd; OPT.Export(ext, new);
				IF OPM.noerr THEN
					cmd:=Modules.ThisCommand(OPV, "Module");
					IF cmd=NIL THEN Texts.WriteLn(W); Texts.WriteString(W, "OPV.Module not found"); Texts.Append(Oberon.Log, W.buf);
					ELSE
						cmd;
						IF OPM.noerr THEN
							IF new OR ext THEN OPM.RegisterNewSym END ;
							IF new THEN OPM.LogWStr(" new symbol file")
							ELSIF ext THEN OPM.LogWStr(" extended symbol file")
							END ;
							OPM.LogWNum(4*OPM.pc, 8); OPM.LogWNum(-OPM.sb, 8);
						ELSE OPM.DeleteNewSym; 
						END
					END;
				END;
			END;
		END;
		OPT.Close;
		OPM.LogWLn; error := ~OPM.noerr;
	END Module;

	PROCEDURE Compile0;
		VAR beg, end, time: LONGINT; error: BOOLEAN; ch: CHAR; 

		PROCEDURE Do(filename: ARRAY OF CHAR; beg: LONGINT);
			VAR S1: Texts.Scanner; line, i: INTEGER; options: ARRAY 32 OF CHAR;
				fbeg, fend, ftime: LONGINT; ftext: Texts.Text; f: BOOLEAN;
		BEGIN
			Texts.WriteString(W, filename); Texts.WriteString(W, "  compiling  "); Texts.WriteString(W, OPM.Dir);
			Texts.OpenScanner(S1, source, beg); Texts.Scan(S1);
			IF (S1.class = Texts.Name) & (S1.s = "MODULE") THEN
				Texts.Scan(S1);
				IF S1.class = Texts.Name THEN Texts.WriteString(W, S1.s) END
			END ;
			Texts.Append(Oberon.Log, W.buf);
			line := S.line; i := 0; f := FALSE;
			Texts.Scan(S);
			IF (S.line = line) & (S.class = Texts.Char) & (S.c = OptionChar) THEN
				ch := S.nextCh;
				WHILE ((ch >= "0") & (ch <= "9") OR (ch >= "a") & (ch <= "z")) & (i < LEN(options) - 1) DO
					options[i] := ch; INC(i);
					IF ch = "f" THEN f := ~f END ;
					Texts.Read(S, ch)
				END ;
				S.nextCh := ch; Texts.Scan(S)
			END ;
			options[i] := 0X;
			IF f THEN
				LOOP
					Oberon.GetSelection(ftext, fbeg, fend, ftime);
					IF ftime >=0 THEN
						Texts.OpenScanner(S1, ftext, fbeg); Texts.Scan(S1);
						IF S1.class = Texts.Int THEN OPM.breakpc := S1.i; EXIT END
					END ;
					Texts.WriteString(W, "  pc not selected"); Texts.WriteLn(W);
					Texts.Append(Oberon.Log, W.buf); error := TRUE; RETURN
				END
			END ;
			Texts.OpenReader(sourceR, source, beg);
			Module(sourceR, options, Oberon.Log, error)
		END Do;
	
	BEGIN
		error := FALSE;	globopt:= defopt;
		Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos); Texts.Scan(S);
		IF (S.class = Texts.Char) & (S.c # OptionChar) THEN
			IF S.c = "*" THEN
				v := Oberon.MarkedViewer();
				IF (v.dsc # NIL) & (v.dsc.next IS TextFrames.Frame) THEN
					source := v.dsc.next(TextFrames.Frame).text; Do("", 0)
				END
			ELSIF S.c = "^" THEN
				Oberon.GetSelection(source, beg, end, time);
				IF time >= 0 THEN
					Texts.OpenScanner(S, source, beg); Texts.Scan(S); NEW(source); 
					WHILE (S.class = Texts.Name) & (Texts.Pos(S) - S.len <= end) & ~error DO
						Texts.Open(source, S.s);
						IF source.len # 0 THEN Do(S.s, 0)
						ELSE
							Texts.WriteString(W, S.s); Texts.WriteString(W, " not found");
							Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf); error := TRUE
						END
					END
				END
			ELSIF S.c = "@" THEN
				Oberon.GetSelection(source, beg, end, time);
				IF time >= 0 THEN Do("", beg) END
			END
		ELSE
			IF (S.class = Texts.Char) & (S.c = OptionChar) THEN
				ch := S.nextCh;
				WHILE (ch >= "a") & (ch <= "z") DO
					SetOpt( globopt, ch);
					Texts.Read(S, ch)
				END ;
				S.nextCh := ch; Texts.Scan(S);
			END;

			NEW(source);
			WHILE (S.class = Texts.Name) & ~error DO
				Texts.Open(source, S.s);
				IF source.len # 0 THEN Do(S.s, 0)
				ELSE
					Texts.WriteLn(W); Texts.WriteString(W, S.s); Texts.WriteString(W, " not found");
					Texts.Append(Oberon.Log, W.buf); error := TRUE
				END
			END
		END;
		Oberon.Collect()
	END Compile0;

PROCEDURE Compile1(mod, dir: ARRAY OF CHAR; tag: CHAR);
BEGIN
	OPV:=Modules.ThisMod(mod);
	IF OPV=NIL THEN Texts.WriteString(W, mod); Texts.WriteString(W, " Module not found"); Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf);
	ELSE
		OPM.OFtag := tag;
		COPY(dir, OPM.Dir);
		Compile0;
	END;
END Compile1;

PROCEDURE CompileA*;
BEGIN	Compile1("AOPV", "armv7/", armv7tag);
END CompileA;

PROCEDURE CompileM*;
BEGIN	Compile1("MOPV", "mips/", mipstag);
END CompileM;

PROCEDURE CompileT*;
BEGIN	Compile1("TOPV", "test/", mipsttag);
END CompileT;

PROCEDURE CompileV*;
BEGIN	Compile1("VOPV", "riscv/", riscvtag);
END CompileV;

PROCEDURE Compile*;
BEGIN
	IF Linux0.ARCH="MIPS" THEN Compile1("MOPV", "mips/", mipstag);
	ELSIF  Linux0.ARCH="RISC-V" THEN Compile1("VOPV", "riscv/", riscvtag);
	ELSE Compile1("AOPV", "armv7/", armv7tag)
	END; 
END Compile;


BEGIN
	Texts.OpenWriter(W); Texts.WriteString(W, SignOnMessage); Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
END RCompiler.

RCompiler.CompileA *
RCompiler.CompileM *
RCompiler.CompileT *
RCompiler.CompileV *
System.Free VOPV VOPC VOPL ~