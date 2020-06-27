MODULE OBH;    (*NW 7.6.87 / 11.7.93 / as 26.11.98 *)

(*	Peter Matthias
		2016-01-13	Changed Result to use VFP registers for REAL results
*)

	IMPORT OBS, OBT, OBE, OBC, OC := OBM;

	TYPE
		LabelRange* = RECORD low*, high*: LONGINT; label*: LONGINT END ;

	VAR
		clrchk* : BOOLEAN;
		curProcParamSize* : LONGINT; (* size of params of the current procedure. Used by Return *)

	PROCEDURE Leng(L: LONGINT); (* pushs L onto the stack *)
	VAR y: OBT.Item;
	BEGIN
		OBE.MakeConstItem(y,L,OBT.linttyp); OBE.PushWord(y);
	END Leng;

	PROCEDURE MoveBlock(VAR x, y: OBT.Item; s: LONGINT); (* x=dest, y=src *)
	VAR reg, cnt : LONGINT;
	BEGIN 
		IF s > 0 THEN
			IF x.mode=OC.Var2 THEN (* We're pushing it onto the stack! (preindexed with writeback) *)
				OBC.PutDP1(OBC.ADD,x.r,x.r,x.a); 
				x.mode:=OC.Var; x.a:=0;
			END;
			OBE.loadAdr(x); OBE.loadAdr(y); OBC.GetReg(reg); OBC.GetReg(cnt);
			IF s>0 THEN (* Move bytes *)
				IF s<3 THEN (* one or two bytes -> no loop (loop would have more instrs) *)
					WHILE s>0 DO
						OBC.PutSDT(OBC.LDRBpost,reg,y.r,1);
						OBC.PutSDT(OBC.STRBpost,reg,x.r,1);
						DEC(s)
					END
				ELSE 
					OBC.LoadConst(cnt,s);
					OBC.PutSDT(OBC.LDRBpost,reg,y.r,1);
					OBC.PutSDT(OBC.STRBpost,reg,x.r,1);
					OBC.PutDP1(OBC.SUB,cnt,cnt,1);
					OBC.PutB(OBC.B,OBC.pc-3); OBC.SetCondition(OBC.pc-1,OBC.NE);
					OBC.FreeReg(cnt)
				END
			END;
			OBC.FreeReg(reg)
		END
	END MoveBlock;

	PROCEDURE DynArrBnd(ftyp, atyp: OBT.Struct; lev, basereg, adr: LONGINT; varpar: BOOLEAN);
	VAR f: INTEGER; y, z: OBT.Item;
	BEGIN (* ftyp.form = DynArr *)
		y.mode := OC.Var;  y.r:=basereg; 
		IF varpar & (ftyp.BaseTyp.form = OC.Byte) THEN
			IF atyp.form # OC.DynArr THEN
				(* IF (atyp.form # OC.Array) OR (atyp.BaseTyp.size > 1) THEN OBS.Mark(-1) END ; *)
				Leng(atyp.size)
			ELSE 
				y.lev := lev; y.a := adr + atyp.adr; y.typ := OBT.linttyp;
				atyp := atyp.BaseTyp;
				IF atyp.form # OC.DynArr THEN
					IF atyp.size > 1 THEN
						OBE.MakeConstItem(z,atyp.size,OBT.linttyp); OBE.load(z);
						OBE.load(y); OBC.PutMUL(OBC.MUL,y.r,z.r,y.r,0); (* MULD z, Ry *)
					END
				ELSE 
					OBE.load(y); 
					REPEAT 
						z.mode := OC.Var; z.r:=basereg; z.lev := lev; z.a := atyp.adr + adr; z.typ := OBT.linttyp;
						OBE.load(z); OBC.PutMUL(OBC.MUL,y.r,z.r,y.r,0);	(* MULD Rz, Ry *)
						atyp := atyp.BaseTyp
					UNTIL atyp.form # OC.DynArr;
					IF atyp.size > 1 THEN
						OBE.MakeConstItem(z,atyp.size,OBT.linttyp); OBE.load(z);
						OBC.PutMUL(OBC.MUL,y.r,z.r,y.r,0) (* MULD z, Ry *)
					END
				END ;
				OBE.PushWord(y); 
			END
		ELSE
			LOOP 
				f := atyp.form;
				IF f = OC.Array THEN Leng(atyp.size DIV atyp.BaseTyp.size)
				ELSIF f = OC.DynArr THEN y.lev := lev; y.a := atyp.adr + adr; y.typ:=OBT.linttyp; OBE.PushWord(y);
				ELSE OBS.Mark(66); EXIT
				END ;
				ftyp := ftyp.BaseTyp; atyp := atyp.BaseTyp;
				IF ftyp.form # OC.DynArr THEN
					IF ftyp # atyp THEN
						IF ~varpar & (ftyp.form = OC.Pointer) & (atyp.form = OC.Pointer) THEN
							ftyp := ftyp.BaseTyp; atyp := atyp.BaseTyp;
							IF (ftyp.form = OC.Record) & (atyp.form = OC.Record) THEN
								WHILE (ftyp # atyp) & (atyp # NIL) DO atyp := atyp.BaseTyp END ;
								IF atyp = NIL THEN OBS.Mark(113) END
							ELSE OBS.Mark(67)
							END
						ELSE OBS.Mark(67)
						END
					END ;
					EXIT
				END
			END
		END
	END DynArrBnd;

	PROCEDURE Trap*(n: INTEGER);
	BEGIN
		OBC.PutSWI(OBC.AL,n);
	END Trap;

	PROCEDURE CompareParLists*(x, y: OBT.Object);
	VAR xt, yt: OBT.Struct;
	BEGIN
		WHILE x # NIL DO
			IF y # NIL THEN
				xt := x.typ; yt := y.typ;
				WHILE (xt.form = OC.DynArr) & (yt.form = OC.DynArr) DO
					xt := xt.BaseTyp; yt := yt.BaseTyp
				END ;
				IF x.mode # y.mode THEN OBS.Mark(115)
				ELSIF xt # yt THEN
					IF (xt.form = OC.ProcTyp) & (yt.form = OC.ProcTyp) THEN
						CompareParLists(xt.link, yt.link)
					ELSE OBS.Mark(115)
					END
				END ;
				y := y.next
			ELSE OBS.Mark(116)
			END ;
			x := x.next
		END ;
		IF (y # NIL) & (y.mode <= OC.Par) & (y.a0 > 0) THEN OBS.Mark(117) END
	END CompareParLists;

	PROCEDURE Assign*(VAR x, y: OBT.Item; param: BOOLEAN); (* x=dest; y=src *)
	VAR f, g, s, vsz : LONGINT; p, q: OBT.Struct; tag, tdes: OBT.Item;
	BEGIN
		f := x.typ.form; g := y.typ.form;
		IF x.mode = OC.Const THEN OBS.Mark(56)
		ELSIF( f # OC.ProcTyp) & (y.mode = OC.LProc) THEN OBS.Mark(55)
		END;
		CASE f OF
			OC.Undef, OC.String:
			| OC.Byte:
					IF g IN {OC.Undef, OC.Byte, OC.Char, OC.SInt} THEN OBE.store(x,y);
					ELSE OBS.Mark(113)
					END

			| OC.Bool:
					IF (y.mode = OC.CC) OR (g = OC.Bool) THEN OBE.store(x,y);
					ELSE OBS.Mark(113)
					END

			| OC.Char, OC.SInt, OC.Set: 
					IF g = f THEN OBE.store(x,y)
					ELSE OBS.Mark(113)
					END

			| OC.Int:
					IF g IN {OC.Int, OC.SInt} THEN OBE.store(x,y) 
					ELSE OBS.Mark(113)
					END

			| OC.LInt:
					IF g IN {OC.LInt, OC.Int, OC.SInt} THEN OBE.store(x,y);
					ELSE OBS.Mark(113)
					END

			| OC.Real:
					IF g = OC.Real THEN OBE.store(x,y);
					ELSIF (OC.SInt <= g) & (g <= OC.LInt) THEN
						OBE.convertIntToReal(y,OBT.realtyp);
						OBE.store(x,y)
					ELSE OBS.Mark(113)
					END

			| OC.LReal:
					IF g = OC.LReal THEN 
						IF param THEN OBE.PushLReal(y) ELSE OBE.storeLReal(x,y) END;
					ELSIF g = OC.Real THEN 
						OBE.convertRealToLReal(y);
						IF param THEN OBE.PushLReal(y) ELSE OBE.storeLReal(x,y) END;
					ELSIF (OC.SInt <= g) & (g <= OC.LInt) THEN 
						OBE.convertIntToReal(y,OBT.lrltyp);
						IF param THEN OBE.PushLReal(y) ELSE OBE.storeLReal(x,y) END;
					ELSE OBS.Mark(113)
					END

			| OC.SysPtr: 
					IF (x.typ = y.typ) OR (g = OC.Pointer) THEN OBE.store(x,y)
					ELSIF g = OC.NilTyp THEN OBE.MakeConstItem(y,0,x.typ); OBE.store(x,y);
					ELSE OBS.Mark(113)
					END

			| OC.Pointer:
					IF x.typ = y.typ THEN OBE.store(x,y)
					ELSIF  f = OC.SysPtr THEN y.typ:=x.typ; OBE.store(x,y)
					ELSIF g = OC.NilTyp THEN OBE.MakeConstItem(y,0,x.typ); OBE.store(x,y);
					ELSIF g = OC.Pointer THEN
						p := x.typ.BaseTyp; q := y.typ.BaseTyp;
						IF (p.form = OC.Record) & (q.form = OC.Record) THEN
							WHILE (q # p) & (q # NIL) DO q := q.BaseTyp END ;
							IF q # NIL THEN OBE.store(x,y) ELSE OBS.Mark(113) END
						ELSE OBS.Mark(113)
						END
					ELSE OBS.Mark(113)
					END

			| OC.Array:
					s := x.typ.size;
					IF x.typ = y.typ THEN MoveBlock(x, y, s)
					ELSIF (g = OC.String) & (x.typ.BaseTyp.form = OC.Char) THEN
						s := y.b; vsz := x.typ.size;  (*check length of string*)
						IF s > vsz THEN OBS.Mark(114) END ;
						MoveBlock(x, y, s)
					ELSIF (g = OC.Char) & (y.mode = OC.Const) & (x.typ.BaseTyp.form = OC.Char) THEN
						OBE.ConstCharToString(y); g := y.typ.form;
						s := y.b; vsz := x.typ.size;  (*check length of string*)
						IF s > vsz THEN OBS.Mark(114) END ;
						MoveBlock(x, y, s)
					ELSE OBS.Mark(113)
					END

			| OC.DynArr: 
					s := x.typ.size;
					IF param THEN (*formal parameter is open array*)
						IF (g = OC.Char) & (y.mode=OC.Const) & (x.typ.BaseTyp.form = OC.Char) THEN
							y.typ := OBT.stringtyp; g:=OC.String;
							NEW(y.obj); NEW(y.obj.ext); 
							y.obj.ext.entered:=FALSE; y.obj.ext.str[0]:=CHR(y.a); y.obj.ext.str[1]:=0X; y.b:=2; 
						END;
						IF (g = OC.String) & (x.typ.BaseTyp.form = OC.Char) THEN Leng(y.b)
						ELSIF ~(y.mode IN {OC.Var,OC.Var1,OC.Par, OC.Par1}) THEN OBS.Mark(59) 
						ELSE DynArrBnd(x.typ, y.typ, y.lev, y.r, y.a, FALSE)
						END ;
						IF g = OC.DynArr THEN OBE.DynArrAdr(y); OBE.PushWord(y);
						ELSE OBE.loadAdr(y); OBE.PushWord(y);
						END
					ELSE OBS.Mark(113)
					END

			| OC.Record: 
					s := x.typ.size;
					IF x.typ # y.typ THEN
						IF g = OC.Record THEN
							q := y.typ.BaseTyp;
							WHILE (q # NIL) & (q # x.typ) DO q := q.BaseTyp END ;
							IF q = NIL THEN OBS.Mark(113) END
						ELSE OBS.Mark(113)
						END
					END;
					IF OBC.typchk & ~param &					
						( (x.mode IN {OC.Var,OC.Par})  & (x.obj = OBC.wasderef)	(* p^ := *)
							OR (x.mode = OC.Par) & (x.obj # NIL) & (x.obj # OBC.wasderef) )	(* varpar := *) THEN
						tag := x; tag.typ:=OBT.linttyp; 
						tdes.mode := OC.Var; tdes.lev := -x.typ.mno; tdes.r:=OBC.PC; tdes.a := x.typ.adr; tdes.typ:=OBT.linttyp;
						IF x.obj = OBC.wasderef THEN 
							IF tag.mode=OC.Var THEN tag.a := - 4
							ELSIF tag.mode=OC.Par THEN tag.b:=-4
							ELSE HALT(215)
							END;
						ELSE tag.mode := OC.Var; INC(tag.a, 4)
						END;
						OBE.load(tdes); OBE.load(tag);
						OBC.PutDP(OBC.CMP,0,tdes.r,tag.r,0);
						OBC.PutSWI(OBC.NE,OC.ImplTypeGuardTrap);
						OBC.Release(tdes); OBC.Release(tag);
					END;
					MoveBlock(x, y, s)

			| OC.ProcTyp:
					IF (x.typ = y.typ) OR (y.typ.form = OC.NilTyp) THEN OBE.store(x,y);
					ELSIF (y.mode = OC.LProc) & (y.lev <= 0) THEN
						(*procedure y to proc. variable x; check compatibility*)
						IF x.typ.BaseTyp = y.typ THEN
							CompareParLists(x.typ.link, y.obj.dsc);
							OBE.loadAdr(y); OBE.store(x,y);
						ELSE OBS.Mark(113)
						END
					ELSE OBS.Mark(111)
					END
					
			| OC.NoTyp, OC.NilTyp:
					OBS.Mark(111)
		END
	END Assign;

	PROCEDURE TempVar*(VAR x : OBT.Item);
	(** Creates a temporary integer var on the stack and assigns it the value of x *)
	VAR y : OBT.Item;
	BEGIN
		IF x.typ.size>4 THEN HALT(204) END;
		
		y.mode:=OC.Var2; y.a:=-4;  y.r:=OBC.SP; y.typ:=OBT.linttyp; (* to keep stack aligned! won't cause problems if y is not LInt *)
		OBE.store(y,x);
		x.mode:=OC.Var;  x.r:=OBC.SP; x.a:=0; x.typ:=y.typ;
	END TempVar;
	
	PROCEDURE RemoveTempVars*(n : INTEGER);
	BEGIN
		ASSERT(n>=0);
		IF n>0 THEN OBC.PutDP1(OBC.ADD,OBC.SP,OBC.SP,n*4) END;
	END RemoveTempVars;
	
	PROCEDURE PrepCall*(VAR x: OBT.Item; VAR fpar: OBT.Object);
	BEGIN
		IF x.mode = OC.LProc THEN
			fpar := x.obj.dsc; 
		ELSIF (x.typ # NIL) & (x.typ.form = OC.ProcTyp) THEN
			fpar := x.typ.link;
		ELSE OBS.Mark(121); fpar := NIL; x.typ := OBT.undftyp
		END
	END PrepCall;

	PROCEDURE Param*(VAR ap: OBT.Item; f: OBT.Object; VAR psize : LONGINT);
	VAR q: OBT.Struct; fp, z: OBT.Item; 
	BEGIN
		fp.mode := OC.Var2; fp.r:=OBC.SP; fp.typ := f.typ;
		IF f.mode = OC.Par THEN (*VAR parameter*)
			IF ap.mode >= OC.Const THEN OBS.Mark(122) END ;
			IF fp.typ.form = OC.DynArr THEN
				DynArrBnd(fp.typ, ap.typ, ap.lev, ap.r, ap.a, TRUE);
				IF ap.typ.form = OC.DynArr THEN OBE.DynArrAdr(ap)
				ELSE OBE.loadAdr(ap)
				END;
				OBE.PushWord(ap);
			ELSIF (fp.typ.form = OC.Record) & (ap.typ.form = OC.Record) THEN
				q := ap.typ;
				WHILE (q # fp.typ) & (q # NIL) DO q := q.BaseTyp END ;
				IF q # NIL THEN
					IF (ap.mode = OC.Par) & (ap.obj # NIL) & (ap.obj # OBC.wasderef) THEN
						(*actual par is VAR-par*)
						z:=ap;  z.mode := OC.Var; z.a := z.a + 4; z.typ:=OBT.linttyp; OBE.PushWord(z); (* push type desc addr *)
						z:=ap;  z.mode := OC.Var; z.typ:=OBT.linttyp; OBE.PushWord(z); (* push addr *)
					ELSIF (ap.mode IN {OC.Var, OC.Par}) & (ap.obj = OBC.wasderef) THEN
						(*actual par is p^*)
						z:=ap; IF ap.mode=OC.Par THEN z.b:=- 4 ELSE z.a:=-4 END; z.typ:=OBT.linttyp; OBE.PushWord(z); (* push type desc addr *)
						z:=ap; OBE.loadAdr(z); z.typ:=OBT.linttyp; OBE.PushWord(z); (* push addr *)
					ELSE
						z.mode := OC.Var; z.r:=OBC.PC; z.lev := -ap.typ.mno; z.a := ap.typ.adr; z.typ:=OBT.linttyp; OBE.PushWord(z); 
						OBE.loadAdr(ap); OBE.PushWord(ap);
					END
				ELSE OBS.Mark(111)
				END
			ELSIF (fp.typ = OBT.sysptrtyp) & (ap.typ.form = OC.Pointer) THEN
				OBE.loadAdr(ap); OBE.PushWord(ap)
			ELSIF (ap.typ = fp.typ) OR ((fp.typ.form = OC.Byte) & (ap.typ.form IN {OC.Char, OC.SInt})) THEN
				IF (ap.mode = OC.Par) & (ap.b = 0) THEN (*actual var par*) ap.mode := OC.Var; ap.typ:=OBT.linttyp; OBE.PushWord(ap);
				ELSE OBE.loadAdr(ap); OBE.PushWord(ap);
				END
			ELSE OBS.Mark(123)
			END
		ELSE
			fp.a:=f.a0-psize;
			Assign(fp, ap, TRUE)
		END;
		psize:=f.a0;
	END Param;

	PROCEDURE Call*(VAR x: OBT.Item);
	VAR  sL: OBT.Item; 
	BEGIN
		IF x.mode = OC.LProc THEN
			IF x.lev >= 0 THEN
				IF x.lev > 0 THEN
					IF x.lev=OBC.level THEN (* Push current FP as static link *)
						sL.mode:=OC.Reg; sL.r:=OBC.FP; sL.typ:=OBT.linttyp; OBE.PushWord(sL)
					ELSE
						sL.mode := OC.Var; sL.typ:=OBT.linttyp; sL.lev:=x.lev+1; sL.r:=OBC.FP; sL.a:=8;
						OBE.load(sL);
						OBC.PutBDT(OBC.STMDB,OBC.SP,{sL.r},TRUE); (* static link *)
						OBC.Release(sL)
					END
				END ;
				IF x.a = -1 THEN OBC.PutBabs(OBC.BL,x.obj.a1); x.obj.a1:=OBC.pc-1; (* forward link *)
				ELSE OBC.PutB(OBC.BL,x.a);
				END
			ELSE OBC.PutBext(-x.lev,x.a);
			END
		ELSIF (x.mode < OC.Const) & (x.typ.form # OC.Undef) THEN
			OBE.load(x);
			OBC.PutDP(OBC.MOV,OBC.LR,0,OBC.PC,0);
			OBC.PutDP(OBC.MOV,OBC.PC,0,x.r,0);
			x.typ := x.typ.BaseTyp 
		ELSE OBS.Mark(121)
		END
		(*function result is marked when restoring registers*)		
	END Call;

	PROCEDURE Enter*(mode: SHORTINT; dsize : LONGINT);
	VAR zero, cnt : OBT.Item;
	BEGIN 
		OBC.CheckCodeSize; 
		OBC.PutBDT(OBC.STMDB,OBC.SP,{OBC.FP,OBC.LR},TRUE(*writeback*)); (* Store FP and LR *)
		OBC.PutDP(OBC.MOV,OBC.FP,0,OBC.SP,0); (* Set new FP *)
		IF mode#OC.Mod THEN
			IF dsize>0 THEN
				IF clrchk THEN 
					ASSERT(dsize MOD 4 = 0);
					OBE.MakeConstItem(zero,0,OBT.linttyp);
					OBE.MakeConstItem(cnt,dsize DIV 4, OBT.linttyp);
					OBE.load(zero); 
					IF cnt.a < 5 THEN	(* 4 or less words -> no loop *)
						WHILE cnt.a > 0 DO OBE.PushWord(zero);  DEC(cnt.a) END
						(* zero is release by OBE.PushWord *)
					ELSE (* 5 or more words -> loop *)
						OBE.load(cnt);
						DEC(OBC.allowConstFlushing);
						OBE.PushWord(zero);
						OBC.PutDP1(OBC.SUB,cnt.r,cnt.r,1);
						OBC.PutB(OBC.B,OBC.pc-2); OBC.SetCondition(OBC.pc-1,OBC.NE);
						INC(OBC.allowConstFlushing);
						OBC.Release(cnt)
						(* zero is release by OBE.PushWord *)
					END
				ELSE
					OBC.PutDP1(OBC.SUB,OBC.SP,OBC.SP,dsize)
				END
			END
		END
	END Enter;

	PROCEDURE CopyDynArray*(adr: LONGINT; typ: OBT.Struct);
	VAR size : OBT.Item; r,src : LONGINT;

		PROCEDURE DynArrSize(typ: OBT.Struct);
		VAR len: OBT.Item;
		BEGIN
			IF typ.form = OC.DynArr THEN 
				DynArrSize(typ.BaseTyp);
				len.mode := OC.Var; len.r:=OBC.FP; len.lev := OBC.level; len.typ := OBT.linttyp; len.a := adr + typ.adr; OBE.load(len);
				IF size.mode=OC.Const THEN
					IF size.a # 1 THEN OBE.load(size); OBC.PutMUL(OBC.MUL,size.r,len.r,size.r,0); OBC.Release(len);
					ELSE size:=len; OBE.load(size);
					END
				ELSE
					OBC.PutMUL(OBC.MUL,size.r,len.r,size.r,0); OBC.Release(len);
				END;
			ELSE
				OBE.MakeConstItem(size,typ.size,OBT.linttyp);
			END
		END DynArrSize;
		
	BEGIN
		DynArrSize(typ);	(* load total byte size of dyn array *)
		OBC.PutDP(OBC.SUB,OBC.SP,OBC.SP,size.r,0); 
		IF typ.BaseTyp.size < 4 THEN
			(* size is not necessarily a multiple of four -> make sure that SP stays aligned *)
			OBC.PutDP1(OBC.BIC,OBC.SP,OBC.SP,3); 
		END;
		OBC.GetReg(r); 
		OBC.GetReg(src); OBC.PutSDT(OBC.LDR,src,OBC.FP,adr);
		DEC(OBC.allowConstFlushing);
		IF typ.BaseTyp.size<4 THEN
			(* Source may be not aligned (neither word nor halfword), so copy byte by byte *)
			OBC.PutDP1(OBC.SUB,size.r,size.r,1);  
			OBC.PutSDT1(OBC.LDRB,r,src,size.r,0);
			OBC.PutSDT1(OBC.STRB,r,OBC.SP,size.r,0);
			OBC.PutB(OBC.B,OBC.pc-3); OBC.SetCondition(OBC.pc-1,OBC.NE); (* Cond code set by SUB instr *)
		ELSE
			(* Source is word-aligned, copy fast *)
			OBC.PutDP1(OBC.SUB,size.r,size.r,4);  
			OBC.PutSDT1(OBC.LDR,r,src,size.r,0);
			OBC.PutSDT1(OBC.STR,r,OBC.SP,size.r,0);
			OBC.PutB(OBC.B,OBC.pc-3); OBC.SetCondition(OBC.pc-1,OBC.NE); (* Cond code set by SUB instr *)
		END;
		INC(OBC.allowConstFlushing);
		OBC.PutSDT(OBC.STR,OBC.SP,OBC.FP,adr); (* store new address of data *)
		OBC.FreeRegs({})
	END CopyDynArray;
(*	
	PROCEDURE Result*(VAR x: OBT.Item; typ: OBT.Struct);
	VAR res: OBT.Item; regs : SET;
	BEGIN
		regs:=OBC.UsedRegisters();
		res.typ:=typ; res.r:=0; res.mode:=OC.Reg; OBC.FreeReg(0);
		IF typ.form=OC.LReal THEN res.mode:=OC.RegX; res.a:=1; OBC.FreeReg(1) END;
		Assign(res, x, FALSE);
		OBC.FreeRegs(regs);
	END Result;
*)
	PROCEDURE Result*(VAR x: OBT.Item; typ: OBT.Struct);
	VAR res: OBT.Item; regs: SET;
	BEGIN
		res.typ:=typ; res.r:=0;
		IF (typ.form=OC.LReal) OR (typ.form=OC.Real) THEN
			regs:=OBC.UsedRegistersF(); 
			res.mode:=OC.RegX;		
			OBC.FreeRegF(0);
			Assign(res, x, FALSE);
			OBC.FreeRegsF(regs);
		ELSE
			regs:=OBC.UsedRegisters();
			res.mode:=OC.Reg;
			OBC.FreeReg(0);
			Assign(res, x, FALSE);
			OBC.FreeRegs(regs);
		END
	END Result;

	PROCEDURE Return*(fromModBody : BOOLEAN);
	BEGIN 
		OBC.PutDP(OBC.MOV,OBC.SP,0,OBC.FP,0);
		IF fromModBody THEN
			OBC.PutBDT(OBC.LDMIA,OBC.SP,{OBC.FP,OBC.PC},TRUE);
		ELSE
			IF curProcParamSize=0 THEN
				OBC.PutBDT(OBC.LDMIA,OBC.SP,{OBC.FP,OBC.PC},TRUE);
			ELSE
				OBC.PutSDT(OBC.LDRpost,OBC.FP,OBC.SP,4); (* Restore old FP *)
				OBC.PutSDT(OBC.LDRpost,OBC.PC,OBC.SP,4+curProcParamSize); (* Return to caller *);
			END
		END
	END Return;

	PROCEDURE CaseIn*(VAR x: OBT.Item; VAR jmpadrloc, else: LONGINT);
	VAR limreg : LONGINT;
	BEGIN 
		else:=0;
		IF x.typ.form IN {OC.LInt, OC.Int, OC.SInt, OC.Char} THEN
			OBE.load(x);
			OBC.GetReg(limreg); 
			DEC(OBC.allowConstFlushing);
			OBC.PutSDT(OBC.LDR,limreg,OBC.PC,OBC.pc*4+10*4); (* load upper limit *)
			OBC.PutDP(OBC.CMP,0,x.r,limreg,0);
			OBC.PutBabs(OBC.B,else); OBC.SetCondition(OBC.pc-1,OBC.GT); else:=OBC.pc-1;
			OBC.PutSDT(OBC.LDR,limreg,OBC.PC,OBC.pc*4+8*4); (* load lower limit *)
			OBC.PutDP(OBC.CMP,0,x.r,limreg,0);
			OBC.PutBabs(OBC.B,else); OBC.SetCondition(OBC.pc-1,OBC.LT); else:=OBC.pc-1;
			OBC.PutDP(OBC.SUB,x.r,x.r,limreg,0);
			OBC.PutSDT(OBC.LDR,limreg,OBC.PC,OBC.pc*4+8); (* Load address of jump table *)
			OBC.PutSDT1(OBC.LDR,OBC.PC,limreg,x.r,2*8); (* Load adress of case-code *)
			OBC.FreeReg(limreg);
			jmpadrloc:=OBC.pc;
			INC(OBC.pc,3); (* Make space for jmp-tab-addr, upper limit, lower limit *)
			INC(OBC.allowConstFlushing);
			OBC.FlushConsts
		ELSE
			jmpadrloc:=0;
			OBS.Mark(125);
		END
	END CaseIn;

	PROCEDURE CaseOut*(jmpadrloc, L, else, n: LONGINT;  VAR tab: ARRAY OF LabelRange);
	VAR i, j: LONGINT;
	BEGIN 
		OBC.FlushConsts; (* this is important if the jump table is large! *)

		(* store limits and address of jump-table *)
		IF n>0 THEN i:=tab[n-1].high; j:=tab[0].low; ELSE i:=-1; j:=0 END;
		OBC.PutWordAt(jmpadrloc,OBC.pc*4); OBC.AddAbsFixup(jmpadrloc);
		OBC.PutWordAt(jmpadrloc+1,i);
		OBC.PutWordAt(jmpadrloc+2,j);
		
		(*generate jump table*)
		i:=tab[0].low;
		FOR j:=0 TO n-1 DO
			WHILE i<tab[j].low DO OBC.PutWord(else*4); OBC.AddAbsFixup(OBC.pc-1); INC(i) END;
			WHILE i<=tab[j].high DO OBC.PutWord(tab[j].label*4); OBC.AddAbsFixup(OBC.pc-1); INC(i) END;
		END;
		OBC.FixLink(L)
	END CaseOut;

END OBH.
