MODULE Browser;	(** portable, except where noted *) (* MH/JT/PRK 24.9.96*)


	(* 5.12.94 mh: fixed output of REAL and LONGREAL numbers *)
	(* 5.12.94 mh: fixed output of record types *)
	(* 9.1.96: pr: fixed correct reader initialisation in the OpenSym proc *)
	(* 18.8.97: prk: OberonX port *)
	(* 24.12.98: as: SharkOberon port *)
(*
	Peter Matthias
	2015-07-07	using OBM.prefix:="arm/" 
*)

IMPORT OBT, OBS, OBM, Files, Texts, Oberon, Display, Out, SYSTEM;

CONST

	LogMsg = "Browser MH/JT/prk/as";

	showAdr = 0; expandTypes = 1;

VAR
	W: Texts.Writer;
	LogMsgPrinted, first, showObj: BOOLEAN;
	sysImported: BOOLEAN;
	syspos: LONGINT;
	option: SET;	(* showAdr, expandTypes *)
	Hex: ARRAY 17 OF CHAR;

	(* ---------------------- output ----------------------- *)

PROCEDURE Str (s: ARRAY OF CHAR);
BEGIN Texts.WriteString(W, s) 
END Str;

PROCEDURE Ch (ch: CHAR); 
BEGIN Texts.Write(W, ch) 
END Ch;

PROCEDURE Num (i: LONGINT);
BEGIN Texts.WriteInt(W, i, 0);
END Num;

PROCEDURE Ln; 
BEGIN Texts.WriteLn(W) 
END Ln;

PROCEDURE Indent (i: INTEGER);  
BEGIN
	WHILE i > 0 DO Ch(9X); DEC(i) END
END Indent;

PROCEDURE WriteFlags (obj: OBT.Object);
END WriteFlags;

PROCEDURE WriteConstValue (obj: OBT.Object);
	VAR i: INTEGER; y: LONGINT; s: SET;  lr : LONGREAL;
BEGIN
	y := obj.a0;
	CASE obj.typ^.form OF
		| OBM.SInt, OBM.Int, OBM.LInt:  Texts.WriteInt(W, y, 0)
		| OBM.Real:  Texts.WriteReal(W, SYSTEM.VAL(REAL, obj.a0), 15)
		| OBM.LReal:  SYSTEM.GET(SYSTEM.ADR(obj.a0),lr); Texts.WriteLongReal(W, lr, 23) 
		| OBM.Bool:  IF y = 0 THEN Str("FALSE") ELSE Str("TRUE") END 
		| OBM.Char:
			IF (y >= 32) & (y <= 126) THEN 
				Ch(22X); Ch(CHR(y)); Ch(22X)
			ELSE i := SHORT(y DIV 16);
				IF i > 0 THEN
					IF i > 9 THEN Ch("0") END;
					Ch(Hex[i])
				END;
				Ch(Hex[y MOD 16]); Ch("X")
			END
		| OBM.Set:
			Ch("{"); y := 0; s := SYSTEM.VAL(SET,obj.a0);
			WHILE y <= MAX(SET) DO
				IF y IN s THEN Texts.WriteInt(W, y, 0); EXCL(s, y);
					IF s # {} THEN Str(", ") END
				END;
				INC(y)
			END;
			Ch("}")
		| OBM.NilTyp:  Str("NIL")
		| OBM.String: Ch(22X); Str(obj.ext.str); Ch(22X)
	END
END WriteConstValue;

PROCEDURE ^ WriteType (typ: OBT.Struct; i: INTEGER; arrDone: BOOLEAN);

PROCEDURE WriteBase (typ: OBT.Struct);  
	VAR base: OBT.Struct;
BEGIN
	base := typ^.BaseTyp;
	IF base # NIL THEN
		Str(" ("); 
		WriteType(typ^.BaseTyp, 0, FALSE);
		IF expandTypes IN option THEN WriteBase(typ^.BaseTyp) END;
		Ch(")")
	END
END WriteBase;

PROCEDURE WriteFields (VAR obj: OBT.Object; i: INTEGER; recField: BOOLEAN);
	VAR typ: OBT.Struct; mode: INTEGER;
