MODULE AOPV;	(* RC 14.3.90 / 17.6.93 *)	(* object model 4.12.93 *)

(*
	Peter Matthias
	2014-11-04	added Ncode
	2015-08-25	changed ActualPar for better register allocation; seems to work now 
	2015-08-26	changed Parameters/Alloc for less register variables
	2015-08-32	changed assign position in stat for less register usage
	2015-10-11	passing static link as first parameter
	2015-11-27	free registers in ActualPar when parameters passed in registers or no function in parameters
	2016-03-17	simplyfied Align, NegAlign
	2016-03-18	initialized OPB.typSize and OPT.typSize in Init; Allocate in Init;
	2016-03-29	allocating 1st and 2nd FP parameters always in FP reg
	2016-11-19	MOPV and VOPV and AOPV are exactly same
	2017-03-10	expr: allocate real const inside code
	2017-04-22	Variables: aligned array to 4
*)

	IMPORT OPM := ROPM, OPB:=ROPB, OPT := ROPT, OPL := AOPL, OPC := AOPC, SYSTEM;
	
	CONST

		(* symbol values and ops *)
		times = 1; slash = 2; div = 3; mod = 4;
		and = 5; plus = 6; minus = 7; or = 8; eql = 9;
		neq = 10; lss = 11; leq = 12; gtr = 13; geq = 14;
		in = 15; is = 16; ash = 17; msk = 18; len = 19;
		conv = 20; abs = 21; cap = 22; odd = 23; not = 33;
		(*SYSTEM*)
		adr = 24; cc = 25; bit = 26; lsh = 27; rot = 28; val = 29;

		(* nodes classes *)
		Nvar = 0; Nvarpar = 1; Nfield = 2; Nderef = 3; Nindex = 4; Nguard = 5; Neguard = 6;
		Nconst = 7; Ntype = 8; Nproc = 9; Nupto = 10; Nmop = 11; Ndop = 12; Ncall = 13;
		Ninittd = 14; Nif = 15; Ncaselse = 16; Ncasedo = 17; Nenter = 18; Nassign = 19;
		Nifelse =20; Ncase = 21; Nwhile = 22; Nrepeat = 23; Nloop = 24; Nexit = 25;
		Nreturn = 26; Nwith = 27; Ntrap = 28; Ncommon = 29;
		Ncode=30;

		(*function number*)
		assign = 0; newfn = 1; incfn = 13; decfn = 14;
		inclfn = 15; exclfn = 16; copyfn = 18; assertfn = 32;

		(*SYSTEM function number*)
		getfn = 24; putfn = 25; getrfn = 26; putrfn = 27; sysnewfn = 30; movefn = 31;
		
		DoCommonDesign = TRUE;	(* was TRUE identify same designators not containing expressions: design := design op expr *)

		WithTrap = 14;
		CaseTrap = 16;
		FuncTrap = 17;

	VAR
		ExitChain, ReturnChain: OPL.Label;
		CommonDesign: OPL.Item;
		CommonDesignClass: SHORTINT;
		assert, findpc: BOOLEAN;
		breakpc: LONGINT;

	PROCEDURE Align(VAR offset: LONGINT; align: LONGINT);
	BEGIN
		INC(offset, (-offset) MOD align)
	END Align;
	
	PROCEDURE NegAlign(VAR offset: LONGINT; align: LONGINT);
	BEGIN
		DEC(offset, offset MOD align)
	END NegAlign;
	
	PROCEDURE Base(typ: OPT.Struct): LONGINT;	(* typ^.comp # DynArr *)
	BEGIN
		WHILE typ^.comp = OPL.Array DO typ := typ^.BaseTyp END ;
		IF typ^.comp = OPL.Record THEN RETURN typ^.align
		ELSE RETURN typ^.size
		END
	END Base;

	PROCEDURE TypeSize*(typ: OPT.Struct);	(* also called from OPT.InStruct for arrays *)
		VAR f, c: INTEGER; offset, size: LONGINT; align, falign: LONGINT;
			fld: OPT.Object; btyp: OPT.Struct;
	BEGIN
		IF typ = OPT.undftyp THEN OPM.err(58)
		ELSIF typ^.size = -1 THEN
			f := typ^.form; c := typ^.comp; btyp := typ^.BaseTyp;
			IF c = OPL.Record THEN
				IF btyp = NIL THEN offset := 0; align := 1
				ELSE TypeSize(btyp); offset := btyp^.size; align := btyp^.align
				END ;
				fld := typ^.link;
				WHILE (fld # NIL) & (fld^.mode = OPT.Fld) DO
					btyp := fld^.typ; TypeSize(btyp);
					size := btyp^.size; falign := Base(btyp); Align(offset, falign);
					fld^.adr := offset; INC(offset, size);
					IF falign > align THEN align := falign END ;
					fld := fld^.link
				END ;
				typ^.align := align;
				Align(offset, Base(typ)); typ^.size := offset;
				typ^.n := -1	(* methods not counted yet *)
			ELSIF c = OPL.Array THEN
				TypeSize(btyp);
				typ^.size := typ^.n * btyp^.size
			ELSIF f = OPL.Pointer THEN
				typ^.size := OPM.PointerSize
			ELSIF f = OPL.ProcTyp THEN
				typ^.size := OPM.ProcSize
			ELSE (* c = DynArr *)
				TypeSize(btyp);
				IF btyp^.comp = OPL.DynArr THEN typ^.size := btyp^.size + 4
				ELSE typ^.size := 8
				END
			END
		END
	END TypeSize;

	PROCEDURE ^Parameters(firstPar, proc: OPT.Object);

	PROCEDURE CountTProcs(rec: OPT.Struct);
		VAR btyp: OPT.Struct;

		PROCEDURE TProcs(obj: OPT.Object);	(* obj^.mnolev = 0, TProcs of base type already counted *)
			VAR redef: OPT.Object;
		BEGIN
			IF obj # NIL THEN
				TProcs(obj^.left);
				IF obj^.mode = OPT.TProc THEN
					OPT.FindField(obj^.name, rec^.BaseTyp, redef);
					(* obj^.adr := 0 *)
					IF redef # NIL THEN obj^.adr := 10000H*(redef^.adr DIV 10000H) (*mthno*) (* + 0 pc *);
						IF ~(OPL.isRedef IN obj^.conval^.setval) THEN OPM.err(119) END
					ELSE obj^.adr := 10000H*rec^.n (* + 0 pc *); INC(rec^.n)
					END ;
					IF ~(OPL.hasBody IN obj^.conval^.setval) THEN OPM.err(129) END
				END ;
				TProcs(obj^.right)
			END
		END TProcs;

	BEGIN
		IF rec^.n = -1 THEN
			rec^.n := 0; btyp := rec^.BaseTyp;
			IF btyp # NIL THEN CountTProcs(btyp); rec^.n := btyp^.n END ;
			TProcs(rec^.link)
		END
	END CountTProcs;

	PROCEDURE ^TProcedures(obj: OPT.Object);

	PROCEDURE TypeAlloc(typ: OPT.Struct);
		VAR f, c: INTEGER; fld: OPT.Object; btyp: OPT.Struct;
	BEGIN
		IF ~typ^.allocated THEN	(* not imported, not predefined, not allocated yet *)
			typ^.allocated := TRUE;
			TypeSize(typ);
			f := typ^.form; c := typ^.comp; btyp := typ^.BaseTyp;
			IF c = OPL.Record THEN
				CountTProcs(typ); OPL.AllocTypDesc(typ);
				IF btyp # NIL THEN TypeAlloc(btyp) END ;
				fld := typ^.link;
				WHILE (fld # NIL) & (fld^.mode = OPT.Fld) DO
					TypeAlloc(fld^.typ); fld := fld^.link
				END ;
				TProcedures(typ^.link)
			ELSIF f = OPL.Pointer THEN
				IF btyp = OPT.undftyp THEN OPM.Mark(128, typ^.txtpos)
				ELSE TypeAlloc(btyp)
				END
			ELSIF f = OPL.ProcTyp THEN
				TypeAlloc(btyp);
				Parameters(typ^.link, NIL)
			ELSE (* c IN {Array, DynArr} *) 
				TypeAlloc(btyp)
			END
		END
	END TypeAlloc;

	PROCEDURE Parameters(firstPar, proc: OPT.Object);
	(* firstPar^.mnolev = 0 *)
		VAR par: OPT.Object; typ: OPT.Struct;
			padr, vadr: LONGINT; f, c, regnr: SHORTINT;
			
		PROCEDURE Alloc(ps, vs: LONGINT);
		BEGIN
			IF  FALSE (*(padr + ps <= 16) & (ps <= 8)*) THEN
				IF (typ^.form IN OPL.realSet) & (par^.mode # OPT.VarPar) THEN
					IF  (f <= OPL.ARF+2 ) THEN par^.adr := f  (* reg nr *); INC(f, OPL.FPRegDist);
					ELSE par^.adr := padr + 64 (* not register-passed *);
					END;
				ELSE par^.adr := padr DIV 4 + regnr; (*f := OPL.ARF+4;*)
				END;
			ELSE par^.adr := padr + 64 (* not register-passed *); (*f:=OPL.ARF+4;*)
			END ;

			IF vs = 0 THEN par^.linkadr := padr + 64
			ELSE NegAlign(vadr, Base(typ)); DEC(vadr, vs); par^.linkadr := vadr
			END ;
			INC(padr, ps)
		END Alloc;
		
	BEGIN
		IF (proc # NIL) & (OPL.slNeeded IN proc^.conval^.setval) THEN padr := 4; regnr:=OPL.ARI-1;	(* static link, passed on stack*)
		ELSE padr := 0; regnr:=OPL.ARI; 
		END;
		vadr := 0; par := firstPar; f := OPL.ARF;
		WHILE par # NIL DO
			typ := par^.typ; c := typ^.comp; TypeAlloc(typ);
			IF c = OPL.DynArr THEN Alloc(typ^.size, 0)
			ELSIF par^.mode = OPT.VarPar THEN
				IF c = OPL.Record THEN Alloc(8, 0)
				ELSE Alloc(4, 0)
				END
			ELSE
				IF c IN {OPL.Record,OPL. Array} THEN Alloc(4, typ^.size)
				ELSIF typ^.form = OPL.LReal THEN Align(padr, 8); Alloc(8, 0)
				ELSE Alloc(4, 0)
				END
			END ;
			par := par^.link
		END ;
		Align(padr, 8);
		IF proc # NIL THEN proc^.conval^.intval := padr; proc^.conval^.intval2 := vadr END
	END Parameters;
	
	PROCEDURE Variables(var: OPT.Object; VAR varSize: LONGINT);	(* allocates only offsets, regs allocated in OPC.Enter *)
		VAR adr: LONGINT; typ: OPT.Struct;
	BEGIN adr := varSize;
		NegAlign(adr, 8);	(* facilitate frame initialization *)
		WHILE var # NIL DO
			typ := var^.typ;
			TypeAlloc(typ);
			NegAlign(adr, Base(typ));
			DEC(adr, typ^.size); 
			IF Base(typ)#typ^.size THEN adr:=adr DIV 4 *4 END;
			var^.adr := adr; var^.linkadr := adr;
			var := var^.link;
		END ;
		NegAlign(adr, 8); varSize := adr
	END Variables;
	
	PROCEDURE ^Objects(obj: OPT.Object);

	PROCEDURE Procedure(obj: OPT.Object);
	(* obj^.mnolev = 0 *)
		VAR oldPos: LONGINT;
	BEGIN
		oldPos := OPM.errpos; OPM.errpos := obj^.scope^.adr;
		TypeAlloc(obj^.typ);
		Parameters(obj^.link, obj);
		IF ~(OPL.hasBody IN obj^.conval^.setval) THEN OPM.err(129) END ;
		Variables(obj^.scope^.scope, obj^.conval^.intval2);	(* local variables *)
		Objects(obj^.scope^.right);
		IF OPL.InterProcInf THEN obj^.conval^.realval := SYSTEM.VAL(LONGREAL, OPL.defaultCalleeUsed) END ;
		OPM.errpos := oldPos
	END Procedure;

	PROCEDURE TProcedures(obj: OPT.Object);
	(* obj^.mnolev = 0 *)
	BEGIN
		IF obj # NIL THEN
			TProcedures(obj^.left);
			IF obj^.mode = OPT.TProc THEN
				TypeAlloc(obj^.typ);
				Parameters(obj^.link, obj);
				Variables(obj^.scope^.scope, obj^.conval^.intval2);	(* local variables *)
				Objects(obj^.scope^.right);
				IF OPL.InterProcInf THEN obj^.conval^.realval := SYSTEM.VAL(LONGREAL, OPL.defaultCalleeUsed) END
			END ;
			TProcedures(obj^.right)
		END
	END TProcedures;

	PROCEDURE Objects(obj: OPT.Object);
	BEGIN
		IF obj # NIL THEN
			Objects(obj^.left);
			IF obj^.mode IN {OPT.Con, OPT.Typ, OPT.LProc, OPT.XProc, OPT.CProc, OPT.IProc} THEN
				IF (obj^.mode IN {OPT.Con, OPT.Typ}) THEN TypeAlloc(obj^.typ);
				ELSE Procedure(obj)
				END
			END ;
			Objects(obj^.right)
		END
	END Objects;

	PROCEDURE Allocate*;
	BEGIN
		OPM.errpos := OPT.topScope^.adr;	(* text position of scope used if error *)
		Variables(OPT.topScope^.scope, OPL.sb);
		Objects(OPT.topScope^.right);
	END Allocate;
	
	PROCEDURE CollectCalls(n: OPT.Node; VAR calleeUsed: OPL.RegSet);
		(* InterProcInf = TRUE, n is a statement *)
		
		PROCEDURE^ expr(n: OPT.Node);
	
		PROCEDURE design(n: OPT.Node);
		BEGIN
			CASE n^.class OF
			  Nvar, Nvarpar:
			| Nfield, Nderef, Nguard, Neguard:
					design(n^.left)
			| Nindex:
					design(n^.left); expr(n^.right)
			| Nproc, Ncommon:
			END
		END design;
	
		PROCEDURE Call(n: OPT.Node);
			VAR used: OPL.RegSet; conval: OPT.Const; proc: OPT.Object;
		BEGIN
			IF n^.left^.class = Nproc THEN
				proc := n^.left^.obj; conval := proc^.conval;
				IF proc^.mnolev >= 0 THEN used := SYSTEM.VAL(OPL.RegSet, conval^.realval);
				ELSE used := OPL.defaultCalleeUsed
				END
			ELSE used := OPL.defaultCalleeUsed
			END ;
			calleeUsed.r := calleeUsed.r + used.r;
			calleeUsed.f := calleeUsed.f + used.f;
			n := n^.right;
			WHILE n # NIL DO expr(n); n := n^.link END
		END Call;
	
		PROCEDURE expr(n: OPT.Node);
		BEGIN
			CASE n^.class OF
			   Nconst:
			| Nmop:
					expr(n^.left);
			| Ndop, Nupto:
					expr(n^.left); expr(n^.right);
			| Ncall:
					Call(n)
			ELSE design(n)
			END
		END expr;
		
		PROCEDURE stat(n: OPT.Node);
			VAR if, case, dim: OPT.Node; subcl: SHORTINT; 
		BEGIN
			WHILE n # NIL DO
				CASE n^.class OF
				  Nenter, Ninittd:
				| Nassign:
						subcl := n^.subcl;
						IF subcl = (*SYSTEM*)movefn THEN
							expr(n^.right^.link); expr(n^.right); expr(n^.left)
						ELSE
							expr(n^.left);
							IF subcl = newfn THEN dim := n^.right;
								WHILE dim # NIL DO expr(dim); dim := dim^.link END
							ELSE expr(n^.right)
							END ;
							IF (subcl = newfn) OR (subcl = sysnewfn) THEN
								calleeUsed.r := calleeUsed.r + OPL.defaultCalleeUsed.r;
								calleeUsed.f := calleeUsed.f + OPL.defaultCalleeUsed.f;
							END
						END
				| Ncall:
						Call(n)
				| Nifelse, Nwith:
						IF (n^.subcl # assertfn) OR assert THEN
							if := n^.left;
							REPEAT expr(if^.left); stat(if^.right); if := if^.link UNTIL if = NIL;
							IF n^.right # NIL THEN stat(n^.right) END
						END
				| Ncase:
						expr(n^.left);
						IF n^.right^.conval^.setval # {} THEN stat(n^.right^.right) END ;
						case := n^.right^.left;
						WHILE case # NIL DO	(* case^.class = Ncasedo *)
							stat(case^.right); case := case^.link
						END
				| Nwhile:
						stat(n^.right); expr(n^.left)
				| Nrepeat:
						stat(n^.left); expr(n^.right)
				| Nloop:
						stat(n^.left)
				| Nexit:
				| Nreturn:
						IF n^.left # NIL THEN expr(n^.left) END ;
				| Ntrap:
				| Ncode:
				END ;
				n := n^.link
			END
		END stat;

	BEGIN
		calleeUsed.r := {}; calleeUsed.f := {}; stat(n)
	END CollectCalls;
	
	PROCEDURE SameDesign(n1, n2: OPT.Node): BOOLEAN;
	BEGIN
		LOOP
			IF (n1^.class # n2^.class) OR (n1^.typ # n2^.typ) THEN RETURN FALSE END ;
			CASE n1^.class OF
			  Nvar, Nvarpar, Nproc: RETURN n1^.obj = n2^.obj
			| Nfield:
					IF n1^.obj # n2^.obj THEN RETURN FALSE END
			| Nderef, Nguard:
			| Nindex:
					IF ~SameDesign(n1^.right, n2^.right) THEN RETURN FALSE END
			ELSE RETURN FALSE
			END ;
			n1 := n1^.left; n2 := n2^.left
		END
	END SameDesign;

	PROCEDURE^ expr(n: OPT.Node; VAR x: OPL.Item; rt: LONGINT);	(* rt # -1 indicates the target register to be used *)

	PROCEDURE design(n: OPT.Node; VAR x: OPL.Item; rt: LONGINT);
		VAR obj: OPT.Object; y: OPL.Item; adr: LONGINT;
	BEGIN
		CASE n^.class OF
		  Nvar, Nvarpar:
				obj := n^.obj; x.mnolev := obj^.mnolev;
				(* CompleteItem: *)
				IF x.mnolev < 0 THEN adr := 64; x.obj := obj
				ELSE adr := obj^.linkadr; x.obj := OPL.GlobData (* GlobData not used if not global *)
				END ;
				IF obj^.typ^.comp = OPL.DynArr THEN (* x set to obj[0], descmode and Tjmp set to descr address *)
					x.mode := OPT.VarPar; x.offset := adr; x.descmode := OPT.Var; x.Tjmp := adr
				ELSE x.mode := obj^.mode; x.offset := adr
				END
		| Nfield:
				design(n^.left, x, rt); OPC.Field(x, n^.obj^.adr, rt)
		| Nderef:
				design(n^.left, x, rt); OPC.DeRef(x, rt);
		| Nindex:
				design(n^.left, x, -1); expr(n^.right, y, -1); OPC.Index(x, y, rt)
		| Nguard:
				design(n^.left, x, rt); OPC.TypTest(x, n^.typ, TRUE, FALSE)
		| Neguard:
				design(n^.left, x, rt); OPC.TypTest(x, n^.typ, TRUE, TRUE)
		| Nproc:
				obj := n^.obj; x.mode := obj^.mode; x.mnolev := obj^.mnolev; x.obj := obj;
				IF x.mode = OPT.TProc THEN x.offset := (*mthno*) obj^.adr DIV 10000H; x.Tjmp := n^.subcl END
		| Ncommon:
				x := CommonDesign; n^.class := CommonDesignClass	(* restore class, may be compiled twice (findpc option!) *)
		END ;
		x.typ := n^.typ
	END design;
	
	PROCEDURE ActualPar(n, receiver: OPT.Node; fp: OPT.Object; VAR proc: OPL.Item);
		VAR ap: OPL.Item; rt: LONGINT; fip: BOOLEAN;	(* fip=function in parameters *)

	PROCEDURE HasFunction(n: OPT.Node);
	VAR c: SHORTINT;
	BEGIN
		IF n# NIL THEN
			c:=n^.class;
			IF c=Ncall THEN fip:=TRUE;
			ELSIF c=Nmop THEN HasFunction( n^.left);
			ELSIF c=Ndop THEN
				HasFunction( n^.left);
				HasFunction( n^.right);
			END;
			HasFunction( n^.link);
		END;		
	END HasFunction;

	BEGIN
		IF n # NIL THEN
(*	original 
			IF (fp^.adr < 64) THEN (* reg *) rt := fp^.adr ELSE rt := -1 END ;
			expr(n, ap, rt);
			OPC.Relation(ap, rt);
			ActualPar(n^.link, receiver, fp^.link, proc);	
			IF n = receiver THEN OPC.LoadMTA(ap, proc.Tjmp = 1, n^.class = Nderef, proc) END ;
			OPC.Param(ap, fp, n^.class = Nderef);
*)
(*
			ActualPar(n^.link, receiver, fp^.link, proc);	
			expr(n, ap, -1);
			OPC.Relation(ap, rt);
			OPC.Param(ap, fp, n^.class = Nderef);
*)

			expr(n, ap, -1);
			fip:=FALSE;
			HasFunction(n^.link);
			IF ~fip THEN OPC.Relation(ap, -1); OPC.Param(ap, fp, n^.class = Nderef) END;	(* freeing registers only works without function parameter. and without reg param?*)
			ActualPar(n^.link, receiver, fp^.link, proc);
			IF n = receiver THEN HALT(255); (*OPC.LoadMTA(ap, proc.Tjmp = 1, n^.class = Nderef, proc) *) END;	(* seems to be never executed *)
			IF fip THEN OPC.Relation(ap, -1); OPC.Param(ap, fp, n^.class = Nderef) END;	(* not freeing registers *)

		END
	END ActualPar;

	PROCEDURE Call(n: OPT.Node; VAR x: OPL.Item);
		VAR proc: OPT.Object; conval: OPT.Const; calleeUsed, saved, live: OPL.RegSet;
			argSize: LONGINT; resForm: SHORTINT; receiver: OPT.Node; 

		PROCEDURE ArgSize(par: OPT.Object): LONGINT;	(* no static link *)
			VAR s: LONGINT; c: SHORTINT; typ: OPT.Struct;
		BEGIN s := 0;
			WHILE par # NIL DO
				typ := par^.typ; c := typ^.comp;
				IF c = OPL.DynArr THEN INC(s, typ^.size)
				ELSIF par^.mode = OPT.VarPar THEN
					IF c = OPL.Record THEN INC(s, 8) ELSE INC(s, 4) END
				ELSE
					IF c IN {OPL.Record, OPL.Array} THEN INC(s, 4)
					ELSIF typ^.form = OPL.LReal THEN INC(s, 8 + s MOD 8)
					ELSE INC(s, 4)
					END
				END ;
				par := par^.link
			END ;
			RETURN s + s MOD 8
		END ArgSize;
	
	BEGIN
		IF n^.left^.class = Nproc THEN
			proc := n^.left^.obj; conval := proc^.conval;
			IF OPL.InterProcInf & (proc^.mnolev >= 0) THEN calleeUsed := SYSTEM.VAL(OPL.RegSet, conval^.realval)
			ELSE calleeUsed := OPL.defaultCalleeUsed
			END ;
			IF proc^.mnolev >= 0 THEN argSize := conval^.intval
			ELSE
				IF conval^.intval = -1 THEN conval^.intval := ArgSize(proc^.link) END ;
				argSize := conval^.intval
			END ;
			INCL(conval^.setval, OPL.alreadyCalled);
			resForm := proc^.typ^.form
		ELSE
			proc := NIL; calleeUsed := OPL.defaultCalleeUsed;
			resForm := n^.left^.typ^.BaseTyp^.form; argSize := ArgSize(n^.left^.typ^.link)
		END ;
		IF resForm # OPL.NoTyp THEN
			IF resForm IN OPL.realSet THEN INCL(calleeUsed.f, OPL.RRF MOD 32)
			ELSE INCL(calleeUsed.r, OPL.RRI)
			END
		END ;
		OPL.SaveRegisters(calleeUsed, argSize, saved, live); 
		design(n^.left, x, -1);
		IF (proc # NIL) & (proc.mode = OPT.TProc) THEN receiver := n^.right ELSE receiver := NIL END ;
		ActualPar(n^.right, receiver, n^.obj, x);
		OPC.Call(x, proc);
		OPL.RestoreRegisters(x, argSize, saved, live);
	END Call;
	
	PROCEDURE expr(n: OPT.Node; VAR x: OPL.Item; rt: LONGINT);	(* rt # -1 indicates the target register to be used *)
		VAR y, z: OPL.Item; f, g: SHORTINT; cval: OPT.Const;
	BEGIN
		CASE n^.class OF
		   Nconst:
				x.typ := n^.typ; f := n.typ^.form; cval := n^.conval;
				CASE f OF
				  OPL.Byte..OPL.LInt, OPL.NilTyp, OPL.Pointer:
						x.mode := OPT.Con; x.offset := cval^.intval
				| OPL.Set:
						x.mode := OPT.Con; x.offset := SYSTEM.VAL(LONGINT, cval^.setval)
				| OPL.Real:
						x.mode := OPT.Con; x.offset := SYSTEM.VAL(LONGINT, SHORT(cval^.realval))
				| OPL.String, (*OPL.Real,*) OPL.LReal:
						IF (n^.obj = NIL) OR (n^.obj^.conval^.intval = OPM.ConstNotAlloc) THEN
							IF f = OPL.String THEN OPL.AllocString(cval^.ext^, cval^.intval2, x.offset)
(*							ELSIF f = OPL.Real THEN OPL.AllocReal(SHORT(cval^.realval), x.offset)*)
							ELSE (* LReal *) OPL.AllocLReal(cval^.realval, x.offset);
							END ;
							IF n^.obj # NIL THEN n^.obj^.conval^.intval := x.offset END
						ELSE x.offset := n^.obj^.conval^.intval
						END ;
						x.mode := OPT.Var; x.mnolev := 0; x.obj := OPL.GlobData; x.Tjmp := cval^.intval2
				END
		| Nupto:	(* n^.typ = OPT.settyp *)
				expr(n^.left, y, -1); expr(n^.right, z, -1); OPC.SetRange(x, y, z, rt)
		| Nmop:
				expr(n^.left, x, rt);
				CASE n^.subcl OF
				   not:
						OPC.Not(x)
				| minus:
						OPC.Neg(x, rt)
				| is:
						OPC.TypTest(x, n^.obj^.typ, FALSE, FALSE)
				| conv:
						f := x.typ^.form; g := n^.typ^.form;
						IF g = OPL.Set THEN OPC.SetElem(x, rt)
						ELSE OPC.Convert(x, rt, f, g)
						END
				| abs:
						OPC.AbsVal(x, rt)
				| cap:
						OPC.Cap(x, rt)
				| odd:
						OPC.Odd(x, rt)
				| (*SYSTEM*)adr:
						OPL.LoadAddr(x, rt)
				| (* SYSTEM.*) val:
						OPC.SYSval(x, rt, x.typ^.form, n^.typ^.form)
				| (*SYSTEM*)cc:
				END ;
				x.typ := n^.typ
		| Ndop:
				expr(n^.left, x, -1); f := x.typ^.form;
				IF n^.subcl = and THEN OPC.CondAnd(x)
				ELSIF n^.subcl = or THEN OPC.CondOr(x)
				ELSIF (n^.subcl >= eql) & (n^.subcl <= geq) THEN OPC.Relation(x, -1)
				END ;
				expr(n^.right, y, -1);
				CASE n^.subcl OF
				   times:
						IF f = OPL.Set THEN OPC.SetInter(x, y, rt)
						ELSE OPC.Mul(x, y, rt, f IN OPL.realSet)
						END
				| slash:
						IF f = OPL.Set THEN OPC.SetSymmDiff(x, y, rt)
						ELSE OPC.Div(x, y, rt, TRUE)
						END
				| div:
						OPC.Div(x, y, rt, FALSE)
				| mod:
						OPC.Mod(x, y, rt)
				| and:
						OPC.And(x, y)
				| plus:
						IF f = OPL.Set THEN OPC.SetUnion(x, y, rt)
						ELSE OPC.Add(x, y, rt, f IN OPL.realSet)
						END
				| minus:
						IF f = OPL.Set THEN OPC.SetDiff(x, y, rt)
						ELSE OPC.Sub(x, y, rt, f IN OPL.realSet)
						END
				| or:
						OPC.Or(x, y)
				| eql..geq:
						OPC.Cmp(x, y, n^.subcl)
				| in:
						OPC.In(x, y)
				| ash:
						OPC.Ash(x, y, rt)
				| msk:
						OPC.Msk(x, y, rt)
				| len:
						OPC.Len(x, y)
				| (*SYSTEM*)bit, lsh, rot:
						OPC.SYSdop(x, y, n^.subcl, rt)
				END ;
		| Ncall:
				Call(n, x)
		ELSE design(n, x, rt)
		END ;
		x.typ := n^.typ
	END expr;
	
	PROCEDURE Checkpc;
	BEGIN
		IF findpc & (OPL.pc > breakpc) & OPM.noerr THEN OPM.err(255) END
		(* in the case of a call, the breakpc value shown in the trap viewer must point to the call instruction
			and not to the next instruction, i.e. breakpc # return address !! *)
	END Checkpc;

	PROCEDURE stat(n: OPT.Node);
		VAR x, y, nofel: OPL.Item; L, Lcbj, prevExitChain: OPL.Label;
			btyp: OPT.Struct;
			rt, ry: LONGINT; subcl: SHORTINT; calleeUsed, saved, live: OPL.RegSet;
		
		PROCEDURE IfStat(n: OPT.Node; withtrap: BOOLEAN);
			VAR x: OPL.Item; Lcfj, Lfix: OPL.Label; if: OPT.Node;
		BEGIN	(* n^.class = Nif *)
			Lfix := 0; if := n^.left;
			LOOP
				OPM.errpos := if^.conval^.intval;
				expr(if^.left, x, -1); OPC.FJf(x, Lcfj); Checkpc; stat(if^.right); if := if^.link;
				IF if = NIL THEN EXIT END ;
				OPC.FJ(Lfix); OPL.FixLink(Lcfj)
			END ;
			IF (n^.right # NIL) OR withtrap THEN OPC.FJ(Lfix); OPL.FixLink(Lcfj);
				IF withtrap THEN OPL.PutTrap( -1, WithTrap); OPM.errpos := n^.conval^.intval; Checkpc
				ELSE stat(n^.right)
				END
			ELSE OPL.FixLink(Lcfj)
			END ;
			OPL.FixLink(Lfix)
		END IfStat;
		
		PROCEDURE CaseStat(n: OPT.Node);
			VAR x: OPL.Item; Lfix, tab: OPL.Label;
				case, lab: OPT.Node; low, high: LONGINT;
		BEGIN
			expr(n^.left, x, -1); low := n^.right^.conval^.intval; high := n^.right^.conval^.intval2;
			OPC.Case(x, low, high, tab); Checkpc; Lfix := 0; 
			IF n^.right^.conval^.setval # {} THEN stat(n^.right^.right); OPC.FJ(Lfix);
			ELSE OPL.PutTrap( -1, CaseTrap);
			END ;
			case := n^.right^.left;
			WHILE case # NIL DO	(* case^.class = Ncasedo *)
				lab := case^.left;
				WHILE lab # NIL DO
					OPC.CaseJump(tab, lab^.conval^.intval - low, lab^.conval^.intval2 - low);
					lab := lab^.link
				END ;
				stat(case^.right); OPC.FJ(Lfix);
				case := case^.link
			END ;
			OPL.FixLink(Lfix)
		END CaseStat;
		
		PROCEDURE Dim(VAR x, y, nofel: OPL.Item; n: OPT.Node; dimtyp, dim0typ: OPT.Struct);
			VAR len: OPL.Item; calleeUsed, saved, live: OPL.RegSet;
		BEGIN
			expr(n, len, -1); OPC.MulDim(len, nofel, dimtyp, dim0typ);
			IF n^.link # NIL THEN
				Dim(x, y, nofel, n^.link, dimtyp^.BaseTyp, dim0typ);
			ELSE
				calleeUsed := OPL.defaultCalleeUsed; INCL(calleeUsed.r, OPL.RRI);
				OPL.SaveRegisters(calleeUsed, 8, saved, live);	(* argsize aligned to 8 *)
				OPC.New(x, nofel);
				y.typ := x.typ; OPL.RestoreRegisters(y, 8, saved, live)
			END ;
			OPC.SetDim(y, len, dimtyp)
		END Dim;

		PROCEDURE Enter(n: OPT.Node);
			VAR proc, type: OPT.Object; i, j, pc, pcOffset: INTEGER;
				ch: CHAR; name: ARRAY 64 OF CHAR; calleeUsed: OPL.RegSet;
		BEGIN
			proc := n^.obj;
			IF proc = NIL THEN (* enter module *)
				calleeUsed := OPL.defaultCalleeUsed;
				OPL.Enter(NIL, calleeUsed);
				OPC.Enter(NIL);
				pc := OPL.pc;
				LOOP
					ReturnChain := 0; stat(n^.right); OPL.FixLink(ReturnChain);
					OPL.Exit(NIL, calleeUsed, pcOffset);
					IF (OPL.pc > OPM.breakpc DIV 4) & OPM.noerr THEN breakpc := OPM.breakpc DIV 4 + pcOffset; OPL.pc := pc
					ELSE EXIT
					END
				END ;
				name := "$$"; OPL.OutRefPoint; OPL.OutRefName(name); OPL.OutRefs(OPT.topScope);
				INC(OPL.level); stat(n^.left); DEC(OPL.level)
			ELSE (* enter proc *)
				INC(OPL.level); stat(n^.left); DEC(OPL.level);
				IF OPL.InterProcInf THEN CollectCalls(n^.right, calleeUsed)
				ELSE calleeUsed := OPL.defaultCalleeUsed
				END ;
				OPL.Enter(proc, calleeUsed);
				OPC.Enter(proc);
				OPC.InitPtrs(proc);
				pc := OPL.pc;
				LOOP
					ReturnChain := 0;
					stat(n^.right);
					IF n^.obj^.typ # OPT.notyp THEN OPL.PutTrap( -1, FuncTrap) END ;
					OPL.FixLink(ReturnChain);
					OPL.Exit(proc, calleeUsed, pcOffset);
					IF OPL.InterProcInf THEN
						proc^.conval^.realval := SYSTEM.VAL(LONGREAL, calleeUsed)
					END ;
					IF (OPL.pc > OPM.breakpc DIV 4) & OPM.noerr THEN breakpc := OPM.breakpc DIV 4 + pcOffset; OPL.pc := pc
					ELSE EXIT
					END
				END ;
				OPL.OutRefPoint;
				IF proc^.mode = OPT.TProc THEN
					type := proc^.link^.typ^.strobj;
					name[0] := "("; i := 1; ch := type^.name[0];
					WHILE ch # 0X DO name[i] := ch; ch := type^.name[i]; INC(i) END ;
					name[i] := ")"; INC(i); j := 0; ch := proc^.name[0];
					WHILE (ch # 0X) & (i < 63) DO name[i] := ch; INC(i); INC(j); ch := proc^.name[j] END ;
					name[i] := 0X;
				ELSE COPY(proc^.name, name)
				END ;
				OPL.OutRefName(name); OPL.OutRefs(proc^.scope^.right)
			END
		END Enter;
		
		PROCEDURE Mem(n: OPT.Node; VAR x: OPL.Item);
			VAR offset: LONGINT;
		BEGIN
			IF (n^.class = Ndop) & (n^.subcl IN {plus, minus}) & (n^.right^.class = Nconst) THEN
				expr(n^.left, x, -1); offset := n^.right^.conval^.intval;
				IF n^.subcl = minus THEN offset := -offset END ;
				OPC.Mem(x, offset)
			ELSE
				expr(n, x, -1); OPC.Mem(x, 0)
			END
		END Mem;

	BEGIN	(* stat *)
		WHILE (n # NIL) & OPM.noerr DO OPM.errpos := n^.conval^.intval; OPL.BegStat;
			CASE n^.class OF
			  Nenter:
					Enter(n)
			| Ninittd:
					(* done at load-time *)
			| Nassign:
					subcl := n^.subcl;
					IF subcl = (*SYSTEM*)movefn THEN	(* x^ := first nofel bytes at y *)
						expr(n^.right^.link, nofel, -1); expr(n^.right, y, -1); expr(n^.left, x, -1);
						OPC.SYSmove(x, y, nofel, FALSE)
					ELSE
						IF subcl = putfn THEN Mem(n^.left, x)
						ELSE expr(n^.left, x, -1)
						END ;
						IF x.mode = OPL.Reg THEN rt := x.reg
						ELSIF (x.mode = OPT.Var) & (x.offset >= 0) & (x.offset < 64) THEN rt := x.offset
						ELSE rt := -1
						END;
						IF subcl IN {assign, getfn, getrfn} THEN ry := rt ELSE ry := -1 END ;
						IF DoCommonDesign & (subcl = assign) & (n^.right^.class IN {Nmop, Ndop}) & SameDesign(n^.left, n^.right^.left) THEN
							OPC.CommonDesign(x); CommonDesign := x;
							CommonDesignClass := n^.right^.left^.class; n^.right^.left^.class := Ncommon
						END;
						IF subcl = getfn THEN Mem(n^.right, y)
						ELSIF ~(subcl IN {newfn, sysnewfn}) THEN expr(n^.right, y, ry)
						END;
						CASE subcl OF
						     assign:
								OPC.Assign(x, y, rt)
					  | newfn:
								btyp := x.typ^.BaseTyp;
								IF n^.right # NIL THEN (*open array*)
									Dim(x, y, nofel, n^.right, btyp, btyp)
								ELSE
									calleeUsed := OPL.defaultCalleeUsed; INCL(calleeUsed.r, OPL.RRI);
									OPL.SaveRegisters(calleeUsed, 8, saved, live);	(* argsize aligned to 8 *)
									OPC.New(x, nofel);	(* nofel not used for record or array *)
									y.typ := x.typ; OPL.RestoreRegisters(y, 8, saved, live)
								END ;
								OPC.Assign(x, y, rt)
						| incfn, decfn:
								OPC.Increment(x, y, rt, subcl = decfn)
						| inclfn, exclfn:
								OPC.Include(x, y, rt, subcl = exclfn)
						| copyfn:
								OPC.Copy(x, y)
						| (*SYSTEM*)getfn, putfn, getrfn, putrfn:
								OPC.SYSgetput(x, y, subcl)
						| (*SYSTEM*)sysnewfn:
								calleeUsed := OPL.defaultCalleeUsed; INCL(calleeUsed.r, OPL.RRI);
								OPL.SaveRegisters(calleeUsed, 8, saved, live);	(* argsize aligned to 8 *)
								expr(n^.right, y, 4); OPC.SYSnew(y);
								y.typ := x.typ; OPL.RestoreRegisters(y, 8, saved, live);
								OPC.Assign(x, y, rt)
						END
					END
			| Ncall:
					Call(n, x)
			| Nifelse:
					IF (n^.subcl # assertfn) OR assert THEN IfStat(n, FALSE) END
			| Ncase:
					CaseStat(n)
			| Nwhile:
					L := 0; OPC.FJ(L); Lcbj := OPL.pc+1-OPL.pcahead; stat(n^.right); OPL.Fixup(L);
					OPM.errpos := n^.conval^.intval; expr(n^.left, x, -1); OPC.BJt(x, Lcbj)
			| Nrepeat:
					L := OPL.pc+1-OPL.pcahead; stat(n^.left); expr(n^.right, x, -1); OPC.BJf(x, L)
			| Nloop:
					prevExitChain := ExitChain; ExitChain := 0;
					L := OPL.pc+1-OPL.pcahead; stat(n^.left); OPC.BJ(L);
					OPL.FixLink(ExitChain); ExitChain := prevExitChain
			| Nexit:
					OPC.FJ(ExitChain)
			| Nreturn:
					IF n^.left # NIL THEN
						IF n^.left^.typ^.form IN {OPL.Real, OPL.LReal} THEN rt := OPL.RRF ELSE rt := OPL.RRI END ;
						expr(n^.left, x, rt); OPC.Result(n^.obj, x)
					END ;
					OPC.FJ(ReturnChain)
			| Nwith:
					IfStat(n, n^.subcl = 0)
			| Ntrap:
					OPL.PutTrap( -1, n^.right^.conval^.intval);
			| Ncode:
					OPL.PutI(n^.right^.conval^.intval, 0, 0, 0)
			END ;
			Checkpc; OPL.EndStat; n := n^.link
		END
	END stat;

	PROCEDURE Init*;
		CONST ass = 7; fpc = 8;
	BEGIN
		OPT.typeSize := TypeSize;
		OPL.Init(OPM.opt); OPC.Init(OPM.opt);
		assert := ass IN OPM.opt; findpc := fpc IN OPM.opt;
		IF ~findpc THEN OPM.breakpc := MAX(LONGINT) END;
		breakpc := MAX(LONGINT);
		Allocate;
	END Init;
	
	PROCEDURE Module*;
	BEGIN
		OPM.NewRefObj(OPT.SelfName);
		stat(OPT.prog);
		IF findpc & OPM.noerr THEN OPM.err(254) END;
		IF OPM.noerr THEN OPL.OutCode
		ELSE OPM.DeleteRefObj 
		END
	END Module;

BEGIN Init;
END AOPV.