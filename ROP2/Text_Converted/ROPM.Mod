MODULE ROPM;	(* RC 6.3.89 / 9.2.94 *)	(* object model 9.2.94 *)
(* Machine dependent constants needed before code generation *)
(* Host interface *)
(* 
		p.m.: changed tag nrs 
		2015-01-28	MakeFileName using directory "arm6/"
		2015-04-17	skip Objects in Get
		2015-06-03	set MinHaltNr. to 32, MaxHaltNr to MaxHaltNr+MinHaltNr
		2015-09-01	removed LEHost, directory; renamed to ROPM.Mod; MakeFilename using "Dir" prefix
		2016-03-18	exported pc, sb so that compiler does not need to import OPL; exported opt, breakpc
		2017-01-21	set NEWusingAdr* = FALSE; MaxHaltNr* = 255;

*)

	IMPORT Fonts, Texts, Oberon, Files, SYSTEM;

	CONST (* MIPS II, RISC-V, ARM6T2 *)
		
		(* basic type sizes *)
		ByteSize* = 1;	(* SYSTEM.BYTE *)
		CharSize* = 1;	(* CHAR *)
		BoolSize* = 1;	(* BOOLEAN *)
		SetSize* = 4;	(* SET *)
		SIntSize* = 1;	(* SHORTINT *)
		IntSize* = 2;	(* INTEGER *)
		LIntSize* = 4;	(* LONGINT *)
		RealSize* = 4;	(* REAL *)
		LRealSize* = 8;	(* LONGREAL *)
		ProcSize* = 4;	(* PROCEDURE type *)
		PointerSize* = 4;	(* POINTER type *)

		(* value of constant NIL *)
		nilval* = 0;
		
		(* target machine minimum values of basic types expressed in host machine format: *)
		MinSInt* = -80H;
		MinInt* = -8000H;
		MinLInt* =  80000000H;	(*-2147483648*)
		MinRealPat = 0FF7FFFFFH;	(* most  negative, 32-bit pattern *)
		MinLRealPatL = 0FFFFFFFFH;	(* most  negative, lower 32-bit pattern *)
		MinLRealPatH = 0FFEFFFFFH;	(* most  negative, higher 32-bit pattern *)
		
		(* target machine maximum values of basic types expressed in host machine format: *)
		MaxSInt* = 7FH;
		MaxInt* = 7FFFH;
		MaxLInt* = 7FFFFFFFH;	(*2147483647*)
		MaxSet* = 31;	(* must be >= 15, else the bootstrapped compiler cannot run (IN-tests) *)
		MaxRealPat = 7F7FFFFFH;	(* most positive, 32-bit pattern *)
		MaxLRealPatL = 0FFFFFFFFH;	(* most positive, lower 32-bit pattern *)
		MaxLRealPatH = 7FEFFFFFH;		(* most positive, higher 32-bit pattern *)
		
		(* maximal index value for array declaration: *)
		MaxIndex* = MaxLInt;
		
		(* parameterization of numeric scanner: *)
		MaxHDig* = 8;	(* maximal hexadecimal longint length *)
		MaxRExp* = 38;	(* maximal real exponent *)
		MaxLExp* = 308;	(* maximal longreal exponent *)
		
		(* inclusive parameter range for standard procedure HALT: *)
		MinHaltNr* = 32;
		MaxHaltNr* = 255;	(* was 255+MinHaltNr *)
		
		(* inclusive range of register number for procedures SYSTEM.GETREG and SYSTEM.PUTREG: *)
		MinRegNr* = 0;
		MaxRegNr* = 79;	(* 0..31: r0-r31, 32..63: f0-f31, 64..79: CP0 r0..r15 *)
		
		(* maximal flag value used to mark interface structures: *)
		MaxSysFlag* = 0;	(* MIPS R2000: only 0 is valid, not used *)
		
		(* maximal condition value of parameter for SYSTEM.CC: *)
		MaxCC* = -1;	(* MIPS R2000: not used *)
		
		(* initialization of constant address, must be different from any valid constant address: *)
		ConstNotAlloc* = -1;	(* MIPS R2000: strings and reals are allocated *)
		
		(* maximal number of cases in a case statement: *)
		MaxCases* = 128;
		
		(* maximal range of a case statement (higher label - lower label ~ jump table size): *)
		MaxCaseRange* = 512;
		
		(* whether hidden pointer fields have to be nevertheless exported: *)
		ExpHdPtrFld* = TRUE;
		HdPtrName* = "@ptr";

		(* whether hidden procedure fields have to be nevertheless exported (may be used for System.Free): *)
		ExpHdProcFld* = FALSE;
		HdProcName* = "@proc";
		
		(* whether hidden bound procedures have to be nevertheless exported: *)
		ExpHdTProc* = FALSE;
		HdTProcName* = "@tproc";

		(* maximal number of hidden fields in an exported record: *)
		MaxHdFld* = 512;

		(* maximal number of exported stuctures: *)
		MaxStruct* = 256;	(* must be < MAX(INTEGER) DIV 2 in object model *)
		
		(* maximal number of pointer fields in a record: *)
		MaxPtr* = 16384;
		
		(* maximal number of global pointers: *)
		MaxGPtr* = 16384;
		
		(* whether field leaf of pointer variable p has to be set to FALSE, when NEW(p) or SYSTEM.NEW(p, n) is used: *)
		NEWusingAdr* = TRUE;	(* for ARMv7, was FALSE *)
		
		(* special character (< " ") returned by procedure Get, if end of text reached *)
		Eot* = 0X;

	TYPE
		FileName = ARRAY 32 OF CHAR;

	VAR
		MinReal*, MaxReal*: REAL;
		MinLReal*, MaxLReal*: LONGREAL;
		noerr*: BOOLEAN;	(* no error found until now *)
		curpos*, errpos*: LONGINT;	(* character and error position in source file *)
		breakpc*: LONGINT;	(* set by Compiler.Module *)
		objname*: ARRAY 64 OF CHAR;
		OFtag*: CHAR;	(* set in compiler module *)
		Dir*: FileName;
		pc*, sb*: LONGINT;
		opt*: SET;

	CONST
		SFext = ".Sym";
		OFext = ".Obj";
		SFtag = 0FAX;	(* symbol file tag, was 0FAX *)
