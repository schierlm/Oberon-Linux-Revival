MODULE VOPC;	(* RC 14.3.90 / 11.2.94 *)	(* object model 29.4.93 *)
(* code generator for RISC-V *)
(*
	Peter Matthias
	2015-08-21	removed delay slots, 
	2015-08-24	traps using TRAP IF condition instructions
	2015-08-26	changed MaxVarR
	2015-10-11	passing static link as first parameter
	2015-11-17	pass static link always on stack
	2015-12-13	using FLOORW in RealToInt (to be tested)
	2016-05-05	AbsVal: made Branch delay slot a NOP

	Traps and AT based changes in blue
	CheckIntRange: Shift amount should not be 16 but 15 ??

	Risc-V: Check parameters for SHIFT 

*)

	IMPORT OPM :=ROPM, OPT := ROPT, OPL := VOPL, S := SYSTEM;

	CONST
		
		(* relations *)
		eql = 9; neq = 10; lss = 11; leq = 12; gtr = 13; geq = 14;

		(*SYSTEM ops*)
		adr = 24; cc = 25; bit = 26; lsh = 27; rot = 28; val = 29;

		(*SYSTEM function number*)
		getfn = 24; putfn = 25; getrfn = 26; putrfn = 27; sysnewfn = 30; movefn = 31;

		RangeTrap =  8;		IndexTrap =  15;		TGTrap = 18;		ITGTrap = 19;

		MaxVarR = 8;	(* can be 10 now; was 8; max nbr of reg var (r4..r7 not included) *)
		MaxVarF = 4; (* was 4; max nbr of float reg var pair (f12..f14 not included) float registers passed via int regs, makes no sense*)

		true = 1;
		
		Tag0Offset = -8;
		Mth0Offset = -72;

	VAR
		inxchk, ranchk, typchk, ptrinit: BOOLEAN;
		Zero: OPL.Item;
		cmpOP, cmpfOP, condf: ARRAY 16 OF LONGINT;
		swapped: ARRAY 16 OF SHORTINT;
		
	PROCEDURE Init*(opt: SET);	(* no overflow check *)
		CONST inx = 0; ran = 2; typ = 3; ptr = 5;
	BEGIN
		inxchk := inx IN opt; ranchk := ran IN opt;
		typchk := typ IN opt; ptrinit := ptr IN opt
	END Init;

	PROCEDURE CommonDesign*(VAR x: OPL.Item);
	BEGIN
		IF (x.mode IN {OPL.Var, OPL.VarPar}) & ((x.offset < 0) OR (x.offset > 63)) THEN OPL.Base(x, -1) END ;
		IF (x.mode = OPL.Based) & (x.reg # OPL.VirtualFP) & (x.reg # OPL.SP) THEN OPL.GetR(OPL.FrozenReg, x.reg) END	(* thaw in OPL.EndStat *)
	END CommonDesign;

	PROCEDURE Field*(VAR x: OPL.Item; offset, rt: LONGINT);
	BEGIN
		IF x.mode IN {OPL.Var, OPL.Based} THEN INC(x.offset, offset)
		ELSE OPL.LoadAddr(x, rt); x.mode := OPL.Based; x.offset := offset
		END
	END Field;
	
	PROCEDURE DeRef*(VAR x: OPL.Item; rt: LONGINT);
		VAR c: SHORTINT; btyp: OPT.Struct;
	BEGIN
		IF rt >= 32 THEN rt := -1 END ;
		OPL.Load(x, rt); x.mode := OPL.Based;
		btyp := x.typ^.BaseTyp; c := btyp^.comp;
		IF c = OPL.DynArr THEN x.offset := btyp^.size + 8 + btyp^.size MOD 8;
			x.descmode := OPL.Based; x.reg2 := x.reg; x.Tjmp := 8; OPL.GetR(OPL.FrozenReg, x.reg2)	(* thaw in OPL.EndStat *)
		ELSIF c = OPL.Array THEN x.offset := 16
		ELSE x.offset := 0
		END
	END DeRef;
	
	PROCEDURE Index*(VAR x, y: OPL.Item; rt: LONGINT);
		VAR len, size, n: OPL.Item; elemsize, nofel, dummy: LONGINT;
	BEGIN
		IF rt >= 32 THEN rt := -1 END ;
		IF x.typ^.comp = OPL.Array THEN elemsize := x.typ^.BaseTyp^.size;
			IF y.mode = OPL.Con THEN
				Field(x, y.offset*elemsize, rt)
			ELSE
				OPL.Load(y, -1);
				IF inxchk THEN nofel := x.typ^.n;
(*
					IF (nofel >= 0FFFFF800H) & (nofel <= 7FFH) THEN dummy := OPL.PutIMM(OPL.SLTIU, T0, y, nofel)	(* simplify, see below *)
					ELSE n.mode := OPL.Con; n.offset := nofel; dummy := OPL.PutSPC(OPL.SLTU, T0, y, n)
					END ;
					OPL.GetR(OPL.TempReg, y.reg); (* was released *)
					OPL.PutSB( OPL.BNE, 0, T0, 2);		OPL.PutU( OPL.XTRAP+ASH( IndexTrap, 15), 0, 0);
*)
					n.mode := OPL.Con; n.offset := nofel; OPL.Load( y, -1); OPL.Load( n, -1); OPL.ReleaseR(n.reg);
					OPL.PutSB( OPL.BLT, y.reg, n.reg, 2);		OPL.PutU( OPL.XTRAP+ASH( IndexTrap, 15), 0, 0);

				END ;
				n.mode := OPL.Con; n.offset := elemsize; OPL.Mul(y, n, -1);
				OPL.LoadAddr(x, -1); x.reg := OPL.PutSPC(OPL.ADD, rt, x, y); x.offset := 0; x.mode := OPL.Based
			END
		ELSE (* x.typ^.comp = DynArr *)
			IF (y.mode # OPL.Con) OR (y.offset # 0) THEN
				OPL.LenDesc(x, len, x.typ);
				IF inxchk THEN n := y;
(*				n := y;
					dummy := OPL.PutSPC(OPL.SLTU, T0, n, len);
					IF y.mode # OPL.Con THEN y := n; OPL.GetR(OPL.TempReg, n.reg) (* was released *) END ;
					OPL.PutSB( OPL.BNE, 0, T0, 2);		OPL.PutU( OPL.XTRAP+ASH( IndexTrap, 15), 0, 0);
*)
					OPL.Load( y,-1); OPL.Load( len, -1); OPL.ReleaseR(len.reg);
					OPL.PutSB( OPL.BLT, y.reg, len.reg, 2); OPL.PutU( OPL.XTRAP+ASH(IndexTrap, 15), 0, 0);
				END ;
				OPL.Size(x, size, -1, x.typ^.BaseTyp); OPL.Mul(y, size, -1);
				OPL.LoadAddr(x, -1); x.reg := OPL.PutSPC(OPL.ADD, rt, x, y); x.offset := 0; x.mode := OPL.Based
			END
		END;
	END Index;

	PROCEDURE SetCond(VAR x, y: OPL.Item; cond: LONGINT);
	BEGIN
		OPL.Load(x, -1); OPL.Load(y, -1);
		x.mode := OPL.Cond; x.reg2 := y.reg; x.offset := cond; x.Tjmp := 0; x.Fjmp := 0
	END SetCond;
	
	PROCEDURE TypTest*(VAR x: OPL.Item; testtyp: OPT.Struct; guard, equal: BOOLEAN);
		VAR xt, tdes: OPL.Item; r: LONGINT;
	BEGIN
		IF typchk OR ~guard THEN r := 0;
			IF x.mode IN {OPL.Reg, OPL.Based} THEN r := x.reg; OPL.GetR(OPL.FrozenReg, r) END ;
			xt := x; xt.typ := OPT.linttyp;
			IF guard & equal THEN
				tdes.mode := OPL.Var; tdes.mnolev := -testtyp^.mno; tdes.offset := 64; tdes.obj := testtyp^.strobj;
				IF xt.mode = OPL.VarPar THEN
					IF xt.offset < 64 THEN xt.mode := OPL.Reg; xt.reg := xt.offset + 1
					ELSE xt.mode := OPL.Var; INC(xt.offset, 4)
					END
				ELSE xt.offset := - 4
				END ;
				OPL.LoadAddr(tdes, -1); OPL.Load(tdes, -1); OPL.Load(xt, -1); 
				OPL.PutSB( OPL.BEQ, tdes.reg, xt.reg, 2);		OPL.PutU( OPL.XTRAP+ASH(ITGTrap, 15), 0, 0);
			ELSE
				IF testtyp^.comp = OPL.Record THEN (* varpar *)
					IF xt.offset < 64 THEN xt.mode := OPL.Based; xt.reg := xt.offset + 1
					ELSE INC(xt.offset, 4); OPL.Base(xt, -1)
					END
				ELSE testtyp := testtyp^.BaseTyp;
					OPL.Load(xt, -1); xt.mode := OPL.Based; xt.offset := -4;
					OPL.Load(xt, -1); xt.mode := OPL.Based
				END ;
				xt.offset := Tag0Offset - 4*testtyp^.extlev;
				tdes.mode := OPL.Var; tdes.mnolev := -testtyp^.mno; tdes.offset := 64; tdes.obj := testtyp^.strobj;
				OPL.LoadAddr(tdes, -1); SetCond(tdes, xt, OPL.BEQ); 
				IF guard THEN OPL.PutSB( OPL.BEQ, tdes.reg, xt.reg, 2);		OPL.PutU( OPL.XTRAP+ASH(ITGTrap, 15), 0, 0);
				ELSE x := tdes
				END
			END ;
			IF r # 0 THEN OPL.ThawR(OPL.FrozenReg, r); OPL.GetR(OPL.TempReg, r) END
		END
	END TypTest;

	PROCEDURE LoadMTA*(VAR ap: OPL.Item; super, deref: BOOLEAN; VAR proc: OPL.Item);	(* ap unchanged *)
		VAR tag: OPL.Item; typ: OPT.Struct; r: LONGINT;
	BEGIN
		OPM.err(700);	(* LoadMTA supposed not to be needed at all *)
		tag := ap; r := 0;
		IF tag.mode IN {OPL.Reg, OPL.Based} THEN r := tag.reg; OPL.GetR(OPL.FrozenReg, r) END ;
		IF super THEN
			typ := tag.typ^.BaseTyp;
			IF tag.typ^.form = OPL.Pointer THEN typ := typ^.BaseTyp END;
			tag.mode := OPL.Var; tag.mnolev := - typ^.mno; tag.offset := 64;
			tag.obj := typ^.strobj; OPL.LoadAddr(tag, -1)
		ELSIF tag.typ^.form = OPL.Pointer THEN DeRef(tag, -1); tag.offset := -4
		ELSIF deref THEN (* ap = p^ *) tag.offset := -4
		ELSIF tag.mode = OPL.VarPar THEN tag.mode := OPL.Var;
			IF tag.offset < 64 THEN (* Reg *) INC(tag.offset) ELSE INC(tag.offset, 4) END
		ELSE tag.mode := OPL.Var; tag.mnolev := - tag.typ^.mno; tag.offset := 64;
			tag.obj := tag.typ^.strobj; OPL.LoadAddr(tag, -1)
		END ;
		tag.typ := OPT.linttyp; OPL.Load(tag, -1);
		IF r # 0 THEN OPL.ThawR(OPL.FrozenReg, r); OPL.GetR(OPL.TempReg, r) END ;
		proc.reg := tag.reg; OPL.GetR(OPL.FrozenReg, tag.reg)	(* thaw in Call *)
	END LoadMTA;

	PROCEDURE CheckIntRange(VAR x: OPL.Item; g: SHORTINT);	(* x.mode = Reg *)
		VAR at: OPL.Item; add, cmp, dummy: LONGINT;
	BEGIN
		IF ranchk THEN
			at.mode := OPL.Reg; at.reg := x.reg; cmp := 256;
			IF g # OPL.Char THEN
				IF g = OPL.Int THEN add := 1; cmp := 2; at.reg := OPL.PutIMM(OPL.SRAI, OPL.T0, x, 16)
				ELSE (* SInt *) add := 128
				END ;
				at.reg := OPL.PutIMM(OPL.ADDI, OPL.T0, at, add)
			END ;
			dummy := OPL.PutIMM(OPL.SLTIU, OPL.T0, at, cmp);
			OPL.PutSB( OPL.BNE, 0, OPL.T0, 2);		OPL.PutU( OPL.XTRAP+ASH( RangeTrap, 15), 0, 0);
			OPL.GetR(OPL.TempReg, x.reg) (* reg was released *)
		END
	END CheckIntRange;
	
	PROCEDURE ToReal(VAR x: OPL.Item; rt: LONGINT; f, g: SHORTINT);
	BEGIN
		OPL.GetF(OPL.TempReg, rt);
		OPL.Load(x,  -1 );
		IF f = OPL.LReal THEN
			IF g=OPL.Real THEN x.reg := OPL.PutFPA( OPL.FCVTSD, rt, x, Zero) ELSE OPM.err(951) END;
		ELSIF f=OPL.Real THEN 
			IF g=OPL.LReal THEN x.reg := OPL.PutFPA( OPL.FCVTDS, rt, x, Zero) ELSE OPM.err(952) END;
		ELSE x.reg := OPL.PutFPA( OPL.FCVTFX+ASH( g DIV OPL.LReal, 25), rt, x, Zero);
		END;
		IF g = OPL.LReal THEN x.typ:= OPT.lrltyp ELSE x.typ:= OPT.realtyp END;
	END ToReal;
	
	PROCEDURE RealToInt(VAR x: OPL.Item; rt: LONGINT; f, g: SHORTINT);
	BEGIN
		x.reg := OPL.PutFPA(OPL.FCVTWF +ASH( f DIV OPL.LReal, 25), rt, x, Zero);
		IF g=OPL.LInt THEN x.typ:=OPT.linttyp;
		ELSIF g=OPL.Int THEN x.typ:= OPT.inttyp;
		ELSIF g=OPL.SInt THEN x.typ:= OPT.sinttyp;
		ELSIF g=OPL.Char THEN x.typ:= OPT.chartyp;
		ELSE HALT(35)	(* debug *)
		END;
		CheckIntRange(x, g)
	END RealToInt;
	
	PROCEDURE Convert*(VAR x: OPL.Item; rt: LONGINT; f, g: SHORTINT);
	BEGIN
		IF f IN OPL.intSet THEN
			IF g IN OPL.intSet THEN OPL.Load(x, rt);
				IF f > g THEN CheckIntRange(x, g) END
			ELSIF g IN OPL.realSet THEN ToReal(x, rt, f, g)
			ELSIF g = OPL.Char THEN OPL.Load(x, rt); CheckIntRange(x, OPL.Char)
			ELSE HALT(35)	(* debug *)
			END
		ELSIF f IN OPL.realSet THEN
			IF g IN OPL.realSet THEN ToReal(x, rt, f, g)
			ELSIF g IN OPL.intSet THEN RealToInt(x, rt, f, g)
			ELSIF g = OPL.Char THEN RealToInt(x, rt, f, OPL.Char)
			ELSE HALT(36)	(* debug *)
			END
		ELSIF (f = OPL.Byte) & (g = OPL.Char) THEN (* ok, type is changed in OPV *)
		ELSIF (f = OPL.Char) OR (f = OPL.Byte) THEN
			IF g IN OPL.intSet THEN
				IF g # OPL.SInt THEN OPL.Load(x, rt) END
			ELSIF g IN OPL.realSet THEN ToReal(x, rt, f, g)
			ELSE HALT(38)	(* debug *)
			END
		ELSE HALT(39)	(* debug *)
		END
	END Convert;

	PROCEDURE Relation*(VAR x: OPL.Item; rt: LONGINT);
	BEGIN IF x.mode = OPL.Cond THEN OPL.Load(x, rt) END
	END Relation;

	PROCEDURE Cmp*(VAR x, y: OPL.Item; rel: SHORTINT);
		VAR f, at: LONGINT; xadr, yadr, z: OPL.Item; 
	BEGIN
		f:=x.typ^.form;
		IF f IN {OPL.Byte..OPL.LInt, OPL.Set, OPL.NilTyp, OPL.Pointer, OPL.ProcTyp} THEN
			IF rel IN {leq, gtr} THEN z := x; x := y; y := z; rel := swapped[rel] END;
			SetCond( x, y, cmpOP[rel]);
		ELSIF f IN OPL.realSet THEN
			x.reg := OPL.PutFPA(condf[rel]+ASH( f DIV OPL.LReal, 25), -1, x, y);
			SetCond(x, Zero, cmpfOP[rel])
		ELSE (* strings *)
			xadr.mode := OPL.Reg; xadr.reg := OPL.T1; yadr.mode := OPL.Reg; yadr.reg := OPL.T2;
			at := -1; OPL.GetR(OPL.FrozenReg, at);
			OPL.LoadAddr(x, OPL.T1); OPL.Move(xadr, x, OPL.LInt); 
			OPL.LoadAddr(y, OPL.T2); OPL.Move(yadr, y, OPL.LInt); 
			(* loop: *) OPL.PutI(OPL.LBU, OPL.T0, OPL.T1, 0);
			OPL.PutI(OPL.LBU, at, OPL.T2, 0);
			OPL.PutI(OPL.ADDI, OPL.T1, OPL.T1, 1);
			OPL.PutSB(OPL.BEQ, OPL.T0, 0, 3);	(* end *)
			OPL.PutI(OPL.ADDI, OPL.T2, OPL.T2, 1);
			OPL.PutSB(OPL.BEQ, OPL.T0, at, -5);	(* loop *)
			(* end: *) OPL.ThawR(OPL.FrozenReg, at); 
			x.mode := OPL.Reg; y.mode := OPL.Reg;
			OPL.GetR(OPL.TempReg, at);
			IF rel IN {leq, gtr} THEN x.reg := at; y.reg := OPL.T0; rel := swapped[rel]
			ELSE x.reg := OPL.T0; y.reg := at
			END ;
			SetCond(x, y, cmpOP[rel])
		END
	END Cmp;

	PROCEDURE CheckSetRange(VAR x: OPL.Item);
		VAR dummy: LONGINT;
	BEGIN
		IF ranchk & (x.mode # OPL.Con) THEN
			dummy := OPL.PutIMM(OPL.SLTIU, OPL.T0, x, 32); 	OPL.GetR(OPL.TempReg, x.reg); (* reg was released *)
			OPL.PutSB( OPL.BNE, 0, OPL.T0, 2);		OPL.PutU( OPL.XTRAP+ASH( 8, 15), 0, 0);
		END
	END CheckSetRange;
	
	PROCEDURE In*(VAR x, y: OPL.Item);
		VAR r: LONGINT;
	BEGIN
		IF x.mode = OPL.Con THEN
			IF x.offset = (OPL.RegSize-1) THEN OPL.Load(y, -1); r := y.reg
			ELSE r := OPL.PutIMM(OPL.SLLI, -1, y, OPL.RegSize-1 - x.offset)
			END
		ELSE CheckSetRange(x);
			x.reg := OPL.PutIMM(OPL.XORI, -1, x, OPL.RegSize-1);
			r := OPL.PutSPC(OPL.SLL, -1, y, x)
		END ;
		x.mode := OPL.Reg; x.reg := r;
		SetCond(x, Zero, OPL.BLT)
	END In;
	
	PROCEDURE SetElem*(VAR x: OPL.Item; rt: LONGINT);
		VAR y: OPL.Item;
	BEGIN CheckSetRange(x);
		y.mode := OPL.Con; y.offset := 1;
		x.reg := OPL.PutSPC(OPL.SLL, rt, y, x)
	END SetElem;
	
	PROCEDURE SetRange*(VAR x, y, z: OPL.Item; rt: LONGINT);	(* x := {y..z} *)
	BEGIN
		IF y.mode = OPL.Con THEN	(* z not constant *)
			CheckSetRange(z);
			y.offset := ASH(1, y.offset) - 1;	(* ...00111...  y ones*)
			x.mode := OPL.Con; x.offset := -2;
			x.reg := OPL.PutSPC(OPL.SLL, -1,  x, z);
			x.reg := OPL.PutSPC(OPL.oR, -1, x, y);		(* NOR *)
			x.reg := OPL.PutIMM(OPL.XORI, rt,  x, -1);
		ELSE CheckSetRange(y);
			x.mode := OPL.Con; x.offset := -1;
			IF (z.mode = OPL.Con) & (z.offset = 31) THEN x.reg := OPL.PutSPC(OPL.SLL, rt, x, y)
			ELSE x.reg := OPL.PutSPC(OPL.SLL, -1, x, y);
				IF z.mode = OPL.Con THEN z.offset := ASH(2, z.offset) - 1	(* ...00111...  z+1 ones*)
				ELSE CheckSetRange(z);
					y.mode := OPL.Con; y.offset := -2;
					z.reg := OPL.PutSPC(OPL.SLL, -1, y, z);
					z.reg := OPL.PutIMM(OPL.XORI, -1,  z, -1);	(* NOT *)
				END ;
				x.reg := OPL.PutSPC(OPL.AND, rt, x, z)
			END
		END
	END SetRange;
	
	PROCEDURE Not*(VAR x: OPL.Item);
		VAR a: LONGINT;
	BEGIN
		IF x.mode = OPL.Cond THEN OPL.Invert(x.offset); a := x.Tjmp; x.Tjmp := x.Fjmp; x.Fjmp := a
		ELSE SetCond(x, Zero, OPL.BEQ)
		END
	END Not;
	
	PROCEDURE Neg*(VAR x: OPL.Item; rt: LONGINT);
		VAR f: SHORTINT;
	BEGIN f := x.typ^.form;
		IF f = OPL.Set THEN x.reg := OPL.PutIMM(OPL.XORI, rt, x, -1);
		ELSIF f IN OPL.intSet THEN x.reg := OPL.PutSPC(OPL.SUB, rt, Zero, x)
		ELSE x.reg := OPL.PutFPA(OPL.FNEG+ASH( f DIV OPL.LReal, 25), rt, x, x)	(* f IN realSet *)
		END
	END Neg;
	
	PROCEDURE AbsVal*(VAR x: OPL.Item; rt: LONGINT);
		VAR f: SHORTINT; dummy: LONGINT;
	BEGIN f := x.typ^.form;
		IF f IN OPL.intSet THEN
			OPL.Load(x, rt);
			IF x.reg#rt THEN x.reg := OPL.PutSPC(OPL.oR, rt, x, Zero) END;
			OPL.PutSB( OPL.BGE, x.reg, 0, 2);
			x.reg := OPL.PutSPC(OPL.SUB, rt, Zero, x);
		ELSE	(* f IN realSet *)
			x.reg := OPL.PutFPA(OPL.FABS+ASH( f DIV OPL.LReal, 25), rt, x, x)
		END
	END AbsVal;
	
	PROCEDURE Cap*(VAR x: OPL.Item; rt: LONGINT);
	BEGIN x.reg := OPL.PutIMM(OPL.ANDI, rt, x, 5FH)
	END Cap;
	
	PROCEDURE Odd*(VAR x: OPL.Item; rt: LONGINT);
	BEGIN x.reg := OPL.PutIMM(OPL.ANDI, rt, x, 1)
	END Odd;
	
	PROCEDURE Add*(VAR x, y: OPL.Item; rt: LONGINT; floating: BOOLEAN);
	BEGIN
		IF floating THEN x.reg := OPL.PutFPA(OPL.FADD+ ASH(y.typ^.form DIV OPL.LReal, 25), rt, x, y)
		ELSE OPL.Add(x, y, rt, FALSE)
		END
	END Add;

	PROCEDURE Sub*(VAR x, y: OPL.Item; rt: LONGINT; floating: BOOLEAN);
	BEGIN
		IF floating THEN x.reg := OPL.PutFPA(OPL.FSUB+ ASH(y.typ^.form DIV OPL.LReal, 25), rt, x, y)
		ELSE OPL.Add(x, y, rt, TRUE)
		END
	END Sub;

	PROCEDURE Increment*(VAR x, y: OPL.Item; rt: LONGINT; decrement: BOOLEAN);
		VAR z: OPL.Item;
	BEGIN CommonDesign(x); z := x; 
		OPL.Add(z, y, rt, decrement); OPL.Move(x, z, x.typ^.form)
	END Increment;

	PROCEDURE Mul*(VAR x, y: OPL.Item; rt: LONGINT; floating: BOOLEAN);
	BEGIN
		IF floating THEN x.reg := OPL.PutFPA(OPL.FMUL + ASH(y.typ^.form DIV OPL.LReal, 25), rt, x, y)
		ELSE OPL.Mul(x, y, rt)
		END
	END Mul;
	
	PROCEDURE Div*(VAR x, y: OPL.Item; rt: LONGINT; floating: BOOLEAN);
	BEGIN
		IF floating THEN x.reg := OPL.PutFPA(OPL.FDIV+ ASH(y.typ^.form DIV OPL.LReal, 25), rt, x, y)
		ELSE OPL.Div(x, y, rt, FALSE)
		END
	END Div;

	PROCEDURE Mod*(VAR x, y: OPL.Item; rt: LONGINT);
	BEGIN OPL.Div(x, y, rt, TRUE)
	END Mod;

	PROCEDURE SetOp(VAR x, y: OPL.Item; rt, op, opi: LONGINT);
		VAR z: OPL.Item; c: LONGINT;
	BEGIN
		IF x.mode = OPL.Con THEN z := x; x := y; y := z END ;
		c := y.offset;
		IF (y.mode = OPL.Con) & (c >= 0) & (c <= 07FFH) THEN x.reg := OPL.PutIMM(opi, rt, x, c)
		ELSE x.reg := OPL.PutSPC(op, rt, x, y)
		END
	END SetOp;
	
	PROCEDURE SetUnion*(VAR x, y: OPL.Item; rt: LONGINT);
	BEGIN SetOp(x, y, rt, OPL.oR, OPL.ORI)
	END SetUnion;

	PROCEDURE SetDiff*(VAR x, y: OPL.Item; rt: LONGINT);
	BEGIN
		IF y.mode = OPL.Con THEN
			IF y.offset = MIN(LONGINT) THEN y.offset := MAX(LONGINT)
			ELSE y.offset := -y.offset - 1
			END
		ELSE Neg(y, -1)
		END ;
		SetOp(x, y, rt, OPL.AND, OPL.ANDI)
	END SetDiff;

	PROCEDURE SetInter*(VAR x, y: OPL.Item; rt: LONGINT);
	BEGIN SetOp(x, y, rt, OPL.AND, OPL.ANDI)
	END SetInter;
	
	PROCEDURE SetSymmDiff*(VAR x, y: OPL.Item; rt: LONGINT);
	BEGIN SetOp(x, y, rt, OPL.XOR, OPL.XORI)
	END SetSymmDiff;
	
	PROCEDURE Include*(VAR x, y: OPL.Item; rt: LONGINT; exclude: BOOLEAN);
		VAR op, opi: LONGINT; z: OPL.Item;
	BEGIN CommonDesign(x); z := x;
		IF y.mode = OPL.Con THEN
			IF exclude THEN op := OPL.AND; opi := OPL.ANDI;
				IF y.offset = 31 THEN y.offset := MAX(LONGINT)
				ELSE y.offset := -1 - ASH(1, y.offset)
				END
			ELSE op := OPL.oR; opi := OPL.ORI; y.offset := ASH(1, y.offset)
			END
		ELSE SetElem(y, -1);
			IF exclude THEN op := OPL.AND;
				y.reg := OPL.PutIMM(OPL.XORI, -1, y, -1);	(* NOR *)
			ELSE op := OPL.oR 
			END
		END ;
		SetOp(z, y, rt, op, opi); OPL.Move(x, z, x.typ^.form)
	END Include;

	PROCEDURE And*(VAR x, y: OPL.Item);
	BEGIN
		IF y.mode # OPL.Cond THEN
			x.reg2 := 0; x.Tjmp := 0; (* x.Fjmp remains unchanged *)
			IF y.mode = OPL.Con THEN x.reg := 0;
				IF y.offset = true THEN x.offset := OPL.BEQ (* always *) ELSE x.offset := OPL.BNE (* never *) END
			ELSE OPL.Load(y, -1); x.reg := y.reg; x.offset := OPL.BNE
			END
		ELSE
			IF y.Fjmp # 0 THEN x.Fjmp := OPL.MergedLinks(x.Fjmp, y.Fjmp) END ;
			x.offset := y.offset; x.reg := y.reg; x.reg2 := y.reg2; x.Tjmp := y.Tjmp
		END
	END And;

	PROCEDURE Or*(VAR x, y: OPL.Item);
	BEGIN
		IF y.mode # OPL.Cond THEN
			x.reg2 := 0; x.Fjmp := 0; (* x.Tjmp remains unchanged *)
			IF y.mode = OPL.Con THEN x.reg := 0;
				IF y.offset = true THEN x.offset := OPL.BEQ (* always *) ELSE x.offset := OPL.BNE (* never *) END
			ELSE OPL.Load(y, -1); x.reg := y.reg; x.offset := OPL.BNE
			END
		ELSE
			IF y.Tjmp # 0 THEN x.Tjmp := OPL.MergedLinks(x.Tjmp, y.Tjmp) END ;
			x.offset := y.offset; x.reg := y.reg; x.reg2 := y.reg2; x.Fjmp := y.Fjmp
		END
	END Or;

	PROCEDURE CondAnd*(VAR x: OPL.Item);
	BEGIN
		IF x.mode = OPL.Cond THEN OPL.Invert(x.offset)
		ELSE (* form = Bool, mode # con *) SetCond(x, Zero, OPL.BEQ)
		END ;
		OPL.PutCond(x, x.Fjmp, FALSE); OPL.PutU( OPL.NOP, 0, 0); x.Fjmp := OPL.pc -2; OPL.FixLink(x.Tjmp)
	END CondAnd;
	
	PROCEDURE CondOr*(VAR x: OPL.Item);
	BEGIN
		IF x.mode # OPL.Cond THEN (* form = Bool, mode # con *) SetCond(x, Zero, OPL.BNE) END ;
		OPL.PutCond(x, x.Tjmp, FALSE); OPL.PutU( OPL.NOP, 0, 0); x.Tjmp := OPL.pc -2; OPL.FixLink(x.Fjmp)
	END CondOr;
	
	PROCEDURE Shift(VAR x, y: OPL.Item; rt, sri, srv: LONGINT);
		VAR c: LONGINT;
	BEGIN
		IF y.mode = OPL.Con THEN c := y.offset;
			IF c > 0 THEN x.reg := OPL.PutIMM(OPL.SLLI, rt, x, c);  
			ELSIF c < 0 THEN x.reg := OPL.PutIMM( sri, rt, x, (-c) MOD 32);
			END
		ELSE OPL.Load(y, -1); OPL.Load(x, -1);
			OPL.ReleaseR(y.reg); OPL.ReleaseR(x.reg); OPL.GetR(OPL.TempReg, rt);
			OPL.PutSB( OPL.BGE, y.reg, 0, 4);
			OPL.PutR( OPL.SUB, y.reg, 0, y.reg);
			OPL.PutR( srv, rt, x.reg, y.reg);
			OPL.PutUJ( OPL.JAL, 0, 2);
			OPL.PutR( OPL.SLL, rt, x.reg, y.reg);
			x.reg:=rt;
		END
	END Shift;

	PROCEDURE Ash*(VAR x, y: OPL.Item; rt: LONGINT);
	BEGIN Shift(x, y, rt, OPL.SRAI, OPL.SRA)
	END Ash;

	PROCEDURE Mem*(VAR x: OPL.Item; offset: LONGINT);	(* x := Mem[x+offset] *)
	BEGIN
		IF x.mode = OPL.Con THEN x.mode := OPL.Based; x.reg := 0; INC(x.offset, offset)
		ELSE OPL.Load(x, -1); x.mode := OPL.Based; x.offset := offset
		END
	END Mem;
	
	PROCEDURE SYSval*(VAR x: OPL.Item; rt: LONGINT; f, g: SHORTINT);	(* implementation of SYSTEM.VAL *)
		VAR r: LONGINT;
	BEGIN
		r := -1;
		IF x.mode = OPL.Reg THEN r := x.reg
		ELSIF (x.mode = OPL.Var) & (x.offset >= 0) & (x.offset < 64) THEN r := x.offset
		END;
		IF (r # -1) & ((f IN OPL.realSet) # (g IN OPL.realSet)) THEN
			IF g IN OPL.realSet THEN OPL.GetF(OPL.TempReg, rt); OPL.PutR( OPL.FMVSX, rt-32, r, 0); OPL.ReleaseR(r);
			ELSE  OPL.GetR(OPL.TempReg, rt); OPL.PutR( OPL.FMVXS, rt, r - 32, 0); OPL.ReleaseF(r);
			END;
			x.mode := OPL.Reg; x.reg := rt;
		END
	END SYSval;
	
	PROCEDURE SYSdop*(VAR x, y: OPL.Item; subcl: SHORTINT; rt: LONGINT);	(* implementation of SYSTEM.BIT, LSH, ROT *)
		VAR size, c, bits, mask, shift: LONGINT; r, s: OPL.Item;
	BEGIN
		CASE subcl OF
		   bit: Mem(x, 0); x.typ := OPT.settyp; In(y, x); x := y
		| lsh: Shift(x, y, rt, OPL.SRLI, OPL.SRL)
		| rot:
			size := x.typ^.size; r.mode := OPL.Reg; s.mode := OPL.Reg;
			ASSERT( size<=4);
			bits:=size*8; mask:=bits-1; shift:=OPL.RegSize-bits;
			IF y.mode = OPL.Con THEN c := y.offset MOD bits;
				IF c # 0 THEN
					r.reg := OPL.PutIMM(OPL.SLLI, OPL.T0, x, c + shift);
					IF shift # 0 THEN s.reg := OPL.PutIMM(OPL.SLLI, OPL.T1, x, shift) ELSE s.reg := x.reg END ;
					s.reg := OPL.PutIMM(OPL.SRLI, OPL.T1, s, bits - c);
					x.reg := OPL.PutSPC(OPL.oR, rt, r, s);
					IF shift # 0 THEN x.reg := OPL.PutIMM(OPL.SRLI, rt, x, shift) END
				END
			ELSE OPL.Load(y, -1);
				IF shift # 0 THEN
					r.reg := OPL.PutIMM(OPL.SLLI, OPL.T0, x, shift);
					y.reg := OPL.PutIMM(OPL.ANDI, OPL.T1, y, mask)
				ELSE OPL.Load(x, OPL.T0); r.reg := x.reg
				END ;
				s.reg := OPL.PutSPC(OPL.SLL, OPL.T2, r, y);
				y.reg := OPL.PutSPC(OPL.SUB, OPL.T1, Zero, y);
				IF mask # 31 THEN y.reg := OPL.PutIMM(OPL.ANDI, OPL.T1, y, mask) END ;
				r.reg := OPL.PutSPC(OPL.SRL, rt, r, y);
				x.reg := OPL.PutSPC(OPL.oR, rt, r, s);
				IF shift # 0 THEN x.reg := OPL.PutIMM(OPL.SRLI, rt, x, shift) END
			END
		END;
	END SYSdop;
	
	PROCEDURE SYSgetput*(VAR x, y: OPL.Item; subcl: SHORTINT);	(* x := y *)
	(* implementation of SYSTEM.GET, PUT, GETREG, PUTREG *)
		VAR f: SHORTINT;
	BEGIN
		CASE subcl OF
		   getfn: y.typ := x.typ; OPL.Move(x, y, x.typ^.form)
		| putfn: x.typ := y.typ; OPL.Move(x, y, y.typ^.form)
		| getrfn:
				IF y.offset < 64 THEN f := x.typ^.form ELSE f := OPL.NoTyp END ;
				y.mode := OPL.Reg; y.reg := y.offset; OPL.Move(x, y, f)
		| putrfn:
				IF x.offset < 64 THEN f := y.typ^.form ELSE f := OPL.NoTyp END ;
				x.mode := OPL.Reg; x.reg := x.offset; OPL.Move(x, y, f)
		END
	END SYSgetput;

	PROCEDURE Msk*(VAR x, y: OPL.Item; rt: LONGINT);	(* y.mode = Con *)
		VAR c: LONGINT; i: LONGINT;
	BEGIN c := y.offset;
		IF c = MIN(LONGINT) THEN c := MAX(LONGINT)
		ELSE c := -c - 1
		END ;
		IF (c >= 0) & (c <= 07FFH) THEN x.reg := OPL.PutIMM(OPL.ANDI, rt, x, c)
		ELSE i := OPL.RegSize;
			WHILE ODD(c) DO c := c DIV 2; DEC(i) END ;
			x.reg := OPL.PutIMM(OPL.SLLI, rt, x, i);
			x.reg := OPL.PutIMM(OPL.SRLI, rt, x, i);
		END
	END Msk;

	PROCEDURE Len*(VAR x, y: OPL.Item);
		VAR typ: OPT.Struct; dim: LONGINT;
	BEGIN
		dim := y.offset; typ := x.typ;
		WHILE dim > 0 DO typ := typ^.BaseTyp; DEC(dim) END ;
		OPL.LenDesc(x, x, typ)
	END Len;
	
	PROCEDURE Copy*(VAR x, y: OPL.Item);	(* x := y *)
		VAR until: LONGINT; xadr, yadr, len: OPL.Item;
	BEGIN
		IF x.typ^.comp = OPL.DynArr THEN OPL.Size(x, len, -1, x.typ);
			len.reg := OPL.PutIMM(OPL.ADDI, -1, len, -1)
		ELSE len.mode := OPL.Con; len.offset := x.typ^.n - 1
		END;
		xadr.mode := OPL.Reg; xadr.reg := OPL.T1; yadr.mode := OPL.Reg; yadr.reg := OPL.T2;
		OPL.LoadAddr(x, OPL.T1); OPL.Move(xadr, x, OPL.LInt);
		OPL.LoadAddr(y, OPL.T2); OPL.Move(yadr, y, OPL.LInt);
		OPL.Add(xadr, len, -1, FALSE); until := xadr.reg;
		OPL.PutI(OPL.LB, OPL.T0, OPL.T2, 0);
		OPL.PutI(OPL.ADDI, OPL.T2, OPL.T2, 1);
		OPL.PutS(OPL.SB, OPL.T0, OPL.T1, 0);
		OPL.PutI(OPL.ADDI, OPL.T1, OPL.T1, 1);
		OPL.PutSB(OPL.BNE, OPL.T1, until, -4);	(* loop *)
	END Copy;
	
	PROCEDURE Base(typ: OPT.Struct): SHORTINT;
	BEGIN
		WHILE typ^.comp IN {OPL.Array, OPL.DynArr} DO typ := typ^.BaseTyp END ;
		IF typ^.comp = OPL.Record THEN RETURN SHORT(SHORT(typ^.align))
		ELSE RETURN SHORT(SHORT(typ^.size))
		END
	END Base;

	PROCEDURE MoveRefBlock(VAR x, y: OPL.Item; s, bx, by: LONGINT);	(* x^ := y^, len = s *)
		VAR until, at, offset, rx, ry: LONGINT; xadr, yadr, len: OPL.Item;	(* at can be removed *)
	BEGIN
		IF s > 0 THEN
			xadr.mode := OPL.Reg; xadr.reg := OPL.T1; yadr.mode := OPL.Reg; yadr.reg := OPL.T2;
			offset := 0; at := -1; OPL.GetR(OPL.FrozenReg, at);
			IF s >= 20 THEN
				OPL.Move(xadr, x, OPL.LInt); rx := OPL.T1;
				OPL.Move(yadr, y, OPL.LInt); ry := OPL.T2;
				len.mode := OPL.Con; len.offset := 4*(s DIV 4); 
				OPL.Add(len, x, -1, FALSE); until := len.reg;
				OPL.PutI(OPL.LW, OPL.T0, OPL.T2, 0);
				OPL.PutI(OPL.ADDI, OPL.T2, OPL.T2, 4);
				OPL.PutS(OPL.SW, OPL.T0, OPL.T1, 0);
				OPL.PutI(OPL.ADDI, OPL.T1, OPL.T1, 4);
				OPL.PutI(OPL.LW, OPL.T0, OPL.T2, 0);
				OPL.PutSB(OPL.BNE, OPL.T1, until, -4);
				s := s MOD 4; OPL.ReleaseR(until);
			ELSE rx := x.reg; ry := y.reg
			END;
			WHILE s>=4 DO
				OPL.PutI(OPL.LW, OPL.T0, ry, offset);
				OPL.PutS(OPL.SW, OPL.T0, rx, offset);
				INC(offset, 4); DEC(s, 4); 
			END;
			IF s >= 2 THEN
				OPL.PutI(OPL.LH, OPL.T0, ry, offset);
				OPL.PutS(OPL.SH, OPL.T0, rx, offset);
				INC(offset, 2); DEC(s, 2); 
			END;
			IF s = 1 THEN
				OPL.PutI(OPL.LB, at, ry, offset);
				OPL.PutS(OPL.SB, at, rx, offset);
				INC(offset); DEC(s); 
			END;
			OPL.ThawR( OPL.FrozenReg, at);
		END
	END MoveRefBlock;

(*
	PROCEDURE MoveRefBlock(VAR x, y: OPL.Item; s, bx, by: LONGINT);	(* x^ := y^, len = s *)
		VAR until, at, last, seclast, t, offset, rx, ry: LONGINT; xadr, yadr, len: OPL.Item;
	BEGIN
		IF s > 0 THEN
			xadr.mode := OPL.Reg; xadr.reg := T1; yadr.mode := OPL.Reg; yadr.reg := T2;
			offset := 0; at := -1; OPL.GetR(OPL.FrozenReg, at);
			IF (bx < 4) OR (by < 4) OR (s < 4) THEN
				IF s >= 16 THEN
					OPL.Move(xadr, x, OPL.LInt); rx := T1;
					OPL.Move(yadr, y, OPL.LInt); ry := T2;
					len.mode := OPL.Con; len.offset := 8*(s DIV 8); 
					OPL.Add(len, y, -1, FALSE); until := len.reg;
					OPL.PutI(OPL.LW, T0, T2, 0);
					OPL.PutI(OPL.ADDI, T2, T2, 8);
					OPL.PutS(OPL.SW, T0, T1, 0);
					OPL.PutI(OPL.LW, T0, T2, - 4);
					OPL.PutI(OPL.ADDI, T1, T1, 8);
					OPL.PutS(OPL.SW, T0, T1, - 4);
					OPL.PutSB(OPL.BNE, T2, until, -6);
					s := s MOD 8; OPL.ReleaseR(until);
				ELSE rx := x.reg; ry := y.reg
				END ;
				IF s >= 8 THEN
					OPL.PutI(OPL.LW, T0, ry, offset);
					OPL.PutI(OPL.LW, at, ry, offset +  4);
					OPL.PutS(OPL.SW, T0, rx, offset);
					OPL.PutS(OPL.SW, at, rx, offset + 4);
					INC(offset, 8); DEC(s, 8)
				END ;
				last := at; seclast := T0;	(* to allow peephole optimization *)
				IF s >= 4 THEN
					OPL.PutI(OPL.LW, T0, ry, offset);
					OPL.PutS(OPL.SW, T0, rx, offset);
					INC(offset, 4); DEC(s, 4); last := T0; seclast := at	(* to allow peephole optimization *)
				END ;
				WHILE s > 0 DO
					OPL.PutI(OPL.LB, seclast, ry, offset);
					OPL.PutS(OPL.SB, seclast, rx, offset);
					INC(offset); DEC(s); t := seclast; seclast := last; last := t	(* to allow peephole optimization *)
				END
			ELSE (* s MOD 4 = 0 *)
				IF s >= 24 THEN
					OPL.Move(xadr, x, OPL.LInt); rx := T1;
					OPL.Move(yadr, y, OPL.LInt); ry := T2;
					len.mode := OPL.Con; len.offset := 12*(s DIV 12); 
					OPL.Add(len, y, -1, FALSE); until := len.reg;
					OPL.PutI(OPL.LW, T0, T2, 0);
					OPL.PutI(OPL.ADDI, T2, T2, 12);
					OPL.PutS(OPL.SW, T0, T1, 0);
					OPL.PutI(OPL.LW, T0, T2, -8);
					OPL.PutI(OPL.ADDI, T1, T1, 12);
					OPL.PutS(OPL.SW, T0, T1, -8);
					OPL.PutI(OPL.LW, T0, T2, -4);
					OPL.PutS(OPL.SW, T0, T1, -4);
					OPL.PutSB(OPL.BNE, T2, until, -8);
					s := s MOD 12; OPL.ReleaseR(until);
				ELSE rx := x.reg; ry := y.reg
				END ;
				WHILE s >= 8 DO
					OPL.PutI(OPL.LW, T0, ry, offset);
					OPL.PutI(OPL.LW, at, ry, offset + 4);
					OPL.PutS(OPL.SW, T0, rx, offset);
					OPL.PutS(OPL.SW, at, rx, offset + 4);
					INC(offset, 8); DEC(s, 8)
				END ;
				IF s = 4 THEN
					OPL.PutI(OPL.LW, T0, ry, offset);
					OPL.PutS(OPL.SW, T0, rx, offset);
				END
			END ;
			OPL.ThawR( OPL.FrozenReg, at);
		END
	END MoveRefBlock;
*)
	PROCEDURE MoveBlock(VAR x, y: OPL.Item; s: LONGINT);	(* x := y, len = s *)
		VAR bx, by: LONGINT;
	BEGIN
		IF s > 0 THEN
			bx := Base(x.typ); OPL.LoadAddr(x, OPL.T1);
			by := Base(y.typ); OPL.LoadAddr(y, OPL.T2);
			MoveRefBlock(x, y, s, bx, by);
		END
	END MoveBlock;

	PROCEDURE DynArrBnd(VAR fp, ap: OPL.Item; ftyp, atyp: OPT.Struct);
		VAR size, len: OPL.Item; rt: LONGINT;
	BEGIN (* ftyp^.comp = DynArr *)
		IF ftyp^.BaseTyp = OPT.bytetyp THEN
			OPL.LenDesc(fp, len, ftyp);
			IF len.mode = OPL.Reg THEN rt := len.reg ELSE rt := -1 END ;
			OPL.Size(ap, size, rt, atyp)
		ELSE	(* atyp^.comp = Array, DynArr *)
			IF ftyp^.BaseTyp^.comp = OPL.DynArr THEN DynArrBnd(fp, ap, ftyp^.BaseTyp, atyp^.BaseTyp) END ;
			IF atyp^.comp = OPL.Array THEN size.mode := OPL.Con; size.offset := atyp^.n
			ELSE OPL.LenDesc(ap, size, atyp)
			END ;
			OPL.LenDesc(fp, len, ftyp)	(* called after recursive call: reg allocation *)
		END ;
		OPL.Move(len, size, OPL.LInt)
	END DynArrBnd;

	PROCEDURE Assign*(VAR x, y: OPL.Item; rt: LONGINT);	(* x := y *)
		VAR f, g: SHORTINT; len, strlen: OPL.Item; s: LONGINT;
	BEGIN
		f := x.typ^.form; g := y.typ^.form;
		CASE f OF
		  OPL.Byte..OPL.LInt, OPL.Set, OPL.Pointer, OPL.ProcTyp:
				OPL.Move(x, y, f)
		| OPL.Real, OPL.LReal:
				IF g # f THEN ToReal(y, rt, g, f) END ;
				OPL.Move(x, y, f)
		| OPL.Comp:
				IF x.typ^.comp = OPL.Array THEN
					s := x.typ^.size;
					IF x.typ = y.typ THEN MoveBlock(x, y, s)
					ELSE (* String *) MoveBlock(x, y, y.Tjmp)
					END
				ELSIF x.typ^.comp = OPL.DynArr THEN	(* x is an argument *)
					IF (g = OPL.String) & (x.typ^.BaseTyp^.form = OPL.Char) THEN
						strlen.mode := OPL.Con; strlen.offset := y.Tjmp;
						OPL.LenDesc(x, len, x.typ); OPL.Move(len, strlen, OPL.LInt)
					ELSE DynArrBnd(x, y, x.typ, y.typ)
					END ;
					OPL.LoadAddr(y, rt); OPL.Move(x, y, OPL.LInt)
				ELSE (* x.typ^.comp = Record *)
					MoveBlock(x, y, x.typ^.size)
				END
		END
	END Assign;

	PROCEDURE MulDim*(len: OPL.Item; VAR nofel: OPL.Item; dimtyp, dim0typ: OPT.Struct);	(* nofel := nofel * len *)
		VAR dummy: LONGINT;
	BEGIN
		IF len.mode IN {OPL.Reg, OPL.Based} THEN OPL.GetR(OPL.FrozenReg, len.reg) END ;	(* thaw in SetDim *)
		IF ranchk & (len.mode # OPL.Con) THEN
			dummy := OPL.PutIMM(OPL.SLTI, OPL.T0, len, 1); OPL.GetR(OPL.TempReg, len.reg); (* reg was released *)
			OPL.PutSB( OPL.BEQ, 0, OPL.T0, 2);		OPL.PutU( OPL.XTRAP+ASH(RangeTrap, 15), 0, 0);
		END ;
		IF dimtyp = dim0typ THEN (*outer dimension*) nofel := len
		ELSE  OPL.Mul(nofel, len, -1); 	(* was 2nd parameter reg. ; migth be buggy ToDo: test *)
		END
	END MulDim;
	
	PROCEDURE SetDim*(p: OPL.Item; VAR len: OPL.Item; dimtyp: OPT.Struct);	(* set LEN(p^, dimtyp^.n) to len *)
		(* len may be modified (loaded), p is the returned value from NewArr (pointer) *) 
		VAR lendesc: OPL.Item; r: LONGINT;
	BEGIN (* p.mode = Reg *)
		DeRef(p, -1); OPL.LenDesc(p, lendesc, dimtyp);
		IF len.mode IN {OPL.Reg, OPL.Based} THEN r := len.reg; OPL.ThawR(OPL.FrozenReg, r); OPL.GetR(OPL.TempReg, r) END ;
		OPL.Move(lendesc, len, OPL.LInt)
	END SetDim;

	PROCEDURE SYSnew*(VAR x: OPL.Item);	(* call to Kernel.NewSys(size: LONGINT): ADDRESS *)
		VAR arg: OPL.Item;
	BEGIN
		IF MaxVarR <4 THEN		(* only valid without static link ??*)
			arg.mode := OPL.Reg; arg.reg := -1; OPL.GetR(OPL.TempReg, arg.reg);  OPL.Move(arg, x, OPL.LInt); OPL.PutS(OPL.SW, arg.reg, OPL.SP, 0);
		ELSE
			arg.mode := OPL.Reg; arg.reg := OPL.ARI; OPL.GetR(OPL.TempReg, arg.reg); OPL.Move(arg, x, OPL.LInt);
		END;
		OPL.PutUJ( OPL.JAL, OPL.RA, OPL.Link(OPL.KNewSys)); (* fix relative jump! *)
		OPL.PutU( 0, 0, 0)
	END SYSnew;

	PROCEDURE New*(VAR x, nofel: OPL.Item);	(* x.typ^.BaseTyp^.comp IN {Record, Array, DynArr}, nofel set if DynArr *)
		VAR arg, tag: OPL.Item; nofdim, nofelem: LONGINT; typ, eltyp: OPT.Struct;
	BEGIN
		typ := x.typ^.BaseTyp; arg.typ := OPT.linttyp; tag.typ := OPT.linttyp;
		IF typ^.comp = OPL.Record THEN	(* call to Kernel.NewRec(tag: Tag): ADDRESS *)
			IF MaxVarR <4 THEN		(* only valid without static link ??*)
				arg.mode := OPL.Reg; arg.reg := -1; OPL.GetR(OPL.TempReg, arg.reg);
				tag.mode := OPL.Var; tag.mnolev := -typ^.mno; tag.offset := 64; tag.obj := typ^.strobj;
				OPL.LoadAddr(tag, arg.reg); OPL.Move(arg, tag, OPL.LInt); OPL.PutS(OPL.SW, arg.reg, OPL.SP, 0);
			ELSE
				arg.mode := OPL.Reg; arg.reg := OPL.ARI; OPL.GetR(OPL.TempReg, arg.reg);
				tag.mode := OPL.Var; tag.mnolev := -typ^.mno; tag.offset := 64; tag.obj := typ^.strobj;
				OPL.LoadAddr(tag, arg.reg); OPL.Move(arg, tag, OPL.LInt);
			END;
			OPL.PutUJ( OPL.JAL, OPL.RA, OPL.Link(OPL.KNewRec));	(* fix relative jump *)
			OPL.PutU( 0, 0, 0)
		ELSE eltyp := typ^.BaseTyp;
			IF typ^.comp = OPL.Array THEN
				nofdim := 0; nofel.mode := OPL.Con; nofel.offset := typ^.n; nofel.typ := OPT.linttyp
			ELSE (* DynArr *)
				nofdim := typ^.n+1;
				WHILE eltyp^.comp = OPL.DynArr DO eltyp := eltyp^.BaseTyp END
			END ;
			nofelem := 1;
			WHILE eltyp^.comp = OPL.Array DO nofelem := nofelem*eltyp^.n; eltyp := eltyp^.BaseTyp END ;
			arg.mode := OPL.Con; arg.offset := nofelem; OPL.Mul(nofel, arg, OPL.ARI+1);
			IF eltyp^.comp = OPL.Record THEN
				tag.mode := OPL.Var; tag.mnolev := -eltyp^.mno; tag.offset := 64; tag.obj := eltyp^.strobj;
				OPL.LoadAddr(tag, OPL.ARI)
			ELSIF eltyp^.form = OPL.Pointer THEN
				tag.mode := OPL.Con; tag.offset := 0	(* special TDesc in Kernel for ARRAY OF POINTER *)
			ELSE	(* eltyp contains no pointer *)
				arg.mode := OPL.Con; arg.offset := eltyp^.size; OPL.Mul(nofel, arg, OPL.ARI);
				arg.offset := 8*(nofdim DIV 2) + 4 + 12; OPL.Add(nofel, arg, OPL.ARI, FALSE);
				SYSnew(nofel); RETURN
			END;
			IF MaxVarR <4 THEN	(* only valid without static link ?? *)
				OPL.PutI(OPL.ADDI, OPL.SP, OPL.SP, -16);	
				arg.mode := OPL.Reg; arg.reg := -1; OPL.GetR(OPL.TempReg, arg.reg); OPL.Move(arg, tag, OPL.LInt); OPL.PutS(OPL.SW, arg.reg, OPL.SP, 0);
				arg.mode := OPL.Reg; arg.reg := -1; OPL.GetR(OPL.TempReg, arg.reg); OPL.Move(arg, nofel, OPL.LInt); OPL.PutS(OPL.SW, arg.reg, OPL.SP, 4);
				nofel.mode := OPL.Con; nofel.offset := nofdim; nofel.typ := OPT.linttyp;
				arg.mode := OPL.Reg; arg.reg := -1; OPL.GetR(OPL.TempReg, arg.reg); OPL.Move(arg, nofel, OPL.LInt); OPL.PutS(OPL.SW, arg.reg, OPL.SP, 8); 
				OPL.PutUJ(OPL.JAL, OPL.RA, OPL.Link(OPL.KNewArr)); OPL.PutU( 0, 0, 0); (* fix relative jump *) OPL.PutI(OPL.ADDI, OPL.SP, OPL.SP, 16 );
			ELSE
				arg.mode := OPL.Reg; arg.reg := OPL.ARI; OPL.GetR(OPL.TempReg, arg.reg); OPL.Move(arg, tag, OPL.LInt);
				arg.mode := OPL.Reg; arg.reg := OPL.ARI+1; OPL.GetR(OPL.TempReg, arg.reg); OPL.Move(arg, nofel, OPL.LInt);
				nofel.mode := OPL.Con; nofel.offset := nofdim; nofel.typ := OPT.linttyp;
				arg.mode := OPL.Reg; arg.reg := OPL.ARI+2; OPL.GetR(OPL.TempReg, arg.reg); OPL.Move(arg, nofel, OPL.LInt);
				OPL.PutUJ( OPL.JAL, OPL.RA, OPL.Link(OPL.KNewArr)); OPL.PutU( 0, 0, 0);	(* fix relative jump *)
			END;
		END
	END New;

	PROCEDURE SYSmove*(VAR x, y, z: OPL.Item; zmult4: BOOLEAN);	(* x^ := z bytes at y *)
	(* doesn't work if overlapping and x > y *)
		VAR until: LONGINT; xadr, yadr: OPL.Item;
	BEGIN
		IF z.mode = OPL.Con THEN OPL.Load(x, OPL.T1); OPL.Load(y, OPL.T2); MoveRefBlock(x, y, z.offset, 1, 1)
		ELSE
			xadr.mode := OPL.Reg; xadr.reg := OPL.T1; yadr.mode := OPL.Reg; yadr.reg := OPL.T2;
			OPL.Move(xadr, x, OPL.LInt);
			OPL.Move(yadr, y, OPL.LInt);
			until := OPL.PutSPC(OPL.ADD, -1, xadr, z);
			OPL.PutSB(OPL.BGEU, OPL.T1, until, 7);	(* was 6 end *)
			OPL.PutI(OPL.LB, OPL.T0, OPL.T2, 0);
			(* loop1: *) OPL.PutI(OPL.ADDI, OPL.T2, OPL.T2, 1);
			OPL.PutS(OPL.SB,OPL.T0,  OPL.T1, 0);
			OPL.PutI(OPL.ADDI, OPL.T1, OPL.T1, 1);
			OPL.PutI(OPL.LB, OPL.T0, OPL.T2, 0);
			OPL.PutSB(OPL.BNE, OPL.T1, until, -4);	(* loop1 *)
			(* end: *) OPL.ReleaseR(until) 
		END
	END SYSmove;

	PROCEDURE SYSmove8(VAR x, y, z: OPL.Item);	(* x^ := z bytes at y multiple of 8 bytes, aligned*)
	CONST FT0=0;
	(* doesn't work if overlapping and x > y *)
		VAR until: LONGINT; xadr, yadr: OPL.Item;
	BEGIN
		IF z.mode = OPL.Con THEN OPL.Load(x, OPL.T1); OPL.Load(y, OPL.T2); MoveRefBlock(x, y, z.offset, 1, 1)
		ELSE
			xadr.mode := OPL.Reg; xadr.reg := OPL.T1; yadr.mode := OPL.Reg; yadr.reg := OPL.T2;
			OPL.Move(xadr, x, OPL.LInt);
			OPL.Move(yadr, y, OPL.LInt);
			until := OPL.PutSPC(OPL.ADD, -1, xadr, z); 
			OPL.PutI(OPL.FLD, FT0, OPL.T2, 0 );
			(* loop0: *) OPL.PutI(OPL.ADDI, OPL.T2, OPL.T2, 8);
			OPL.PutS(OPL.FSD, FT0, OPL.T1, 0);
			OPL.PutI(OPL.ADDI, OPL.T1, OPL.T1, 8);
			OPL.PutI(OPL.FLD, FT0, OPL.T2, 0 );
			OPL.PutSB(OPL.BNE, OPL.T1, until, -4);	(* loop0 *)
			(* end: *) OPL.ReleaseR(until) 
		END
	END SYSmove8;

	PROCEDURE VarParRecord(VAR arg, ap: OPL.Item; rt: LONGINT; deref: BOOLEAN);
		VAR aptag, argtag: OPL.Item; aptyp: OPT.Struct; apr, tagrt: LONGINT;
	BEGIN
		arg.typ := OPT.linttyp; aptyp := ap.typ; ap.typ := OPT.linttyp; argtag := arg; aptag := ap; apr := 0;
		IF aptag.mode = OPL.Based THEN apr := aptag.reg; OPL.GetR(OPL.FrozenReg, apr) END ;
		IF argtag.mode = OPL.Reg THEN INC(argtag.reg) ELSE INC(argtag.offset, 4) END ;
		IF ap.mode = OPL.VarPar THEN aptag.mode := OPL.Var;
			IF ap.offset < 64 THEN (* Reg *) INC(aptag.offset) ELSE INC(aptag.offset, 4) END
		ELSIF deref THEN (* ap = p^ *) aptag.offset := -4
		ELSE aptag.mode := OPL.Var; aptag.mnolev := -aptyp^.mno; aptag.offset := 64; aptag.obj := aptyp^.strobj;
			IF rt = -1 THEN tagrt := -1 ELSE tagrt := rt + 1 END ;
			OPL.LoadAddr(aptag, tagrt)
		END ;
		OPL.LoadAddr(ap, rt); OPL.Move(argtag, aptag, OPL.LInt);	(* arg := ap done in param *)
		IF apr # 0 THEN OPL.ThawR(OPL.FrozenReg, apr); OPL.GetR(OPL.TempReg, apr) END
	END VarParRecord;

	PROCEDURE VarParOther(fp: OPT.Object; VAR arg, ap: OPL.Item; rt: LONGINT);
		VAR tag, ptr: OPL.Item; btyp: OPT.Struct;
	BEGIN
		IF (fp^.typ = OPT.sysptrtyp) & (ap.typ # OPT.sysptrtyp) THEN (* ptr to record, else undef *)
			btyp := ap.typ^.BaseTyp;
			tag.mode := OPL.Var; tag.mnolev := -btyp^.mno; tag.offset := 64; tag.obj := btyp^.strobj;
			OPL.LoadAddr(tag, -1); OPL.LoadAddr(ap, rt);
			ptr.mode := OPL.Based; ptr.reg := ap.reg; ptr.offset := 0;
			OPL.Move(ptr, tag, OPL.LInt); OPL.GetR(OPL.TempReg, ap.reg)
		ELSE OPL.LoadAddr(ap, rt)
		END ;
		arg.typ := OPT.linttyp
	END VarParOther;

	PROCEDURE Param*(VAR ap: OPL.Item; fp: OPT.Object; deref: BOOLEAN);
		VAR c: SHORTINT; arg: OPL.Item; adr, rt: LONGINT; 
	BEGIN
		c := fp^.typ^.comp; adr := fp^.adr; arg.typ := fp^.typ;
		IF   (adr < 64) THEN (* register-passed *)
			arg.mode := OPL.Reg; arg.descmode := OPL.Reg;
			rt := adr;
			IF adr < 32 THEN OPL.GetR(OPL.TempReg, rt)
			ELSE OPL.GetF(OPL.TempReg, rt)
			END ;
			arg.reg := rt; arg.reg2 := rt
		ELSE rt := -1;
			arg.mode := OPL.Based; arg.descmode := OPL.Based;
			arg.reg := OPL.SP; arg.reg2 := OPL.SP;
			arg.offset := adr - 64; arg.Tjmp := adr - 64
		END ;
		IF fp^.mode = OPL.VarPar THEN
			IF c = OPL.Record THEN VarParRecord(arg, ap, rt, deref)
			ELSIF c # OPL.DynArr THEN VarParOther(fp, arg, ap, rt)
			END
		ELSIF c IN {OPL.Record, OPL.Array} THEN arg.typ := OPT.linttyp; OPL.LoadAddr(ap, rt)
		END ;
		Assign(arg, ap, rt)
	END Param;
	
	PROCEDURE Call*(VAR x: OPL.Item; proc: OPT.Object);
		VAR i, j, n, instr, link: LONGINT; mth, sl: OPL.Item;
	BEGIN
		IF (x.mode = OPL.LProc) OR (x.mode = OPL.XProc) & (x.mnolev = 0) THEN
			IF OPL.slNeeded IN proc^.conval^.setval THEN
				sl.mode := OPL.Based; sl.offset := 0; sl.reg := OPL.LoadFP(x.mnolev, -1); OPL.LoadAddr(sl, -1);
				OPL.PutS(OPL.SW, sl.reg, OPL.SP, 0);		(* pass static link, always on stack *)
			END ;
			link := proc^.adr+1;
			IF link # 1 THEN (* compiled *) OPL.SetLink(link);
			ELSE (* forward *) link:=OPL.Link(proc);
			END;
			OPL.PutUJ( OPL.JAL, OPL.RA, link);
		ELSIF x.mode = OPL.XProc THEN
			OPL.PutUJ( OPL.JAL, OPL.RA, OPL.Link(proc));	(* fixed by linker *)
			OPL.PutU( 0, 0, 0);
		ELSIF x.mode = OPL.TProc THEN OPL.ThawR(OPL.FrozenReg, x.reg);
			mth.mode := OPL.Based; mth.reg := x.reg; mth.offset := Mth0Offset - 4 * x.offset; mth.typ := OPT.linttyp;
			i := OPL.PutSPC(OPL.JALR, OPL.RA, mth, Zero);
		ELSIF x.mode = OPL.CProc THEN i := 1; n := ORD(proc^.conval^.ext^[0]);
			WHILE i <= n DO instr := 0; j := 0;
				WHILE (j < 4) & (i <= n) DO INC(instr,  S.LSH(LONG(proc^.conval^.ext^[i]), 8*j)); INC(i); INC(j) END ;
				OPL.PutU(instr, 0, 0)
			END
		ELSE	(* proc var *)
			i := OPL.PutSPC(OPL.JALR, OPL.RA, x, Zero);
			x.typ := x.typ.BaseTyp
		END
		(*function result is marked when restoring registers, x.typ must be valid*)
	END Call;
	
	PROCEDURE CopyDynArray(adr: LONGINT; typ: OPT.Struct);
		VAR sr: LONGINT; a0, desc, size, stk: OPL.Item;
	BEGIN
		a0.mode := OPL.VarPar; a0.mnolev := OPL.level; a0.offset := adr; a0.descmode := OPL.Var; a0.Tjmp := adr;
		desc.mode := OPL.Var; desc.mnolev := OPL.level; desc.offset := adr;
		OPL.Size(a0, size, -1, typ); sr := OPL.PutIMM(OPL.ADDI, -1, size, 7);
		OPL.PutI(OPL.SRLI, sr, sr, 3);
		OPL.PutI(OPL.SLLI, sr, sr, 3); 
		OPL.PutR(OPL.SUB, OPL.SP, OPL.SP, sr);
		a0.typ := typ; stk.mode := OPL.Reg; stk.reg := OPL.SP; stk.typ := OPT.linttyp;
		size.reg := sr; OPL.LoadAddr(a0, OPL.T2); SYSmove8(stk, a0, size);	(* move block of size aligned to 8-byte *)
		stk.mode := OPL.Reg; stk.reg := OPL.SP; OPL.Move(desc, stk, OPL.LInt)
	END CopyDynArray;

	PROCEDURE InitPtrs*(proc: OPT.Object);
		CONST MaxPtrs = 16;
		VAR i, nofptrs: INTEGER; x, y, xadr, yadr, nil: OPL.Item; obj: OPT.Object;
			ptrTab: ARRAY MaxPtrs + 1 OF LONGINT;
	BEGIN
		IF ptrinit THEN
			nofptrs := 0; obj := proc^.scope^.scope;	(* local variables *)
			WHILE (obj # NIL) & (nofptrs <= MaxPtrs) DO
				OPL.FindPtrs(obj^.typ, obj^.linkadr, ptrTab, nofptrs);
				obj := obj^.link
			END ;
			nil.mode := OPL.Reg; nil.reg := 0;
			IF nofptrs > MaxPtrs THEN
				(* initialize local frame (not copied parameters) to NIL *)
				obj := proc^.scope^.scope;	(* first local variable *)
				x.offset := proc^.conval^.intval2;
				y.offset := obj^.adr + obj^.typ^.size;
				x.mode := OPL.Var; x.typ := OPT.sysptrtyp; x.mnolev := OPL.level;
				y.mode := OPL.Var; y.typ := OPT.sysptrtyp; y.mnolev := OPL.level;
				xadr.mode := OPL.Reg; xadr.reg := OPL.T1; yadr.mode := OPL.Reg; yadr.reg := OPL.T2;
				OPL.LoadAddr(x, OPL.T1); OPL.Move(xadr, x, OPL.LInt);
				OPL.LoadAddr(y, OPL.T2); OPL.Move(yadr, y, OPL.LInt);
				OPL.PutI(OPL.ADDI, OPL.T1, OPL.T1, 8);
				OPL.PutS(OPL.SW, 0, OPL.T1, -8);
				OPL.PutS(OPL.SW, 0, OPL.T1, -4);
				OPL.PutSB(OPL.BNE, OPL.T1, OPL.T2,-3);
				nofptrs := 0;	(* find pointer registers *)
				WHILE obj # NIL DO
					IF (obj^.linkadr > 0) & (obj^.typ^.form = OPL.Pointer) THEN ptrTab[nofptrs] := obj^.linkadr; INC(nofptrs) END ;
					obj := obj^.link
				END
			END ;
			i := 0;
			WHILE i < nofptrs DO
				x.mode := OPL.Var; x.typ := OPT.sysptrtyp; x.mnolev := OPL.level;
				x.offset := ptrTab[i]; OPL.Move(x, nil, OPL.Pointer); INC(i)
			END
		END
	END InitPtrs;

	PROCEDURE Enter*(proc: OPT.Object);
		VAR var: OPT.Object; from, to: OPL.Item;
			f: SHORTINT; nofVarR, nofVarF, c, r, padr, vadr: LONGINT;
			typ: OPT.Struct;
			
		PROCEDURE AllocPar(nofr: LONGINT; floating: BOOLEAN);
			VAR r, r2, n: LONGINT; from, to: OPL.Item; regalloc: BOOLEAN; form: SHORTINT;
		BEGIN (* floating passed in r (not f) always copied to mem *)
			IF padr < 64 THEN (* register-passed *)
				IF var^.leaf & (nofr <= 2) & (~floating OR (padr >= 32)) THEN
					regalloc := TRUE; n := nofr;
					IF proc^.leaf THEN r := padr;
						IF floating THEN OPL.GetF(OPL.VarReg, r)
						ELSE REPEAT OPL.GetR(OPL.VarReg, r); (* reserve r *) INC(r); DEC(n) UNTIL n = 0
						END ;
						vadr := padr
					ELSE
						r := -1;
						IF floating THEN OPL.GetF(OPL.VarReg, r)
						ELSE OPL.GetR(OPL.VarReg, r);
							IF nofr = 2 THEN r2 := -1; OPL.GetR(OPL.VarReg, r2); regalloc := r + 1 = r2;
								IF ~regalloc THEN OPL.ThawR(OPL.VarReg, r); OPL.ThawR(OPL.VarReg, r2) END
							END
						END ;
						IF regalloc THEN
							to.mode := OPL.Reg; to.reg := r;
							from.mode := OPL.Reg; from.reg := padr;
							REPEAT OPL.Move(to, from, f); INC(to.reg); INC(from.reg); DEC(n) UNTIL n = 0;
							vadr := r
						END
					END
				ELSE regalloc := FALSE
				END ;
				IF regalloc THEN
					IF floating THEN DEC(nofVarF, nofr)
					ELSE DEC(nofVarR, nofr)
					END
				ELSE (* copy to mem *)
					IF var^.mode = OPL.VarPar THEN form := OPL.LInt ELSE form := f END ;
					REPEAT
						to.mode := OPL.Var; to.mnolev := OPL.level; to.offset := vadr + (nofr - 1)*4;
						from.mode := OPL.Reg; from.reg := padr + nofr - 1;
						OPL.Move(to, from, form); DEC(nofr)
					UNTIL nofr = 0
				END
			ELSE (* remains in mem *) vadr := padr
			END
		END AllocPar;
		
	BEGIN
		IF proc = NIL THEN (* enter module *)
		ELSE (* enter proc *)
			nofVarR := MaxVarR; nofVarF := MaxVarF;
			var := proc^.link;	(* parameters *)
			WHILE var # NIL DO
				typ := var^.typ; f := typ^.form; c := typ^.comp; padr := var^.adr; vadr := var^.linkadr;
				IF c = OPL.DynArr THEN
					AllocPar(typ^.size DIV 4, FALSE);
					IF var^.mode = OPL.Var THEN CopyDynArray(vadr, typ) (* vadr > 0, may be reg *) END
				ELSIF var^.mode = OPL.VarPar THEN
					IF c = OPL.Record THEN AllocPar(2, FALSE)
					ELSE AllocPar(1, FALSE)
					END
				ELSE
					IF c IN {OPL.Record, OPL.Array} THEN
						from.mode := OPL.VarPar; from.mnolev := OPL.level; from.offset := padr; from.typ := typ; (* padr > 0, may be reg *)
						to.mode := OPL.Var; to.mnolev := OPL.level; to.offset := vadr; to.typ := typ; (* vadr < 0 *)
						MoveBlock(to, from, typ^.size)
					ELSE AllocPar(1, f IN OPL.realSet);
					END
				END ;
				var^.linkadr := vadr; var := var^.link
			END ;
			var := proc^.scope^.scope;	(* local vars *)
			IF proc^.leaf THEN nofVarR := MaxVarR; nofVarF := MaxVarF END ;
			WHILE var # NIL DO
				IF var^.typ^.form IN OPL.realSet THEN
					IF var^.leaf & (nofVarF > 0) THEN
						r := -1; OPL.GetF(OPL.VarReg, r); var^.linkadr := r; DEC(nofVarF)
					END
				ELSIF var^.typ^.comp = OPL.Basic THEN
					IF var^.leaf & (nofVarR > 0) THEN
						r := -1; OPL.GetR(OPL.VarReg, r); var^.linkadr := r; DEC(nofVarR)
					END
				END ;
				var := var^.link
			END ;
			IF OPL.dynArrCopied THEN OPL.resCallArea := OPL.pc; OPL.PutI(OPL.ADDI, OPL.SP, OPL.SP, 0) END	(* fixed in OPL.Exit *)
		END
	END Enter;
	
	PROCEDURE Result*(proc: OPT.Object; VAR res: OPL.Item);
		VAR r: OPL.Item;
	BEGIN
		r.mode := OPL.Reg; r.typ := proc.typ;
		IF r.typ^.form IN OPL.realSet THEN r.reg := OPL.RRF; OPL.GetF(OPL.TempReg, r.reg );
		ELSE r.reg := OPL.RRI; OPL.GetR(OPL.TempReg, r.reg);	(* result still in RRI *)
		END ;
		Assign(r, res, r.reg)
	END Result;
		
	PROCEDURE With*(VAR x: OPL.Item);
	BEGIN
		IF x.mode IN {OPL.Reg, OPL.Based} THEN OPL.ReleaseR(x.reg) END
	END With;
	
	PROCEDURE FJ*(VAR loc: OPL.Label);	(* unconditional forward jump *)
	BEGIN
		IF loc = 0 THEN (* end of chain *) loc := OPL.pc END ;
		OPL.PutUJ( OPL.JAL,  0, loc - OPL.pc -1); loc := OPL.pc -1;
	END FJ;

	PROCEDURE SetBNZ(VAR x: OPL.Item);
	BEGIN
		OPL.Load(x, -1);
		x.mode := OPL.Cond; x.reg2 := 0; x.offset := OPL.BNE; x.Tjmp := 0; x.Fjmp := 0
	END SetBNZ;
	
	PROCEDURE FJf*(VAR x: OPL.Item; VAR loc: OPL.Label);	(* conditional forward jump on false *)
	BEGIN
		IF x.mode # OPL.Cond THEN SetBNZ(x) END;
		OPL.Invert(x.offset); OPL.PutCond(x, x.Fjmp, FALSE); OPL.PutU( OPL.NOP, 0, 0);	(* B~cond Fjmp *)
		loc := OPL.pc -2; OPL.FixLink(x.Tjmp)
	END FJf;

	PROCEDURE BJ*(loc: OPL.Label);	(* unconditional backward jump *)
	BEGIN
		IF loc = 0 THEN (* end of chain *) loc := OPL.pc END;
		OPL.PutUJ(OPL.JAL, 0, loc - OPL.pc -1);
	END BJ;

	PROCEDURE BJf*(VAR x: OPL.Item; loc: OPL.Label);	(* conditional backward jump on false *)
	BEGIN
		IF x.mode # OPL.Cond THEN SetBNZ(x) END;
		OPL.Invert(x.offset); OPL.PutCond(x, loc, FALSE);	(* B~cond loc *)
		OPL.FixLinkWith(x.Fjmp, loc); OPL.FixLink(x.Tjmp)
	END BJf;

	PROCEDURE BJt*(VAR x: OPL.Item; loc: OPL.Label);	(* conditional backward jump on true *)
	BEGIN
		IF x.mode # OPL.Cond THEN SetBNZ(x) END;
		OPL.PutCond(x, loc, FALSE);	(* Bcond loc *)
		OPL.FixLinkWith(x.Tjmp, loc); OPL.FixLink(x.Fjmp)
	END BJt;

	PROCEDURE CaseJump*(tab: OPL.Label; from, to: LONGINT);
		VAR i, j: OPL.Label;
	BEGIN
		i := OPL.pc; OPL.pc := SHORT(tab + 1*from); j := tab + 1*to;
		WHILE OPL.pc <= j DO OPL.PutUJ(OPL.JAL, 0, i - OPL.pc -0) END ;
		OPL.pc := SHORT(i)
	END CaseJump;
	
	PROCEDURE Case*(VAR x: OPL.Item; low, high: LONGINT; VAR tab: OPL.Label);
		VAR y: OPL.Item; n, dummy: LONGINT;
	BEGIN n := high - low + 1;
		y.mode := OPL.Con; y.offset := low; OPL.Add(x, y, -1, TRUE);
		dummy := OPL.PutIMM(OPL.SLTIU, OPL.T1, x, n);
		OPL.PutSB(OPL.BEQ,  OPL.T1, 0, 5 + 1*n);	(* else *)
		OPL.PutU( OPL.AUIPC, OPL.T1, 0);
		OPL.PutI( OPL.SLLI, OPL.T0, x.reg, 2);
		OPL.PutR( OPL.ADD, OPL.T0, OPL.T0, OPL.T1); 
		OPL.PutI( OPL.JALR, 0, OPL.T0, 16); 
		tab := OPL.pc; INC(OPL.pc, SHORT(n));
		CaseJump(tab, 0, high - low)
	END Case;

BEGIN
	Zero.mode := OPL.Reg; Zero.reg := 0;
		
	cmpOP[eql] := OPL.BEQ;
	cmpOP[neq] := OPL.BNE;
	cmpOP[lss] := OPL.BLT;
	cmpOP[geq] := OPL.BGE;
	
	cmpfOP[eql] := OPL.BNE;
	cmpfOP[neq] := OPL.BEQ;
	cmpfOP[lss] := OPL.BNE;
	cmpfOP[leq] := OPL.BNE;
	cmpfOP[gtr] := OPL.BEQ;
	cmpfOP[geq] := OPL.BEQ;

	condf[eql] := OPL.FEQ;
	condf[neq] := OPL.FEQ;
	condf[lss] := OPL.FLT;
	condf[leq] := OPL.FLE;
	condf[gtr] := OPL.FLE;
	condf[geq] := OPL.FLT;
	
	swapped[eql] := -1;
	swapped[neq] := -1;
	swapped[lss] := -1;
	swapped[leq] := geq;
	swapped[gtr] := lss;
	swapped[geq] := -1;

END VOPC.
