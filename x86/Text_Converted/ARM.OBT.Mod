MODULE OBT;  (*NW 28.5.87 / 10.7.93*)

	IMPORT Files, OBS, OC := OBM;

	CONST 
			SFtag = 0F7X; firstStr = 17;
			maxEnt = 256; maxStr = 256; maxUDP = 32; maxMod = 24; maxParLev = 6;
			PtrSize = 4; ProcSize = 4; NotYetExp = 0;
			
		(* Standard Function Numbers *)
			(* functions/procs with one parameter *)
			FnHalt* = 0; FnNew* = 1; FnSysCC* = 2; FnAbs* = 3; FnCap* = 4; FnOrd* = 5;
			FnEntier* = 6; FnSize* = 7; FnOdd* = 8; FnSysAdr* = 9; FnMin* = 10;
			FnMax* = 11; FnChr* = 12; FnShort* = 13; FnLong* = 14; FnSysHalt*=15; FnAssert*=16;
			FnSysEnableInterrupts* = 17; FnSysDisableInterrupts* = 18; FnSysRestoreInterrupts* = 19;
			(* functions/procs with >=2 parameters allowed *)
			FnInc* = 30; FnDec* = 31; FnIncl* = 32; FnExcl* = 33; FnLen* = 34; FnAsh* = 35; 
			FnSysLsh* = 36; FnSysRot* = 37; FnSysGet* = 38; FnSysPut* = 39; FnSysBit* = 40; 
			FnSysVal* = 41; FnSysNew* = 42; FnCopy* = 43; FnSysMove* = 44;  
			FnSysGetReg* = 45; FnSysPutReg* = 46;

	TYPE
		Object* = POINTER TO ObjDesc;
		Struct* = POINTER TO StrDesc;

		ConstExt* = RECORD
								str*: ARRAY 128 OF CHAR;
								entered* : BOOLEAN;
							END;
		
		ObjDesc* = RECORD
								dsc*, next*: Object;
								typ*:  Struct;
								a0*, a1*, a2* : LONGINT;
								mode*: SHORTINT;
								marked*: BOOLEAN;
								name*: ARRAY 32 OF CHAR;
								ext* : POINTER TO ConstExt;
							END ;

		StrDesc* = RECORD
								form*, extlev*, mno*: INTEGER;
								ref*: SHORTINT;
								size*, adr*: LONGINT;
								BaseTyp*: Struct;
								link*, strobj*: Object
							END ;

		Item* =    RECORD
								mode*, lev*: LONGINT;
								a*, b*, r* : LONGINT; 
								typ*: Struct;
								obj*: Object
							END ;

	(** Item forms:
		mode    a       b       r         Remarks
		------------------------------------------------------------
		Var     offset  -       basereg   [basereg, offset], Pre-Inc/Dec, no write-back
		Var1    ofsreg  scale   basereg   [basereg, ofsreg LSL scale] Pre-Inc/Dec, no wb
		Var2    offset  -       basereg   [basereg, offset] Pre-Inc/Dec, write-back
		Par     adr     offset  basereg   [[basereg,adr]+offset]
		Par1	adr     ofsreg  basereg   [[basereg,adr]+ofsreg]
		Const   value/procadr
				adr     len  (String-Consts)
		Reg     -       -       reg
		RegX    reg2    -       reg1
		CC      Tchain  Fchain  condition  
		LProc   adr/pno -       -
		Fld     offset  -       -   
	*)

	(* Objects and Items:

		mode  | a0    a1     dsc   | lev  a0   a1   a2   obj   ext
	 -------------------------------------------------------------
  	0 Undef |                    |
  	1 Var   | adr/vno            | lev  adr/vno        obj
  	2 VarX  |                    | lev  adr       RX
  	3 Ind   |                    | lev  adr  off
  	4 IndX  |                    | lev  adr  off  RX
  	5 RegI  |                    |      R    off
  	6 RegX  |                    |      R    off  RX
  	7 Abs   |                    |      adr
  	8 Con   | val                |      val0 val1
  			| adr   len          |      adr  len             data (Strings)
  	9 Stk   |                    |
	 10 Coc   |                    |      CC   Tjmp Fjmp
	 11 Reg   |                    |      R
	 12 Fld   | off                |      off            obj
	 13 Typ   |                    | mno  adr            obj
	 14 LProc | adr/pno fixl  par  |      adr/pno        obj
	 16 SProc | fno                |      fno
	 17 CProc | cno          par   |      cno            obj
	 18 IProc | adr                |      adr            obj
	 19 Mod   | mno   key          |      mno            obj
	 20 Head  | lev                |

		Structures:

		form    | n     BaseTyp   link     mno   adr   
	--------------------------------------------------
  	0 Undef   |
  	1 Byte    |
  	2 Bool    |
  	3 Char    |
  	4 SInt    |
  	5 Int     |
  	6 LInt    |
  	7 Real    |
  	8 LReal   |
  	9 Set     |
	 10 String  |
	 11 NilTyp  |
	 12 NoTyp   |
	 13 SysPtr  |
	 14 Pointer |       PBaseTyp
	 15 ProcTyp |       ResTyp    param        
 	16 Array   |       ElemTyp
	 17 DynArr  |       ElemTyp
	 18 Record  | exlev RBaseTyp  fields   mno   descr  *)

	VAR topScope*: Object;
		undftyp*, bytetyp*, booltyp*, chartyp*, sinttyp*, inttyp*, linttyp*,
		realtyp*, lrltyp*, settyp*, stringtyp*, niltyp*, notyp*, sysptrtyp*: Struct;
		nofGmod*, entno*: INTEGER;   (*nof imports, nof entries*)
		GlbMod*:  ARRAY OC.MaxImps OF Object;
		entry*: ARRAY maxEnt OF LONGINT;
		softfloatImport* : Object;

		universe, syslink: Object;
		strno, udpinx: INTEGER;  (*for export*)
		nofExp: SHORTINT;
		undPtr: ARRAY maxUDP OF Struct;

	PROCEDURE Init*;
	BEGIN topScope := universe; strno := 0; udpinx := 0; nofGmod := 0; softfloatImport := NIL;
	END Init;

	PROCEDURE Close*;
	BEGIN
		WHILE nofGmod > 0 DO DEC(nofGmod); GlbMod[nofGmod] := NIL END
	END Close;

	PROCEDURE IsParam*(obj : Object) : BOOLEAN;
	BEGIN
		RETURN (obj # NIL) & (obj.mode IN {OC.Var, OC.Par}) & (obj.a0 > 0)
	END IsParam;

	PROCEDURE HasPtr*(typ : Struct) : BOOLEAN;
		VAR fld: Object;
	BEGIN
		IF (typ.form = OC.Pointer) OR (typ.form = OC.SysPtr) THEN RETURN TRUE
		ELSIF (typ.form = OC.Array) OR (typ.form=OC.DynArr) THEN RETURN HasPtr(typ.BaseTyp)
		ELSIF typ.form = OC.Record THEN
			IF (typ.BaseTyp # NIL) & HasPtr(typ.BaseTyp) THEN RETURN TRUE END ;
			fld := typ.link;
			WHILE fld # NIL DO
				IF (fld.name = "") OR HasPtr(fld.typ) THEN RETURN TRUE END ;
				fld := fld.next
			END
		END ;
		RETURN FALSE
	END HasPtr;
		
	PROCEDURE FindImport*(mod: Object; VAR res: Object);
		VAR obj: Object;
	BEGIN obj := mod.dsc;
		WHILE (obj # NIL) & (obj.name # OBS.name) DO obj := obj.next END ;
		IF (obj # NIL) & (obj.mode = OC.Typ) & ~obj.marked THEN obj := NIL END ;
		res := obj
	END FindImport;

	PROCEDURE Find*(VAR res: Object; VAR level: INTEGER);
		VAR obj, head: Object;
	BEGIN head := topScope;
		LOOP obj := head.next;
			WHILE (obj # NIL) & (obj.name # OBS.name) DO obj := obj.next END ;
			IF obj # NIL THEN level := SHORT(head.a0); EXIT END ;
			head := head.dsc;
			IF head = NIL THEN level := 0; EXIT END
		END ;
		res := obj
	END Find;

	PROCEDURE FindField*(typ: Struct; VAR res: Object);
		VAR obj: Object;
	BEGIN (*typ.form = Record*)
		LOOP obj := typ.link;
			WHILE (obj # NIL) & (obj.name # OBS.name) DO obj := obj.next END ;
			IF obj # NIL THEN EXIT END ;
			typ := typ.BaseTyp;
			IF typ = NIL THEN EXIT END
		END ;
		res := obj
	END FindField;

	PROCEDURE Insert*(VAR name: ARRAY OF CHAR; VAR res: Object);
		VAR obj, new: Object;
	BEGIN obj := topScope;
		WHILE (obj.next # NIL) & (obj.next.name # name) DO obj := obj.next END ;
		IF obj.next = NIL THEN NEW(new);
			new.dsc := NIL; new.next := NIL; COPY(name, new.name); obj.next := new; res := new
		ELSE OBS.Mark(1); (*multiple declaration*) res := obj.next
		END
	END Insert;

	PROCEDURE InsertType*(VAR name: ARRAY OF CHAR; VAR res: Object);
		VAR obj, new: Object;
	BEGIN obj := topScope;
		WHILE (obj.next # NIL) & (obj.next.name # name) DO obj := obj.next END ;
		IF obj.next = NIL THEN NEW(new);
			new.dsc := NIL; new.next := NIL; COPY(name, new.name); obj.next := new; res := new
		ELSIF obj.next.mode # OC.Undef THEN OBS.Mark(1); res := obj.next
		ELSE (*forward type decl*) res := obj.next
		END
	END InsertType;

	PROCEDURE Remove*(proc: Object);
		VAR obj: Object;
	BEGIN obj := topScope;
		WHILE obj.next # proc DO obj := obj.next END ;
		obj.next := proc.next
	END Remove;

	PROCEDURE OpenScope*(level: INTEGER);
		VAR head: Object;
	BEGIN NEW(head);
		head.mode := OC.Head; head.a0 := level; head.typ := NIL;
		head.dsc := topScope; head.next := NIL; topScope := head
	END OpenScope;

	PROCEDURE CloseScope*;
	BEGIN topScope := topScope.dsc
	END CloseScope;

	(*---------------------- import ------------------------*)

	PROCEDURE Import*(VAR name, self, ModName: ARRAY OF CHAR);
		VAR i, m, s, class: INTEGER; k: LONGINT;
				nofLmod, strno, parlev, fldlev: INTEGER;
				obj, ob0: Object;
				typ: Struct;
				ch, ch1: CHAR;
				si: SHORTINT;
				SymFile: Files.File; R: Files.Rider;
				modname, FileName: ARRAY 32 OF CHAR;
				LocMod:  ARRAY maxMod OF Object;
				struct:  ARRAY maxStr OF Struct;
				lastpar, lastfld: ARRAY maxParLev OF Object;

		PROCEDURE reversedList(p: Object): Object;
			VAR q, r: Object;
		BEGIN q := NIL;
			WHILE p # NIL DO
				r := p.next; p.next := q; q := p; p := r
			END ;
			RETURN q
		END reversedList;
				
	BEGIN
		nofLmod := 0; strno := firstStr;
		parlev := -1; fldlev := -1;
		IF OC.IsSYSTEMName(ModName) THEN
			Insert(name, obj); obj.mode := OC.Mod; obj.dsc := syslink;
			obj.a0 := 0; obj.typ := undftyp
		ELSE
			OC.MakeFileName(ModName, FileName, OC.SFext);
			SymFile := Files.Old(FileName);
			IF SymFile # NIL THEN
				Files.Set(R, SymFile, 0); Files.Read(R, ch);
				IF ch = SFtag THEN
					struct[OC.Undef] := undftyp; struct[OC.Byte] := bytetyp;
					struct[OC.Bool] := booltyp;  struct[OC.Char] := chartyp;
					struct[OC.SInt] := sinttyp;  struct[OC.Int] := inttyp;
					struct[OC.LInt] := linttyp;  struct[OC.Real] := realtyp;
					struct[OC.LReal] := lrltyp;  struct[OC.Set] := settyp;
					struct[OC.String] := stringtyp; struct[OC.NilTyp] := niltyp; struct[OC.NoTyp] := notyp;
					struct[OC.SysPtr] := sysptrtyp;
					LOOP (*read next item from symbol file*)
						Files.Read(R, ch); class := ORD(ch);
						IF R.eof THEN EXIT END ;
						CASE class OF
						  0: OBS.Mark(151); EXIT;
						| 1..7: (*object*) NEW(obj); m := 0;
							Files.Read(R, ch); s := ORD(ch); obj.typ := struct[s];
							CASE class OF
							  1: obj.mode := OC.Const;
										CASE obj.typ.form OF
											OC.SInt, OC.Bool: Files.Read(R, si); obj.a0 := si
										| OC.Byte, OC.Char: Files.Read(R, ch); obj.a0 := ORD(ch)
										| OC.Int: Files.ReadInt(R, i); obj.a0 := i
										| OC.LInt, OC.Real, OC.Set: Files.ReadLInt(R, obj.a0)
										| OC.LReal: Files.ReadLInt(R, obj.a0); Files.ReadLInt(R, obj.a1)
										| OC.String: Files.ReadLInt(R,obj.a1); NEW(obj.ext); Files.ReadString(R, obj.ext.str);
										| OC.NilTyp: (*NIL*)
										END
							|2,3: obj.mode := OC.Typ; Files.Read(R, ch); m := ORD(ch);
										IF obj.typ.strobj = NIL THEN obj.typ.strobj := obj END;
										obj.marked := class = 2
							|4: obj.mode := OC.Var; Files.Read(R, ch); obj.a0 := ORD(ch) 
							|5,6:	obj.mode := OC.LProc; Files.Read(R, ch);
										obj.a0 := ORD(ch);
										obj.dsc := reversedList(lastpar[parlev]); DEC(parlev)
							END ;
							Files.ReadString(R, obj.name); ob0 := LocMod[m];
							WHILE (ob0.next # NIL) & (ob0.next.name # obj.name) DO ob0 := ob0.next END ;
							IF ob0.next = NIL THEN ob0.next := obj; obj.next := NIL  (*insert object*)
							ELSIF obj.mode = OC.Typ THEN struct[s] := ob0.next.typ
							END
						|  8..12: (*structure*)
							NEW(typ); typ.strobj := NIL; typ.ref := 0;
							Files.Read(R, ch); typ.BaseTyp := struct[ORD(ch)];
							Files.Read(R, ch); typ.mno := SHORT(LocMod[ORD(ch)].a0);
							CASE class OF
								 8: typ.form := OC.Pointer; typ.size := PtrSize
							|  9: typ.form := OC.ProcTyp; typ.size := ProcSize;
										typ.link := reversedList(lastpar[parlev]); DEC(parlev)
							| 10: typ.form := OC.Array; Files.ReadLInt(R, typ.size)
							| 11: typ.form := OC.DynArr; Files.ReadLInt(R, typ.size); Files.ReadLInt(R, typ.adr)
							| 12: typ.form := OC.Record; Files.ReadLInt(R, typ.size); 
										typ.link := reversedList(lastfld[fldlev]); DEC(fldlev);
										IF typ.BaseTyp = notyp THEN typ.BaseTyp := NIL; typ.extlev := 0
										ELSE typ.extlev := typ.BaseTyp.extlev + 1
										END ;
										Files.ReadLInt(R, typ.adr) (* entry no of descriptor*)
							END ;
							struct[strno] := typ; INC(strno)
						| 13: (*parameter list start*)
							IF parlev < maxParLev-1 THEN INC(parlev); lastpar[parlev] := NIL
							ELSE OBS.Mark(229)
							END
						| 14, 15: (*parameter*)
							NEW(obj);
							IF class = 14 THEN obj.mode := OC.Var ELSE obj.mode := OC.Par END ;
							Files.Read(R, ch); obj.typ := struct[ORD(ch)]; Files.ReadString(R, obj.name);
							Files.ReadLInt(R,obj.a0); obj.dsc := NIL; obj.next := lastpar[parlev]; lastpar[parlev] := obj
						| 16: (*start field list*)
							IF fldlev < maxParLev-1 THEN INC(fldlev); lastfld[fldlev] := NIL
							ELSE OBS.Mark(229)
							END
						| 17: (*field*)
							NEW(obj); obj.mode := OC.Fld; Files.Read(R, ch);
							obj.typ := struct[ORD(ch)]; Files.ReadLInt(R, obj.a0);
							Files.ReadString(R, obj.name); obj.marked := TRUE;
							obj.dsc := NIL; obj.next := lastfld[fldlev]; lastfld[fldlev] := obj
						| 18: (*hidden pointer field*)
							NEW(obj); obj.mode := OC.Fld; Files.ReadLInt(R, obj.a0);
							obj.name := ""; obj.typ := notyp; obj.marked := FALSE;
							obj.dsc := NIL; obj.next := lastfld[fldlev]; lastfld[fldlev] := obj
						| 19: (*hidden procedure field*) Files.ReadLInt(R, k)
						| 20: (*fixup pointer typ*)
							Files.Read(R, ch); typ := struct[ORD(ch)];
							Files.Read(R, ch1);
							IF typ.BaseTyp = undftyp THEN typ.BaseTyp := struct[ORD(ch1)] END
						| 21, 23, 24: OBS.Mark(151); EXIT
						| 22: (*module anchor*)
							Files.ReadLInt(R, k); Files.ReadString(R, modname);
							IF modname = self THEN OBS.Mark(154) END;
							i := 0;
							WHILE (i < nofGmod) & (modname # GlbMod[i].name) DO INC(i) END ;
							IF i < nofGmod THEN (*module already present*)
								IF k # GlbMod[i].a1 THEN OBS.Mark(150) END ;
								obj := GlbMod[i]
							ELSE NEW(obj);
								IF nofGmod < OC.MaxImps THEN GlbMod[nofGmod] := obj; INC(nofGmod)
								ELSE OBS.Mark(227)
								END ;
								obj.mode := NotYetExp; COPY(modname, obj.name);
								obj.a1 := k; obj.a0 := nofGmod; obj.next := NIL
							END ;
							IF nofLmod < maxMod THEN LocMod[nofLmod] := obj; INC(nofLmod)
							ELSE OBS.Mark(227)
							END
						END
					END (*LOOP*) ;
					Insert(name, obj); 
					obj.mode := OC.Mod; obj.dsc := LocMod[0].next;
					obj.a0  := LocMod[0].a0; obj.a1 := LocMod[0].a1; obj.typ := notyp;
					IF OC.IsSoftFloatName(ModName) THEN softfloatImport:=obj END;
				ELSE OBS.Mark(151)
				END
			ELSE OBS.Mark(152)   (*sym file not found*)
			END
		END
	END Import;

	(*---------------------- export ------------------------*)

	PROCEDURE^ OutStr(VAR W: Files.Rider; typ: Struct);

	PROCEDURE OutPars(VAR W: Files.Rider; par: Object);
	BEGIN Files.Write(W, 13);
		WHILE (par # NIL) & (par.mode <= OC.Par) & (par.a0 >= 0) DO
			OutStr(W, par.typ);
			IF par.mode = OC.Var THEN Files.Write(W, 14) ELSE Files.Write(W, 15) END ;
			Files.Write(W, par.typ.ref); Files.WriteString(W, par.name); Files.WriteLInt(W,par.a0); par := par.next
		END
	END OutPars;

	PROCEDURE OutFlds(VAR W: Files.Rider; fld: Object; adr: LONGINT; visible: BOOLEAN);
	BEGIN
		IF visible THEN Files.Write(W, 16) END ;
		WHILE fld # NIL DO
			IF fld.marked & visible THEN
				OutStr(W, fld.typ); Files.Write(W, 17); Files.Write(W, fld.typ.ref);
				Files.WriteLInt(W, fld.a0); Files.WriteString(W, fld.name)
			ELSIF fld.typ.form = OC.Record THEN OutFlds(W, fld.typ.link, fld.a0 + adr, FALSE)
			ELSIF (fld.typ.form = OC.Pointer) OR (fld.name = "") THEN
				Files.Write(W, 18); Files.WriteLInt(W, fld.a0 + adr)
			END ;
			fld := fld.next
		END
	END OutFlds;

	PROCEDURE OutStr(VAR W: Files.Rider; typ: Struct);
		VAR m, em: INTEGER; r: SHORTINT; btyp: Struct; mod: Object;
	BEGIN
		IF typ.ref = 0 THEN
			m := typ.mno; btyp := typ.BaseTyp;
			IF m > 0 THEN mod := GlbMod[m-1]; em := mod.mode;
				IF em = NotYetExp THEN
					GlbMod[m-1].mode := nofExp; m := nofExp; INC(nofExp);
					Files.Write(W, 22); Files.WriteLInt(W, mod.a1); Files.WriteString(W, mod.name)
				ELSE m := em
				END
			END;
			CASE typ.form OF
				OC.Undef .. OC.NoTyp, OC.SysPtr:
			| OC.Pointer: Files.Write(W, 8);
						IF btyp.ref > 0 THEN Files.Write(W, btyp.ref)
						ELSE Files.Write(W, OC.Undef);
							IF udpinx < maxUDP THEN undPtr[udpinx] := typ; INC(udpinx) ELSE OBS.Mark(224) END
						END ;
						Files.Write(W, SHORT(m))
			| OC.ProcTyp: OutStr(W, btyp); OutPars(W, typ.link);
						Files.Write(W, 9); Files.Write(W, btyp.ref); Files.Write(W, SHORT(m))
			| OC.Array: OutStr(W, btyp);
						Files.Write(W, 10); Files.Write(W, btyp.ref); Files.Write(W, SHORT(m));
						Files.WriteLInt(W, typ.size)
			| OC.DynArr: OutStr(W, btyp);
						Files.Write(W, 11); Files.Write(W,btyp.ref); Files.Write(W, SHORT(m));
						Files.WriteLInt(W, typ.size); Files.WriteLInt(W, typ.adr)
			| OC.Record:
						IF btyp = NIL THEN r := OC.NoTyp
						ELSE OutStr(W, btyp); r := btyp.ref
						END ;
						OutFlds(W, typ.link, 0, TRUE); Files.Write(W, 12); Files.Write(W, r); Files.Write(W, SHORT(m));
						Files.WriteLInt(W, typ.size);
						IF m = 0 THEN
							IF entno=maxEnt THEN OBS.Mark(253); entno:=0 END;
							Files.WriteLInt(W, entno); entry[entno] := typ.adr; INC(entno);
						ELSE Files.WriteLInt(W, typ.adr)
						END					
			END ;
			IF typ.strobj # NIL THEN
				IF typ.strobj.marked THEN Files.Write(W, 2) ELSE Files.Write(W, 3) END;
				Files.Write(W, SHORT(strno)); Files.Write(W, SHORT(m));
				Files.WriteString(W, typ.strobj.name)
			END ;
			typ.ref := SHORT(strno); INC(strno);
			IF strno > maxStr THEN OBS.Mark(228) END
		END
	END OutStr;

	PROCEDURE OutObjs(VAR W: Files.Rider);
		VAR obj: Object; f: INTEGER;
	BEGIN obj := topScope.next;
		WHILE obj # NIL DO
			IF obj.marked THEN
				IF obj.mode = OC.Const THEN
					Files.Write(W, 1); f := obj.typ.form; Files.Write(W, SHORT(f));
					 CASE f OF
						 OC.Undef:
					 | OC.Byte, OC.Bool, OC.Char, OC.SInt: Files.Write(W, CHR(obj.a0))
					 | OC.Int: Files.WriteInt(W, SHORT(obj.a0))
					 | OC.LInt, OC.Real, OC.Set: Files.WriteLInt(W, obj.a0)
					 | OC.LReal:  Files.WriteLInt(W, obj.a0); Files.WriteLInt(W, obj.a1)
					 | OC.String: Files.WriteLInt(W,obj.a1); Files.WriteString(W, obj.ext.str)
					 | OC.NilTyp:
					 END;
					Files.WriteString(W, obj.name)
				ELSIF obj.mode = OC.Typ THEN 
					OutStr(W, obj.typ);
					IF (obj.typ.strobj # obj) & (obj.typ.strobj # NIL) THEN
						Files.Write(W, 2); Files.Write(W, obj.typ.ref); Files.Write(W, 0);
						Files.WriteString(W, obj.name)
					END
				ELSIF obj.mode = OC.Var THEN
					OutStr(W, obj.typ); Files.Write(W, 4);
					Files.Write(W, obj.typ.ref); 
					IF entno=maxEnt THEN OBS.Mark(236); entno:=0 END;
					Files.Write(W, SHORT(entno)); entry[entno] := obj.a0; INC(entno); 
					Files.WriteString(W, obj.name);
					(* OLD: IF obj.a0 < MIN(LONGINT) THEN OBS.Mark(236) END *)
				ELSIF obj.mode = OC.LProc THEN
					OutStr(W, obj.typ); OutPars(W, obj.dsc); Files.Write(W, 6);
					Files.Write(W, obj.typ.ref); 
					IF entno=maxEnt THEN OBS.Mark(226); entno:=0 END;					
					Files.Write(W, SHORT(entno));
					entry[entno] := obj.a0*4; (* we work with word addrs, but we want byte addrs in the obj file! *)
					INC(entno); Files.WriteString(W, obj.name)
				END
			END ;
			obj := obj.next
		END
	END OutObjs;

	PROCEDURE Export*(VAR name, FileName: ARRAY OF CHAR;
			VAR newSF: BOOLEAN; VAR key: LONGINT);
		VAR i: INTEGER;
			ch0, ch1: CHAR;
			oldkey: LONGINT;
			typ: Struct;
			oldFile, newFile: Files.File;
			W, R: Files.Rider;
	BEGIN
		entno := 0; newFile := Files.New(FileName);
		IF newFile # NIL THEN
			Files.Set(W, newFile, 0); Files.Write(W, SFtag); strno := firstStr;
			Files.Write(W, 22); Files.WriteLInt(W, key); Files.WriteString(W, name); nofExp := 1;
			OutObjs(W); i := 0;
			WHILE i < udpinx DO
				typ := undPtr[i]; OutStr(W, typ.BaseTyp); undPtr[i] := NIL; INC(i);
				Files.Write(W, 20); (*fixup*)
				Files.Write(W, typ.ref); Files.Write(W, typ.BaseTyp.ref)
			END ;
			IF ~OBS.scanerr THEN
				oldFile := Files.Old(FileName);
				IF oldFile # NIL THEN (*compare*)
					Files.Set(R, oldFile, 2); Files.ReadLInt(R, oldkey); Files.Set(W, newFile, 6);
					REPEAT Files.Read(R, ch0); Files.Read(W, ch1)
					UNTIL (ch0 # ch1) OR W.eof;
					IF R.eof & W.eof THEN (*equal*) newSF := FALSE;  key := oldkey
					ELSIF newSF THEN Files.Register(newFile)
					ELSE OBS.Mark(155)
					END
				ELSE Files.Register(newFile); newSF := TRUE
				END
			ELSE newSF := FALSE
			END
		ELSE OBS.Mark(153)
		END
	END Export;

	(*------------------------ initialization ------------------------*)

	PROCEDURE InitStruct(VAR typ: Struct; f: SHORTINT);
	BEGIN NEW(typ); typ.form := f; typ.ref := f; typ.size := 1
	END InitStruct;

	PROCEDURE EnterConst(name: ARRAY OF CHAR; value: INTEGER);
		VAR obj: Object;
	BEGIN Insert(name, obj); obj.mode := OC.Const; obj.typ := booltyp; obj.a0 := value
	END EnterConst;

	PROCEDURE EnterTyp(name: ARRAY OF CHAR; form: SHORTINT;
			size: INTEGER; VAR res: Struct);
		VAR obj: Object; typ: Struct;
	BEGIN Insert(name, obj);
		NEW(typ); obj.mode := OC.Typ; obj.typ := typ; obj.marked := TRUE;
		typ.form := form; typ.strobj := obj; typ.size := size;
		typ.mno := 0; typ.ref := form; res := typ
	END EnterTyp;

	PROCEDURE EnterProc(name: ARRAY OF CHAR; num: INTEGER);
		VAR obj: Object;
	BEGIN Insert(name, obj); obj.mode := OC.SProc; obj.typ := notyp; obj.a0 := num
	END EnterProc;

BEGIN 
	topScope := NIL;
	InitStruct(undftyp, OC.Undef); InitStruct(notyp, OC.NoTyp);
	InitStruct(stringtyp, OC.String); InitStruct(niltyp, OC.NilTyp); 
	OpenScope(0);

	(*initialization of module SYSTEM*)
	EnterProc("LSH", FnSysLsh);
	EnterProc("ROT", FnSysRot);
	EnterProc("ADR",  FnSysAdr);
	EnterProc("GET", FnSysGet);
	EnterProc("PUT", FnSysPut);
	EnterProc("BIT", FnSysBit);
	EnterProc("VAL", FnSysVal);
	EnterProc("NEW", FnSysNew);
	EnterProc("MOVE",FnSysMove);
	EnterProc("CC",  FnSysCC);
	EnterProc("GETREG", FnSysGetReg);
	EnterProc("PUTREG", FnSysPutReg);
	EnterProc("HALT",FnSysHalt);
	EnterProc("ENABLEINTERRUPTS",FnSysEnableInterrupts);
	EnterProc("DISABLEINTERRUPTS",FnSysDisableInterrupts);
	EnterProc("RESTOREINTERRUPTS",FnSysRestoreInterrupts);
	EnterTyp("BYTE", OC.Byte, 1, bytetyp);
	EnterTyp("PTR", OC.SysPtr, 4, sysptrtyp);
	syslink := topScope.next;
	universe := topScope; topScope.next := NIL;

	EnterTyp("CHAR", OC.Char, 1, chartyp);
	EnterTyp("SET", OC.Set, 4, settyp);
	EnterTyp("REAL", OC.Real, 4, realtyp);
	EnterTyp("INTEGER", OC.Int, 2, inttyp);
	EnterTyp("LONGINT",  OC.LInt, 4, linttyp);
	EnterTyp("LONGREAL", OC.LReal, 8, lrltyp);
	EnterTyp("SHORTINT", OC.SInt, 1, sinttyp);
	EnterTyp("BOOLEAN", OC.Bool, 1, booltyp);
	EnterProc("INC",   FnInc);
	EnterProc("DEC",   FnDec);
	EnterConst("FALSE", 0);
	EnterConst("TRUE",  1);
	EnterProc("HALT",   FnHalt);
	EnterProc("ASSERT", FnAssert);
	EnterProc("NEW",    FnNew);
	EnterProc("ABS",    FnAbs);
	EnterProc("CAP",    FnCap);
	EnterProc("ORD",    FnOrd);
	EnterProc("ENTIER", FnEntier);
	EnterProc("SIZE",   FnSize);
	EnterProc("ODD",   FnOdd);
	EnterProc("MIN",   FnMin);
	EnterProc("MAX",   FnMax);
	EnterProc("CHR",   FnChr);
	EnterProc("SHORT", FnShort);
	EnterProc("LONG",  FnLong);
	EnterProc("INCL",  FnIncl);
	EnterProc("EXCL",  FnExcl);
	EnterProc("LEN",   FnLen);
	EnterProc("ASH",   FnAsh);
	EnterProc("COPY",  FnCopy);
END OBT.