(*		OFtag = 0F9X;	 object file tag, was 0F9X for MIPS*)
		
	VAR
		lastpos: LONGINT;	(* last position error in source file *)
		inR: Texts.Reader;
		Log: Texts.Text;
		W: Texts.Writer;
		oldSF, newSF, ObjF, RefF: Files.Rider;
		oldSFile, newSFile, ObjFile, RefFile: Files.File;
		
	PROCEDURE Init*(source: Texts.Reader; log: Texts.Text);
	BEGIN inR := source; Log := log;
		noerr := TRUE; curpos := Texts.Pos(inR); errpos := curpos; lastpos := curpos-10
	END Init;
	
	PROCEDURE Get*(VAR ch: CHAR);	(* read next character from source text, Eot if no more *)
	BEGIN
		(* System3 get: skip embedded objects *)
		REPEAT
			Texts.Read(inR, ch); INC(curpos)
		UNTIL inR.eot OR ((inR.lib # NIL) & (inR.lib IS Fonts.Font))
	END Get;
	
	PROCEDURE MakeFileName(VAR name, FName: ARRAY OF CHAR; ext: ARRAY OF CHAR);
		VAR i, j: LONGINT; ch: CHAR;
	BEGIN
		j:=0;
		WHILE Dir[j]#0X DO
			FName[j]:=Dir[j]; INC(j);
		END;
		i := 0;
		LOOP ch := name[i];
			IF ch = 0X THEN EXIT END ;
			FName[j] := ch; INC(i); INC(j);
		END ;
		i := 0;
		REPEAT ch := ext[i]; FName[j] := ch; INC(i); INC(j)
		UNTIL ch = 0X
	END MakeFileName;
	
	(* ------------------------- Log Output ------------------------- *)
	
	PROCEDURE LogW*(ch: CHAR);
	BEGIN
		Texts.Write(W, ch); Texts.Append(Log, W.buf)
	END LogW;
	
	PROCEDURE LogWStr*(s: ARRAY OF CHAR);
	BEGIN
		Texts.WriteString(W, s); Texts.Append(Log, W.buf)
	END LogWStr;
	
	PROCEDURE LogWNum*(i, len: LONGINT);
	BEGIN
		Texts.WriteInt(W, i, len); Texts.Append(Log, W.buf)
	END LogWNum;

	PROCEDURE LogWHex*(i: LONGINT);
	BEGIN
		Texts.WriteHex(W, i); Texts.Write(W, "H"); Texts.Append(Log, W.buf)
	END LogWHex;

	PROCEDURE LogWLn*;
	BEGIN
		Texts.WriteLn(W); Texts.Append(Log, W.buf)
	END LogWLn;
	
	PROCEDURE Mark*(n: INTEGER; pos: LONGINT);
	BEGIN
		IF n >= 0 THEN
			noerr := FALSE;
			IF (pos < lastpos) OR (lastpos + 9 < pos) THEN lastpos := pos; LogWLn; LogWStr("  ");
				IF n < 249 THEN LogWStr("  pos"); LogWNum(pos, 6); LogWStr("  err"); LogWNum(n, 4)
				ELSIF n = 255 THEN LogWStr("pos"); LogWNum(pos, 6); LogWStr("  pc "); LogWHex(breakpc)
				ELSIF n = 254 THEN LogWStr("pc not found")
				ELSE LogWStr(objname);
					IF n = 253 THEN LogWStr(" is new, compile with \e")
					ELSIF n = 252 THEN LogWStr(" is redefined, compile with \s")
					ELSIF n = 251 THEN LogWStr(" is redefined (private part only), compile with \s")
					ELSIF n = 250 THEN LogWStr(" is no longer visible, compile with \s")
					ELSIF n = 249 THEN LogWStr(" is not consistently imported, recompile imports")
					END
				END
			END
		ELSE
			LogWLn; LogWStr("  pos"); LogWNum(pos, 6); LogWStr("  warning"); LogWNum(-n, 4)
		END
	END Mark;
	
	PROCEDURE err*(n: INTEGER);
	BEGIN Mark(n, errpos)
	END err;

	PROCEDURE FPrint*(VAR fp: LONGINT; val: LONGINT);
	BEGIN
		fp := SYSTEM.ROT(SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, fp) / SYSTEM.VAL(SET, val)), 1)
	END FPrint;

	PROCEDURE FPrintSet*(VAR fp: LONGINT; set: SET);
	BEGIN FPrint(fp, SYSTEM.VAL(LONGINT, set))
	END FPrintSet;

	PROCEDURE FPrintReal*(VAR fp: LONGINT; real: REAL);
	BEGIN FPrint(fp, SYSTEM.VAL(LONGINT, real))
	END FPrintReal;

	PROCEDURE FPrintLReal*(VAR fp: LONGINT; lr: LONGREAL);
		VAR l, h: LONGINT;
	BEGIN
		SYSTEM.GET(SYSTEM.ADR(lr), l); SYSTEM.GET(SYSTEM.ADR(lr)+4, h);
		FPrint(fp, l); FPrint(fp, h)
	END FPrintLReal;

	(* ------------------------- Read Symbol File ------------------------- *)
	
	PROCEDURE SymRCh*(VAR ch: CHAR);
	BEGIN Files.Read(oldSF, ch)
	END SymRCh;
	
	PROCEDURE SymRInt*(): LONGINT;
		VAR k: LONGINT;
	BEGIN Files.ReadNum(oldSF, k); RETURN k
	END SymRInt;
		
	PROCEDURE SymRSet*(VAR s: SET);
		VAR j: LONGINT;
	BEGIN Files.ReadNum(oldSF, j); s := SYSTEM.VAL(SET, j)
	END SymRSet;

	PROCEDURE SymRReal*(VAR r: REAL);
	BEGIN Files.ReadReal(oldSF, r)
	END SymRReal;
	
	PROCEDURE SymRLReal*(VAR lr: LONGREAL);
	BEGIN Files.ReadLReal(oldSF, lr)
	END SymRLReal;
	
	PROCEDURE CloseOldSym*;
	END CloseOldSym;

	PROCEDURE OldSym*(VAR modName: ARRAY OF CHAR; VAR done: BOOLEAN);
		VAR ch: CHAR; fileName: FileName;
	BEGIN MakeFileName(modName, fileName, SFext);
		oldSFile := Files.Old(fileName); done := oldSFile # NIL;
		IF done THEN
			Files.Set(oldSF, oldSFile, 0); Files.Read(oldSF, ch);
			IF ch # SFtag THEN err(151);  (*not a symbol file*)
				CloseOldSym; done := FALSE
			END
		END
	END OldSym;
	
	PROCEDURE eofSF*(): BOOLEAN;
	BEGIN RETURN oldSF.eof
	END eofSF;
	
	(* ------------------------- Write Symbol File ------------------------- *)
	
	PROCEDURE SymWCh*(ch: CHAR);
	BEGIN Files.Write(newSF, ch)
	END SymWCh;

	PROCEDURE SymWInt*(i: LONGINT);
	BEGIN Files.WriteNum(newSF, i)
	END SymWInt;

	PROCEDURE SymWSet*(s: SET);
	BEGIN Files.WriteNum(newSF, SYSTEM.VAL(LONGINT, s))
	END SymWSet;

	PROCEDURE SymWReal*(r: REAL);
	BEGIN Files.WriteReal(newSF, r)
	END SymWReal;
	
	PROCEDURE SymWLReal*(lr: LONGREAL);
	BEGIN Files.WriteLReal(newSF, lr)
	END SymWLReal;
	
	PROCEDURE RegisterNewSym*;
	BEGIN Files.Register(newSFile)
	END RegisterNewSym;
	
	PROCEDURE DeleteNewSym*;
	END DeleteNewSym;

	PROCEDURE NewSym*(VAR modName: ARRAY OF CHAR);
		VAR fileName: FileName;
	BEGIN MakeFileName(modName, fileName, SFext);
		newSFile := Files.New(fileName);
		IF newSFile # NIL THEN Files.Set(newSF, newSFile, 0); Files.Write(newSF, SFtag)
		ELSE err(153)
		END
	END NewSym;

	(* ------------------------- Write Reference & Object Files ------------------------- *)

	PROCEDURE RefW*(ch: CHAR);
	BEGIN Files.Write(RefF, ch)
	END RefW;

	PROCEDURE RefWNum*(i: LONGINT);
	BEGIN Files.WriteNum(RefF, i)
	END RefWNum;

	PROCEDURE ObjW*(ch: CHAR);
	BEGIN Files.Write(ObjF, ch)
	END ObjW;

	PROCEDURE ObjWNum*(i: LONGINT);
	BEGIN Files.WriteNum(ObjF, i)
	END ObjWNum;

	PROCEDURE ObjWInt(i: INTEGER);
	BEGIN Files.WriteInt(ObjF, i)
	END ObjWInt;

	PROCEDURE ObjWLInt*(i: LONGINT);
	BEGIN Files.WriteLInt(ObjF, i)
	END ObjWLInt;

	PROCEDURE ObjWBytes*(VAR bytes: ARRAY OF SYSTEM.BYTE; n: LONGINT);
	BEGIN Files.WriteBytes(ObjF, bytes, n)
	END ObjWBytes;

	PROCEDURE NewRefObj*(VAR modName: ARRAY OF CHAR);
		VAR FName: ARRAY 32 OF CHAR; dummyL: LONGINT; dummy: INTEGER;
	BEGIN
		errpos := 0;
		RefFile := Files.New(""); Files.Set(RefF, RefFile, 0);
		MakeFileName(modName, FName, OFext);
		ObjFile := Files.New(FName);
		IF ObjFile # NIL THEN
			Files.Set(ObjF, ObjFile, 0);
			ObjW(OFtag); ObjW("6"); dummyL := 0; dummy := 0;
			ObjWLInt(dummyL);	(*refsize*)
			ObjWInt(dummy);	(*nofexp*)
			ObjWInt(dummy);	(*nofdesc*)
			ObjWInt(dummy);	(*nofcom*)
			ObjWInt(dummy)	(*nofptr*)
		ELSE err(153)
		END
	END NewRefObj;

	PROCEDURE DeleteRefObj*;
	END DeleteRefObj;

	PROCEDURE RegisterRefObj*(nofexp, nofdesc, nofcom, nofptr: INTEGER);
		VAR refsize: LONGINT; ch: CHAR; ref: Files.Rider;
	BEGIN
		refsize := 0; ObjW(8AX);
		Files.Set(ref, RefFile, 0); Files.Read(ref, ch);
		WHILE ~ref.eof DO INC(refsize); ObjW(ch); Files.Read(ref, ch) END ;
		Files.Set(ObjF, ObjFile, 2); ObjWLInt(refsize);
		ObjWInt(nofexp); ObjWInt(nofdesc); ObjWInt(nofcom); ObjWInt(nofptr);
		Files.Register(ObjFile)
	END RegisterRefObj;

	PROCEDURE InitHost;
		VAR patL, patH: LONGINT; L, H: SHORTINT;
	BEGIN
		L := 0; H := 4;
		patL := MinRealPat; SYSTEM.PUT(SYSTEM.ADR(MinReal), patL);
		patL := MaxRealPat; SYSTEM.PUT(SYSTEM.ADR(MaxReal), patL);
		patL := MinLRealPatL; patH := MinLRealPatH;
		SYSTEM.PUT(SYSTEM.ADR(MinLReal) + L, patL);
		SYSTEM.PUT(SYSTEM.ADR(MinLReal) + H, patH);
		patL := MaxLRealPatL; patH := MaxLRealPatH;
		SYSTEM.PUT(SYSTEM.ADR(MaxLReal) + L, patL);
		SYSTEM.PUT(SYSTEM.ADR(MaxLReal) + H, patH)
	END InitHost;

BEGIN InitHost; Texts.OpenWriter(W); Log := Oberon.Log
END ROPM.
