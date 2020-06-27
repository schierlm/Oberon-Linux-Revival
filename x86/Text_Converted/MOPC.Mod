MODULE MOPC;	(* RC 14.3.90 / 11.2.94 *)	(* object model 29.4.93 *)
(* code generator for MIPS II *)
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

*)

	IMPORT OPM :=ROPM, OPT := ROPT, OPL := MOPL, S := SYSTEM;

	CONST
		(* structure forms *)
		Undef = 0; Byte = 1; Bool = 2; Char = 3; SInt = 4; Int = 5; LInt = 6;
		Real = 7; LReal = 8; Set = 9; String = 10; NilTyp = 11; NoTyp = 12;
		Pointer = 13; ProcTyp = 14; Comp = 15;
		intSet = {SInt..LInt}; realSet = {Real, LReal};

		(* composite structure forms *)
		Basic = 1; Array = 2; DynArr = 3; Record = 4;

		(* item base modes (=object modes) *)
		Var = 1; VarPar = 2; Con = 3; Fld = 4; LProc = 6; XProc = 7; CProc = 9; IProc = 10; TProc = 13;
		(* item modes for MIPS R2000 (must not overlap item basemodes,  > 13) *)
		Based = 14; Cond = 15; Reg = 16; FReg = 17;
		
		(* relations *)
		eql = 9; neq = 10; lss = 11; leq = 12; gtr = 13; geq = 14;

		(*SYSTEM ops*)
		adr = 24; cc = 25; bit = 26; lsh = 27; rot = 28; val = 29;

		(*SYSTEM function number*)
		getfn = 24; putfn = 25; getrfn = 26; putrfn = 27; sysnewfn = 30; movefn = 31;

		(* procedure flags (conval^.setval) *)
		hasBody = 1; isRedef = 2; slNeeded = 3; alreadyCalled (*back-end only *) = 16;

		RangeTrap =  8;		IndexTrap =  15;		TGTrap = 18;		ITGTrap = 19;

		(* instruction format *)
		OP = 4000000H; RS = 200000H; RT = 10000H; RD = 800H; IMM = 10000H; SHAMT = 40H;
		NOP = 0; (* SLL 0, 0, 0 *)
		
		(* register usage *)
		T0= 1; T1= 2; T2=3; SP = 29; FP = 30; RA = 31; VirtualFP = OPM.MaxRegNr+1;
		TempReg = 0; VarReg = 1; FrozenReg = 2; (* register classes *)

		MaxVarR = 8;	(* can be 10 now; was 8; max nbr of reg var (r4..r7 not included) *)
		MaxVarF = 4+OPL.RegSize DIV 64 * 16; (* was 4; max nr of float reg var pair (f12..f14 not included) float registers passed via int regs, makes no sense*)

		(* R2000 opcodes *)
		SPECIAL = 0; BCOND = 1; J = 2; JAL = 3; BEQ = 4; BNE = 5; BLEZ = 6; BGTZ = 7;
		ADDI = 8; ADDIU = 9; SLTI = 10; SLTIU = 11; ANDI = 12; ORI = 13; XORI = 14; LUI = 15;
		LB = -32; LH = -31;  LW = -29; LBU = -28; LHU = -27; 
		SB = -24; SH = -23;  SW = -21; 
		COP0 = 16; LWC0 = -16; SWC0 = -8; COP1 = 17; LWC1 = -15; SWC1 = -7; LDC1=-11; SDC1= -3;
		
		(* SPECIAL *)
		SLL = 0; SRL = 2; SRA = 3; SLLV = 4; SRLV = 6; SRAV = 7;
		JR = 8; JALR = 9;  
		ADDU = 33; SUBU = 35; AND = 36; oR = 37; XOR = 38; NOR = 39;
		SLT = 42; SLTU = 43;
		
		(* BCOND *)
		BLTZ = 0; BGEZ = 1; BGEZAL = 17;
		
		(* COPZ *)
		BCF = 256; BCT = 257; CF = 2; CT = 6;

		MFCx = 0;	MTCx = 4*RS; 

		(* R2010 functions *)
		ADDf = 0; SUBf = 1; MULf = 2; DIVf = 3; ABSf = 5; MOVf = 6; NEGf = 7; FLOORWf=15;
		CVTSf = 32; CVTDf = 33; CVTWf = 36; CEQf = 50; CLTf = 60; CLEf = 62; 

		true = 1;
		
		Tag0Offset = -8;
		Mth0Offset = -72;


	VAR
		inxchk, ranchk, typchk, ptrinit: BOOLEAN;
		Zero: OPL.Item;
		cmpiOP, cmp0OP, cmpOP, cmpfOP, condf: ARRAY 16 OF LONGINT;
		swapped: ARRAY 16 OF SHORTINT;
		
	PROCEDURE Init*(opt: SET);	(* no overflow check *)
		CONST inx = 0; ran = 2; typ = 3; ptr = 5;
	BEGIN
		inxchk := inx IN opt; ranchk := ran IN opt;
		typchk := typ IN opt; ptrinit := ptr IN opt
	END Init;

	PROCEDURE CommonDesign*(VAR x: OPL.Item);
	BEGIN
		IF (x.mode IN {Var, VarPar}) & ((x.offset < 0) OR (x.offset > 63)) THEN OPL.Base(x, -1) END ;
		IF (x.mode = Based) & (x.reg # VirtualFP) & (x.reg # SP) THEN OPL.GetR(FrozenReg, x.reg) END	(* thaw in OPL.EndStat *)
	END CommonDesign;

	PROCEDURE Field*(VAR x: OPL.Item; offset, rt: LONGINT);
	BEGIN
		IF x.mode IN {Var, Based} THEN INC(x.offset, offset)
		ELSE OPL.LoadAddr(x, rt); x.mode := Based; x.offset := offset
		END
	END Field;
	
	PROCEDURE DeRef*(VAR x: OPL.Item; rt: LONGINT);
		VAR c: SHORTINT; btyp: OPT.Struct;
	BEGIN
		IF rt >= 32 THEN rt := -1 END ;
		OPL.Load(x, rt); x.mode := Based;
		btyp := x.typ^.BaseTyp; c := btyp^.comp;
		IF c = DynArr THEN x.offset := btyp^.size + 8 + btyp^.size MOD 8;
			x.descmode := Based; x.reg2 := x.reg; x.Tjmp := 8; OPL.GetR(FrozenReg, x.reg2)	(* thaw in OPL.EndStat *)
		ELSIF c = Array THEN x.offset := 16
		ELSE x.offset := 0
		END
	END DeRef;
	
	PROCEDURE Index*(VAR x, y: OPL.Item; rt: LONGINT);
		VAR len, size, n: OPL.Item; elemsize, nofel, dummy: LONGINT;
	BEGIN
		IF rt >= 32 THEN rt := -1 END ;
		IF x.typ^.comp = Array THEN elemsize := x.typ^.BaseTyp^.size;
			IF y.mode = Con THEN
				Field(x, y.offset*elemsize, rt)
			ELSE
				OPL.Load(y, -1);
				IF inxchk THEN nofel := x.typ^.n;
					IF (nofel >= 0FFFF8000H) & (nofel <= 7FFFH) THEN dummy := OPL.PutIMM(SLTIU, T0, y, nofel)
					ELSE n.mode := Con; n.offset := nofel; dummy := OPL.PutSPC(SLTU, T0, y, n)
					END ;
					OPL.GetR(TempReg, y.reg); (* was released *)
					OPL.PutTEQ( 0, T0, IndexTrap);
				END ;
				n.mode := Con; n.offset := elemsize; OPL.Mul(y, n, -1);
				OPL.LoadAddr(x, -1); x.reg := OPL.PutSPC(ADDU, rt, x, y); x.offset := 0; x.mode := Based
			END
		ELSE (* x.typ^.comp = DynArr *)
			IF (y.mode # Con) OR (y.offset # 0) THEN
				OPL.LenDesc(x, len, x.typ);
				IF inxchk THEN n := y;
					dummy := OPL.PutSPC(SLTU, T0, n, len);
					IF y.mode # Con THEN y := n; OPL.GetR(TempReg, n.reg) (* was released *) END ;
					OPL.PutTEQ( 0, T0, IndexTrap);
				END ;
				OPL.Size(x, size, -1, x.typ^.BaseTyp); OPL.Mul(y, size, -1);
				OPL.LoadAddr(x, -1); x.reg := OPL.PutSPC(ADDU, rt, x, y); x.offset := 0; x.mode := Based
			END
		END;
	END Index;

	PROCEDURE SetCond(VAR x, y: OPL.Item; cond: LONGINT);
	BEGIN
		OPL.Load(x, -1); OPL.Load(y, -1);
		x.mode := Cond; x.reg2 := y.reg; x.offset := cond; x.Tjmp := 0; x.Fjmp := 0
	END SetCond;
	
	PROCEDURE TypTest*(VAR x: OPL.Item; testtyp: OPT.Struct; guard, equal: BOOLEAN);
		VAR xt, tdes: OPL.Item; r: LONGINT;
	BEGIN
		IF typchk OR ~guard THEN r := 0;
			IF x.mode IN {Reg, Based} THEN r := x.reg; OPL.GetR(FrozenReg, r) END ;
			xt := x; xt.typ := OPT.linttyp;
			IF guard & equal THEN
				tdes.mode := Var; tdes.mnolev := -testtyp^.mno; tdes.offset := 64; tdes.obj := testtyp^.strobj;
				IF xt.mode = VarPar THEN
					IF xt.offset < 64 THEN xt.mode := Reg; xt.reg := xt.offset + 1
					ELSE xt.mode := Var; INC(xt.offset, 4)
					END
				ELSE xt.offset := - 4
				END ;
				OPL.LoadAddr(tdes, -1); OPL.Load(tdes, -1); OPL.Load(xt, -1); 
				OPL.PutTNE( tdes.reg, xt.reg, ITGTrap);
			ELSE
				IF testtyp^.comp = Record THEN (* varpar *)
					IF xt.offset < 64 THEN xt.mode := Based; xt.reg := xt.offset + 1
					ELSE INC(xt.offset, 4); OPL.Base(xt, -1)
					END
				ELSE testtyp := testtyp^.BaseTyp;
					OPL.Load(xt, -1); xt.mode := Based; xt.offset := -4;
					OPL.Load(xt, -1); xt.mode := Based
				END ;
				xt.offset := Tag0Offset - 4*testtyp^.extlev;
				tdes.mode := Var; tdes.mnolev := -testtyp^.mno; tdes.offset := 64; tdes.obj := testtyp^.strobj;
				OPL.LoadAddr(tdes, -1); SetCond(tdes, xt, BEQ*OP); 
				IF guard THEN OPL.PutTNE( tdes.reg, xt.reg, ITGTrap);
				ELSE x := tdes
				END
			END ;
			IF r # 0 THEN OPL.ThawR(FrozenReg, r); OPL.GetR(TempReg, r) END
		END
	END TypTest;

	PROCEDURE LoadMTA*(VAR ap: OPL.Item; super, deref: BOOLEAN; VAR proc: OPL.Item);	(* ap unchanged *)
		VAR tag: OPL.Item; typ: OPT.Struct; r: LONGINT;
	BEGIN
		OPM.err(700);	(* LoadMTA supposed not to be needed at all *)
		tag := ap; r := 0;
		IF tag.mode IN {Reg, Based} THEN r := tag.reg; OPL.GetR(FrozenReg, r) END ;
		IF super THEN
			typ := tag.typ^.BaseTyp;
			IF tag.typ^.form = Pointer THEN typ := typ^.BaseTyp END;
			tag.mode := Var; tag.mnolev := - typ^.mno; tag.offset := 64;
			tag.obj := typ^.strobj; OPL.LoadAddr(tag, -1)
		ELSIF tag.typ^.form = Pointer THEN DeRef(tag, -1); tag.offset := -4
		ELSIF deref THEN (* ap = p^ *) tag.offset := -4
		ELSIF tag.mode = VarPar THEN tag.mode := Var;
			IF tag.offset < 64 THEN (* Reg *) INC(tag.offset) ELSE INC(tag.offset, 4) END
		ELSE tag.mode := Var; tag.mnolev := - tag.typ^.mno; tag.offset := 64;
			tag.obj := tag.typ^.strobj; OPL.LoadAddr(tag, -1)
		END ;
		tag.typ := OPT.linttyp; OPL.Load(tag, -1);
		IF r # 0 THEN OPL.ThawR(FrozenReg, r); OPL.GetR(TempReg, r) END ;
		proc.reg := tag.reg; OPL.GetR(FrozenReg, tag.reg)	(* thaw in Call *)
	END LoadMTA;

	PROCEDURE CheckIntRange(VAR x: OPL.Item; g: SHORTINT);	(* x.mode = Reg *)
		VAR at: OPL.Item; add, cmp, dummy: LONGINT;
	BEGIN
		IF ranchk THEN
			at.mode := Reg; at.reg := x.reg; cmp := 256;
			IF g # Char THEN
				IF g = Int THEN add := 1; cmp := 2; at.reg := OPL.PutSPC(16*SHAMT + SRA, T0, Zero, x)
				ELSE (* SInt *) add := 128
				END ;
				at.reg := OPL.PutIMM(ADDIU, T0, at, add)
			END ;
			dummy := OPL.PutIMM(SLTIU, T0, at, cmp);
			OPL.PutTEQ(0, T0, RangeTrap);
			OPL.GetR(TempReg, x.reg) (* reg was released *)
		END
	END CheckIntRange;
	
	PROCEDURE ToReal(VAR x: OPL.Item; rt: LONGINT; f, g: SHORTINT);
		VAR func: LONGINT;
	BEGIN
		OPL.GetF(TempReg, rt);
		OPL.Load(x,  -1 );
		IF ~(f IN realSet) THEN
			OPL.PutFP( 0, MTCx, 0, rt, x.reg);  OPL.ReleaseR(x.reg); (*to be moved to OPL*)
			x.reg:=rt;
		END ;
		IF g = LReal THEN func := CVTDf; x.typ:= OPT.lrltyp ELSE func := CVTSf; x.typ:= OPT.realtyp END ;
		x.reg := OPL.PutFPA(func, f, rt, x, Zero)
	END ToReal;
	
	PROCEDURE RealToInt(VAR x: OPL.Item; rt: LONGINT; f, g: SHORTINT);
		VAR y: OPL.Item;
	BEGIN
		y := x; y.reg := OPL.PutFPA(FLOORWf, f, rt, y, Zero);
		x.mode := Reg; OPL.GetR(TempReg, rt); x.reg := rt;
		OPL.PutFP( 0, MFCx, 0, y.reg, rt );  OPL.ReleaseF(y.reg); (*to be moved to OPL*)
		IF g=LInt THEN x.typ:=OPT.linttyp;
		ELSIF g=Int THEN x.typ:= OPT.inttyp;
		ELSIF g=SInt THEN x.typ:= OPT.sinttyp;
		ELSIF g=Char THEN x.typ:= OPT.chartyp;
		ELSE HALT(35)	(* debug *)
		END;
		CheckIntRange(x, g)
	END RealToInt;
	
	PROCEDURE Convert*(VAR x: OPL.Item; rt: LONGINT; f, g: SHORTINT);
	BEGIN
		IF f IN intSet THEN
			IF g IN intSet THEN OPL.Load(x, rt);
				IF f > g THEN CheckIntRange(x, g) END
			ELSIF g IN realSet THEN ToReal(x, rt, f, g)
			ELSIF g = Char THEN OPL.Load(x, rt); CheckIntRange(x, Char)
			ELSE HALT(35)	(* debug *)
			END
		ELSIF f IN realSet THEN
			IF g IN realSet THEN ToReal(x, rt, f, g)
			ELSIF g IN intSet THEN RealToInt(x, rt, f, g)
			ELSIF g = Char THEN RealToInt(x, rt, f, Char)
			ELSE HALT(36)	(* debug *)
			END
		ELSIF (f = Byte) & (g = Char) THEN (* ok, type is changed in OPV *)
		ELSIF (f = Char) OR (f = Byte) THEN
			IF g IN intSet THEN
				IF g # SInt THEN OPL.Load(x, rt) END
			ELSIF g IN realSet THEN ToReal(x, rt, f, g)
			ELSE HALT(38)	(* debug *)
			END
		ELSE HALT(39)	(* debug *)
		END
	END Convert;

	PROCEDURE Relation*(VAR x: OPL.Item; rt: LONGINT);
	BEGIN IF x.mode = Cond THEN OPL.Load(x, rt) END
	END Relation;

	PROCEDURE Cmp*(VAR x, y: OPL.Item; rel: SHORTINT);
		VAR f: SHORTINT; at, c: LONGINT; done: BOOLEAN; xadr, yadr, z: OPL.Item;
	BEGIN
		f := x.typ^.form;
		IF f IN {Byte..LInt, Set, NilTyp, Pointer, ProcTyp} THEN
			IF (x.mode = Con) OR (x.mode = Reg) & (x.reg = 0) THEN z := x; x := y; y := z; rel := swapped[rel] END ;
			IF (y.mode = Con) OR (y.mode = Reg) & (y.reg = 0) THEN
				IF y.mode = Reg THEN c := 0 ELSE c := y.offset END ;
				done := TRUE;
				IF c = 0 THEN SetCond(x, Zero, cmp0OP[rel])
				ELSIF (rel IN {lss, geq}) & (c <= 7FFFH) & (c >= 0FFFF8000H) THEN
					x.reg := OPL.PutIMM(SLTI, -1, x, c); SetCond(x, Zero, cmpiOP[rel])
				ELSIF (rel IN {leq, gtr}) & (c <= 7FFEH) & (c >= 0FFFF7FFFH) THEN
					x.reg := OPL.PutIMM(SLTI, -1, x, c + 1); SetCond(x, Zero, cmpiOP[rel])
				ELSE done := FALSE
				END
			ELSE done := FALSE
			END ;
			IF ~done THEN
				IF rel IN {eql, neq} THEN (*SetCond(x, y, cmpOP[rel]);*)
					IF TRUE THEN SetCond(x, y, cmpOP[rel]);
					ELSE
						x.reg := OPL.PutSPC(XOR, -1, x, y);
						x.reg := OPL.PutSPC(SLTU, -1, Zero, x);			
						IF rel=eql THEN x.reg := OPL.PutIMM(XORI, -1, x, 1) END;
						x.mode := Reg; x.typ:= OPT.booltyp;
					END;
				ELSE
					IF rel IN {leq, gtr} THEN x.reg := OPL.PutSPC(SLT, -1, y, x); rel := swapped[rel]
					ELSE x.reg := OPL.PutSPC(SLT, -1, x, y)
					END ;
					SetCond(x, Zero, cmpOP[rel])
				END
			END
		ELSIF f IN realSet THEN
			at := OPL.PutFPA(condf[rel], f, -1, x, y); 
			x := Zero; SetCond(x, Zero, cmpfOP[rel])
		ELSE (* strings *)
			xadr.mode := Reg; xadr.reg := T1; yadr.mode := Reg; yadr.reg := T2;
			at := -1; OPL.GetR(FrozenReg, at);
			OPL.LoadAddr(x, T1); OPL.Move(xadr, x, LInt); 
			OPL.LoadAddr(y, T2); OPL.Move(yadr, y, LInt); 
			(* loop: *) OPL.Put(LBU*OP + T1*RS + T0*RT);
			OPL.Put(LBU*OP + T2*RS + at*RT);
			OPL.Put(BEQ*OP + T0*RS + 3);	(* end *)
			OPL.Put(ADDIU*OP + T1*(RS + RT) + 1);
			OPL.Put(BEQ*OP + T0*RS + at*RT + (-5) MOD IMM);	(* loop *)
			OPL.Put(ADDIU*OP + T2*(RS + RT) + 1);
			(* end: *) OPL.ThawR(FrozenReg, at);
			x.mode := Reg; y.mode := Reg;
			IF rel IN {eql, neq} THEN x.reg := T0; y.reg := at;  OPL.GetR(TempReg, at); SetCond(x, y, cmpOP[rel])
			ELSE
				IF rel IN {leq, gtr} THEN x.reg := at; y.reg := T0; rel := swapped[rel]
				ELSE x.reg := T0; y.reg := at
				END ;
				x.reg := OPL.PutSPC(SLT, -1, x, y); SetCond(x, Zero, cmpOP[rel])
			END;
		END
	END Cmp;

	PROCEDURE CheckSetRange(VAR x: OPL.Item);
		VAR dummy: LONGINT;
	BEGIN
		IF ranchk & (x.mode # Con) THEN
			dummy := OPL.PutIMM(SLTIU, T0, x, 32); 	OPL.GetR(TempReg, x.reg); (* reg was released *)
			OPL.PutTEQ(0, T0, 8);
		END
	END CheckSetRange;
	
	PROCEDURE In*(VAR x, y: OPL.Item);
		VAR r: LONGINT;
	BEGIN
		IF x.mode = Con THEN
			IF x.offset = OPL.RegSize-1 THEN OPL.Load(y, -1); r := y.reg
			ELSE r := OPL.PutSPC(SLL + (OPL.RegSize-1 - x.offset)*SHAMT, -1, Zero, y)	
			END
		ELSE CheckSetRange(x);
			x.reg := OPL.PutIMM(XORI, -1, x, OPL.RegSize-1);
			r := OPL.PutSPC(SLLV, -1, x, y)	(* reversed operands in MIPS *)
		END ;
		x.mode := Reg; x.reg := r;
		SetCond(x, Zero, BCOND*OP + BLTZ*RT)
	END In;
	
	PROCEDURE SetElem*(VAR x: OPL.Item; rt: LONGINT);
		VAR y: OPL.Item;
	BEGIN CheckSetRange(x);
		y.mode := Con; y.offset := 1;
		x.reg := OPL.PutSPC(SLLV, rt, x, y)
	END SetElem;
	
	PROCEDURE SetRange*(VAR x, y, z: OPL.Item; rt: LONGINT);	(* x := {y..z} *)
	BEGIN
		IF y.mode = Con THEN	(* z not constant *)
			CheckSetRange(z);
			y.offset := ASH(1, y.offset) - 1;	(* ...00111...  y ones*)
			x.mode := Con; x.offset := -2;
			x.reg := OPL.PutSPC(SLLV, -1, z, x);
			x.reg := OPL.PutSPC(NOR, rt, x, y)
		ELSE CheckSetRange(y);
			x.mode := Con; x.offset := -1;
			IF (z.mode = Con) & (z.offset = 31) THEN x.reg := OPL.PutSPC(SLLV, rt, y, x)
			ELSE x.reg := OPL.PutSPC(SLLV, -1, y, x);
				IF z.mode = Con THEN z.offset := ASH(2, z.offset) - 1	(* ...00111...  z+1 ones*)
				ELSE CheckSetRange(z);
					y.mode := Con; y.offset := -2;
					z.reg := OPL.PutSPC(SLLV, -1, z, y);
					z.reg := OPL.PutSPC(NOR, -1, z, Zero)
				END ;
				x.reg := OPL.PutSPC(AND, rt, x, z)
			END
		END
	END SetRange;
	
	PROCEDURE Not*(VAR x: OPL.Item);
		VAR a: LONGINT;
	BEGIN
		IF x.mode = Cond THEN OPL.Invert(x.offset); a := x.Tjmp; x.Tjmp := x.Fjmp; x.Fjmp := a
		ELSE SetCond(x, Zero, BEQ*OP)
		END
	END Not;
	
	PROCEDURE Neg*(VAR x: OPL.Item; rt: LONGINT);
		VAR f: SHORTINT;
	BEGIN f := x.typ^.form;
		IF f = Set THEN
			x.reg := OPL.PutSPC(NOR, rt, x, Zero)
		ELSIF f IN intSet THEN
			x.reg := OPL.PutSPC(SUBU, rt, Zero, x)
		ELSE	(* f IN realSet *)
			x.reg := OPL.PutFPA(NEGf, f, rt, x, Zero)
		END
	END Neg;
	
	PROCEDURE AbsVal*(VAR x: OPL.Item; rt: LONGINT);
		VAR f: SHORTINT; dummy: LONGINT;
	BEGIN f := x.typ^.form;
		IF f IN intSet THEN
			OPL.Load(x, rt);
			OPL.PutI( BCOND, BGEZ, x.reg, 2);
			IF x.reg=rt THEN OPL.Put( NOP) ELSE x.reg := OPL.PutSPC(oR, rt, x, Zero) END;
			x.reg := OPL.PutSPC(SUBU, rt, Zero, x);
		ELSE	(* f IN realSet *)
			x.reg := OPL.PutFPA(ABSf, f, rt, x, Zero)
		END
	END AbsVal;
	
	PROCEDURE Cap*(VAR x: OPL.Item; rt: LONGINT);
	BEGIN x.reg := OPL.PutIMM( ANDI, rt, x, 5FH)
	END Cap;
	
	PROCEDURE Odd*(VAR x: OPL.Item; rt: LONGINT);
	BEGIN x.reg := OPL.PutIMM( ANDI, rt, x, 1)
	END Odd;
	
	PROCEDURE Add*(VAR x, y: OPL.Item; rt: LONGINT; floating: BOOLEAN);
	BEGIN
		IF floating THEN x.reg := OPL.PutFPA(ADDf, y.typ^.form, rt, x, y)
		ELSE OPL.Add( x, y, rt, FALSE)
		END
	END Add;

	PROCEDURE Sub*(VAR x, y: OPL.Item; rt: LONGINT; floating: BOOLEAN);
	BEGIN
		IF floating THEN x.reg := OPL.PutFPA(SUBf, y.typ^.form, rt, x, y)
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
		IF floating THEN x.reg := OPL.PutFPA(MULf, y.typ^.form, rt, x, y)
		ELSE OPL.Mul(x, y, rt)
		END
	END Mul;
	
	PROCEDURE Div*(VAR x, y: OPL.Item; rt: LONGINT; floating: BOOLEAN);
	BEGIN
		IF floating THEN x.reg := OPL.PutFPA(DIVf, y.typ^.form, rt, x, y)
		ELSE OPL.Div(x, y, rt, FALSE)
		END
	END Div;

	PROCEDURE Mod*(VAR x, y: OPL.Item; rt: LONGINT);
	BEGIN OPL.Div(x, y, rt, TRUE)
	END Mod;

	PROCEDURE SetOp(VAR x, y: OPL.Item; rt, op, opi: LONGINT);
		VAR z: OPL.Item; c: LONGINT;
	BEGIN
		IF x.mode = Con THEN z := x; x := y; y := z END ;
		c := y.offset;
		IF (y.mode = Con) & (c >= 0) & (c <= 0FFFFH) THEN x.reg := OPL.PutIMM(opi, rt, x, c)
		ELSE x.reg := OPL.PutSPC(op, rt, x, y)
		END
	END SetOp;
	
	PROCEDURE SetUnion*(VAR x, y: OPL.Item; rt: LONGINT);
	BEGIN SetOp(x, y, rt, oR, ORI)
	END SetUnion;

	PROCEDURE SetDiff*(VAR x, y: OPL.Item; rt: LONGINT);
	BEGIN
		IF y.mode = Con THEN
			IF y.offset = MIN(LONGINT) THEN y.offset := MAX(LONGINT)
			ELSE y.offset := -y.offset - 1
			END
		ELSE Neg(y, -1)
		END ;
		SetOp(x, y, rt, AND, ANDI)
	END SetDiff;

	PROCEDURE SetInter*(VAR x, y: OPL.Item; rt: LONGINT);
	BEGIN SetOp(x, y, rt, AND, ANDI)
	END SetInter;
	
	PROCEDURE SetSymmDiff*(VAR x, y: OPL.Item; rt: LONGINT);
	BEGIN SetOp(x, y, rt, XOR, XORI)
	END SetSymmDiff;
	
	PROCEDURE Include*(VAR x, y: OPL.Item; rt: LONGINT; exclude: BOOLEAN);
		VAR op, opi: LONGINT; z: OPL.Item;
	BEGIN CommonDesign(x); z := x;
		IF y.mode = Con THEN
			IF exclude THEN op := AND; opi := ANDI;
				IF y.offset = 31 THEN y.offset := MAX(LONGINT)
				ELSE y.offset := -1 - ASH(1, y.offset)
				END
			ELSE op := oR; opi := ORI; y.offset := ASH(1, y.offset)
			END
		ELSE SetElem(y, -1);
			IF exclude THEN op := AND; y.reg := OPL.PutSPC(NOR, -1, y, Zero) ELSE op := oR END
		END ;
		SetOp(z, y, rt, op, opi); OPL.Move(x, z, x.typ^.form)
	END Include;

	PROCEDURE And*(VAR x, y: OPL.Item);
	BEGIN
		IF y.mode # Cond THEN
			x.reg2 := 0; x.Tjmp := 0; (* x.Fjmp remains unchanged *)
			IF y.mode = Con THEN x.reg := 0;
				IF y.offset = true THEN x.offset := BEQ*OP (* always *) ELSE x.offset := BNE*OP (* never *) END
			ELSE OPL.Load(y, -1); x.reg := y.reg; x.offset := BNE*OP
			END
		ELSE
			IF y.Fjmp # 0 THEN x.Fjmp := OPL.MergedLinks(x.Fjmp, y.Fjmp) END ;
			x.offset := y.offset; x.reg := y.reg; x.reg2 := y.reg2; x.Tjmp := y.Tjmp
		END
	END And;

	PROCEDURE Or*(VAR x, y: OPL.Item);
	BEGIN
		IF y.mode # Cond THEN
			x.reg2 := 0; x.Fjmp := 0; (* x.Tjmp remains unchanged *)
			IF y.mode = Con THEN x.reg := 0;
				IF y.offset = true THEN x.offset := BEQ*OP (* always *) ELSE x.offset := BNE*OP (* never *) END
			ELSE OPL.Load(y, -1); x.reg := y.reg; x.offset := BNE*OP
			END
		ELSE
			IF y.Tjmp # 0 THEN x.Tjmp := OPL.MergedLinks(x.Tjmp, y.Tjmp) END ;
			x.offset := y.offset; x.reg := y.reg; x.reg2 := y.reg2; x.Fjmp := y.Fjmp
		END
	END Or;

	PROCEDURE CondAnd*(VAR x: OPL.Item);
	BEGIN
		IF x.mode = Cond THEN OPL.Invert(x.offset)
		ELSE (* form = Bool, mode # con *) SetCond(x, Zero, BEQ*OP)
		END ;
		OPL.PutCond(x, x.Fjmp, FALSE); x.Fjmp := OPL.pc - 2; OPL.FixLink(x.Tjmp)
	END CondAnd;
	
	PROCEDURE CondOr*(VAR x: OPL.Item);
	BEGIN
		IF x.mode # Cond THEN (* form = Bool, mode # con *) SetCond(x, Zero, BNE*OP) END ;
		OPL.PutCond(x, x.Tjmp, FALSE); x.Tjmp := OPL.pc - 2; OPL.FixLink(x.Fjmp)
	END CondOr;
	
	PROCEDURE Shift(VAR x, y: OPL.Item; rt, sr, srv: LONGINT);
		VAR c: LONGINT; at: OPL.Item;
	BEGIN
		IF y.mode = Con THEN c := y.offset;
			IF c > 0 THEN x.reg := OPL.PutSPC(SLL + (c MOD 32)*SHAMT, rt, Zero, x)
			ELSIF c < 0 THEN x.reg := OPL.PutSPC(sr + ((-c) MOD 32)*SHAMT, rt, Zero, x)
			END
		ELSE OPL.Load(y, -1); OPL.Load(x, -1);
			at.mode := Cond; at.reg := y.reg; at.reg2 := 0; at.offset := BCOND*OP + BLTZ*IMM;
			OPL.PutCond(at, 3, TRUE); DEC(OPL.pc); (* remove NOP *)
			OPL.Put(SPECIAL*OP + SUBU + y.reg*RT + T0*RD);
			OPL.Put(BEQ*OP + 2);
			rt := OPL.PutSPC(SLLV, rt, y, x);
			at.mode := Reg; at.reg := T0; x.reg := OPL.PutSPC(srv, rt, at, x);
		END
	END Shift;

	PROCEDURE Ash*(VAR x, y: OPL.Item; rt: LONGINT);
	BEGIN Shift(x, y, rt, SRA, SRAV)
	END Ash;

	PROCEDURE Mem*(VAR x: OPL.Item; offset: LONGINT);	(* x := Mem[x+offset] *)
	BEGIN
		IF x.mode = Con THEN x.mode := Based; x.reg := 0; INC(x.offset, offset)
		ELSE OPL.Load(x, -1); x.mode := Based; x.offset := offset
		END
	END Mem;
	
	PROCEDURE SYSval*(VAR x: OPL.Item; rt: LONGINT; f, g: SHORTINT);	(* implementation of SYSTEM.VAL *)
		VAR r: LONGINT;
	BEGIN
		r := -1;
		IF x.mode = Reg THEN r := x.reg
		ELSIF (x.mode = Var) & (x.offset >= 0) & (x.offset < 64) THEN r := x.offset
		END;
		IF (r # -1) & ((f IN realSet) # (g IN realSet)) THEN
			IF g IN realSet THEN OPL.GetF(TempReg, rt); OPL.PutFP( 0, MTCx, 0, rt, r); OPL.ReleaseR(r);
			ELSE  OPL.GetR(TempReg, rt); OPL.PutFP(0, MFCx, 0, r, rt); OPL.ReleaseF(r);
			END ;
			x.mode := Reg; x.reg := rt;
		END
	END SYSval;
	
	PROCEDURE SYSdop*(VAR x, y: OPL.Item; subcl: SHORTINT; rt: LONGINT);	(* implementation of SYSTEM.BIT, LSH, ROT *)
		VAR size, c, bits, mask, shift: LONGINT; r, s: OPL.Item;
	BEGIN
		CASE subcl OF
		   bit: Mem(x, 0); x.typ := OPT.settyp; In(y, x); x := y
		| lsh: Shift(x, y, rt, SRL, SRLV)
		| rot:
			size := x.typ^.size; r.mode := Reg; s.mode := Reg;
			IF size = 1 THEN bits := 8; mask := 7; shift := 24
			ELSIF size = 2 THEN bits := 16; mask := 15; shift := 16
			ELSE bits := 32; mask := 31; shift := 0
			END ;
(* VOPC:			bits:=size*8; mask:=bits-1; shift:=OPL.RegSize-bits;*)

			IF y.mode = Con THEN c := y.offset MOD bits;
				IF c # 0 THEN
					r.reg := OPL.PutSPC(SLL + (c + shift)*SHAMT, T0, Zero, x);
					IF shift # 0 THEN s.reg := OPL.PutSPC(SLL + shift*SHAMT, T1, Zero, x) ELSE s.reg := x.reg END ;
					s.reg := OPL.PutSPC(SRL + (bits - c)*SHAMT, T1, Zero, s);
					x.reg := OPL.PutSPC(oR, rt, r, s);
					IF shift # 0 THEN x.reg := OPL.PutSPC(SRL + shift*SHAMT, rt, Zero, x) END
				END
			ELSE OPL.Load(y, -1);
				IF shift # 0 THEN
					r.reg := OPL.PutSPC(SLL + shift*SHAMT, T0, Zero, x);
					y.reg := OPL.PutIMM(ANDI, T1, y, mask)
				ELSE OPL.Load(x, T0); r.reg := x.reg
				END ;
				s.reg := OPL.PutSPC(SLLV, T2, y, r);
				y.reg := OPL.PutSPC(SUBU, T1, Zero, y);
				IF mask # 31 THEN y.reg := OPL.PutIMM(ANDI, T1, y, mask) END ;
				r.reg := OPL.PutSPC(SRLV, rt, y, r);
				x.reg := OPL.PutSPC(oR, rt, r, s);
				IF shift # 0 THEN x.reg := OPL.PutSPC(SRL + shift*SHAMT, rt, Zero, x) END
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
				IF y.offset < 64 THEN f := x.typ^.form ELSE f := NoTyp END ;
				y.mode := Reg; y.reg := y.offset; OPL.Move(x, y, f)
		| putrfn:
				IF x.offset < 64 THEN f := y.typ^.form ELSE f := NoTyp END ;
				x.mode := Reg; x.reg := x.offset; OPL.Move(x, y, f)
		END
	END SYSgetput;

	PROCEDURE Msk*(VAR x, y: OPL.Item; rt: LONGINT);	(* y.mode = Con *)
		VAR c: LONGINT; i: LONGINT;
	BEGIN c := y.offset;
		IF c = MIN(LONGINT) THEN c := MAX(LONGINT)
		ELSE c := -c - 1
		END ;
		IF (c >= 0) & (c <= 0FFFFH) THEN x.reg := OPL.PutIMM(ANDI, rt, x, c)
		ELSE i := OPL.RegSize;
			WHILE ODD(c) DO c := c DIV 2; DEC(i) END ;
			x.reg := OPL.PutSPC(SLL + i*SHAMT, rt, Zero, x);
			x.reg := OPL.PutSPC(SRL + i*SHAMT, rt, Zero, x);
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
		IF x.typ^.comp = DynArr THEN OPL.Size(x, len, -1, x.typ);
			len.reg := OPL.PutIMM(ADDIU, -1, len, -1)
		ELSE len.mode := Con; len.offset := x.typ^.n - 1
		END;
		xadr.mode := Reg; xadr.reg := T1; yadr.mode := Reg; yadr.reg := T2;
		OPL.LoadAddr(x, T1); OPL.Move(xadr, x, LInt);
		OPL.LoadAddr(y, T2); OPL.Move(yadr, y, LInt);
		OPL.Add(xadr, len, -1, FALSE); until := xadr.reg;
(*
		(* loop: *) OPL.Put(SPECIAL*OP + SLTU + T1*RS + until*RT + T0*RD);
		OPL.Put(BEQ*OP + T0*RS + 4);	(* end *)
		OPL.Put(ADDIU*OP + T1*(RS + RT) + 1);
		OPL.Put(LB*OP + T2*RS + T0*RT);
		OPL.Put(ADDIU*OP + T2*(RS + RT) + 1);
		OPL.Put(BNE*OP + T0*RS + (-6) MOD IMM);	(* loop *)
		(* end *) OPL.Put(SB*OP + T1*RS + T0*RT + (-1) MOD IMM);
*)
		(* loop: *) OPL.PutI( LB, T0, T2, 0);
		OPL.PutI( ADDIU, T1, T1, 1);
		OPL.PutI( ADDIU, T2, T2, 1);
		OPL.PutI( BNE, until, T1, -4);	(* loop *)
		OPL.PutI( SB, T0, T1, -1);

	END Copy;
	
	PROCEDURE Base(typ: OPT.Struct): SHORTINT;
	BEGIN
		WHILE typ^.comp IN {Array, DynArr} DO typ := typ^.BaseTyp END ;
		IF typ^.comp = Record THEN RETURN SHORT(SHORT(typ^.align))
		ELSE RETURN SHORT(SHORT(typ^.size))
		END
	END Base;

	PROCEDURE MoveRefBlock(VAR x, y: OPL.Item; s, bx, by: LONGINT);	(* x^ := y^, len = s *)
		VAR until, at, last, seclast, t, offset, rx, ry: LONGINT; xadr, yadr, len: OPL.Item;
	BEGIN
		IF s > 0 THEN
			xadr.mode := Reg; xadr.reg := T1; yadr.mode := Reg; yadr.reg := T2;
			offset := 0; at := -1; OPL.GetR(FrozenReg, at);
			IF (bx < 4) OR (by < 4) OR (s < 4) THEN
				IF s >= 16 THEN
					OPL.Move(xadr, x, LInt); rx := T1;
					OPL.Move(yadr, y, LInt); ry := T2;
					len.mode := Con; len.offset := 8*(s DIV 8); 
					OPL.Add(len, y, -1, FALSE); until := len.reg;
					OPL.Put(LW*OP + T2*RS + T0*RT );
					OPL.Put(ADDIU*OP + T2*(RS + RT) + 8);
					OPL.Put(SW*OP + T1*RS + T0*RT );
					OPL.Put(LW*OP + T2*RS + T0*RT + (- 4) MOD IMM);
					OPL.Put(ADDIU*OP + T1*(RS + RT) + 8);
					OPL.Put(BNE*OP + T2*RS + until*RT + (-6) MOD IMM);
					OPL.Put(SW*OP + T1*RS + T0*RT + (- 4) MOD IMM);
					s := s MOD 8; OPL.ReleaseR(until);
				ELSE rx := x.reg; ry := y.reg
				END ;
				IF s >= 8 THEN
					OPL.Put(LW*OP + ry*RS + T0*RT + offset );
					OPL.Put(LW*OP + ry*RS + at*RT + offset +  4);
					OPL.Put(SW*OP + rx*RS + T0*RT + offset );
					OPL.Put(SW*OP + rx*RS + at*RT + offset + 4);
					INC(offset, 8); DEC(s, 8)
				END ;
				last := at; seclast := T0;	(* to allow peephole optimization *)
				IF s >= 4 THEN
					OPL.Put(LW*OP + ry*RS + T0*RT + offset );
					OPL.Put(SW*OP + rx*RS + T0*RT + offset );
					INC(offset, 4); DEC(s, 4); last := T0; seclast := at	(* to allow peephole optimization *)
				END ;
				WHILE s > 0 DO
					OPL.Put(LB*OP + ry*RS + seclast*RT + offset);
					OPL.Put(SB*OP + rx*RS + seclast*RT + offset);
					INC(offset); DEC(s); t := seclast; seclast := last; last := t	(* to allow peephole optimization *)
				END
			ELSE (* s MOD 4 = 0 *)
				IF s >= 24 THEN
					OPL.Move(xadr, x, LInt); rx := T1;
					OPL.Move(yadr, y, LInt); ry := T2;
					len.mode := Con; len.offset := 12*(s DIV 12); 
					OPL.Add(len, y, -1, FALSE); until := len.reg;
					OPL.Put(LW*OP + T2*RS + T0*RT);
					OPL.Put(ADDIU*OP + T2*(RS + RT) + 12);
					OPL.Put(SW*OP + T1*RS + T0*RT);
					OPL.Put(LW*OP + T2*RS + T0*RT + (-8) MOD IMM);
					OPL.Put(ADDIU*OP + T1*(RS + RT) + 12);
					OPL.Put(SW*OP + T1*RS + T0*RT + (-8) MOD IMM);
					OPL.Put(LW*OP + T2*RS + T0*RT + (-4) MOD IMM);
					OPL.Put(BNE*OP + T2*RS + until*RT + (-8) MOD IMM);
					OPL.Put(SW*OP + T1*RS + T0*RT + (-4) MOD IMM);
					s := s MOD 12; OPL.ReleaseR(until);
				ELSE rx := x.reg; ry := y.reg
				END ;
				WHILE s >= 8 DO
					OPL.Put(LW*OP + ry*RS + T0*RT + offset);
					OPL.Put(LW*OP + ry*RS + at*RT + offset + 4);
					OPL.Put(SW*OP + rx*RS + T0*RT + offset);
					OPL.Put(SW*OP + rx*RS + at*RT + offset + 4);
					INC(offset, 8); DEC(s, 8)
				END ;
				IF s = 4 THEN
					OPL.Put(LW*OP + ry*RS + T0*RT + offset MOD IMM);
					OPL.Put(SW*OP + rx*RS + T0*RT + offset MOD IMM);
				END
			END ;
			OPL.ThawR( FrozenReg, at);
		END
	END MoveRefBlock;

	PROCEDURE MoveBlock(VAR x, y: OPL.Item; s: LONGINT);	(* x := y, len = s *)
		VAR bx, by: LONGINT;
	BEGIN
		IF s > 0 THEN
			bx := Base(x.typ); OPL.LoadAddr(x, T1);
			by := Base(y.typ); OPL.LoadAddr(y, T2);
			MoveRefBlock(x, y, s, bx, by);
		END
	END MoveBlock;

	PROCEDURE DynArrBnd(VAR fp, ap: OPL.Item; ftyp, atyp: OPT.Struct);
		VAR size, len: OPL.Item; rt: LONGINT;
	BEGIN (* ftyp^.comp = DynArr *)
		IF ftyp^.BaseTyp = OPT.bytetyp THEN
			OPL.LenDesc(fp, len, ftyp);
			IF len.mode = Reg THEN rt := len.reg ELSE rt := -1 END ;
			OPL.Size(ap, size, rt, atyp)
		ELSE	(* atyp^.comp = Array, DynArr *)
			IF ftyp^.BaseTyp^.comp = DynArr THEN DynArrBnd(fp, ap, ftyp^.BaseTyp, atyp^.BaseTyp) END ;
			IF atyp^.comp = Array THEN size.mode := Con; size.offset := atyp^.n
			ELSE OPL.LenDesc(ap, size, atyp)
			END ;
			OPL.LenDesc(fp, len, ftyp)	(* called after recursive call: reg allocation *)
		END ;
		OPL.Move(len, size, LInt)
	END DynArrBnd;

	PROCEDURE Assign*(VAR x, y: OPL.Item; rt: LONGINT);	(* x := y *)
		VAR f, g: SHORTINT; len, strlen: OPL.Item; s: LONGINT;
	BEGIN
		f := x.typ^.form; g := y.typ^.form;
		CASE f OF
		  Byte..LInt, Set, Pointer, ProcTyp:
				OPL.Move(x, y, f)
		| Real, LReal:
				IF g # f THEN ToReal(y, rt, g, f) END ;
				OPL.Move(x, y, f)
		| Comp:
				IF x.typ^.comp = Array THEN
					s := x.typ^.size;
					IF x.typ = y.typ THEN MoveBlock(x, y, s)
					ELSE (* String *) MoveBlock(x, y, y.Tjmp)
					END
				ELSIF x.typ^.comp = DynArr THEN	(* x is an argument *)
					IF (g = String) & (x.typ^.BaseTyp^.form = Char) THEN
						strlen.mode := Con; strlen.offset := y.Tjmp;
						OPL.LenDesc(x, len, x.typ); OPL.Move(len, strlen, LInt)
					ELSE DynArrBnd(x, y, x.typ, y.typ)
					END ;
					OPL.LoadAddr(y, rt); OPL.Move(x, y, LInt)
				ELSE (* x.typ^.comp = Record *)
					MoveBlock(x, y, x.typ^.size)
				END
		END
	END Assign;

	PROCEDURE MulDim*(len: OPL.Item; VAR nofel: OPL.Item; dimtyp, dim0typ: OPT.Struct);	(* nofel := nofel * len *)
		VAR dummy: LONGINT;
	BEGIN
		IF len.mode IN {Reg, Based} THEN OPL.GetR(FrozenReg, len.reg) END ;	(* thaw in SetDim *)
		IF ranchk & (len.mode # Con) THEN
			dummy := OPL.PutIMM(SLTI, T0, len, 1); OPL.GetR(TempReg, len.reg); (* reg was released *)
			OPL.PutTNE(0, T0, RangeTrap);
		END ;
		IF dimtyp = dim0typ THEN (*outer dimension*) nofel := len
		ELSE  OPL.Mul(nofel, len, -1); 	(* migth be buggy ToDo: test *)
		END
	END MulDim;
	
	PROCEDURE SetDim*(p: OPL.Item; VAR len: OPL.Item; dimtyp: OPT.Struct);	(* set LEN(p^, dimtyp^.n) to len *)
		(* len may be modified (loaded), p is the returned value from NewArr (pointer) *) 
		VAR lendesc: OPL.Item; r: LONGINT;
	BEGIN (* p.mode = Reg *)
		DeRef(p, -1); OPL.LenDesc(p, lendesc, dimtyp);
		IF len.mode IN {Reg, Based} THEN r := len.reg; OPL.ThawR(FrozenReg, r); OPL.GetR(TempReg, r) END ;
		OPL.Move(lendesc, len, LInt)
	END SetDim;

	PROCEDURE SYSnew*(VAR x: OPL.Item);	(* call to Kernel.NewSys(size: LONGINT): ADDRESS *)
		VAR arg: OPL.Item;
	BEGIN
		IF MaxVarR <4 THEN		(* only valid without static link ??*)
			arg.mode := Reg; arg.reg := -1; OPL.GetR(TempReg, arg.reg);  OPL.Move(arg, x, LInt); OPL.Put(SW*OP + SP*RS + arg.reg*RT +0);
		ELSE
			arg.mode := Reg; arg.reg := OPL.ARI; OPL.GetR(TempReg, arg.reg); OPL.Move(arg, x, LInt);
		END;
		OPL.Put(JAL*OP + OPL.Link(OPL.KNewSys)); OPL.Put(NOP)
	END SYSnew;

	PROCEDURE New*(VAR x, nofel: OPL.Item);	(* x.typ^.BaseTyp^.comp IN {Record, Array, DynArr}, nofel set if DynArr *)
		VAR arg, tag: OPL.Item; nofdim, nofelem: LONGINT; typ, eltyp: OPT.Struct;
	BEGIN
		typ := x.typ^.BaseTyp; arg.typ := OPT.linttyp; tag.typ := OPT.linttyp;
		IF typ^.comp = Record THEN	(* call to Kernel.NewRec(tag: Tag): ADDRESS *)
			IF MaxVarR <4 THEN		(* only valid without static link ??*)
				arg.mode := Reg; arg.reg := -1; OPL.GetR(TempReg, arg.reg);
				tag.mode := Var; tag.mnolev := -typ^.mno; tag.offset := 64; tag.obj := typ^.strobj;
				OPL.LoadAddr(tag, arg.reg); OPL.Move(arg, tag, LInt); OPL.Put(SW*OP + SP*RS + arg.reg*RT +0);
			ELSE
				arg.mode := Reg; arg.reg := 4; OPL.GetR(TempReg, arg.reg);
				tag.mode := Var; tag.mnolev := -typ^.mno; tag.offset := 64; tag.obj := typ^.strobj;
				OPL.LoadAddr(tag, arg.reg); OPL.Move(arg, tag, LInt);
			END;
			OPL.Put(JAL*OP + OPL.Link(OPL.KNewRec)); OPL.Put(NOP)
		ELSE eltyp := typ^.BaseTyp;
			IF typ^.comp = Array THEN
				nofdim := 0; nofel.mode := Con; nofel.offset := typ^.n; nofel.typ := OPT.linttyp
			ELSE (* DynArr *)
				nofdim := typ^.n+1;
				WHILE eltyp^.comp = DynArr DO eltyp := eltyp^.BaseTyp END
			END ;
			nofelem := 1;
			WHILE eltyp^.comp = Array DO nofelem := nofelem*eltyp^.n; eltyp := eltyp^.BaseTyp END ;
			arg.mode := Con; arg.offset := nofelem; OPL.Mul(nofel, arg, 5);
			IF eltyp^.comp = Record THEN
				tag.mode := Var; tag.mnolev := -eltyp^.mno; tag.offset := 64; tag.obj := eltyp^.strobj;
				OPL.LoadAddr(tag, 4)
			ELSIF eltyp^.form = Pointer THEN
				tag.mode := Con; tag.offset := 0	(* special TDesc in Kernel for ARRAY OF POINTER *)
			ELSE	(* eltyp contains no pointer *)
				arg.mode := Con; arg.offset := eltyp^.size; OPL.Mul(nofel, arg, 4);
				arg.offset := 8*(nofdim DIV 2) + 4 + 12; OPL.Add(nofel, arg, 4, FALSE);
				SYSnew(nofel); RETURN
			END;
			IF MaxVarR <4 THEN	(* only valid without static link ?? *)
				OPL.Put(ADDI*OP + SP*RS + SP*RT +  (-16) MOD IMM );	
				arg.mode := Reg; arg.reg := -1; OPL.GetR(TempReg, arg.reg); OPL.Move(arg, tag, LInt); OPL.Put(SW*OP + SP*RS + arg.reg*RT +0);
				arg.mode := Reg; arg.reg := -1; OPL.GetR(TempReg, arg.reg); OPL.Move(arg, nofel, LInt); OPL.Put(SW*OP + SP*RS + arg.reg*RT +4);
				nofel.mode := Con; nofel.offset := nofdim; nofel.typ := OPT.linttyp;
				arg.mode := Reg; arg.reg := -1; OPL.GetR(TempReg, arg.reg); OPL.Move(arg, nofel, LInt); 
				OPL.Put(JAL*OP + OPL.Link(OPL.KNewArr)); OPL.Put(SW*OP + SP*RS + arg.reg*RT +8); OPL.Put(ADDI*OP + SP*RS + SP*RT + 16 );
			ELSE
				arg.mode := Reg; arg.reg := 4; OPL.GetR(TempReg, arg.reg); OPL.Move(arg, tag, LInt);
				arg.mode := Reg; arg.reg := 5; OPL.GetR(TempReg, arg.reg); OPL.Move(arg, nofel, LInt);
				nofel.mode := Con; nofel.offset := nofdim; nofel.typ := OPT.linttyp;
				arg.mode := Reg; arg.reg := 6; OPL.GetR(TempReg, arg.reg); OPL.Move(arg, nofel, LInt);
				OPL.Put(JAL*OP + OPL.Link(OPL.KNewArr)); OPL.Put(NOP)
			END;
		END
	END New;

	PROCEDURE SYSmove*(VAR x, y, z: OPL.Item; zmult4: BOOLEAN);	(* x^ := z bytes at y *)
	(* doesn't work if overlapping and x > y *)
		VAR until: LONGINT; xadr, yadr: OPL.Item;
	BEGIN
		IF z.mode = Con THEN OPL.Load(x, T1); OPL.Load(y, T2); MoveRefBlock(x, y, z.offset, 1, 1)
		ELSE
			xadr.mode := Reg; xadr.reg := T1; yadr.mode := Reg; yadr.reg := T2;
			OPL.Move(xadr, x, LInt);
			OPL.Move(yadr, y, LInt);
			until := OPL.PutSPC(ADDU, -1, yadr, z);
			OPL.Put(SPECIAL*OP + SLTU + T2*RS + until*RT + T0*RD);
			OPL.Put(BEQ*OP + T0*RS + 5);	(* end *)
			(* loop1: *) OPL.Put(LB*OP + T2*RS + T0*RT );
			OPL.Put(ADDIU*OP + T2*(RS + RT) + 1);
			OPL.Put(ADDIU*OP + T1*(RS + RT) + 1);
			OPL.Put(BNE*OP + T2*RS + until*RT +(-4) MOD IMM);	(* loop1 *)
			OPL.Put(SB*OP + T1*RS + T0*RT+(-1) MOD IMM);
			(* end: *) OPL.ReleaseR(until) 
		END
	END SYSmove;

	PROCEDURE SYSmove8(VAR x, y, z: OPL.Item);	(* x^ := z bytes at y multiple of 8 bytes, aligned*)
	(* doesn't work if overlapping and x > y *)
		VAR until: LONGINT; xadr, yadr: OPL.Item;
	BEGIN
		IF z.mode = Con THEN OPL.Load(x, T1); OPL.Load(y, T2); MoveRefBlock(x, y, z.offset, 1, 1)
		ELSE
			xadr.mode := Reg; xadr.reg := T1; yadr.mode := Reg; yadr.reg := T2;
			OPL.Move(xadr, x, LInt);
			OPL.Move(yadr, y, LInt);
			until := OPL.PutSPC(ADDU, -1, yadr, z); 
			(* loop0: *) OPL.Put(LDC1*OP + T2*RS + 0*RT );
			OPL.Put(ADDIU*OP + T2*(RS + RT) + 8);
			OPL.Put(ADDIU*OP + T1*(RS + RT) + 8);
			OPL.Put(BNE*OP + T2*RS + until*RT + (-4) MOD IMM);	(* loop0 *)
			OPL.Put(SDC1*OP + T1*RS + 0*RT + (-8) MOD IMM);
			(* end: *) OPL.ReleaseR(until) 
		END
	END SYSmove8;

	PROCEDURE VarParRecord(VAR arg, ap: OPL.Item; rt: LONGINT; deref: BOOLEAN);
		VAR aptag, argtag: OPL.Item; aptyp: OPT.Struct; apr, tagrt: LONGINT;
	BEGIN
		arg.typ := OPT.linttyp; aptyp := ap.typ; ap.typ := OPT.linttyp; argtag := arg; aptag := ap; apr := 0;
		IF aptag.mode = Based THEN apr := aptag.reg; OPL.GetR(FrozenReg, apr) END ;
		IF argtag.mode = Reg THEN INC(argtag.reg) ELSE INC(argtag.offset, 4) END ;
		IF ap.mode = VarPar THEN aptag.mode := Var;
			IF ap.offset < 64 THEN (* Reg *) INC(aptag.offset) ELSE INC(aptag.offset, 4) END
		ELSIF deref THEN (* ap = p^ *) aptag.offset := -4
		ELSE aptag.mode := Var; aptag.mnolev := -aptyp^.mno; aptag.offset := 64; aptag.obj := aptyp^.strobj;
			IF rt = -1 THEN tagrt := -1 ELSE tagrt := rt + 1 END ;
			OPL.LoadAddr(aptag, tagrt)
		END ;
		OPL.LoadAddr(ap, rt); OPL.Move(argtag, aptag, LInt);	(* arg := ap done in param *)
		IF apr # 0 THEN OPL.ThawR(FrozenReg, apr); OPL.GetR(TempReg, apr) END
	END VarParRecord;

	PROCEDURE VarParOther(fp: OPT.Object; VAR arg, ap: OPL.Item; rt: LONGINT);
		VAR tag, ptr: OPL.Item; btyp: OPT.Struct;
	BEGIN
		IF (fp^.typ = OPT.sysptrtyp) & (ap.typ # OPT.sysptrtyp) THEN (* ptr to record, else undef *)
			btyp := ap.typ^.BaseTyp;
			tag.mode := Var; tag.mnolev := -btyp^.mno; tag.offset := 64; tag.obj := btyp^.strobj;
			OPL.LoadAddr(tag, -1); OPL.LoadAddr(ap, rt);
			ptr.mode := Based; ptr.reg := ap.reg; ptr.offset := 0;
			OPL.Move(ptr, tag, LInt); OPL.GetR(TempReg, ap.reg)
		ELSE OPL.LoadAddr(ap, rt)
		END ;
		arg.typ := OPT.linttyp
	END VarParOther;

	PROCEDURE Param*(VAR ap: OPL.Item; fp: OPT.Object; deref: BOOLEAN);
		VAR c: SHORTINT; arg: OPL.Item; adr, rt: LONGINT; 
	BEGIN
		c := fp^.typ^.comp; adr := fp^.adr; arg.typ := fp^.typ;
		IF   (adr < 64) THEN (* register-passed *)
			arg.mode := Reg; arg.descmode := Reg;
			rt := adr;
			IF adr < 32 THEN OPL.GetR(TempReg, rt)
			ELSE OPL.GetF(TempReg, rt)
			END ;
			arg.reg := rt; arg.reg2 := rt
		ELSE rt := -1;
			arg.mode := Based; arg.descmode := Based;
			arg.reg := SP; arg.reg2 := SP;
			arg.offset := adr - 64; arg.Tjmp := adr - 64
		END ;
		IF fp^.mode = VarPar THEN
			IF c = Record THEN VarParRecord(arg, ap, rt, deref)
			ELSIF c # DynArr THEN VarParOther(fp, arg, ap, rt)
			END
		ELSIF c IN {Record, Array} THEN arg.typ := OPT.linttyp; OPL.LoadAddr(ap, rt)
		END ;
		Assign(arg, ap, rt)
	END Param;
	
	PROCEDURE Call*(VAR x: OPL.Item; proc: OPT.Object);
		VAR i, j, n, instr, link: LONGINT; mth, r3, sl: OPL.Item;
	BEGIN
		IF (x.mode = LProc) OR (x.mode = XProc) & (x.mnolev = 0) THEN
			IF slNeeded IN proc^.conval^.setval THEN
				sl.mode := Based; sl.offset := 0; sl.reg := OPL.LoadFP(x.mnolev, -1); OPL.LoadAddr(sl, -1);
				OPL.Put(SW*OP + SP*RS + sl.reg*RT + 0);		(* pass static link, always on stack *)
	(*			r3.mode := Reg; r3.reg := 3; OPL.Move(r3, sl, LInt)	pass static link at R3	*)

			END ;
			link := proc^.adr;
			IF link # 0 THEN (* compiled *) OPL.SetLink(link)
			ELSE (* forward *) link := OPL.Link(proc)
			END ;
			OPL.Put(BCOND*OP + BGEZAL*IMM + link); OPL.Put(NOP)
		ELSIF x.mode = XProc THEN
			OPL.Put(JAL*OP + OPL.Link(proc)); OPL.Put(NOP)
		ELSIF x.mode = TProc THEN OPL.ThawR(FrozenReg, x.reg);
			mth.mode := Based; mth.reg := x.reg; mth.offset := Mth0Offset - 4 * x.offset; mth.typ := OPT.linttyp;
			i := OPL.PutSPC(JALR, RA, mth, Zero); OPL.Put(NOP)
		ELSIF x.mode = CProc THEN i := 1; n := ORD(proc^.conval^.ext^[0]);
			WHILE i <= n DO instr := 0; j := 0;
				WHILE (j < 4) & (i <= n) DO INC(instr,  S.LSH(LONG(proc^.conval^.ext^[i]), 8*j)); INC(i); INC(j) END ;
				OPL.Put(instr)
			END
		ELSE	(* proc var *)
			i := OPL.PutSPC(JALR, RA, x, Zero); OPL.Put( NOP ); (* was: OPL.Put(SPECIAL*OP + x.reg*RT + 25*RD + oR);	 cp address to R25 why ? *)
			x.typ := x.typ.BaseTyp
		END
		(*function result is marked when restoring registers, x.typ must be valid*)
	END Call;
	
	PROCEDURE CopyDynArray(adr: LONGINT; typ: OPT.Struct);
		VAR sr: LONGINT; a0, desc, size, stk: OPL.Item;
	BEGIN
		a0.mode := VarPar; a0.mnolev := OPL.level; a0.offset := adr; a0.descmode := Var; a0.Tjmp := adr;
		desc.mode := Var; desc.mnolev := OPL.level; desc.offset := adr;
		OPL.Size(a0, size, -1, typ); sr := OPL.PutIMM(ADDIU, -1, size, 7);
		OPL.Put(SPECIAL*OP + SRL + 3*SHAMT + sr*(RT + RD));
		OPL.Put(SPECIAL*OP + SLL + 3*SHAMT + sr*(RT + RD));
		OPL.Put(SPECIAL*OP + SUBU + SP*(RS + RD) + sr*RT);
		a0.typ := typ; stk.mode := Reg; stk.reg := SP; stk.typ := OPT.linttyp;
		size.reg := sr; OPL.LoadAddr(a0, T2); SYSmove8(stk, a0, size);	(* move block of size aligned to 8-byte *)
		stk.mode := Reg; stk.reg := SP; OPL.Move(desc, stk, LInt)
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
			nil.mode := Reg; nil.reg := 0;
			IF nofptrs > MaxPtrs THEN
				(* initialize local frame (not copied parameters) to NIL *)
				obj := proc^.scope^.scope;	(* first local variable *)
				x.offset := proc^.conval^.intval2;
				y.offset := obj^.adr + obj^.typ^.size;
				x.mode := Var; x.typ := OPT.sysptrtyp; x.mnolev := OPL.level;
				y.mode := Var; y.typ := OPT.sysptrtyp; y.mnolev := OPL.level;
				xadr.mode := Reg; xadr.reg := T1; yadr.mode := Reg; yadr.reg := T2;
				OPL.LoadAddr(x, T1); OPL.Move(xadr, x, LInt);
				OPL.LoadAddr(y, T2); OPL.Move(yadr, y, LInt);
				OPL.Put(ADDIU*OP + T1*(RS + RT) + 8);
				OPL.Put(SW*OP + T1*RS + (-8) MOD IMM);
				OPL.Put(BNE*OP + T1*RS + T2*RT + (-3) MOD IMM);
				OPL.Put(SW*OP + T1*RS + (-4) MOD IMM);
				nofptrs := 0;	(* find pointer registers *)
				WHILE obj # NIL DO
					IF (obj^.linkadr > 0) & (obj^.typ^.form = Pointer) THEN ptrTab[nofptrs] := obj^.linkadr; INC(nofptrs) END ;
					obj := obj^.link
				END
			END ;
			i := 0;
			WHILE i < nofptrs DO
				x.mode := Var; x.typ := OPT.sysptrtyp; x.mnolev := OPL.level;
				x.offset := ptrTab[i]; OPL.Move(x, nil, Pointer); INC(i)
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
						IF floating THEN OPL.GetF(VarReg, r)
						ELSE REPEAT OPL.GetR(VarReg, r); (* reserve r *) INC(r); DEC(n) UNTIL n = 0
						END ;
						vadr := padr
					ELSE
						r := -1;
						IF floating THEN OPL.GetF(VarReg, r)
						ELSE OPL.GetR(VarReg, r);
							IF nofr = 2 THEN r2 := -1; OPL.GetR(VarReg, r2); regalloc := r + 1 = r2;
								IF ~regalloc THEN OPL.ThawR(VarReg, r); OPL.ThawR(VarReg, r2) END
							END
						END ;
						IF regalloc THEN
							to.mode := Reg; to.reg := r;
							from.mode := Reg; from.reg := padr;
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
					IF var^.mode = VarPar THEN form := LInt ELSE form := f END ;
					REPEAT
						to.mode := Var; to.mnolev := OPL.level; to.offset := vadr + (nofr - 1)*4;
						from.mode := Reg; from.reg := padr + nofr - 1;
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
				IF c = DynArr THEN
					AllocPar(typ^.size DIV 4, FALSE);
					IF var^.mode = Var THEN CopyDynArray(vadr, typ) (* vadr > 0, may be reg *) END
				ELSIF var^.mode = VarPar THEN
					IF c = Record THEN AllocPar(2, FALSE)
					ELSE AllocPar(1, FALSE)
					END
				ELSE
					IF c IN {Record, Array} THEN
						from.mode := VarPar; from.mnolev := OPL.level; from.offset := padr; from.typ := typ; (* padr > 0, may be reg *)
						to.mode := Var; to.mnolev := OPL.level; to.offset := vadr; to.typ := typ; (* vadr < 0 *)
						MoveBlock(to, from, typ^.size)
					ELSE AllocPar(1, f IN realSet);
					END
				END ;
				var^.linkadr := vadr; var := var^.link
			END ;
			var := proc^.scope^.scope;	(* local vars *)
			IF proc^.leaf THEN nofVarR := MaxVarR; nofVarF := MaxVarF END ;
			WHILE var # NIL DO
				IF var^.typ^.form IN realSet THEN
					IF var^.leaf & (nofVarF > 0) THEN
						r := -1; OPL.GetF(VarReg, r); var^.linkadr := r; DEC(nofVarF)
					END
				ELSIF var^.typ^.comp = Basic THEN
					IF var^.leaf & (nofVarR > 0) THEN
						r := -1; OPL.GetR(VarReg, r); var^.linkadr := r; DEC(nofVarR)
					END
				END ;
				var := var^.link
			END ;
			IF OPL.dynArrCopied THEN OPL.resCallArea := OPL.pc; OPL.Put(ADDIU*OP + SP*(RS + RT)) END	(* fixed in OPL.Exit *)
		END
	END Enter;
	
	PROCEDURE Result*(proc: OPT.Object; VAR res: OPL.Item);
		VAR r: OPL.Item;
	BEGIN
		r.mode := Reg; r.typ := proc.typ;
		IF r.typ^.form IN {Real, LReal} THEN r.reg := OPL.RRF; OPL.GetF(TempReg, r.reg);
		ELSE r.reg := OPL.RRI; OPL.GetR(TempReg, r.reg);	(* result still in RRx *)
		END ;
		Assign(r, res, r.reg)
	END Result;
		
	PROCEDURE With*(VAR x: OPL.Item);
	BEGIN
		IF x.mode IN {Reg, Based} THEN OPL.ReleaseR(x.reg) END
	END With;
	
	PROCEDURE FJ*(VAR loc: OPL.Label);	(* unconditional forward jump *)
	BEGIN
		IF loc = 0 THEN (* end of chain *) loc := OPL.pc END ;
		OPL.Put(BEQ*OP + (loc - OPL.pc - 1) MOD IMM); loc := OPL.pc - 1; OPL.Put(NOP)
	END FJ;
	
	PROCEDURE SetBNE(VAR x: OPL.Item);
	BEGIN
		OPL.Load(x, -1);
		x.mode := Cond; x.reg2 := 0; x.offset := BNE*OP; x.Tjmp := 0; x.Fjmp := 0
	END SetBNE;

	PROCEDURE FJf*(VAR x: OPL.Item; VAR loc: OPL.Label);	(* conditional forward jump on false *)
	BEGIN
		IF x.mode # Cond THEN SetBNE(x) END ;
		OPL.Invert(x.offset);  OPL.PutCond(x, x.Fjmp, FALSE);	(* B~cond Fjmp *)
		loc := OPL.pc - 2; OPL.FixLink(x.Tjmp)
	END FJf;

	PROCEDURE BJ*(loc: OPL.Label);	(* unconditional backward jump *)
	BEGIN
		IF loc = 0 THEN (* end of chain *) loc := OPL.pc END ;
		OPL.Put(BEQ*OP + (loc - OPL.pc - 1) MOD IMM); OPL.Put(NOP)
	END BJ;

	PROCEDURE BJf*(VAR x: OPL.Item; loc: OPL.Label);	(* conditional backward jump on false *)
	BEGIN
		IF x.mode # Cond THEN SetBNE(x) END ;
		OPL.Invert(x.offset); OPL.PutCond(x, loc, FALSE);	(* B~cond loc *)
		OPL.FixLinkWith(x.Fjmp, loc); OPL.FixLink(x.Tjmp)
	END BJf;

	PROCEDURE BJt*(VAR x: OPL.Item; loc: OPL.Label);	(* conditional backward jump on true *)
	BEGIN
		IF x.mode # Cond THEN SetBNE(x) END ;
		OPL.PutCond(x, loc, FALSE);	(* Bcond loc *)
		OPL.FixLinkWith(x.Tjmp, loc); OPL.FixLink(x.Fjmp)
	END BJt;

	PROCEDURE CaseJump*(tab: OPL.Label; from, to: LONGINT);
		VAR i, j: OPL.Label;
	BEGIN
		i := OPL.pc; OPL.pc := SHORT(tab + 2*from); j := tab + 2*to;
		WHILE OPL.pc <= j DO OPL.Put(BEQ*OP + (i - OPL.pc -1) MOD IMM); OPL.Put(NOP) END ;
		OPL.pc := SHORT(i)
	END CaseJump;
	
	PROCEDURE Case*(VAR x: OPL.Item; low, high: LONGINT; VAR tab: OPL.Label);
		VAR y: OPL.Item; n, else, save: LONGINT;	(* T0 is CC ON ARM *)
	BEGIN n := high - low + 1;
		y.mode := Con; y.offset := low; OPL.Add(x, y, -1, TRUE);
		else := OPL.PutIMM(SLTIU, T0, x, n);
		else := 6 + 2*n;
		IF OPL.LeafProc THEN INC(else) END ;
		OPL.Put(BEQ*OP + T0*RS + else);
		OPL.Put(SPECIAL*OP + SLL + 3*SHAMT + x.reg*RT + T0*RD);
		IF OPL.LeafProc THEN
			save := -1; OPL.GetR(TempReg, save); OPL.ReleaseR(save);
			OPL.Put(SPECIAL*OP + oR + RA*RT + save*RD)
		END ;
		OPL.Put(BCOND*OP + BGEZAL*IMM + 1);
		OPL.Put(ADDIU*OP + RA*(RS + RT) + 12);
		OPL.Put(SPECIAL*OP + ADDU + RA*RS + T0*(RT + RD));
		OPL.Put(SPECIAL*OP + JR + T0*RS);
		IF OPL.LeafProc THEN OPL.Put(SPECIAL*OP + oR + save*RT + RA*RD) ELSE OPL.Put(NOP) END ;
		tab := OPL.pc; INC(OPL.pc, SHORT(2*n));
		CaseJump(tab, 0, high - low)
	END Case;

BEGIN
	Zero.mode := Reg; Zero.reg := 0;
	
	cmpiOP[lss] := BNE*OP;
	cmpiOP[leq] := BNE*OP;
	cmpiOP[gtr] := BEQ*OP;
	cmpiOP[geq] := BEQ*OP;
	
	cmp0OP[eql] := BEQ*OP;
	cmp0OP[neq] := BNE*OP;
	cmp0OP[lss] := BCOND*OP + BLTZ*RT;
	cmp0OP[leq] := BLEZ*OP;
	cmp0OP[gtr] := BGTZ*OP;
	cmp0OP[geq] := BCOND*OP + BGEZ*RT;
	
	cmpOP[eql] := BEQ*OP;
	cmpOP[neq] := BNE*OP;
	cmpOP[lss] := BNE*OP;
	cmpOP[geq] := BEQ*OP;
	
	cmpfOP[eql] := COP1*OP + BCT*IMM;
	cmpfOP[neq] := COP1*OP + BCF*IMM;
	cmpfOP[lss] := COP1*OP + BCT*IMM;
	cmpfOP[leq] := COP1*OP + BCT*IMM;
	cmpfOP[gtr] := COP1*OP + BCF*IMM;
	cmpfOP[geq] := COP1*OP + BCF*IMM;
	
	condf[eql] := CEQf;
	condf[neq] := CEQf;
	condf[lss] := CLTf;
	condf[leq] := CLEf;
	condf[gtr] := CLEf;
	condf[geq] := CLTf;
	
	swapped[eql] := eql;
	swapped[neq] := neq;
	swapped[lss] := gtr;
	swapped[leq] := geq;
	swapped[gtr] := lss;
	swapped[geq] := leq;
END MOPC.
