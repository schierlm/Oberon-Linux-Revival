(*
	Peter Matthias
	2015-02-12	set default prefix to arm/
	2015-12-28	adapted to OBC.SaveRegisters/OBC.RestoreRegisters with FP register set

*)

MODULE ACompiler;   (*NW 7.6.87 / 21.8.92 / 14.12.93*)

	IMPORT SYSTEM, Kernel, Texts, TextFrames, Oberon, OBS, OBT, OBA, OBC, OBE, OBH, OC := OBM;

	CONST
		NofCases = 128; ModNameLen = 20; 
		RecDescSize = 8; AdrSize = 4; ProcSize = 4; PtrSize = 4;
		XParOrg = 12; LParOrg = 8; MaxJumpTableEntries = 1024; (* reine Willkr! *) 
		
		MaxExits = 32;
		MaxLoopNesting = 32;
			
		(*structure forms*)
			intSet = {OC.SInt .. OC.LInt}; labeltyps = {OC.Char .. OC.LInt};
			
	VAR W: Texts.Writer;
			sym : INTEGER;
			newSF: BOOLEAN;
			dsize: LONGINT;
			LoopLevel, ExitNo: INTEGER;
			LoopExit: ARRAY MaxExits OF LONGINT;
			ForDepth: ARRAY MaxLoopNesting OF INTEGER;
			openArrayAllowed : BOOLEAN;
			statistics : BOOLEAN;
			statW : Texts.Writer;
			statsEmpty : BOOLEAN;
			noFiles: BOOLEAN;	(*don't write output file*)

	PROCEDURE^ Type(VAR typ: OBT.Struct);
	PROCEDURE^ FormalType(VAR typ: OBT.Struct);
	PROCEDURE^ Expression(VAR x: OBT.Item);
	PROCEDURE^ Block(VAR dsize: LONGINT; proc : OBT.Object);

	PROCEDURE CheckSym(s: INTEGER);
	BEGIN
		IF sym = s THEN OBS.Get(sym) ELSE OBS.Mark(s) END
	END CheckSym;

	PROCEDURE qualident(VAR x: OBT.Item);
		VAR mnolev: INTEGER; obj: OBT.Object;
	BEGIN (*sym = OC.ident*)
		OBT.Find(obj, mnolev); IF obj = NIL THEN OBS.Mark(0) END;
		OBS.Get(sym);
		IF (sym = OC.period) & (obj # NIL) & (obj.mode = OC.Mod) THEN
			OBS.Get(sym); mnolev := SHORT(-obj.a0);
			IF sym = OC.ident THEN
				OBT.FindImport(obj, obj); IF obj = NIL THEN OBS.Mark(0) END; 
				OBS.Get(sym);  
			ELSE OBS.Mark(10); obj := NIL
			END
		END ;
		IF obj # NIL THEN
			OBE.MakeItem(obj,x,mnolev);
		ELSE
			x.mode := OC.Var;
			x.typ := OBT.undftyp; x.a := 0; x.obj := NIL
		END
	END qualident;

	PROCEDURE ConstExpression(VAR x: OBT.Item);
	BEGIN
		Expression(x);
		IF x.mode # OC.Const THEN
			OBS.Mark(50); x.mode := OC.Const; x.typ := OBT.inttyp; x.a := 1
		END
	END ConstExpression;

	PROCEDURE NewStr(form: INTEGER): OBT.Struct;
		VAR typ: OBT.Struct;
	BEGIN NEW(typ);
		typ.form := form; typ.mno := 0; typ.size := 4; typ.ref := 0;
		typ.BaseTyp := OBT.undftyp; typ.strobj := NIL; RETURN typ
	END NewStr;

	PROCEDURE CheckMark(VAR mk: BOOLEAN);
	BEGIN OBS.Get(sym);
		IF sym = OC.times THEN
			IF OBC.level = 0 THEN mk := TRUE ELSE mk := FALSE; OBS.Mark(47) END ;
			OBS.Get(sym)
		ELSE mk := FALSE
		END
	END CheckMark;

	PROCEDURE CheckUndefPointerTypes;
		VAR obj: OBT.Object;
	BEGIN obj := OBT.topScope.next;
		WHILE obj # NIL DO
			IF obj.mode = OC.Undef THEN OBS.Mark(128) END ;
			obj := obj.next
		END
	END CheckUndefPointerTypes;

	PROCEDURE RecordType(VAR typ: OBT.Struct);
		VAR adr, size: LONGINT;
			fld, fld0, fld1: OBT.Object;
			ftyp, btyp: OBT.Struct;
			base: OBT.Item;
	BEGIN
		adr := 0; typ := NewStr(OC.Record); typ.BaseTyp := NIL; typ.extlev := 0;
		IF sym = OC.lparen THEN
			OBS.Get(sym); (*record extension*)
			IF sym = OC.ident THEN
				qualident(base);
				IF (base.mode = OC.Typ) & (base.typ.form = OC.Record) THEN
					typ.BaseTyp := base.typ; typ.extlev := base.typ.extlev + 1; adr := base.typ.size
				ELSE OBS.Mark(52)
				END
			ELSE OBS.Mark(10)
			END ;
			CheckSym(OC.rparen)
		END ;
		OBT.OpenScope(0); fld := NIL; fld1 := OBT.topScope;
		LOOP
			IF sym = OC.ident THEN
				LOOP
					IF sym = OC.ident THEN
						IF typ.BaseTyp # NIL THEN
							OBT.FindField(typ.BaseTyp, fld0);
							IF fld0 # NIL THEN OBS.Mark(1) END
						END ;
						OBT.Insert(OBS.name, fld); CheckMark(fld.marked); fld.mode := OC.Fld
					ELSE OBS.Mark(10)
					END ;
					IF sym = OC.comma THEN OBS.Get(sym)
					ELSIF sym = OC.ident THEN OBS.Mark(19)
					ELSE EXIT
					END
				END ;
				CheckSym(OC.colon); Type(ftyp); size := ftyp.size; btyp := ftyp;
				WHILE btyp.form = OC.Array DO btyp := btyp.BaseTyp END ;
				IF btyp.size >= 4 THEN INC(adr, (-adr) MOD 4)
				ELSIF btyp.size = 2 THEN INC(adr, adr MOD 2)
				END ;
				WHILE fld1.next # NIL DO
					fld1 := fld1.next; fld1.typ := ftyp; fld1.a0 := adr; INC(adr, size)
				END
			END ;
			IF sym = OC.semicolon THEN OBS.Get(sym)
			ELSIF sym = OC.ident THEN OBS.Mark(38)
			ELSE EXIT
			END
		END ;
		typ.size := (-adr) MOD 4 + adr; 
		typ.mno := 0; typ.link := OBT.topScope.next;
		CheckUndefPointerTypes; OBT.CloseScope;
		IF OBC.level = 0 THEN INC(dsize, (-dsize) MOD 4 + 4); typ.adr := -dsize END ;
		OBC.RegisterRecType(typ)
	END RecordType;

	PROCEDURE AdjustOpenArrayAddrs(typ : OBT.Struct);
	VAR a : LONGINT; t : OBT.Struct; dims : LONGINT;
	BEGIN
		t:=typ; a:=0; dims:=0;
		WHILE t.form=OC.DynArr DO
			INC(dims); IF dims=OC.MaxOpenDims THEN OBS.Mark(255) END; INC(a,4); t:=t.BaseTyp
		END;
		WHILE typ.form=OC.DynArr DO
			typ.size:=a+4; typ.adr:=a; 
			DEC(a,4); typ:=typ.BaseTyp
		END			
	END AdjustOpenArrayAddrs;
	
	PROCEDURE ArrayType(VAR typ: OBT.Struct);
		VAR x: OBT.Item; f : INTEGER;
	BEGIN
		IF (sym=OC.of) & openArrayAllowed THEN
			typ := NewStr(OC.DynArr);
			OBS.Get(sym); (* read over OF *)
			Type(typ.BaseTyp);
		ELSE	
			typ := NewStr(OC.Array); 
			IF sym=OC.of THEN OBS.Mark(88); x.mode:=OC.Const; x.a:=1; x.typ:=OBT.inttyp 
			ELSE ConstExpression(x) 
			END;
			openArrayAllowed:=FALSE;
			f := x.typ.form;
			IF f IN intSet THEN
				IF x.a <= 0 THEN x.a := 1; OBS.Mark(63) END
			ELSE OBS.Mark(51); x.a := 1
			END ;
			IF sym = OC.of THEN OBS.Get(sym); Type(typ.BaseTyp)
			ELSIF sym = OC.comma THEN OBS.Get(sym); ArrayType(typ.BaseTyp)
			ELSE OBS.Mark(35)
			END ;
			typ.size := x.a * typ.BaseTyp.size
		END
	END ArrayType;

	PROCEDURE FormalParameters(VAR resTyp: OBT.Struct; VAR psize: LONGINT);
		VAR mode: SHORTINT;
			adr, size: LONGINT; res: OBT.Item;
			par, par1: OBT.Object; typ: OBT.Struct;
	BEGIN
		par1 := OBT.topScope; adr := 0;
		IF (sym = OC.ident) OR (sym = OC.var) THEN
			LOOP
				IF sym = OC.var THEN OBS.Get(sym); mode := OC.Par ELSE mode := OC.Var END ;			
				LOOP
					IF sym = OC.ident THEN
						OBT.Insert(OBS.name, par); OBS.Get(sym); par.mode := mode
					ELSE OBS.Mark(10)
					END ;
					IF sym = OC.comma THEN OBS.Get(sym)
					ELSIF sym = OC.ident THEN OBS.Mark(19)
					ELSIF sym = OC.var THEN OBS.Mark(19); OBS.Get(sym)
					ELSE EXIT
					END
				END ;
				CheckSym(OC.colon); FormalType(typ);
				IF mode = OC.Par THEN (*VAR param*)
					IF typ.form = OC.Record THEN size := RecDescSize
					ELSIF typ.form = OC.DynArr THEN size := typ.size
					ELSE size := AdrSize
					END
				ELSE
					size := (-typ.size) MOD 4 + typ.size
				END ;

				WHILE par1.next # NIL DO
					par1 := par1.next; par1.typ := typ; DEC(adr, size); par1.a0 := adr; 
				END ;
				IF sym = OC.semicolon THEN OBS.Get(sym)
				ELSIF sym = OC.ident THEN OBS.Mark(38)
				ELSE EXIT
				END
			END
		END ;
		psize := psize - adr; (* total Grsse des Param-Blocks anpassen (ist auf 4 aligned) *)
		par := OBT.topScope.next;
		WHILE par # NIL DO
			(* Adresse anpassen *)
			INC(par.a0, psize);
			par := par.next 
		END ;

		CheckSym(OC.rparen);
		IF sym = OC.colon THEN
			OBS.Get(sym); resTyp := OBT.undftyp;
			IF sym = OC.ident THEN qualident(res);
				IF res.mode = OC.Typ THEN
					IF (res.typ.form <= OC.ProcTyp) & (res.typ.form # OC.NoTyp) THEN resTyp := res.typ
					ELSE OBS.Mark(54)
					END
				ELSE OBS.Mark(52)
				END
			ELSE OBS.Mark(10)
			END
		ELSE resTyp := OBT.notyp
		END
	END FormalParameters;

	PROCEDURE ProcType(VAR typ: OBT.Struct);
		VAR psize: LONGINT;
	BEGIN typ := NewStr(OC.ProcTyp); typ.size := ProcSize;
		IF sym = OC.lparen THEN
			OBS.Get(sym); OBT.OpenScope(OBC.level); psize := LParOrg; 
			FormalParameters(typ.BaseTyp, psize); typ.link := OBT.topScope.next;
			OBT.CloseScope
		ELSE typ.BaseTyp := OBT.notyp; typ.link := NIL
		END
	END ProcType;

	PROCEDURE SetPtrBase(ptyp, btyp: OBT.Struct);
	BEGIN
		IF (btyp.form = OC.Record) OR (btyp.form IN {OC.Array, OC.DynArr}) (* OLD: & ~OBT.HasPtr(btyp.BaseTyp) *) THEN
			ptyp.BaseTyp := btyp
		ELSE ptyp.BaseTyp := OBT.undftyp; OBS.Mark(57)
		END
	END SetPtrBase;

	PROCEDURE Type(VAR typ: OBT.Struct);
		VAR lev: INTEGER; obj: OBT.Object; x: OBT.Item;
	BEGIN typ := OBT.undftyp;
		IF sym < OC.lparen THEN OBS.Mark(12);
			REPEAT OBS.Get(sym) UNTIL sym >= OC.lparen
		END ;
		IF sym = OC.ident THEN qualident(x);
			IF x.mode = OC.Typ THEN typ := x.typ;
				IF typ = OBT.notyp THEN OBS.Mark(58) END
			ELSE OBS.Mark(52)
			END
		ELSIF sym = OC.array THEN 
			OBS.Get(sym); ArrayType(typ)
		ELSIF sym = OC.record THEN 
			openArrayAllowed:=FALSE;
			OBS.Get(sym); RecordType(typ); CheckSym(OC.end)
		ELSIF sym = OC.pointer THEN
			openArrayAllowed:=TRUE;
			OBS.Get(sym); typ := NewStr(OC.Pointer); typ.link := NIL; typ.size := PtrSize;
			CheckSym(OC.to);
			IF sym = OC.ident THEN OBT.Find(obj, lev);
				IF obj = NIL THEN (*forward ref*)
					OBT.Insert(OBS.name, obj); typ.BaseTyp := OBT.undftyp;
					obj.mode := OC.Undef; obj.typ := typ; OBS.Get(sym)
				ELSE qualident(x);
					IF x.mode = OC.Typ THEN SetPtrBase(typ, x.typ)
					ELSE typ.BaseTyp := OBT.undftyp; OBS.Mark(52)
					END
				END
			ELSE Type(x.typ); SetPtrBase(typ, x.typ); AdjustOpenArrayAddrs(x.typ);
			END
		ELSIF sym = OC.procedure THEN OBS.Get(sym); ProcType(typ)
		ELSE OBS.Mark(12)
		END ;
		IF (sym < OC.semicolon) OR (OC.else < sym) THEN OBS.Mark(15);
			WHILE (sym <= OC.ident) OR (OC.else < sym) & (sym < OC.begin) DO
				OBS.Get(sym)
			END
		END
	END Type;

	PROCEDURE FormalType(VAR typ: OBT.Struct);
		VAR x: OBT.Item; typ0: OBT.Struct; a, s: LONGINT;
	BEGIN typ := OBT.undftyp; a := 0;
		WHILE sym = OC.array DO
			OBS.Get(sym); CheckSym(OC.of); INC(a, 4)
		END ;
		IF sym = OC.ident THEN qualident(x);
			IF x.mode = OC.Typ THEN typ := x.typ;
				IF typ = OBT.notyp THEN OBS.Mark(58) END
			ELSE OBS.Mark(52)
			END
		ELSIF sym = OC.procedure THEN OBS.Get(sym); ProcType(typ)
		ELSE OBS.Mark(10)
		END ;
		s := a + 8;
		WHILE a > 0 DO
			typ0 := NewStr(OC.DynArr); typ0.BaseTyp := typ;
			typ0.size := s-a; typ0.adr := typ0.size-4; typ0.mno := 0; typ := typ0; DEC(a, 4)
		END
	END FormalType;

	PROCEDURE selector(VAR x: OBT.Item);
		VAR fld: OBT.Object; y: OBT.Item;
	BEGIN
		LOOP
			IF sym = OC.lbrak THEN OBS.Get(sym);
				LOOP
					IF x.mode IN {OC.Const, OC.Typ..OC.Mod} THEN OBS.Mark(112); Expression(y)
					ELSE
						IF (x.typ # NIL) & (x.typ.form = OC.Pointer) THEN OBE.DeRef(x) END ;
						Expression(y);  OBE.Index(x, y);
					END ;
					IF sym = OC.comma THEN OBS.Get(sym) ELSE EXIT END
				END ;
				CheckSym(OC.rbrak)
			ELSIF sym = OC.period THEN OBS.Get(sym);
				IF sym = OC.ident THEN
					IF x.typ # NIL THEN
						IF x.typ.form = OC.Pointer THEN OBE.DeRef(x) END ;
						IF x.typ.form = OC.Record THEN OBT.FindField(x.typ, fld); OBE.Field(x, fld) ; 
						ELSE OBS.Mark(53)
						END
					ELSE OBS.Mark(52)
					END ;
					OBS.Get(sym)
				ELSE OBS.Mark(10)
				END
			ELSIF sym = OC.arrow THEN
				OBS.Get(sym); OBE.DeRef(x)
			ELSIF (sym = OC.lparen) & (x.mode < OC.Typ) & (x.typ.form # OC.ProcTyp) THEN
				OBS.Get(sym);
				IF sym = OC.ident THEN
					qualident(y);
					IF y.mode = OC.Typ THEN OBE.TypTest(x, y, FALSE,OC.TypeGuardTrap) ELSE OBS.Mark(52) END
				ELSE OBS.Mark(10)
				END ;
				CheckSym(OC.rparen)
			ELSE EXIT
			END
		END
	END selector;

	PROCEDURE ActualParameters(VAR x: OBT.Item; fpar: OBT.Object);
		VAR apar: OBT.Item; R: SET; psize : LONGINT;
	BEGIN
		IF OBT.IsParam(fpar) THEN
			(* Calculate size of Parameter-Block including both links and return address and align it *)
			psize:=fpar.a0+fpar.typ.size; psize:=(psize+3) DIV 4 * 4; 
		END;
		IF sym # OC.rparen THEN
			R := OBC.UsedRegisters();
			LOOP
				Expression(apar);
				IF OBT.IsParam(fpar) THEN OBH.Param(apar, fpar, psize); fpar := fpar.next
				ELSE OBS.Mark(64)
				END ;
				OBC.FreeRegs(R);
				IF sym = OC.comma THEN OBS.Get(sym)
				ELSIF (OC.lparen <= sym) & (sym <= OC.ident) THEN OBS.Mark(19)
				ELSE EXIT
				END
			END
		END ;
		IF OBT.IsParam(fpar) THEN OBS.Mark(65)
		END
	END ActualParameters;

	PROCEDURE NewOpenArr(VAR x : OBT.Item);
	VAR y : OBT.Item; typ : OBT.Struct; dims : ARRAY OC.MaxOpenDims OF OBT.Item; dimcnt : LONGINT;
	BEGIN (* Addr of pointer already pushed by StPar1 *)
		typ:=x.typ.BaseTyp; dimcnt:=0;
		IF typ.form#OC.DynArr THEN OBS.Mark(111) END;
		LOOP
			INC(dimcnt); Expression(y); IF typ.form#OC.DynArr THEN OBS.Mark(64) END;
			IF dimcnt>OC.MaxOpenDims THEN dimcnt:=1 END; (* error already reported! *)
			IF (y.mode = OC.Const) & (y.a < 0) THEN OBS.Mark(63) END;
			dims[dimcnt-1]:=y; typ:=typ.BaseTyp;
			IF sym = OC.comma THEN OBS.Get(sym)
			ELSIF (OC.lparen <= sym) & (sym <= OC.ident) THEN OBS.Mark(19)
			ELSE EXIT
			END
		END;
		IF typ.form=OC.DynArr THEN OBS.Mark(65) END;
		
		OBE.NewOpenArr(x,typ,dims,dimcnt);
	END NewOpenArr;
	
	PROCEDURE StandProcCall(VAR x: OBT.Item);
		VAR oldx, y, z: OBT.Item; m, n: LONGINT;
	BEGIN
		m := SHORT(x.a); n := 0;
		IF sym = OC.lparen THEN OBS.Get(sym);
			IF sym # OC.rparen THEN
				LOOP
					IF n = 0 THEN Expression(x); oldx:=x; OBE.StPar1(x, m); n := 1
					ELSIF n = 1 THEN 
						IF (m=OBT.FnNew) & (oldx.typ.form=OC.Pointer) & (oldx.typ.BaseTyp.form=OC.DynArr) THEN NewOpenArr(oldx)
						ELSE Expression(y); OBE.StPar2(x, y, m);  n := 2
						END
					ELSIF n = 2 THEN Expression(z); OBE.StPar3(x, z, m); n := 3
					ELSE OBS.Mark(64); Expression(y)
					END ;
					IF sym = OC.comma THEN OBS.Get(sym)
					ELSIF (OC.lparen <= sym) & (sym <= OC.ident) THEN OBS.Mark(19)
					ELSE EXIT
					END
				END ;
				CheckSym(OC.rparen)
			ELSE OBS.Get(sym)
			END ;
			OBE.StFct(x, y, z, m, n)
		ELSE OBS.Mark(30)
		END
	END StandProcCall;

	PROCEDURE Element(VAR x: OBT.Item);
		VAR e1, e2: OBT.Item;
	BEGIN
		Expression(e1);
		IF sym = OC.upto THEN
			OBS.Get(sym); Expression(e2); OBE.Set1(x, e1, e2)
		ELSE OBE.Set0(x, e1)
		END ;
	END Element;

	PROCEDURE Sets(VAR x: OBT.Item);
		VAR y: OBT.Item;
	BEGIN x.typ := OBT.settyp; y.typ := OBT.settyp;
		IF sym # OC.rbrace THEN
			Element(x);
			LOOP
				IF sym = OC.comma THEN OBS.Get(sym)
				ELSIF (OC.lparen <= sym) & (sym <= OC.ident) THEN OBS.Mark(19)
				ELSE EXIT
				END ;
				Element(y); OBE.Op(OC.plus, x, y)  (*x := x+y*)
			END
		ELSE x.mode := OC.Const; x.a := 0
		END ;
		CheckSym(OC.rbrace)
	END Sets;

	PROCEDURE Factor(VAR x: OBT.Item);
		VAR fpar: OBT.Object; gR, gF: SET; 
	BEGIN
		IF sym < OC.lparen THEN OBS.Mark(13);
			REPEAT OBS.Get(sym) UNTIL sym >= OC.lparen
		END ;
		IF sym = OC.ident THEN
			qualident(x); selector(x);
			IF x.mode = OC.SProc THEN StandProcCall(x)
			ELSIF sym = OC.lparen THEN
				OBS.Get(sym); 
				OBH.PrepCall(x, fpar); 
				OBC.SaveRegisters(gR, gF, x); 
				ActualParameters(x, fpar);
				OBH.Call(x); 
				OBC.RestoreRegisters(gR, gF, x); 
				CheckSym(OC.rparen)
			END
		ELSIF sym = OC.number THEN
			OBS.Get(sym); x.mode := OC.Const;
			CASE OBS.numtyp OF
				1: x.typ := OBT.chartyp; x.a := OBS.intval
			| 2: x.a:=OBS.intval; OBE.SetIntType(x)
			| 3: x.typ := OBT.realtyp; SYSTEM.PUT(SYSTEM.ADR(x.a), OBS.realval)
			| 4: x.typ := OBT.lrltyp; SYSTEM.PUT(SYSTEM.ADR(x.a), OBS.lrlval) 
			END;
		ELSIF sym = OC.string THEN
			x.typ := OBT.stringtyp; x.mode := OC.Const; 
			NEW(x.obj); NEW(x.obj.ext); 
			x.obj.ext.entered:=FALSE; COPY(OBS.name,x.obj.ext.str); 
			x.b:=0; REPEAT INC(x.b) UNTIL OBS.name[x.b-1]=0X;
			OBS.Get(sym)
		ELSIF sym = OC.nil THEN
			OBS.Get(sym); x.typ := OBT.niltyp; x.mode := OC.Const; x.a := 0
		ELSIF sym = OC.lparen THEN
			OBS.Get(sym); Expression(x); CheckSym(OC.rparen)
		ELSIF sym = OC.lbrak THEN
			OBS.Get(sym); OBS.Mark(30); Expression(x); CheckSym(OC.rparen)
		ELSIF sym = OC.lbrace THEN OBS.Get(sym); Sets(x)
		ELSIF sym = OC.not THEN
			OBS.Get(sym); Factor(x); OBE.MOp(OC.not, x)
		ELSE OBS.Mark(13); OBS.Get(sym); x.typ := OBT.undftyp; x.mode := OC.Var; x.a := 0
		END
	END Factor;

	PROCEDURE Term(VAR x: OBT.Item);
		VAR y: OBT.Item; mulop: INTEGER;
	BEGIN 
		Factor(x);
		WHILE (OC.times <= sym) & (sym <= OC.and) DO
			IF x.mode = OC.LProc THEN OBS.Mark(55) END;
			mulop := sym; OBS.Get(sym);
			IF mulop = OC.and THEN OBE.MOp(OC.and, x) END ;
			Factor(y);
			IF y.mode = OC.LProc THEN OBS.Mark(55) END;
			OBE.Op(mulop, x, y)
		END
	END Term;

	PROCEDURE SimpleExpression(VAR x: OBT.Item);
		VAR y: OBT.Item; addop: INTEGER;
	BEGIN
		IF sym = OC.minus THEN OBS.Get(sym); Term(x); OBE.MOp(OC.minus, x)
		ELSIF sym = OC.plus THEN OBS.Get(sym); Term(x); OBE.MOp(OC.plus, x)
		ELSE Term(x)
		END ;
		WHILE (OC.plus <= sym) & (sym <= OC.or) DO
			IF x.mode = OC.LProc THEN OBS.Mark(55) END;
			addop := sym; OBS.Get(sym);
			IF addop = OC.or THEN OBE.MOp(OC.or, x) END ;
			Term(y);
			IF y.mode = OC.LProc THEN OBS.Mark(55) END;
			OBE.Op(addop, x, y)
		END
	END SimpleExpression;

	PROCEDURE Expression(VAR x: OBT.Item);
		VAR y: OBT.Item; relation: INTEGER;
	BEGIN
		SimpleExpression(x);
		IF (OC.eql <= sym) & (sym <= OC.geq) THEN
			IF x.mode = OC.LProc THEN OBS.Mark(55) END;
			relation := sym; OBS.Get(sym);
			IF x.typ.form = OC.Bool THEN OBE.MOp(relation, x) END ;
			SimpleExpression(y); 
			IF y.mode = OC.LProc THEN OBS.Mark(55) END;
			OBE.Op(relation, x, y)
		ELSIF sym = OC.in THEN
			IF x.mode = OC.LProc THEN OBS.Mark(55) END;
			OBS.Get(sym); SimpleExpression(y); OBE.In(x, y)
		ELSIF sym = OC.is THEN
			IF x.mode >= OC.Typ THEN OBS.Mark(112) END ;
			OBS.Get(sym);
			IF sym = OC.ident THEN
				qualident(y);
				IF y.mode = OC.Typ THEN OBE.TypTest(x, y, TRUE,0(* not used*)) ELSE OBS.Mark(52) END
			ELSE OBS.Mark(10)
			END
		END
	END Expression;

	PROCEDURE ProcedureDeclaration;
		VAR proc, proc1, par: OBT.Object;
			L1: INTEGER;
			mode: SHORTINT; body: BOOLEAN;
			oldpsize, psize, dsize: LONGINT;
	BEGIN 
		dsize := 0; proc := NIL; body := TRUE;
		IF (sym # OC.ident) & (OBC.level = 0) THEN
			mode:=OC.LProc;
			IF sym = OC.arrow THEN (*forward*) body := FALSE
			ELSIF (sym = OC.times) OR (sym = OC.plus) OR (sym = OC.minus) THEN (* just ignore it! *)
			ELSE mode := OC.LProc; OBS.Mark(10)
			END ;
			OBS.Get(sym)
		ELSE mode := OC.LProc
		END ;
		IF sym = OC.ident THEN
			IF OBC.level = 0 THEN OBT.Find(proc1, L1) ELSE proc1 := NIL END;
			IF (proc1 # NIL) & (proc1.mode = OC.LProc) & (proc1.a0 = -1) THEN
				(*there exists a corresponding forward declaration*)
				OBT.Remove(proc1); OBT.Insert(OBS.name, proc);
				CheckMark(proc.marked); 
				mode := OC.LProc; 
				OBC.FixLink(proc1.a1); OBC.FixAddr(proc1.a2, OBC.pc*4);
			ELSE
				IF proc1 # NIL THEN OBS.Mark(1); proc1 := NIL END ;
				OBT.Insert(OBS.name, proc); 
				CheckMark(proc.marked);
			END ;
			proc.mode := mode; proc.typ := OBT.notyp; proc.a0 := -1; proc.a1 := 0; proc.dsc := NIL;
			INC(OBC.level); OBT.OpenScope(OBC.level);
			IF (mode = OC.LProc) & (OBC.level = 1) THEN psize := LParOrg ELSE psize := XParOrg END ;
			IF sym = OC.lparen THEN
				OBS.Get(sym); 
				FormalParameters(proc.typ, psize); 
				proc.dsc := OBT.topScope.next
			END;
			IF proc1 # NIL THEN  (*forward*)
				OBH.CompareParLists(proc.dsc, proc1.dsc);
				IF proc.typ # proc1.typ THEN OBS.Mark(118) END
			END ;
			IF body THEN
				CheckSym(OC.semicolon); 
				IF sym=OC.code THEN
					(* Assembler Procedure *)
					proc.a0 := OBC.pc; OBC.FixLink(proc.a1);
					par := proc.dsc;
					LOOP
						IF par=NIL THEN EXIT END;
						IF (par.typ.form = OC.DynArr) & (par.mode = OC.Var) THEN OBS.Mark(256); EXIT END;
						par:=par.next;
					END ;
					OBA.Assemble;
					OBC.FlushConsts;
					OBS.Get(sym);
				ELSE
					OBT.topScope.typ:=proc.typ;
					oldpsize:=OBH.curProcParamSize; 
					OBH.curProcParamSize:=psize-8; (* Dyn. link and return address are NOT parameters, static link IS *)
					Block(dsize,proc);
					proc.dsc := OBT.topScope.next;
					IF proc.typ = OBT.notyp THEN OBH.Return(FALSE) ELSE OBH.Trap(OC.NoReturnTrap) END ;
					OBC.FlushConsts;
					OBH.curProcParamSize:=oldpsize;
				END;
				proc.a2:=OBC.pc;
				IF sym = OC.ident THEN
					IF OBS.name # proc.name THEN OBS.Mark(4) END ;
					OBS.Get(sym)
				ELSE OBS.Mark(10)
				END
			END ;
			DEC(OBC.level); OBT.CloseScope
		END
	END ProcedureDeclaration;


	PROCEDURE CaseLabelList(LabelForm: INTEGER;
						VAR n: INTEGER; VAR tab: ARRAY OF OBH.LabelRange; VAR low, high : LONGINT);
		VAR x, y: OBT.Item; i, f: INTEGER;
	BEGIN
		IF ~(LabelForm IN labeltyps) THEN OBS.Mark(61) END ;
		LOOP ConstExpression(x); f := x.typ.form;
			IF f IN intSet THEN
				IF LabelForm < f THEN OBS.Mark(60) END
			ELSIF f # LabelForm THEN OBS.Mark(60)
			END ;
			IF sym = OC.upto THEN
				OBS.Get(sym); ConstExpression(y);
				IF (y.typ.form # f) & ~((f IN intSet) & (y.typ.form IN intSet)) THEN OBS.Mark(60) END ;
				IF y.a < x.a THEN OBS.Mark(63); y.a := x.a END
			ELSE y := x
			END;
			(*enter label range into ordered table*)  
			IF x.a<low THEN low:=x.a END;
			IF y.a>high THEN high:=y.a END;
			IF high-low >= MaxJumpTableEntries THEN OBS.Mark(209); n := 0 END;
			i := n;
			IF i < NofCases THEN
				LOOP
					IF i = 0 THEN EXIT END ;
					IF tab[i-1].low <= y.a THEN
						IF tab[i-1].high >= x.a THEN OBS.Mark(62) END ;
						EXIT
					END ;
					tab[i] := tab[i-1]; DEC(i)
				END ;
				tab[i].low := x.a; tab[i].high := y.a;
				tab[i].label := OBC.pc; INC(n)
			ELSE OBS.Mark(213)
			END ;
			IF sym = OC.comma THEN OBS.Get(sym)
			ELSIF (sym = OC.number) OR (sym = OC.ident) THEN OBS.Mark(19)
			ELSE EXIT
			END
		END
	END CaseLabelList;

	PROCEDURE StatSeq;
		VAR fpar: OBT.Object; xtyp: OBT.Struct;
				x, x0, y, z: OBT.Item; ExitIndex: INTEGER;
				L0, L1 : LONGINT;
				tempVar : BOOLEAN;

		PROCEDURE CasePart;
			VAR x: OBT.Item; n : INTEGER;
					tab: ARRAY NofCases OF OBH.LabelRange;
					low, high : LONGINT;
					jmpadrloc, else, L : LONGINT;
					
		BEGIN
			n := 0; L := 0;
			Expression(x); OBH.CaseIn(x, jmpadrloc, else); OBC.FreeRegs({});
			CheckSym(OC.of);
			low:=MAX(LONGINT); high:=MIN(LONGINT);
			LOOP
				IF sym < OC.bar THEN
					CaseLabelList(x.typ.form, n, tab, low, high);
					CheckSym(OC.colon); StatSeq; OBE.FJ(L)
				END ;
				IF sym = OC.bar THEN OBS.Get(sym) ELSE EXIT END
			END ;
			OBC.FixLink(else);
			else:=OBC.pc;
			IF sym = OC.else THEN OBS.Get(sym); StatSeq; OBE.FJ(L)
			ELSE OBH.Trap(OC.CaseTrap);
			END;
			OBH.CaseOut(jmpadrloc,L,else,n,tab)
		END CasePart;

	BEGIN
		LOOP
			IF sym < OC.ident THEN OBS.Mark(14);
				REPEAT OBS.Get(sym) UNTIL sym >= OC.ident
			END ;
			IF sym = OC.ident THEN
				qualident(x); selector(x);
				IF sym = OC.becomes THEN 
					OBS.Get(sym); Expression(y); OBH.Assign(x, y, FALSE)
				ELSIF sym = OC.eql THEN
					OBS.Mark(34); OBS.Get(sym); Expression(y); OBH.Assign(x, y, FALSE)
				ELSIF x.mode = OC.SProc THEN
					StandProcCall(x);
					IF x.typ.form # OC.NoTyp THEN OBS.Mark(55) END
				ELSE OBH.PrepCall(x, fpar);
					IF sym = OC.lparen THEN
						OBS.Get(sym); ActualParameters(x, fpar); CheckSym(OC.rparen)
					ELSIF OBT.IsParam(fpar) THEN OBS.Mark(65)
					END ;
					OBH.Call(x);
					IF x.typ.form # OC.NoTyp THEN OBS.Mark(55) END
				END
			ELSIF sym = OC.if THEN
				OBS.Get(sym); Expression(x); OBE.CFJ(x, L0); OBC.FreeRegs({});
				CheckSym(OC.then); StatSeq;  L1 := 0;
				WHILE sym = OC.elsif DO
					OBS.Get(sym); OBE.FJ(L1); OBC.FlushConsts; OBC.FixLink(L0);
					Expression(x); OBE.CFJ(x, L0); OBC.FreeRegs({});
					CheckSym(OC.then); StatSeq
				END ;
				IF sym = OC.else THEN OBS.Get(sym); OBE.FJ(L1); OBC.FlushConsts; OBC.FixLink(L0); StatSeq
				ELSE OBC.FixLink(L0)
				END ;
				OBC.FixLink(L1); CheckSym(OC.end)
			ELSIF sym = OC.case THEN
				OBS.Get(sym); CasePart; CheckSym(OC.end)
			ELSIF sym = OC.while THEN
				OBS.Get(sym); L1 := OBC.pc;
				Expression(x); OBE.CFJ(x, L0); OBC.FreeRegs({});
				CheckSym(OC.do); StatSeq; OBE.BJ(L1); OBC.FixLink(L0);
				CheckSym(OC.end)
			ELSIF sym = OC.repeat THEN
				OBS.Get(sym); L0 := OBC.pc; StatSeq;
				IF sym = OC.until THEN
					OBS.Get(sym); Expression(x); OBE.CBJ(x, L0)
				ELSE OBS.Mark(44)
				END
			ELSIF sym = OC.loop THEN
				OBS.Get(sym); ExitIndex := ExitNo; 
				INC(LoopLevel);
				IF LoopLevel>MaxLoopNesting THEN OBS.Mark(257) 
				ELSE ForDepth[LoopLevel-1]:=0;
				END;
				L0 := OBC.pc; StatSeq; OBE.BJ(L0); DEC(LoopLevel);
				WHILE ExitNo > ExitIndex DO
					DEC(ExitNo); OBC.fixup(LoopExit[ExitNo])
				END ;
				CheckSym(OC.end)
			ELSIF sym = OC.for THEN
				OBS.Get(sym);
				IF sym = OC.ident THEN
					qualident(x);
					IF ~(x.typ.form IN {OC.SInt, OC.Int, OC.LInt}) THEN OBS.Mark(68) END ;
					IF sym = OC.becomes THEN
						OBS.Get(sym); Expression(y); OBH.Assign(x, y, FALSE);
						CheckSym(OC.to); Expression(y);
						IF (OC.SInt > y.typ.form) OR (y.typ.form > x.typ.form) THEN
							OBS.Mark(113);
							tempVar:=FALSE; y.mode := OC.Const; y.a := 1; y.typ := OBT.sinttyp
						ELSIF y.mode # OC.Const THEN (*temp var for limit*)
							OBH.TempVar(y); 
							IF (LoopLevel>0) & (LoopLevel<=MaxLoopNesting) THEN INC(ForDepth[LoopLevel-1]) END; 
							tempVar:=TRUE;
						ELSE
							tempVar:=FALSE;
						END ;
						IF sym = OC.by THEN OBS.Get(sym); ConstExpression(z)
						ELSE z.mode := OC.Const; z.a := 1
						END ;
						L0 := OBC.pc; x0 := x; z.typ := x.typ;
						IF z.a > 0 THEN OBE.Op(OC.leq, x0, y)
						ELSIF z.a < 0 THEN OBE.Op(OC.geq, x0, y)
						ELSE OBS.Mark(99)
						END ;
						OBE.CFJ(x0, L1);
						CheckSym(OC.do); StatSeq; CheckSym(OC.end);
						OBE.Inc(x, z); OBE.BJ(L0); OBC.FixLink(L1);
						IF tempVar THEN 
							OBH.RemoveTempVars(1); 
							IF (LoopLevel>0) & (LoopLevel<=MaxLoopNesting) THEN DEC(ForDepth[LoopLevel-1]) END
						END;
					ELSE OBS.Mark(34)
					END
				ELSE OBS.Mark(10)
				END
			ELSIF sym = OC.with THEN
				OBS.Get(sym); x.obj := NIL; xtyp := NIL;
				IF sym = OC.ident THEN
					qualident(x); CheckSym(OC.colon);
					IF sym = OC.ident THEN qualident(y);
						IF y.mode = OC.Typ THEN
							IF x.obj # NIL THEN
								xtyp := x.typ; OBE.TypTest(x, y, FALSE,OC.WithGuardTrap); x.obj.typ := x.typ
							ELSE OBS.Mark(130)
							END
						ELSE OBS.Mark(52)
						END
					ELSE OBS.Mark(10)
					END
				ELSE OBS.Mark(10)
				END ;
				CheckSym(OC.do); OBC.FreeRegs({}); StatSeq; CheckSym(OC.end);
				IF xtyp # NIL THEN x.obj.typ := xtyp END
			ELSIF sym = OC.exit THEN
				IF (LoopLevel>0) & (LoopLevel<=MaxLoopNesting) THEN OBH.RemoveTempVars(ForDepth[LoopLevel-1]) END;
				OBS.Get(sym); OBE.FJ(L0);
				IF LoopLevel = 0 THEN OBS.Mark(46)
				ELSIF ExitNo < MaxExits THEN LoopExit[ExitNo] := L0; INC(ExitNo)
				ELSE OBS.Mark(214)
				END
			ELSIF sym = OC.return THEN OBS.Get(sym);
				IF OBC.level > 0 THEN
					IF sym < OC.semicolon THEN
						Expression(x); OBH.Result(x, OBT.topScope.typ)
					ELSIF OBT.topScope.typ.form # OC.NoTyp THEN OBS.Mark(124)
					END ;
					OBH.Return(FALSE);
				ELSE (*return from module body*)
					IF sym < OC.semicolon THEN Expression(x); OBS.Mark(124) END ;
					OBH.Return(TRUE);
				END
			END ;
			OBC.FreeRegs({});
			IF sym = OC.semicolon THEN OBS.Get(sym)
			ELSIF (sym <= OC.ident) OR (OC.if <= sym) & (sym <= OC.return) THEN OBS.Mark(38)
			ELSE EXIT
			END
		END
	END StatSeq;

	PROCEDURE Block(VAR dsize: LONGINT; proc : OBT.Object);
		VAR typ, forward: OBT.Struct;
			obj, first, par: OBT.Object;
			x: OBT.Item;
			size: LONGINT;
			mk: BOOLEAN;
			id0: ARRAY 32 OF CHAR;

	BEGIN
		obj := OBT.topScope;
		WHILE obj.next # NIL DO obj := obj.next END ;
		LOOP
			IF sym = OC.const THEN
				OBS.Get(sym);
				WHILE sym = OC.ident DO
					COPY(OBS.name, id0); CheckMark(mk);
					IF sym = OC.eql THEN OBS.Get(sym); ConstExpression(x)
					ELSIF sym = OC.becomes THEN OBS.Mark(9); OBS.Get(sym); ConstExpression(x)
					ELSE OBS.Mark(9)
					END ;
					OBT.Insert(id0, obj); obj.mode := OC.Const;
					obj.typ := x.typ; obj.a0 := x.a; obj.a1 := x.b; obj.marked := mk; 
					IF x.obj#NIL THEN obj.ext:=x.obj.ext END;
					CheckSym(OC.semicolon)
				END
			END ;
			IF sym = OC.type THEN
				OBS.Get(sym);
				WHILE sym = OC.ident DO
					openArrayAllowed:=TRUE;
					typ := OBT.undftyp; OBT.InsertType(OBS.name, obj); forward := obj.typ;						
					obj.mode := OC.Typ; obj.typ := OBT.notyp; CheckMark(obj.marked);
					IF sym = OC.eql THEN OBS.Get(sym); 
					Type(typ); AdjustOpenArrayAddrs(typ);
					ELSIF (sym = OC.becomes) OR (sym = OC.colon) THEN OBS.Mark(9); OBS.Get(sym); Type(typ)
					ELSE OBS.Mark(9)
					END ;
					obj.typ := typ;
					IF typ.strobj = NIL THEN typ.strobj := obj END ;
					IF forward # NIL THEN (*fixup*) SetPtrBase(forward, typ) END ;
					CheckSym(OC.semicolon)
				END
			END ;
			IF sym = OC.var THEN
				OBS.Get(sym);
				openArrayAllowed:=FALSE;
				WHILE sym = OC.ident DO
					OBT.Insert(OBS.name, obj); first := obj; CheckMark(obj.marked);
					obj.mode := OC.Var; obj.typ := OBT.undftyp;
					LOOP
						IF sym = OC.comma THEN OBS.Get(sym)
						ELSIF sym = OC.ident THEN OBS.Mark(19)
						ELSE EXIT
						END ;
						IF sym = OC.ident THEN
							OBT.Insert(OBS.name, obj); CheckMark(obj.marked);
							obj.mode := OC.Var; obj.typ := OBT.undftyp
						ELSE OBS.Mark(10)
						END
					END ;
					CheckSym(OC.colon); Type(typ); size := typ.size; 
					IF size >= 4 THEN INC(size, (-size) MOD 4); INC(dsize, (-dsize) MOD 4); 
					ELSIF size = 2 THEN INC(size, size MOD 1); INC(dsize, dsize MOD 2)
					END ;
					WHILE first # NIL DO
						first.typ := typ; INC(dsize, size); first.a0 := -dsize; 
						first := first.next; 
					END ;
					CheckSym(OC.semicolon)
				END
			END ;
			IF (sym < OC.const) OR (sym > OC.var) THEN EXIT END ;
		END ;

		CheckUndefPointerTypes; INC(dsize, (-dsize) MOD 4);
		IF OBC.level = 0 THEN OBC.SetRecTypesOffset(dsize) END ;
		WHILE sym = OC.procedure DO
			OBS.Get(sym); ProcedureDeclaration; CheckSym(OC.semicolon)
		END ;
		IF proc#NIL THEN (* procedure *)
			proc.a0 := OBC.pc; OBC.FixLink(proc.a1);  
			OBH.Enter(proc.mode, dsize);
			par := proc.dsc;
			WHILE par # NIL DO
				(*code for dynamic array value parameters*)
				IF (par.typ.form = OC.DynArr) & (par.mode = OC.Var) THEN
					OBH.CopyDynArray(par.a0, par.typ)
				END ;
				par := par.next
			END
		ELSE (* module body *)
			OBC.moduleBody:=OBC.pc;
			OBH.Enter(OC.Mod,0);
		END;
		IF sym = OC.begin THEN OBS.Get(sym); StatSeq END ;
		CheckSym(OC.end);
	END Block;

	(* print some statistics. do it in a excel-friendly way :-) *)
	PROCEDURE WriteStats;
	BEGIN
		statsEmpty:=FALSE;
		Texts.WriteString(statW,OBE.modName); Texts.Write(statW,",");
		Texts.WriteInt(statW,OBC.nofConstBlocks,1); Texts.Write(statW,",");
		Texts.WriteInt(statW,OBC.constJumpOvers,1); Texts.Write(statW,",");
		Texts.WriteInt(statW,OBC.minConstBlock,1); Texts.Write(statW,",");
		Texts.WriteInt(statW,OBC.maxConstBlock,1); Texts.Write(statW,",");
		Texts.WriteReal(statW,OBC.totConsts/OBC.nofConstBlocks,30); Texts.WriteLn(statW)
	END WriteStats;
	
	PROCEDURE ShowStats;
	VAR txt : Texts.Text;
	BEGIN
		IF statsEmpty THEN RETURN END;
		NEW(txt); Texts.Open(txt,""); 
		Texts.Append(txt, statW.buf); 			
		Oberon.OpenText("Statistics", txt, 600, 300);
	END ShowStats;
	
	PROCEDURE ShowInUse;
	VAR m: Kernel.Module;
	BEGIN
		m := Kernel.modules;
		WHILE (m # NIL) & (m.name # OBE.modName) DO m := m.next END;
		IF m # NIL THEN Texts.WriteString(W, " (in use) ") END
	END ShowInUse;

	PROCEDURE CompilationUnit(source: Texts.Text; pos: LONGINT);
		VAR L0: INTEGER; ch: CHAR;
				time, date, key: LONGINT;
				impid, FName: ARRAY 32 OF CHAR;

	BEGIN
		dsize := 0; LoopLevel := 0; ExitNo := 0; 
		OBC.Init; OBT.Init; OBS.Init(source, pos); OBS.Get(sym);
		Texts.WriteString(W, "  compiling ");
		IF sym = OC.module THEN OBS.Get(sym) ELSE OBS.Mark(16) END ;
		IF sym = OC.ident THEN
			OC.MakeFileName(OBS.name, FName, "");
			Texts.WriteString(W, FName); Texts.Append(Oberon.Log, W.buf);
			L0 := 0; ch := OBS.name[0];
			WHILE (ch # 0X) & (L0 < ModNameLen-1) DO OBE.modName[L0] := ch; INC(L0); ch := OBS.name[L0] END ;
			OBE.modName[L0] := 0X;
			IF ch # 0X THEN OBS.Mark(240) END ;
			OBT.OpenScope(0); 
			OBS.Get(sym);
			CheckSym(OC.semicolon); 
			IF sym = OC.import THEN
				OBS.Get(sym);
				LOOP
					IF sym = OC.ident THEN
						COPY(OBS.name, impid); COPY(OBS.name, FName); OBS.Get(sym);
						IF sym = OC.becomes THEN OBS.Get(sym);
							IF sym = OC.ident THEN
								COPY(OBS.name, FName);
								OBS.Get(sym)
							ELSE OBS.Mark(10)
							END
						END ;
						OBT.Import(impid, OBE.modName, FName);
					ELSE OBS.Mark(10)
					END ;
					IF sym = OC.comma THEN OBS.Get(sym)
					ELSIF sym = OC.ident THEN OBS.Mark(19)
					ELSE EXIT
					END
				END ;
				CheckSym(OC.semicolon)
			END ;
			IF ~OBS.scanerr THEN
				Block(dsize,NIL); OBH.Return(TRUE); OBC.FlushConsts;
				IF sym = OC.ident THEN
					IF OBS.name # OBE.modName THEN OBS.Mark(4) END ;
					OBS.Get(sym)
				ELSE OBS.Mark(10)
				END ;
				IF sym # OC.period THEN OBS.Mark(18) END ;
				IF ~OBS.scanerr THEN
					Oberon.GetClock(time, date); key := (date MOD 4000H) * 20000H + time;
					OC.MakeFileName(OBE.modName, FName, OC.SFext);
					IF ~noFiles THEN OBT.Export(OBE.modName, FName, newSF, key) END;
					IF newSF THEN Texts.WriteString(W, " new symbol file") END ;
					IF ~OBS.scanerr THEN
						OBS.scanerr := noFiles;	(*suppress output file if requested*) 
						OC.MakeFileName(OBE.modName, FName, OC.OFext);
						OBC.OutCode(FName, OBE.modName, key); Texts.Write(W, " ");
						IF (OC.prefix = "") THEN ShowInUse END;
						IF ~OBS.scanerr THEN
							Texts.WriteInt(W, OBC.pc*4, 1); Texts.Write(W, " ");
							Texts.WriteInt(W, dsize, 1);
							IF statistics THEN WriteStats END;
						END
					END
				END
			END ;
			OBT.CloseScope
		ELSE OBS.Mark(10)
		END;
		OBT.Close;
		Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
	END CompilationUnit;

	PROCEDURE Compile*;
		VAR beg, end, time: LONGINT;
			T: Texts.Text;
			S: Texts.Scanner;
			global, local: ARRAY 32 OF CHAR;
		
		PROCEDURE ReadOptions(VAR opt: ARRAY OF CHAR);
		VAR i, j: LONGINT;
		BEGIN
			i := 0;
			WHILE (S.class=Texts.Char) & (S.c = "\") DO
				Texts.Scan(S);
				IF S.class=Texts.Name THEN 
					j := 0;
					WHILE S.s[j] # 0X DO  opt[i] := S.s[j]; INC(i); INC(j)  END;
					opt[i] := " ";  INC(i); Texts.Scan(S)
				END
			END;
			opt[i] := 0X;
		END ReadOptions;
		
		PROCEDURE ParseOptions(opt: ARRAY OF CHAR);
		VAR i, k: LONGINT;  fs: Texts.Scanner;  t: Texts.Text;  beg, end, time: LONGINT;
		BEGIN
			i := 0;
			WHILE opt[i] # 0X DO
				IF opt[i] = "x" THEN OBE.inxchk := ~OBE.inxchk
				ELSIF opt[i] = "t" THEN OBC.typchk:= ~OBC.typchk
				ELSIF opt[i] = "z" THEN OBH.clrchk := ~OBH.clrchk 
				ELSIF opt[i] = "v" THEN OBE.ovfchk := ~OBE.ovfchk
				ELSIF opt[i] = "s" THEN newSF := ~newSF
				ELSIF opt[i] = "a" THEN statistics := ~statistics
				ELSIF opt[i] = "f"  THEN
					Oberon.GetSelection(t, beg, end, time);
					IF time # -1 THEN
						Texts.OpenScanner(fs, t, beg); Texts.Scan(fs);
						end := S.line;
						WHILE (fs.class # Texts.Int) & (fs.line = end) & ~fs.eot DO  Texts.Scan(fs)  END;
						IF (fs.class = Texts.Int) THEN  OBC.trapPos := fs.i DIV 4
						ELSE
							Texts.WriteString(W, "no pc found"); Texts.WriteLn(W);
							Texts.Append(Oberon.Log, W.buf);
							OBC.trapPos := MAX(LONGINT)
						END
					END;
					noFiles := TRUE
				ELSIF opt[i] = "P" THEN
					INC(i);  k := 0;
					WHILE (opt[i] # 0X) & (opt[i] # " ") DO
						OC.prefix[k] := opt[i];  INC(k);  INC(i)
					END;
					OC.prefix[k] := 0X;  INC(k);  DEC(i)
				END;
				INC(i)
			END
		END ParseOptions;
		
		PROCEDURE ApplyOptions;
		BEGIN
			(*set the default values*)
			OBE.inxchk := TRUE; OBC.typchk := TRUE; OBH.clrchk := TRUE; 
			OBE.ovfchk := FALSE; newSF := FALSE; statistics := FALSE; statsEmpty := TRUE;
			noFiles := FALSE; OBC.trapPos := MAX(LONGINT);
			OC.prefix := "arm/";
			ParseOptions(global);  ParseOptions(local);
		END ApplyOptions;

	BEGIN		
		Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos); Texts.Scan(S);
		ReadOptions(global);
		
		IF S.class = Texts.Char THEN
			IF S.c = "*" THEN
				T := Oberon.MarkedText();
				Texts.Scan(S);  ReadOptions(local);  ApplyOptions;
				IF T # NIL THEN CompilationUnit(Oberon.MarkedText(), 0) END
			ELSIF S.c = "^" THEN
				Oberon.GetSelection(T, beg, end, time);
				IF time >= 0 THEN
					Texts.OpenScanner(S, T, beg); Texts.Scan(S);
					IF S.class = Texts.Name THEN
						Texts.WriteString(W, S.s); NEW(T); Texts.Open(T, S.s);
						Texts.Scan(S);  ReadOptions(local);  ApplyOptions;
						IF T.len # 0 THEN CompilationUnit(T, 0)
						ELSE Texts.WriteString(W, " not found");
							Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
						END
					END
				END
			ELSIF S.c = "@" THEN
				Texts.Scan(S);  ReadOptions(local);  ApplyOptions;
				Oberon.GetSelection(T, beg, end, time);
				IF time >= 0 THEN CompilationUnit(T, beg) END
			END
		ELSE 
			NEW(T); OBS.scanerr := FALSE;
			WHILE (S.class = Texts.Name) & ~OBS.scanerr DO
				Texts.WriteString(W, S.s); Texts.Open(T, S.s);
				Texts.Scan(S);  ReadOptions(local);  ApplyOptions;
				IF T.len # 0 THEN CompilationUnit(T, 0)
				ELSE Texts.WriteString(W, " not found");
					Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf);
					OBS.scanerr := TRUE
				END ;
				Oberon.Collect
			END
		END ;
		OC.prefix := "";
		ShowStats;
		Oberon.Collect
	END Compile;

BEGIN 
	Texts.OpenWriter(W);
	Texts.WriteString(W, "Compiler  NW 14.12.93 / as 2.12.98 / prk 09.12.99"); Texts.WriteLn(W);
	Texts.Append(Oberon.Log, W.buf);
	Texts.OpenWriter(statW);
END ACompiler.