BEGIN
	typ := obj^.typ; mode := obj^.mode;
	LOOP
		IF recField & (showAdr IN option) THEN Ch("["); Num(obj.a0); Str("] ") END;
		Str(obj^.name);
		obj := obj.next;
		IF (obj = NIL) OR (obj^.mode # mode) OR (obj^.typ # typ) THEN EXIT END;
		Str(", ");
	END;
	Str(": "); WriteType(typ, i + 1, FALSE)
END WriteFields;

PROCEDURE WriteParams (param: OBT.Object; res: OBT.Struct);
BEGIN
	IF (param # NIL) OR (res # OBT.notyp) THEN
		Str(" (");
		WHILE (param # NIL) DO
			IF param.mode = OBM.Par THEN Str("VAR ") END;
			IF param.name = "" THEN
				WriteType(param.typ, 0, FALSE);
				param := param.next;
				IF param # NIL THEN Str(", ") END
			ELSE
				WriteFields(param, 0, FALSE);
				IF param # NIL THEN Str("; ") END
			END
		END;
		Ch(")");
	END;
	IF res # OBT.notyp THEN Str(": "); WriteType(res, 0, FALSE) END
END WriteParams;

PROCEDURE WriteProc (obj: OBT.Object);
BEGIN
	IF showAdr IN option THEN Ch("["); Num(obj^.a0); Str("] ") END;
	Str("PROCEDURE ");
	Str(obj^.name);
	WriteParams(obj^.dsc, obj^.typ);
	Ch(";");
	WriteFlags (obj)
END WriteProc;

PROCEDURE WriteFieldList (obj: OBT.Object; i: INTEGER);
BEGIN
	WHILE (obj # NIL) & (obj^.mode = OBM.Fld) DO
		IF obj.name="" THEN obj:=obj.next
		ELSE
			Indent(i);
			WriteFields(obj, i, TRUE); Ch(";");
			Ln
		END
	END
END WriteFieldList;

PROCEDURE WriteInstVars (typ: OBT.Struct; i: INTEGER; extlev: INTEGER);
BEGIN
	IF typ # NIL THEN
		IF (extlev > 0) & (expandTypes IN option) THEN
			WriteInstVars(typ^.BaseTyp, i, extlev);
			Indent(i); Str("(* "); Str(OBT.GlbMod[typ.mno-1].name); Ch("."); Str(typ^.strobj.name); Str(" *)"); Ln
		END;
		WriteFieldList(typ^.link, i);
	END
END WriteInstVars;

PROCEDURE WriteInterval(typ: OBT.Struct);
BEGIN
	IF typ.form=OBM.Array THEN Texts.WriteInt(W, typ.size DIV typ.BaseTyp.size, 0)
	END
END WriteInterval;

PROCEDURE WriteForm (typ: OBT.Struct; i: INTEGER; arrDone: BOOLEAN);
	VAR open: BOOLEAN;
BEGIN
	IF typ^.form = OBM.Record THEN
		Str("RECORD"); WriteBase(typ);
		IF typ.strobj # NIL THEN WriteFlags (typ.strobj) END;
		IF showAdr IN option THEN Str(" [size = "); Num( typ^.size); Ch("]") END;
		IF typ^.link # NIL (*OR (expandTypes IN option)*) THEN
			Ln; WriteInstVars(typ, i, typ.extlev); Indent(i - 1) ELSE Ch(" ")
		END;
		Str("END")
	ELSIF typ^.form IN {OBM.Array, OBM.DynArr} THEN
		IF ~arrDone THEN Str("ARRAY ") END;
		open := (typ.form = OBM.DynArr) & ~arrDone;		(*open array*)
		IF typ.form = OBM.Pointer THEN typ := typ.BaseTyp END;
		IF ~open THEN WriteInterval(typ) END;
		IF ~open &  (typ^.BaseTyp.form IN {OBM.Array, OBM.DynArr}) THEN Str(" , ") ELSE Str(" OF ") END;
		WriteType(typ^.BaseTyp, i, ~open)
	ELSIF typ^.form = OBM.Pointer THEN
		Str("POINTER TO ");
		WriteType(typ^.BaseTyp, i, FALSE);
	ELSIF typ^.form = OBM.ProcTyp THEN
		Str("PROCEDURE");
		WriteParams(typ^.link, typ^.BaseTyp)
	END
END WriteForm;

PROCEDURE WriteType (typ: OBT.Struct; i: INTEGER; arrDone: BOOLEAN);
BEGIN
	IF (typ^.strobj # NIL)  THEN (* named type *)
		IF (typ = OBT.bytetyp) OR (typ = OBT.sysptrtyp) THEN
			Str("SYSTEM."); sysImported := TRUE;
		ELSIF (typ^.mno > 1) OR ((typ^.mno = 1) & showObj) THEN
			Str(OBT.GlbMod[typ^.mno-1]^.name); Ch(".");
		END;
		Str(typ^.strobj^.name)
	ELSE (* anonymous type *) WriteForm(typ, i, arrDone)
	END
END WriteType;

PROCEDURE WriteObject (VAR obj: OBT.Object; mode: INTEGER);
	VAR h: OBT.Object;
BEGIN
	IF mode = OBM.Const THEN
		IF first THEN Indent(1); Str("CONST"); Ln; first := FALSE END;
		Indent(2); Str(obj.name); Str(" = "); WriteConstValue(obj); Ch(";");
		Ln;
	ELSIF mode = OBM.Var THEN
		IF first THEN Indent(1); Str("VAR"); Ln; first := FALSE END;
		Indent(2);
		IF showAdr IN option THEN Str(" ["); Num(obj.a0); Str("] "); END;
		Str(obj.name);
		Str(": "); WriteType(obj^.typ, 3, FALSE); Ch(";");
		Ln;
	ELSIF mode = OBM.Typ THEN
		IF first THEN Indent(1); Str("TYPE"); Ln; first := FALSE END;
		Indent(2);
		Str(obj^.name); Str(" = ");
		IF (obj.typ.strobj#NIL) & (obj.typ.strobj#obj) THEN WriteType(obj^.typ, 0, FALSE);  (* alias type *)
		ELSE WriteForm(obj^.typ, 3, FALSE);	
		END;
		Ch(";"); Ln;
	ELSIF mode = OBM.LProc THEN first := FALSE; Indent(1); WriteProc(obj); Ln;
	END
END WriteObject;

PROCEDURE WriteImports;
	VAR i: INTEGER;
BEGIN
	i := 1; (* assume that OBT.GlbMod[0] is "self" *)
	first := TRUE;
	WHILE i < OBT.nofGmod DO
		IF first THEN Indent(1); Str("IMPORT "); first := FALSE; syspos := W.buf.len ELSE Str(", ") END;
		Str(OBT.GlbMod[i]^.name);
		IF showAdr IN option THEN Str(" ["); Texts.WriteHex(W, OBT.GlbMod[i]^.a0); Ch("]"); END;
		INC(i);
	END;
	IF ~first THEN Ch(";"); Ln; Ln END;
END WriteImports;

PROCEDURE WriteScope (obj: OBT.Object; mode: INTEGER);
BEGIN
	first := TRUE;
	WHILE obj#NIL DO
		IF obj.mode=mode THEN WriteObject(obj,mode) END;
		obj:=obj.next
	END;
	IF ~first THEN Ln END
END WriteScope;

PROCEDURE WriteModule (mod: ARRAY OF CHAR);
	VAR anchor: OBT.Object;
BEGIN
	anchor := OBT.topScope.dsc;
	Str("DEFINITION ");
	WriteFlags (OBT.topScope.dsc);
	Str(mod);
	IF showAdr IN option THEN Str(" ["); Texts.WriteHex(W, OBT.GlbMod[0].a0); Ch("]") END;
	Ch(";"); Ln; Ln;
	syspos := W.buf.len; sysImported := FALSE;
	WriteImports;
	WriteScope(anchor, OBM.Const);
	WriteScope(anchor, OBM.Typ);
	WriteScope(anchor, OBM.Var);
	WriteScope(anchor, OBM.LProc);
	Str("END "); Str(mod); Ch(".")
END WriteModule;

PROCEDURE DisplayW (name: ARRAY OF CHAR);  
VAR T: Texts.Text;
BEGIN
	NEW(T); Texts.Open(T, ""); Texts.Append(T, W.buf);
	IF sysImported & ~showObj THEN
		IF OBT.nofGmod > 1 THEN Str("SYSTEM, ") ELSE Ch(09X); Str("IMPORT SYSTEM;"); Ln; Ln END;
		Texts.Insert(T, syspos, W.buf);
	END;
	Oberon.OpenText(name, T, 400, 200)
END DisplayW;

	(* ------------------------ symbol file ------------------- *)

PROCEDURE Find(name: ARRAY OF CHAR; VAR res: OBT.Object);	(*this is OBT.FindImport, not OBT.Find!*)
	VAR obj: OBT.Object;
BEGIN obj := OBT.topScope.dsc;
	WHILE (obj # NIL) & (obj.name # name) DO obj := obj.next END ;
	IF (obj # NIL) & (obj.mode = OBM.Typ) & ~obj.marked THEN obj := NIL END ;
	res := obj
END Find;


PROCEDURE ReadSym (name: ARRAY OF CHAR);
	VAR dummyT: Texts.Text; dummyR: Texts.Reader; selfname: ARRAY 32 OF CHAR; obj : OBT.Object; dummy : INTEGER;
		filename : ARRAY 32 OF CHAR;
BEGIN
	NEW(dummyT); Texts.Open(dummyT, ""); Texts.OpenReader( dummyR, dummyT, 0);		(* Bug fixed *)
	OBT.Init; OBT.OpenScope(0);
	selfname[0]:=1X; selfname[1]:=0X;
	OBT.Import(name, selfname, name);
	COPY(name,OBS.name);
	OBT.Find(obj,dummy); OBT.topScope:=obj
END ReadSym;

	(* ---------------- user interface --------------- *)

PROCEDURE Append (VAR d: ARRAY OF CHAR; s: ARRAY OF CHAR);
	VAR i, j: INTEGER; ch: CHAR;
BEGIN
	i := 0; WHILE d[i] # 0X DO INC(i) END;
	j := 0; REPEAT ch := s[j]; d[i] := ch; INC(i); INC(j) UNTIL ch = 0X
END Append;

PROCEDURE GetArgs (VAR S: Texts.Scanner);
	VAR text: Texts.Text; i, beg, end, time: LONGINT;
BEGIN
	option := {};
	Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos); Texts.Scan(S);
	IF (S.class = Texts.Char) & (S.c = Oberon.OptionChar) THEN Texts.Scan(S);
		IF S.class=Texts.Name THEN i := 0;
			WHILE S.s[i] # 0X DO
				CASE CAP(S.s[i]) OF
					| "X": INCL(option, expandTypes);
					| "D": INCL(option, showAdr);
				ELSE
				END;
				INC(i);
			END;
			Texts.Scan(S);
		END
	END;
	IF (S.class = Texts.Char) & (S.c = "^") THEN
		Oberon.GetSelection(text, beg, end, time);
		IF time>=0 THEN Texts.OpenScanner(S, text, beg); Texts.Scan(S) ELSE S.class := Texts.Inval END
	ELSIF (S.class # Texts.Name) OR (S.line # 0) THEN S.class := Texts.Inval;
	END;
	IF ~LogMsgPrinted THEN Str(LogMsg); Ln; Texts.Append(Oberon.Log, W.buf); LogMsgPrinted := TRUE END;
END GetArgs;

PROCEDURE QualIdent (name: ARRAY OF CHAR; VAR first, second: ARRAY OF CHAR);
	VAR i, j: INTEGER;
BEGIN
	i := 0; j := 0;
	WHILE (name[i] # ".") & (name[i] # 0X) DO
		first[j] := name[i];
		IF name[i] = "\" THEN j := 0 ELSE INC(j) END;
		INC(i);
	END;
	first[j] := 0X; INC(i); j := 0; 
	WHILE name[i] # 0X DO second[j] := name[i]; INC(i); INC(j) END;
	second[j] := 0X
END QualIdent;

PROCEDURE ShowDef*;	(** [ "/" ["x"] ["d"] ] **)
	VAR S: Texts.Scanner; symname, mod, dummy : ARRAY 32 OF CHAR; f: Files.File;
		errmsg : ARRAY 64 OF CHAR;
BEGIN
	errmsg:=""; OBS.scanerr := FALSE;
	GetArgs(S);
	IF S.class=Texts.Name THEN
		OBM.prefix:="arm/";
		QualIdent(S.s, mod, dummy);
		OBM.MakeFileName(mod,symname,OBM.SFext); f := Files.Old(symname);
		IF f = NIL THEN Str(symname); Str(" not found"); Ln; Texts.Append(Oberon.Log, W.buf); RETURN END;
		ReadSym(mod);
		IF ~OBS.scanerr THEN showObj := FALSE;
			WriteModule(mod);
			Append(mod, ".Def"); DisplayW(mod)
		ELSE
			errmsg:="could not read symbol file";
			HALT(99)
		END
	END
END ShowDef;

PROCEDURE ShowObj*;	(** [ "/" ["x"] ["d"] ] **)	(** non-portable *)
	VAR S: Texts.Scanner; symname, mod, objName, qualid: ARRAY 32 OF CHAR; obj: OBT.Object; f: Files.File;
		errmsg : ARRAY 64 OF CHAR;
BEGIN
	errmsg:=""; OBS.scanerr := FALSE;
	GetArgs(S);
	IF S.class=Texts.Name THEN
		COPY(S.s, qualid); QualIdent(S.s, mod, objName);
		OBM.MakeFileName(mod,symname,OBM.SFext); f := Files.Old(symname);
		IF f = NIL THEN Str(symname); Str(" not found"); Ln; Texts.Append(Oberon.Log, W.buf); RETURN END;
		ReadSym(mod);
		IF ~OBS.scanerr THEN Find(objName, obj);
			IF obj # NIL THEN showObj := TRUE; first := TRUE;
				WriteObject(obj, obj.mode);
				DisplayW(qualid)
			END
		ELSE
			errmsg:="could not read symbol file";
			HALT(99)
		END
	END
END ShowObj;

BEGIN
	Hex := "0123456789ABCDEF";
	Texts.OpenWriter(W);
	LogMsgPrinted := FALSE;
END Browser.



Builder.Compile *
Builder.Compile \D=CrossCompiler *

ABrowser.ShowDef ^

OFW.Call  ~
Kernel
ImportTest2
ImportTest