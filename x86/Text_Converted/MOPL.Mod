MODULE MOPL;	(* RC 14.3.90 / 8.9.93 *)	(* object model 9.2.94 *)
(* low level code generator for MIPS 32 *)
(*

	Peter Matthias
	2015-08-19	using SDC1, LDC1, removed load delay slot; removed multiply delay slot
	2015-08-23	changed CalleeSavedR to test register allocation
	2015-08-24	trapping for DIV 0 in Div
	2015-10-11	passing static link as first parameter
	2015-10-12	removed usage of AT register, using GetR( TempReg, atr)
	2015-10-14	removed rt argument in AddUpperToBase (not needed)
	2015-11-11	fixed bug in MultOp
	2015-11-17	pass static link always on stack
	2015-11-24	using T0 as temp. register AT
	2015-11-28	cleaned up Div and Mul; changed RestoreRegs base to T0 in Exit
	2015-12-03	fixed Load/Move LongReal to/from integer register
	2015-12-08	AddUpperToBase: removed read argument 
	2016-10-19	exported pcahead, PutTrap
	2017-02-11	fixed Load const with ODD(bit 15); made Div OBERON compatible

ToDo: remove export of ReleaseR, ReleaseF 
 
*)

	IMPORT OPM:=ROPM, OPS:=ROPS, OPT:=ROPT, S := SYSTEM;

	TYPE
		Item* = RECORD
			mode*, mnolev*, descmode*: SHORTINT;	(* mnolev < 0 -> mno = -mnolev *)
			typ*: OPT.Struct;
			(* extension for MIPS R2000: *)
			reg*, reg2*: LONGINT;	(* LONGINT instead of SHORTINT to avoid truncation during multiplication with constants *)
			offset*: LONGINT;
			Tjmp*, Fjmp*: LONGINT;
			obj*: OPT.Object
		END ;

	CONST
		pcahead*=1;
		RegSize*=32;	(* integer register size, also set Linux0.RegSize manually to the same! *)
		FPRegDist*= 64 DIV RegSize;
		ReservedIRegs={0..7};

		(* item base modes (=object modes) *)
		Var = 1; VarPar = 2; Con = 3; LProc = 6; XProc = 7; CProc = 9; IProc = 10; TProc = 13;
		(* item modes for MIPS R2000 (must not overlap item basemodes,  > 13) *)
		Based = 14; Cond = 15; Reg = 16;
		
		(* register usage *)
		T0*=1; T1*=2; T2*=3; ARI* =4; RRI*=2; ARF*=12; RRF*=0+32;(* argument reg, Return reg *)
		SP* = 29; FP* = 30; RA* = 31; VirtualFP = OPM.MaxRegNr + 1;

		CallerSavedR = { 4..15, 24, 25};	(* without register variables:{ 8..13}; with: 4..17; was: {4..15, 24, 25}; r28 can also be used*)
		CalleeSavedR = {16..23};	(* without register variables:{14..16}; with: 18..25; was: {16..23};*)
		CallerSavedF = {4..19};		(* was {4..19} *)
		CalleeSavedF = {20..31};	(* was {20..31} *)

	TYPE
		RegSet* = RECORD
			r*, f*: SET
		END ;

(* Items:

	the fields mnolev and typ are set for all modes in OPV.
	mnolev is not set for non-allocated constants.

MIPS R2000 :
   mode  | reg   reg2  offset  Tjmp  Fjmp
------------------------------------------
 1 Var   |             adr
 2 VarPar|             adr
 3 Con   |             val
         |             adr     len         (for string)
 6 LProc |
 7 XProc |	(* exported or assigned *)
 9 CProc |
10 IProc |
13 TProc | tag         mthno   0/1         (0 = normal / 1 = super call)
14 Based | r           offset              (r may be VirtualFP)
15 Cond  | rs    rt    Bcond   Tjmp  Fjmp
16 Reg   | r                               ( if r < 32 then general register r else FPA register r - 32 )
                                           (r cannot be VirtualFP)

field descmode is the mode of an open array descriptor, reg2 -> reg, Tjmp -> offset
*)

	TYPE
		Label* = LONGINT;
		
	VAR
		level*: SHORTINT;
		pc*, resCallArea*: INTEGER;
		InterProcInf*: BOOLEAN;	(* inter-procedural information about register allocation *)
		sb*: LONGINT;
		defaultCalleeUsed*: RegSet;
		dynArrCopied*, LeafProc*: BOOLEAN;
		KNewRec*, KNewSys*, KNewArr*, GlobData*: OPT.Object;
		
	CONST
		(* structure forms *)
		Undef = 0; Byte = 1; Bool = 2; Char = 3; SInt = 4; Int = 5; LInt = 6;
		Real = 7; LReal = 8; Set = 9; String = 10; NilTyp = 11; NoTyp = 12;
		Pointer = 13; ProcTyp = 14; Comp = 15;
		intSet = {SInt..LInt}; realSet = {Real, LReal};
		
		(* composite structure forms *)
		Basic = 1; Array = 2; DynArr = 3; Record = 4;
		
		(* object modes *)
		Fld = 4; Typ = 5; Head = 12;
		
		(* module visibility of objects *)
		internal = 0; external = 1; externalR = 2;
		
		(* history of imported objects *)
		inserted = 0; same = 1; pbmodified = 2; pvmodified = 3; removed = 4; inconsistent = 5;

		(* procedure flags (conval^.setval) *)
		hasBody = 1; isRedef = 2; slNeeded = 3; alreadyCalled (*back-end only *) = 16;

		(* register usage *)
		TempReg = 0; VarReg = 1; FrozenReg = 2; (* register classes *)

		(* instruction format *)
		OP = 4000000H; RS = 200000H; RT = 10000H; RD = 800H; IMM = 10000H; SHAMT = 40H;
		CO = 2000000H; FMT = RS; FT = RT; FS = RD; FD = SHAMT;
				
		(* R2000 opcodes *)
		SPECIAL = 0; BCOND = 1; J = 2; JAL = 3; BEQ = 4; BNE = 5; BLEZ = 6; BGTZ = 7;
		ADDI = 8; ADDIU = 9; SLTI = 10; SLTIU = 11; ANDI = 12; ORI = 13; XORI = 14; LUI = 15;
		SPECIAL2=28; 
		LB = -32; LH = -31; (*LWL = -30;*) LW = -29; LBU = -28; LHU = -27; (*LWR = -26;*)
		SB = -24; SH = -23; (*SWL = -22;*) SW = -21; (*SWR = -18;*)
		COP0 = 16; LWC0 = -16; SWC0 = -8; COP1 = 17; LWC1 = -15; SWC1 = -7; LDC1=-11; SDC1= -3;
		NOP = 0; (* SLL 0, 0, 0 *)
		
		(* SPECIAL *)
		SLL = 0; SRL = 2; SRA = 3; SLLV = 4; SRLV = 6; SRAV = 7;
		JR = 8; JALR = 9; MFHI = 16; MFLO = 18; MULT = 24; dIV = 26;
		ADDU = 33; SUBU = 35; AND = 36; oR = 37; XOR = 38; NOR = 39;
		SLT = 42; SLTU = 43;
(*		TGE=48; TGEU=49; TLT=50; TLTU=51; *)TEQ=52;  TNE=54; 

		(* SPECIAL2 *)
		MUL= SPECIAL2*OP+2;
		
		(* BCOND *)
		BLTZx = 0; BGEZ = 1; BGEZALx = 17;
		
		(* COPZ *)
		MF = 0; MT = 4; BCF = 256; BCT = 257; CF = 2; CT = 6;
		
		(* R2010 functions *)
		ADDf = 0; SUBf = 1; MULf = 2; DIVf = 3; ABSf = 5; MOVf = 6; NEGf = 7;
		CVTSf = 32; CVTDf = 33; CVTWf = 36; CEQf = 50; CLTf = 60; CLEf = 62; 

		(* MIPS R2000 implementation restrictions *)
		CodeLength =  32000; (* words *)
		CodeLim = CodeLength - 500;
		MaxEntryCode = 64;
		ConstLength = 5000;
		MaxComs = 128;
		MaxExts = 15;
		MaxLittleFrame = 32768 - 256 (* callee-saved *) - 256 (* arguments *) - 1536 (* stack extensions *);

		NoShift = MAX(INTEGER);

	VAR
		locUsedR, calleesUsedR, mayBeUsedR, tempLiveR, permLiveR, frozenR: SET;	(* r IN frozenR => r IN tempLiveR *)
		locUsedF, calleesUsedF, mayBeUsedF, tempLiveF, permLiveF: SET;
		saved: RegSet;
		thisProc: INTEGER;
		NoFP, RegsSaved: BOOLEAN;
		frameSize, callArea, stackExt: LONGINT;
		loadOp, storeOp: ARRAY 16 OF SHORTINT;
		COfmt: ARRAY 16 OF LONGINT;
		conx, adjlx, lacx, shiftx, curshiftx: INTEGER;
		CodeOvF: BOOLEAN;
		code:  ARRAY CodeLength OF LONGINT;
		constant: ARRAY ConstLength OF CHAR;
		adjustLink: ARRAY 1024 OF INTEGER;
		localAccess: ARRAY 4096 OF INTEGER;
		shiftTab: ARRAY 512 OF INTEGER;	(* one for each procedure *)
		nofdesc: INTEGER;

PROCEDURE Put*(instr: LONGINT);
BEGIN	code[pc] := instr; INC(pc)
END Put;

PROCEDURE PutI*( op, rt, rs, imm: LONGINT);
BEGIN
	code[pc] := op*OP+rs*RS+rt*RT+imm MOD IMM; INC(pc)
END PutI;

PROCEDURE PutR*( op, rd, rs, rt: LONGINT);
BEGIN	(* SPECIAL=0 *)
	code[pc] := rs*RS+rd*RD+ rt*RT+ op; INC(pc)
END PutR;

PROCEDURE PutFP*( op, fmt, rd, rs, rt: LONGINT);	(* fmt already shifted*)
BEGIN	(* SPECIAL=0 *)
	code[pc] := COP1*OP+fmt+(rd MOD 32)*FD+(rs MOD 32)*FS+ (rt MOD 32)*FT+ op; INC(pc)
END PutFP;

PROCEDURE PutSHI(op, rd, rt, sa: LONGINT);	(* shift immideate *)
BEGIN	code[pc] := SPECIAL*OP+rt*RT+ rd*RD+sa*SHAMT+op; INC(pc)
END PutSHI;

PROCEDURE PutTEQ*(rs, rt, cod: LONGINT);
BEGIN	code[pc] := rs*RS+rt*RT+ (cod MOD 400H)*SHAMT+TEQ; INC(pc)
END PutTEQ;

PROCEDURE PutTNE*(rs, rt, cod: LONGINT);
BEGIN	code[pc] := rs*RS+rt*RT+ (cod MOD 400H)*SHAMT+TNE; INC(pc)
END PutTNE;

PROCEDURE PutTrap*( nr: LONGINT);
BEGIN
	code[pc] := (nr MOD 400H)*SHAMT+TEQ;;
	INC(pc)
END PutTrap;

	PROCEDURE AllocConst(cadr: LONGINT; len: INTEGER; VAR adr: LONGINT; align: SHORTINT);
	BEGIN
		WHILE (conx MOD align) #0 DO constant[conx] := 0X; INC(conx) END ;
		IF conx > ConstLength-255 THEN OPM.err(230); conx := 0 END ;
		adr := conx + 64;
		S.MOVE(cadr, S.ADR(constant[conx]), len);
		INC(conx, len);
	END AllocConst;
(*
	PROCEDURE AllocConst(cadr: LONGINT; len: INTEGER; VAR adr: LONGINT; align: SHORTINT);
		VAR fill, i, c: INTEGER;
	BEGIN
		c := conx;
		fill := (-c) MOD align;
		WHILE fill > 0 DO constant[c] := 0X; INC(c); DEC(fill) END ;
		IF c > ConstLength-255 THEN OPM.err(230); c := 0 END ;
		adr := c + 64;
		S.MOVE(cadr, S.ADR(constant[c]), len); INC(c, len);
		conx := c
	END AllocConst;
*)
	PROCEDURE AllocString*(VAR s: ARRAY OF CHAR; len: LONGINT; VAR adr: LONGINT);
	BEGIN AllocConst(S.ADR(s[0]), SHORT(len), adr, 4)
	END AllocString;

	PROCEDURE AllocReal*(r: REAL; VAR adr: LONGINT);
	BEGIN AllocConst(S.ADR( r), 4, adr, 4)
	END AllocReal;

	PROCEDURE AllocLReal*(r: LONGREAL; VAR adr: LONGINT);
	BEGIN AllocConst(S.ADR( r), 8, adr, 8)
	END AllocLReal;

	PROCEDURE AllocTypDesc*(typ: OPT.Struct);   (* typ^.comp = Record *)
		VAR obj: OPT.Object; name: OPS.Name;
	BEGIN
		IF (typ^.strobj = NIL) OR (typ^.strobj^.mnolev > 0) THEN OPT.IdFPrint(typ);	(* before deleting name *)
			(* insert a global object of that type, in order to find it when in OutCode *)
			name := "@"; OPT.Insert(name, obj); obj^.name := "";	(* avoid err 1 *)
			obj^.mode := Typ; obj^.typ := typ; typ^.strobj := obj	(* obj.linkadr needed, obj^.typ^.strobj = obj else alias ! *)
		END ;
		IF typ^.extlev > MaxExts THEN OPM.err(233) END
	END AllocTypDesc; 

	PROCEDURE BegStat*;	(* general-purpose procedure which is called before each statement *)
	BEGIN
		IF pc > CodeLim THEN
			IF ~CodeOvF THEN OPM.err(210); CodeOvF := TRUE END ;
			pc := 0
		END
	END BegStat;

	PROCEDURE EndStat*;	(* general-purpose procedure which is called after each statement *)
	BEGIN
		tempLiveR := {}; tempLiveF := {}; frozenR := {}
		(* frozenR used for open array bases, see OPC.DeRef, and for common design bases, see OPC.CommonDesign *)
	END EndStat;

	PROCEDURE Fixup*(L: Label);	(* enter pc at L, pc > L *)
	BEGIN
		code[L] := IMM*(code[L] DIV IMM) + pc - L - pcahead
	END Fixup;

	PROCEDURE FixLink*(L: Label);
		VAR L1: Label; c: LONGINT;
	BEGIN
		IF ~CodeOvF & (L # 0) THEN
			REPEAT
				L1 := L; c := code[L1];
				L := L1 + S.LSH(c, 16) DIV IMM + 1;
				code[L1] := IMM*(c DIV IMM) + pc - L1 - pcahead
			UNTIL L = L1
		END
	END FixLink;
	
	PROCEDURE FixLinkWith*(L, val: Label);
		VAR L1: Label; c: LONGINT;
	BEGIN
		IF ~CodeOvF & (L # 0) THEN
			REPEAT
				L1 := L; c := code[L1];
				L := L1 + S.LSH(c, 16) DIV IMM + 1;
				code[L1] := IMM*(c DIV IMM) + (val - L1 - 1) MOD IMM
			UNTIL L = L1
		END
	END FixLinkWith;

	PROCEDURE MergedLinks*(L0, L1: Label): Label;
		VAR L2, L3: Label; c: LONGINT;
	BEGIN
		IF ~CodeOvF & (L0 # 0) THEN L2 := L0;
			LOOP c := code[L2];
				L3 := L2 + S.LSH(c, 16) DIV IMM + 1;
				IF L3 = L2 THEN EXIT END ;
				L2 := L3
			END ;
			code[L2] := IMM*(c DIV IMM) + (L1 - 1 - L2) MOD IMM;
			RETURN L0
		ELSE RETURN L1
		END
	END MergedLinks;

	PROCEDURE FixBranches(proc: OPT.Object);	(* don't fix proc assign *)
		VAR L, L1, newL, link: Label; c: LONGINT;
	BEGIN
		L := proc.linkadr; newL := 0;
		IF ~CodeOvF & (L # 0) THEN
			IF proc.x < shiftx THEN DEC(L, LONG(shiftTab[proc.x])); proc.x := NoShift END ;
			REPEAT
				L1 := L; c := code[L1];
				L := L1 + S.LSH(c, 16) DIV IMM + 1;
				IF c DIV OP = LUI THEN (* proc assign *)
					IF newL = 0 THEN link := (-1) MOD IMM
					ELSE link := (newL - L1 - pcahead) MOD IMM
					END ;
					newL := L1
				ELSE link := pc - L1 - 1
				END ;
				code[L1] := IMM*(c DIV IMM) + link
			UNTIL L = L1
		END ;
		proc^.linkadr := SHORT(newL)
	END FixBranches;

	PROCEDURE PickR(pool: SET; VAR r: LONGINT): BOOLEAN;	(* TRUE if found *)
		VAR i: LONGINT;
	BEGIN
		pool := pool - ReservedIRegs - tempLiveR - permLiveR;
		IF pool = {} THEN RETURN FALSE END ;
		i := 8;
		WHILE ~(i IN pool) DO INC(i) END ;
		r := i; RETURN TRUE
	END PickR;
				
	PROCEDURE GetR*(class: SHORTINT; VAR rt: LONGINT);	(* class IN {TempReg, FrozenReg, VarReg} *)
	BEGIN
		ASSERT((rt # VirtualFP) & ((rt # SP) OR (class = TempReg)));
		IF (rt < 0) OR (rt > 31) THEN
			IF class IN {TempReg, FrozenReg} THEN
				IF PickR(locUsedR*CalleeSavedR, rt) OR 
					InterProcInf & (~LeafProc & (
						PickR(mayBeUsedR*CallerSavedR, rt) OR PickR(CallerSavedR, rt) OR PickR(mayBeUsedR, rt))) OR
					PickR(CallerSavedR, rt) OR PickR(CalleeSavedR, rt)
				THEN
					INCL(locUsedR, rt); INCL(tempLiveR, rt);
					IF class = FrozenReg THEN INCL(frozenR, rt) END
				ELSE OPM.err(215); rt := 0
				END
			ELSE (* class = VarReg *)
				IF LeafProc & (PickR(CallerSavedR, rt) OR PickR(CalleeSavedR, rt)
					) OR ~LeafProc & (
						InterProcInf & (
							PickR(mayBeUsedR*CalleeSavedR, rt) OR PickR(CalleeSavedR, rt) OR PickR(mayBeUsedR, rt)) OR
						PickR(CalleeSavedR, rt) OR PickR(CallerSavedR, rt)
					)
				THEN INCL(locUsedR, rt); INCL(permLiveR, rt)
				ELSE OPM.err(215); rt := 0
				END
			END
		ELSE
			IF class = TempReg THEN INCL(tempLiveR, rt)	(* param regs *)
			ELSIF class = FrozenReg THEN INCL(tempLiveR, rt); INCL(frozenR, rt)	(* freeze function *)
			ELSE INCL(permLiveR, rt)	(* param var regs *)
			END
		END
	END GetR;

	PROCEDURE ReleaseR*(r: LONGINT); 
	BEGIN
		IF ~(r IN frozenR) THEN EXCL(tempLiveR, r) END
	END ReleaseR;
	
	PROCEDURE ThawR*(class: SHORTINT; r: LONGINT);	(* class IN {FrozenReg, VarReg} *)
	BEGIN
		IF class = FrozenReg THEN EXCL(frozenR, r); EXCL(tempLiveR, r)
		ELSE EXCL(permLiveR, r)
		END
	END ThawR;
	
	PROCEDURE PickF(pool: SET; VAR f: LONGINT): BOOLEAN;	(* TRUE if found *)
		VAR i: LONGINT;
	BEGIN
		pool := pool - tempLiveF - permLiveF;
		IF pool = {} THEN RETURN FALSE END ;
		i := 0;
		WHILE (i # 32) & ~(i IN pool) DO INC(i, FPRegDist) END ;
		f := i; RETURN i # 32
	END PickF;
				
	PROCEDURE GetF*(class: SHORTINT; VAR ft: LONGINT);	(* class IN {TempReg, VarReg}, always allocates pair, not efficient for REALs ! *)
	BEGIN
		ASSERT(ft # VirtualFP);
		IF ft < 32 THEN
			IF class = TempReg THEN
				IF PickF(locUsedF*CalleeSavedF, ft) OR 
					InterProcInf & (~LeafProc & (
						PickF(mayBeUsedF*CallerSavedF, ft) OR PickF(CallerSavedF, ft) OR PickF(mayBeUsedF, ft))) OR
					PickF(CallerSavedF, ft) OR PickF(CalleeSavedF, ft)
				THEN
					INCL(locUsedF, ft); INCL(tempLiveF, ft); INC(ft, 32)
				ELSE OPM.err(216); ft := 32
				END
			ELSE (* class = VarReg *)
				IF LeafProc & (PickF(CallerSavedF, ft) OR PickF(CalleeSavedF, ft)
					) OR ~LeafProc & (
						InterProcInf & (
							PickF(mayBeUsedF*CalleeSavedF, ft) OR PickF(CalleeSavedF, ft) OR PickF(mayBeUsedF, ft)) OR
						PickF(CalleeSavedF, ft) OR PickF(CallerSavedF, ft)
					)
				THEN INCL(locUsedF, ft); INCL(permLiveF, ft); INC(ft, 32)
				ELSE OPM.err(216); ft := 32
				END
			END
		ELSE
			IF class = TempReg THEN INCL(tempLiveF, ft - 32)	(* param regs *)
			ELSE INCL(permLiveF, ft - 32)	(* param var regs *)
			END
		END
	END GetF;
	
	PROCEDURE ReleaseF*(f: LONGINT);
	BEGIN EXCL(tempLiveF, f - 32)
	END ReleaseF;

	PROCEDURE Invert*(VAR instr: LONGINT);
		VAR op: LONGINT;
	BEGIN
		op := instr DIV OP;
		CASE op OF
		  BEQ, BLEZ:
				instr := (op + 1)*OP + instr MOD OP
		| BNE, BGTZ:
				instr := (op - 1)*OP + instr MOD OP
		| BCOND, COP1:
				op := instr DIV RT;
				IF ODD(op) THEN instr := (op - 1)*RT + instr MOD RT
				ELSE instr := (op + 1)*RT + instr MOD RT
				END
		END
	END Invert;
		
	PROCEDURE PutCond*(VAR x: Item; loc: Label; locok: BOOLEAN);
		VAR rs, rt: LONGINT;
	BEGIN
		rs := x.reg; rt := x.reg2;
		IF loc = 0 THEN (* end of chain *) loc := -1
		ELSIF ~locok THEN loc := loc - pc -1
		END ;
		Put(x.offset + rs*RS + rt*RT + loc MOD IMM); Put( NOP);
		ReleaseR(rs); ReleaseR(rt)
	END PutCond;
	
	PROCEDURE SetLink*(VAR link: LONGINT);
	BEGIN
		IF link = 0 THEN link := (-1) MOD IMM
		ELSE
			IF link < thisProc + MaxEntryCode THEN adjustLink[adjlx] := pc; INC(adjlx) END;
			link := (link - pc - 1) MOD IMM
		END
	END SetLink;
	
	PROCEDURE Link*(obj: OPT.Object): LONGINT;
		VAR link: LONGINT;
	BEGIN
		IF (obj.linkadr # 0) & (obj.x < shiftx) THEN DEC(obj.linkadr, LONG(shiftTab[obj.x])) END ;
		obj.x := curshiftx; link := obj.linkadr; obj.linkadr := pc; SetLink(link);
		RETURN link
	END Link;
	
	PROCEDURE ^Load*(VAR x: Item; rt: LONGINT);	(* returned x.mode = Reg, x.typ must be defined *)
	
	PROCEDURE LoadFP*(lev: SHORTINT; rt: LONGINT): LONGINT;
		VAR sl: Item;
	BEGIN
		lev := level-lev;
		IF lev = 0 THEN (* local *)
			IF NoFP THEN RETURN VirtualFP ELSE RETURN FP END
		ELSE (* intermediate *)
			sl.mode := Var; sl.mnolev := level; sl.typ := OPT.linttyp;
			sl.offset := 64; Load(sl, rt);
			WHILE lev > 1 DO DEC(lev);
				sl.mode := Based; sl.offset := 0; Load(sl, rt)
			END ;
			RETURN sl.reg
		END
	END LoadFP;
	
	PROCEDURE Base*(VAR x: Item; rt: LONGINT);		(* x.mode IN {Var, VarPar, Based}, returned x.mode = Based *)
		VAR lev: SHORTINT; typ: OPT.Struct; offset: LONGINT;
	BEGIN
		IF rt >= 32 THEN rt := -1 END ;
		lev := x.mnolev;
		CASE x.mode OF
		  Var:
				IF (x.offset > 0) & (x.offset < 64) THEN OPM.err(127) END ;
				IF x.offset >= 64 THEN DEC(x.offset, 64) END ;
				IF lev <= 0 THEN (* global or extern, Var only *)
					GetR(TempReg, rt);
					PutI( ADDIU, rt, rt, Link(x.obj));		(* replaced at load-time by LUI rt, upper adjusted *)
					Put(x.offset);									(* replaced at load-time by ADDIU rt, rt, lower *)
					x.offset := 0; x.reg := rt
				ELSE x.reg := LoadFP(lev, rt)
				END
		| VarPar:
				offset := x.offset;
				IF (offset >= 0) & (offset < 64) THEN x.reg := offset; x.offset := 0
				ELSE
					IF offset >= 64 THEN DEC(x.offset, 64) END ;
					typ := x.typ; x.typ := OPT.linttyp;
					x.reg := LoadFP(lev, rt); x.mode := Based; Load(x, rt); x.offset := 0; x.typ := typ
				END
		| Based:
				(* ok *)
		ELSE OPM.err(127); x.reg := 0; x.offset := 0
		END ;
		x.mode := Based
	END Base;
	
	PROCEDURE AddUpperToBase(VAR x: Item);	(* x.mode = Based, returned x.offset is 16 bit *)
		(* the next instruction MUST use returned x.reg as base *)
		VAR offset, base, rt: LONGINT;
	BEGIN
		ASSERT(x.mode = Based, 32);
		base := x.reg;
		IF base = VirtualFP THEN INC(x.offset, stackExt) END ;
		offset := x.offset;
		IF (offset >= 0FFFF8000H) & (offset <= 7FFFH) THEN
			IF base = VirtualFP THEN base := SP; localAccess[lacx] := pc; INC(lacx) END;
		ELSE ASSERT(base # VirtualFP, 33);
			rt := -1; GetR(TempReg, rt); ReleaseR(base);
			PutI( LUI, rt, 0, offset DIV IMM + (offset MOD IMM) DIV 8000H );
			IF base # 0 THEN PutR( ADDU, rt, rt, base) END ;
			base := rt; x.offset := S.LSH(offset, 16) DIV IMM
		END ;
		x.reg := base
	END AddUpperToBase;

	PROCEDURE LoadAddr*(VAR x: Item; rt: LONGINT);	(* returned x.mode = Reg, x.reg # VirtualFP *)
	BEGIN
		Base(x, rt);
		IF (x.offset # 0) OR (x.reg = VirtualFP) THEN
			IF x.reg # VirtualFP THEN ReleaseR(x.reg) END ;
			GetR(TempReg, rt); AddUpperToBase(x);
			PutI( ADDIU, rt, x.reg, x.offset); x.reg := rt
		END ;
		x.mode := Reg; x.typ := OPT.linttyp
	END LoadAddr;

	PROCEDURE Load*(VAR x: Item; rt: LONGINT);	(* returned x.mode = Reg, x.typ must be defined if not Reg*)
		VAR val, upper, lower: LONGINT; f: SHORTINT;
	BEGIN
		CASE x.mode OF
		  Var:
				f := x.typ^.form; lower := x.offset; 
				IF (lower >= 0) & (lower < 64) THEN x.mode := Reg; x.reg := lower
				ELSIF x.mnolev <= 0 THEN (* global or extern *)
					IF lower >= 64 THEN DEC(x.offset, 64) END ;
					IF f IN realSet THEN GetF(TempReg, rt) ELSE GetR(TempReg, rt) END;
					PutI(loadOp[f], rt MOD 32, T0, Link(x.obj));
					Put(x.offset); x.mode := Reg; x.reg := rt;
				ELSE (* local or intermediate *)
					Base(x, rt); Load(x, rt)
				END
		| VarPar:
				Base(x, rt); Load(x, rt)
		| Con:
				val := x.offset;
				IF val = 0 THEN rt := 0
				ELSE GetR(TempReg, rt);
					upper := val DIV (IMM DIV 2); lower := val MOD IMM;
					IF (upper = 0) OR (upper = -1) THEN PutI( ADDIU, rt, 0, lower)
(*					ELSIF upper DIV 2=0 THEN PutI( ORI, rt, 0, lower)*)
					ELSE PutI( LUI, rt, 0, upper DIV 2+upper MOD 2); 
						IF lower # 0 THEN PutI( ADDIU, rt, rt, lower) END
					END
				END ;
				x.mode := Reg; x.reg := rt
		| XProc, IProc:
				GetR(TempReg, rt);
				PutI( LUI, rt, 0, Link(x.obj));
				PutI( ORI, rt, rt, 0);
				x.mode := Reg; x.reg := rt
		| Based:
				AddUpperToBase(x); lower := x.offset MOD IMM;
				f := x.typ^.form;
				ReleaseR(x.reg);
				IF f IN realSet THEN GetF(TempReg, rt) ELSE GetR(TempReg, rt) END;
				PutI(loadOp[f], rt MOD 32, x.reg, lower);
				x.mode := Reg; x.reg := rt; 
		| Cond:
				GetR(TempReg, rt);
				IF x.Tjmp = 0 THEN
					PutCond(x, 2, TRUE); DEC(pc); PutI( ORI, rt, 0, 1); FixLink(x.Fjmp); PutI( ORI, rt, 0, 0)
				ELSIF x.Fjmp = 0 THEN Invert(x.offset);
					PutCond(x, 2, TRUE); DEC(pc); PutI( ORI, rt, 0, 0); FixLink(x.Tjmp); PutI( ORI, rt, 0, 1)
				ELSE
					PutCond(x, 4, TRUE); DEC(pc); PutI( ORI, rt, 0, 1); FixLink(x.Fjmp); PutI( BEQ, 0, 0, 2);
					PutI( ORI, rt, 0, 0); FixLink(x.Tjmp); PutI( ORI, rt, 0, 1)
				END ;
				x.mode := Reg; x.reg := rt
		| Reg:
		ELSE OPM.err(127); x.mode := Reg; x.reg := 0
		END
	END Load;
	
	PROCEDURE Move*(VAR x, y: Item; xform: SHORTINT);	(* x := y *)
		VAR rx, ry, lower: LONGINT;
	BEGIN
		IF x.mode = Var THEN lower := x.offset;
			IF (lower >= 0) & (lower < 64) THEN x.mode := Reg; x.reg := lower END
		END ;
		IF y.mode # Reg THEN
			IF x.mode = Reg THEN ry := x.reg ELSE ry := -1 END ;
			Load(y, ry)
		END ;
		ry := y.reg;
		CASE x.mode OF
		  Var:
				IF x.mnolev <= 0 THEN (* global or extern *)
					IF lower >= 64 THEN DEC(lower, 64) END ;
					PutI(storeOp[xform], ry MOD 32, T0, Link(x.obj));	(* replaced at load-time by LUI T0, upper adjusted *)
					Put(lower);
					IF ry < 32 THEN ReleaseR(ry)
					ELSIF ry < 64 THEN ReleaseF(ry)
					END
				ELSE (* local or intermediate *)
					Base(x, -1); Move(x, y, xform)
				END
		| VarPar:
				Base(x, -1); Move(x, y, xform)
		| Based:
				AddUpperToBase(x); lower := x.offset MOD IMM;
				ReleaseR(x.reg);
				PutI(storeOp[xform], ry MOD 32, x.reg, lower);
				IF ry < 32 THEN ReleaseR(ry)
				ELSIF ry < 64 THEN ReleaseF(ry)
				END
		| Reg:
				rx := x.reg;
				IF ry # rx THEN
					IF rx < 32 THEN
						IF ry < 32 THEN PutR( oR, rx, ry, 0); ReleaseR(ry)
						ELSE OPM.err(706);
						END
					ELSIF rx < 64 THEN
						IF ry < 32 THEN OPM.err(707);
						ELSE PutFP(MOVf, COfmt[ xform], rx, ry, 0 ); ReleaseF(ry)
						END
					ELSE OPM.err(708);
					END
				END
		ELSE OPM.err(127)
		END
	END Move;

	PROCEDURE PutSPC*(funct, rt: LONGINT; VAR x, y: Item): LONGINT;
		VAR rx, ry: LONGINT;
	BEGIN
		Load(x, -1); Load(y, -1); rx := x.reg; ry := y.reg;
		ReleaseR(rx); ReleaseR(ry); GetR(TempReg, rt);
		PutR( funct, rt, rx, ry);
		RETURN rt
	END PutSPC;
	
	PROCEDURE PutIMM*(oper, rt: LONGINT; VAR x: Item; imm: LONGINT): LONGINT;
		VAR rx: LONGINT;
	BEGIN
		Load(x, -1); rx := x.reg; ReleaseR(rx); GetR(TempReg, rt);
		PutI(oper, rt, rx, imm);
		RETURN rt
	END PutIMM;
	
	PROCEDURE PutFPA*(func, f, ft: LONGINT; VAR x, y: Item): LONGINT;	(* x or y may be R0 *)
		VAR fx, fy: LONGINT;
	BEGIN
		Load(x, -1); Load(y, -1); fx := x.reg; fy := y.reg;
		IF fx # 0 THEN ReleaseF(fx) END ;
		IF fy # 0 THEN ReleaseF(fy) END ;
		IF func <= CVTWf THEN (* 3 operands *) GetF(TempReg, ft)
		ELSE (* conditional, 2 operands *) ft := 0
		END ;
		ASSERT(((fx = 0) OR (fx > 31)) & ((fy = 0) OR (fy > 31)) & ((ft > 31) OR (ft = 0)));
		PutFP(func, COfmt[ f], ft, fx, fy);
		RETURN ft
	END PutFPA;
	
	PROCEDURE Add*(VAR x, y: Item; rt: LONGINT; sub: BOOLEAN);	(* x := x+-y *)
		VAR z: Item; c: LONGINT; xc, yc: BOOLEAN;
	BEGIN
		xc := x.mode = Con; yc := y.mode = Con;
		IF xc & yc THEN
			IF sub THEN DEC(x.offset, y.offset) ELSE INC(x.offset, y.offset) END ;
			RETURN
		END ;
		IF xc & ~sub THEN z := x; x := y; y := z; yc := TRUE END ;
		IF yc THEN
			IF sub & (y.offset # MIN(LONGINT)) THEN y.offset := -y.offset END ;
			c := y.offset;
			IF c # 0 THEN
				IF (c <= 7FFFH) & (c >= 0FFFF8000H) THEN x.reg := PutIMM(ADDIU, rt, x, c)
				ELSE x.reg := PutSPC(ADDU, rt, x, y)
				END
			END
		ELSIF sub THEN x.reg := PutSPC(SUBU, rt, x, y)
		ELSE x.reg := PutSPC(ADDU, rt, x, y)
		END
	END Add;

	PROCEDURE Mul*(VAR x, y: Item; rt: LONGINT);	(* x := x*y *)
		VAR c, ones, shift, pos, r, acc: LONGINT; xc, yc: BOOLEAN;
		
		PROCEDURE Shift(shift, to: LONGINT);
		BEGIN
			IF (acc # 0) & (shift # 0) THEN 
				ReleaseR(acc); GetR(TempReg, to); PutSHI(SLL, to, acc, shift); acc := to
			END
		END Shift;
		
		PROCEDURE Inc(to: LONGINT);
		BEGIN
			IF acc = 0 THEN Load(x, -1); acc := x.reg
			ELSE
				ReleaseR(acc); GetR(TempReg, to); PutR( ADDU, to, acc, x.reg); acc := to
			END
		END Inc;
		
		PROCEDURE Dec(to: LONGINT);
		BEGIN
			IF acc = 0 THEN Load(x, -1) END ;
			ReleaseR(acc); GetR(TempReg, to); PutR( SUBU, to, acc, x.reg); acc := to
		END Dec;
		
	BEGIN
		xc := x.mode = Con; yc := y.mode = Con;
		IF xc & yc THEN x.offset := x.offset*y.offset
		ELSIF xc OR yc THEN
			IF xc THEN c := x.offset; x := y ELSE c := y.offset END ;
			shift := 0; acc := 0; pos := 31;
			WHILE c # 0 DO
				ones := 0;
				WHILE c < 0 DO c := S.LSH(c, 1); DEC(pos); INC(ones) END ;
				IF c = 0 THEN r := rt ELSE r := T0 END ;
				IF ones > 0 THEN
					IF ones + pos = 31 THEN Dec(r); shift := 1
					ELSIF ones = 1 THEN Shift(shift, T0); Inc(r); shift := 1
					ELSE Shift(shift-1, T0); Inc(T0); Shift(ones, T0); Dec(r); shift := 1
					END
				END ;
				c := S.LSH(c, 1); DEC(pos); INC(shift)
			END ;
			ReleaseR(x.reg); Shift(shift + pos, rt); GetR(TempReg, acc);
			x.mode := Reg; x.reg := acc
		ELSE
			Load(x, -1); Load(y, -1); ReleaseR(x.reg); ReleaseR(y.reg);  GetR(TempReg, rt);
			PutR( MUL, rt, x.reg, y.reg);	(* MIPS32 *)
			x.mode:= Reg; x.reg:=rt;
		END
	END Mul;
	
	PROCEDURE Div*(VAR x, y: Item; rt: LONGINT; mod: BOOLEAN);
	BEGIN
		Load(x, -1); Load(y, -1); 
		ReleaseR(x.reg);  GetR(TempReg, rt); ReleaseR(y.reg);  
		PutR( dIV, 0, x.reg, y.reg);
		PutTEQ( y.reg, 0, 7);		
		IF mod THEN
			IF rt = y.reg THEN rt:=-1; GetR(TempReg, rt); ReleaseR(y.reg) END;
			ASSERT(rt # y.reg);	(* should always be TRUE *)
			PutR( MFHI, rt, 0, 0); 
			PutI( BCOND, BGEZ, rt, 5);
			Put( NOP);
			PutI( BCOND, BGEZ, y.reg, 3);
			PutR( ADDU, rt, rt, y.reg);	(* branch delay *)
			PutR( SUBU, rt, rt, y.reg);
			PutR( SUBU, rt, rt, y.reg);
		ELSE
			PutR( MFHI, T0, 0, 0);
			PutI( BCOND, BGEZ, T0, 4);
			PutR( MFLO, rt, 0, 0); 
			PutI( BCOND, BGEZ, y.reg, 2);
			PutI( ADDIU, rt, rt, -1);
			PutI( ADDIU, rt, rt, 2);
		END;
		x.reg := rt
	END Div;
	
	PROCEDURE LenDesc*(VAR x, len: Item; typ: OPT.Struct);	(* set len to LEN(x, typ^.n), x.typ^.comp = DynArr *)
	BEGIN
		len.mode := x.descmode; len.mnolev := x.mnolev; len.reg := x.reg2; len.offset := x.Tjmp; len.typ := OPT.linttyp;
		IF len.mode = Reg THEN INC(len.reg, typ^.n + 1)
		ELSIF (len.mode IN {Var, VarPar}) & (len.offset >= 0) & (len.offset < 64) THEN (* Reg *) INC(len.offset, typ^.n + 1)
		ELSE INC(len.offset, typ^.n*4 + 4)
		END
	END LenDesc;
	
	PROCEDURE Size*(VAR x, size: Item; rt: LONGINT; typ: OPT.Struct);	(* size := SIZE(x), x of type typ *)
		VAR len: Item;
	BEGIN
		IF typ^.comp # DynArr THEN size.mode := Con; size.offset := typ^.size
		ELSE Size(x, size, rt, typ^.BaseTyp); LenDesc(x, len, typ); Mul(size, len, rt)
		END
	END Size;
	
	PROCEDURE SaveRegs(r, f: SET; offset: LONGINT; VAR size: LONGINT);
		VAR i, s: LONGINT; rg, sp: Item;
	BEGIN i := 32-FPRegDist; s := 0;
		WHILE i >= 0 DO
			IF i IN f THEN
				rg.mode := Reg; rg.reg := i + 32; sp.mode := Based; sp.reg := SP; sp.offset := offset;
				Move(sp, rg, LReal); INC(offset, 8); INC(s, 8)
			END ;
			DEC(i, FPRegDist)
		END ;
		i := 31;
		WHILE i >= 0 DO
			IF i IN r THEN
				rg.mode := Reg; rg.reg := i; sp.mode := Based; sp.reg := SP; sp.offset := offset;
				Move(sp, rg, LInt); INC(offset, 4); INC(s, 4)
			END ;
			DEC(i)
		END ;
		size := s + s MOD 8
	END SaveRegs;
	
	PROCEDURE RestoreRegs(r, f: SET; offset, base: LONGINT; VAR size: LONGINT);
		VAR i, s: LONGINT; rg, sp: Item;
	BEGIN i := 32-FPRegDist; s := 0;
		WHILE i >= 0 DO
			IF i IN f THEN
				rg.mode := Reg; rg.reg := i + 32; sp.mode := Based; sp.reg := base; sp.offset := offset;
				AddUpperToBase(sp); base := sp.reg; offset := sp.offset; sp.typ := OPT.lrltyp;
				Move(rg, sp, LReal); INC(offset, 8); INC(s, 8)
			END ;
			DEC(i, FPRegDist)
		END ;
		i := 31;
		WHILE i >= 0 DO
			IF (i IN r) THEN
				rg.mode := Reg; rg.reg := i; sp.mode := Based; sp.reg := base; sp.offset := offset;
				AddUpperToBase(sp); base := sp.reg; offset := sp.offset; sp.typ := OPT.linttyp;
				Move(rg, sp, LInt); INC(offset, 4); INC(s, 4)
			END ;
			DEC(i)
		END ;
		size := s + s MOD 8
	END RestoreRegs;

	PROCEDURE Enter*(proc: OPT.Object; calleeUsed: RegSet);
		VAR par: OPT.Object;
	BEGIN (* IProc ? *)
		callArea := 0; dynArrCopied := FALSE;
		adjlx := 0; lacx := 0; thisProc := -MaxEntryCode;
		calleesUsedR := calleeUsed.r; calleesUsedF := calleeUsed.f;
		IF InterProcInf THEN
			mayBeUsedR := CallerSavedR + CalleeSavedR - calleeUsed.r;
			mayBeUsedF := CallerSavedF + CalleeSavedF - calleeUsed.f
		END ;
		locUsedR := {}; locUsedF := {}; tempLiveR := {}; tempLiveF := {};
		permLiveR := {}; permLiveF := {}; frozenR := {};
		curshiftx := NoShift;
		IF proc = NIL THEN (* module *)
			NoFP := TRUE; LeafProc := FALSE
		ELSE
			par := proc^.link;
			WHILE par # NIL DO
				IF (par^.mode = Var) & (par^.typ^.comp = DynArr) THEN dynArrCopied := TRUE END ;
				par := par^.link
			END ;
			LeafProc := proc^.leaf;
			NoFP := ~dynArrCopied & (proc^.conval^.intval - proc^.conval^.intval2 <= MaxLittleFrame);
			INC(proc^.adr, LONG(pc));	(* do not destroy mthd no *)
			FixBranches(proc)
		END ;
		thisProc := pc; INC(pc, MaxEntryCode); curshiftx := shiftx
	END Enter;
	
	PROCEDURE Exit*(proc: OPT.Object; VAR calleeUsed: RegSet; VAR pcOffset: INTEGER);
		VAR i, j, savedPC, shift: INTEGER; sp, fp, y, r3, sl: Item;
				instr, spdisp, offset, varSize, calleeSize, dummy: LONGINT;
				saveR, saveF: SET; openProc: BOOLEAN;
	BEGIN
		calleeUsed.r := locUsedR + calleesUsedR; calleeUsed.f := locUsedF + calleesUsedF;
		IF proc = NIL THEN (* module *)
			openProc := TRUE; varSize := 0
		ELSE
			openProc := (proc^.mode = XProc) (* exported or assigned *) OR (alreadyCalled IN proc^.conval^.setval);
			varSize := proc^.conval^.intval2
		END ;
		IF ~InterProcInf OR openProc THEN
			saveR := calleeUsed.r*CalleeSavedR; saveF := calleeUsed.f*CalleeSavedF;
			calleeUsed.r := calleeUsed.r*CallerSavedR; calleeUsed.f := calleeUsed.f*CallerSavedF
		ELSE
			saveR := {}; saveF := {}
		END ;
		IF dynArrCopied THEN code[resCallArea] := IMM*(code[resCallArea] DIV IMM) + (-callArea) MOD IMM END ;
		(* entry code: *)
		savedPC := pc; pc := thisProc; curshiftx := NoShift;
(* now passed on stack by caller
		IF (OPM.Dir="mips/") & (proc # NIL) & (slNeeded IN proc^.conval^.setval) THEN	(* static link in r3 ToDo: move to caller to save R3 *)
			r3.mode := Reg; r3.reg := 3; sl.mode := Based; sl.reg := SP; sl.offset := 0; Move(sl, r3, LInt)
		END ;
*)
		IF ~LeafProc THEN INCL(saveR, RA) END ;
		IF ~NoFP THEN INCL(saveR, FP) END ;
		calleeSize := 0; i := 0;
		WHILE i < 32 DO
			IF i IN saveF THEN INC(calleeSize, 8) END ;
			INC(i, FPRegDist)
		END ;
		i := 0;
		WHILE i < 32 DO
			IF i IN saveR THEN INC(calleeSize, 4) END ;
			INC(i)
		END ;
		INC(calleeSize, calleeSize MOD 8);	(* +0 or +4 *)
		frameSize := calleeSize - varSize + callArea;
		IF dynArrCopied THEN spdisp := calleeSize - varSize ELSE spdisp := frameSize END ;
		sp.mode := Reg; sp.reg := SP;
		IF ~NoFP & (spdisp >= 8000H) THEN y.mode := Reg; y.reg := T1; Move(y, sp, LInt)
		END ;
		y.mode := Con; y.offset := spdisp; Add(sp, y, SP, TRUE);
		IF dynArrCopied THEN offset := 0 ELSE offset := callArea END ;
		SaveRegs(saveR, saveF, offset, dummy);
		IF ~NoFP THEN
			IF spdisp >= 8000H THEN fp.mode := Reg; fp.reg := FP; y.mode := Reg; y.reg := T1; Move(fp, y, LInt)
			ELSE sp.mode := Reg; sp.reg := SP; y.mode := Con; y.offset := spdisp; Add(sp, y, FP, FALSE)
			END
		ELSE i := 0;
			WHILE i < lacx DO
				j := localAccess[i]; INC(i); instr := code[j];
				code[j] := (instr DIV IMM)*IMM + (instr + frameSize) MOD IMM
			END
		END ;
		shift := thisProc + MaxEntryCode - pc; pcOffset := shift;
		i := 0;
		WHILE i < adjlx DO
			j := adjustLink[i]; INC(i); instr := code[j];
			code[j] := (instr DIV IMM)*IMM + (instr + shift) MOD IMM; 
		END ;
		shiftTab[shiftx] := shift; INC(shiftx);
		i := thisProc + MaxEntryCode;
		WHILE i < savedPC DO code[i - shift] := code[i]; INC(i) END ;
		pc := savedPC - shift;
		(* exit code: *)
		IF NoFP THEN RestoreRegs(saveR, saveF, callArea, SP, dummy)
		ELSE
			fp.mode := Reg; fp.reg := FP; y.mode := Reg; y.reg := T0; Move(y, fp, LInt);
			RestoreRegs(saveR, saveF, varSize - calleeSize, T0, dummy)
		END ;
		sp.mode := Reg; sp.reg := SP;
		IF NoFP & (frameSize >= 8000H) THEN y.mode := Con; y.offset := frameSize; Add(sp, y, SP, FALSE) END ;
		PutR(JR, 0, RA, 0);	(* IProc ? *)
		IF ~NoFP THEN y.mode := Reg; y.reg := T0; Move(sp, y, LInt)
		ELSE
			IF (frameSize > 0) & (frameSize < 8000H) THEN y.mode := Con; y.offset := frameSize; Add(sp, y, SP, FALSE)
			ELSE Put(NOP)
			END
		END ;
		saved.r := saveR; saved.f := saveF;
	END Exit;
	
	PROCEDURE SaveRegisters*(calleeUsed: RegSet; argSize: LONGINT; VAR saved, live: RegSet);	(* argSize aligned to 8 *)
		VAR sp, ext: Item; saveSize, patch: LONGINT;
	BEGIN
		saved.r := (tempLiveR + permLiveR)*calleeUsed.r; live.r := tempLiveR;
		saved.f := (tempLiveF + permLiveF)*calleeUsed.f; live.f := tempLiveF;
		saveSize := 0; patch := 0;
		IF (saved.r # {}) OR (saved.f # {}) THEN (* something to save *)
			IF RegsSaved THEN	(* extend stack *)
				sp.mode := Reg; sp.reg := SP;
				ext.mode := Con; ext.offset := 1;	(* 1 to be patched *)
				Add(sp, ext, SP, TRUE);
				patch := pc-1
			ELSE RegsSaved := TRUE
			END ;
			SaveRegs(saved.r, saved.f, argSize, saveSize);
			tempLiveR := tempLiveR - saved.r; tempLiveF := tempLiveF - saved.f
		END ;
		INC(saveSize, argSize);
		IF saveSize > callArea THEN callArea := saveSize END ;
		IF patch # 0 THEN
			code[patch] := IMM*(code[patch] DIV IMM) + (-saveSize) MOD IMM;
			INC(stackExt, saveSize)
		END
	END SaveRegisters;

	PROCEDURE RestoreRegisters*(VAR x: Item; argSize: LONGINT; saved, live: RegSet);
		VAR y, sp, ext: Item; rt, rx, saveSize: LONGINT; f: SHORTINT;
	BEGIN
		tempLiveR := live.r; tempLiveF := live.f;
		IF x.typ # OPT.notyp THEN
			x.mode := Reg; f := x.typ^.form; rt := -1; 
			IF f IN {Real, LReal} THEN rx := RRF; INCL(tempLiveF, RRF-32);
				IF RRF-32 IN saved.f THEN GetF(TempReg, rt) END
			ELSE rx := RRI; INCL(tempLiveR, RRI);
				IF RRI IN saved.r THEN GetR(TempReg, rt) END
			END ;
			IF rt # -1 THEN y.mode := Reg; y.reg := rx; x.reg := rt; Move(x, y, f)
			ELSE x.reg := rx
			END ;
		END ;
		IF (saved.r # {}) OR (saved.f # {}) THEN (* something to restore *)
			RestoreRegs(saved.r, saved.f, argSize, SP, saveSize);
			IF stackExt = 0 THEN
				RegsSaved := FALSE
			ELSE
				INC(saveSize, argSize);
				sp.mode := Reg; sp.reg := SP;
				ext.mode := Con; ext.offset := saveSize;
				Add(sp, ext, SP, FALSE);
				DEC(stackExt, saveSize)
			END
		END
	END RestoreRegisters;

	PROCEDURE OutRefPoint*;
	BEGIN
		OPM.RefW(0F8X); OPM.RefWNum(pc);
		OPM.RefWNum(S.VAL(LONGINT, saved.r));
		OPM.RefWNum(S.VAL(LONGINT, saved.f));
		OPM.RefWNum(frameSize); OPM.RefWNum(callArea)
	END OutRefPoint;
	
	PROCEDURE OutRefName*(VAR name: ARRAY OF CHAR);
		VAR ch: CHAR; i: INTEGER;
	BEGIN i := 0;
		REPEAT ch := name[i]; OPM.RefW(ch); INC(i) UNTIL ch = 0X
	END OutRefName;

	PROCEDURE OutRefs*(obj: OPT.Object);
		VAR f: SHORTINT;
	BEGIN
		IF obj # NIL THEN
			OutRefs(obj^.left);
			IF (obj^.mode = Var) OR (obj^.mode = VarPar) THEN
				f := obj^.typ^.form;
				IF (f IN {Byte .. Set, Pointer, ProcTyp})
					OR (obj^.typ^.comp = Array) & (obj^.typ^.BaseTyp^.form = Char) THEN
					IF obj^.mode = Var THEN OPM.RefW(1X) ELSE OPM.RefW(3X) END ;
					IF obj^.typ^.comp = Array THEN OPM.RefW(0FX)
					ELSE OPM.RefW(CHR(f))
					END ;
					OPM.RefWNum(obj^.linkadr);
					OutRefName(obj^.name)
				END
			END ;
			OutRefs(obj^.right)
		END
	END OutRefs;

	PROCEDURE FindPtrs*(typ: OPT.Struct; adr: LONGINT; VAR tab: ARRAY OF LONGINT; VAR last: INTEGER);
		VAR fld: OPT.Object; btyp: OPT.Struct; i, n: LONGINT; last1: INTEGER;
		
		PROCEDURE Add(adr: LONGINT);
		BEGIN IF last < LEN(tab) THEN tab[last] := adr; INC(last) END
		END Add;

	BEGIN
		IF typ^.form = Pointer THEN Add(adr)
		ELSIF typ^.comp = Record THEN
			btyp := typ^.BaseTyp;
			IF btyp # NIL THEN FindPtrs(btyp, adr, tab, last) END ;
			fld := typ^.link;
			WHILE (fld # NIL) & (fld^.mode = Fld) DO
				IF fld^.name = OPM.HdPtrName THEN Add(fld^.adr + adr)
				ELSE FindPtrs(fld^.typ, fld^.adr + adr, tab, last)
				END ;
				fld := fld^.link
			END
		ELSIF typ^.comp = Array THEN
			btyp := typ^.BaseTyp; n := typ^.n;
			WHILE btyp^.comp = Array DO n := btyp^.n * n; btyp := btyp^.BaseTyp END ;
			IF (btyp^.form = Pointer) OR (btyp^.comp = Record) THEN
				last1 := last; FindPtrs(btyp, adr, tab, last);
				IF last # last1 THEN i := 1;
					WHILE (i < n) & (last < LEN(tab)) DO
						INC(adr, btyp^.size); FindPtrs(btyp, adr, tab, last); INC(i)
					END
				END
			END
		END
	END FindPtrs;

	PROCEDURE WLink(obj: OPT.Object);
		VAR link: INTEGER;
	BEGIN
		link := SHORT(obj.linkadr);
		IF (link # 0) & (obj.x < shiftx) THEN DEC(link, shiftTab[obj.x]); obj.linkadr := link; obj.x := NoShift END ;
		OPM.ObjWNum(link)
	END WLink;

	PROCEDURE WName(VAR name: OPS.Name);
		VAR ch: CHAR; i: INTEGER;
	BEGIN i := 0;
		REPEAT ch := name[i]; OPM.ObjW(ch); INC(i) UNTIL ch = 0X
	END WName;

	PROCEDURE WTDesc(typ: OPT.Struct);
		VAR btyp: OPT.Struct; nofinhmth, nofnewmeth, nofptr, i: INTEGER;
			ptrTab: ARRAY OPM.MaxPtr + 1 OF LONGINT;
			NewMthTab: ARRAY 256 OF OPT.Object;

		PROCEDURE FindNewMths(obj: OPT.Object);
		BEGIN
			IF obj # NIL THEN
				FindNewMths(obj^.left);
				IF obj^.mode = TProc THEN NewMthTab[nofnewmeth] := obj; INC(nofnewmeth) END ;
				FindNewMths(obj^.right)
			END
		END FindNewMths;
			
	BEGIN
		IF typ^.ref >= 0 THEN
			btyp := typ^.BaseTyp;
			typ^.ref := -nofdesc-1; INC(nofdesc);
			OPM.ObjW(8X); WName(typ^.strobj^.name);
			IF typ^.strobj^.name = "" THEN OPT.FPrintStr(typ); OPM.ObjWNum(typ^.pvfp) END ;
			WLink(typ^.strobj); OPM.ObjWNum(typ^.size);
			IF btyp = NIL THEN nofinhmth := 0; OPM.ObjWNum(-1)
			ELSE nofinhmth := SHORT(btyp^.n);
				OPM.ObjWNum(btyp^.mno); WName(btyp^.strobj^.name);
				IF btyp^.strobj^.name = "" THEN OPT.FPrintStr(btyp); OPM.ObjWNum(btyp^.pvfp) END
				(* extension table of base td copied by loader *)
			END ;
			OPM.ObjWNum(typ^.n); (* total nof method *)
			OPM.ObjWNum(nofinhmth); (* nof of inherited method *)
			nofnewmeth := 0; FindNewMths(typ^.link);
			OPM.ObjWNum(nofnewmeth);
			nofptr := 0; FindPtrs(typ, 0, ptrTab, nofptr);
			IF nofptr > OPM.MaxPtr THEN OPM.err(221) END ;
			OPM.ObjWNum(nofptr);
			WHILE nofnewmeth > 0 DO DEC(nofnewmeth);
				OPM.ObjWNum(NewMthTab[nofnewmeth]^.adr DIV 10000H);	(*mthno*)
				OPM.ObjWNum(NewMthTab[nofnewmeth]^.adr MOD 10000H)	(*pc*)
			END ;
			i := 0;
			WHILE i < nofptr DO OPM.ObjWNum(ptrTab[i]); INC(i) END ;
		END
	END WTDesc;

	PROCEDURE OutCode*;
		VAR i, nofexp, nofcom, nofptr: INTEGER;
			obj: OPT.Object;
			ptrTab: ARRAY OPM.MaxGPtr + 1 OF LONGINT;
			ComTab: ARRAY MaxComs OF OPT.Object;

		PROCEDURE WriteName(VAR name: OPS.Name);
			VAR i: INTEGER; ch: CHAR;
		BEGIN i := 0;
			REPEAT ch := name[i]; OPM.ObjW(ch); INC(i)
			UNTIL ch = 0X
		END WriteName;

		PROCEDURE Export(obj: OPT.Object);

			PROCEDURE WStruct(obj: OPT.Object);
				VAR strobj: OPT.Object; typ: OPT.Struct;
			BEGIN
				typ := obj^.typ; strobj := typ^.strobj;
				IF (strobj = obj) & (typ^.form = Comp) THEN	(* not an alias *)	ASSERT(obj^.typ^.mno = 0);
					IF (strobj^.name # "") & (typ^.ref # OPM.MaxStruct) THEN	(* named and exported type *)
						INC(nofexp, 2);	(* 2 entries in module desc, pbfp and pvfp *)
						OPM.ObjW(6X); WName(strobj^.name); OPT.FPrintStr(typ);
						OPM.ObjWNum(typ^.pbfp); OPM.ObjWNum(typ^.pvfp)
					END ;
					IF typ^.comp = Record THEN WTDesc(obj^.typ) END
				END
			END WStruct;

		BEGIN
			IF obj # NIL THEN
				Export(obj^.left);
				IF obj^.history # removed THEN
					IF obj^.vis # internal THEN OPT.FPrintObj(obj);
						IF obj^.mode = Con THEN INC(nofexp);
							OPM.ObjW(1X); WName(obj^.name); OPM.ObjWNum(obj^.fprint)
						ELSIF obj^.mode = Typ THEN INC(nofexp);
							OPM.ObjW(2X); WName(obj^.name); OPM.ObjWNum(obj^.fprint); WStruct(obj)
						ELSIF obj^.mode = Var THEN INC(nofexp);
							OPM.ObjW(3X); WName(obj^.name); OPM.ObjWNum(obj^.fprint); OPM.ObjWNum(obj^.adr);
							FindPtrs(obj^.typ, obj^.adr, ptrTab, nofptr)
						ELSIF obj^.mode IN {XProc, IProc} THEN INC(nofexp);
							OPM.ObjW(4X); WName(obj^.name); OPM.ObjWNum(obj^.fprint); OPM.ObjWNum(obj^.adr);
							IF obj^.linkadr # 0 (*assigned*) THEN OPM.ObjW(9X); OPM.ObjWNum(obj^.adr); WLink(obj) END ;
							IF (obj^.link = NIL) & (obj^.typ = OPT.notyp) THEN	(*command*)
								IF nofcom < MaxComs THEN ComTab[nofcom] := obj; INC(nofcom)
								ELSE OPM.err(232); nofcom := 0
								END
							END
						ELSIF obj^.mode = CProc THEN INC(nofexp);
							OPM.ObjW(5X); WName(obj^.name); OPM.ObjWNum(obj^.fprint)
						END
					ELSIF obj^.mode = Typ THEN WStruct(obj)
					ELSIF obj^.mode = Var THEN FindPtrs(obj^.typ, obj^.adr, ptrTab, nofptr)
					ELSIF (obj^.mode IN {XProc, IProc}) & (obj^.linkadr # 0) THEN	(* assigned *)
						OPM.ObjW(9X); OPM.ObjWNum(obj^.adr); WLink(obj)
					END
				END ;
				Export(obj^.right)
			END
		END Export;

		PROCEDURE Use(obj: OPT.Object);
			VAR typ: OPT.Struct; strobj: OPT.Object;
		BEGIN
			IF obj # NIL THEN
				Use(obj^.left);
				IF obj^.used THEN OPT.FPrintObj(obj);
					IF obj^.mode = Con THEN
						OPM.ObjW(1X); WName(obj^.name); OPM.ObjWNum(obj^.fprint)
					ELSIF obj^.mode = Typ THEN
						OPM.ObjW(2X); WName(obj^.name); OPM.ObjWNum(obj^.fprint)
					ELSIF obj^.mode = Var THEN
						OPM.ObjW(3X); WName(obj^.name); OPM.ObjWNum(obj^.fprint); WLink(obj)
					ELSIF obj^.mode IN {XProc, IProc} THEN
						OPM.ObjW(4X); WName(obj^.name); OPM.ObjWNum(obj^.fprint); WLink(obj)
					ELSIF obj^.mode = CProc THEN
						OPM.ObjW(5X); WName(obj^.name); OPM.ObjWNum(obj^.fprint)
					END
				END ;
				IF obj^.mode = Typ THEN typ := obj^.typ; strobj := typ^.strobj;
					IF (typ^.form = Comp) & (strobj = obj) THEN OPT.FPrintStr(typ);
						IF strobj^.name # "" THEN	(* not only Record, e.g. non-exported dereferenced external array *)
							IF typ^.pvused THEN OPM.ObjW(7X); WName(strobj^.name); OPM.ObjWNum(typ^.pvfp);
								IF obj^.history = inconsistent THEN OPT.FPrintErr(obj, 249) END
							ELSIF typ^.pbused THEN OPM.ObjW(6X); WName(strobj^.name); OPM.ObjWNum(typ^.pbfp)
							END
						(* ELSE fp already checked *)
						END ;
						IF (typ^.comp = Record) & (strobj^.linkadr # 0) THEN
							OPM.ObjW(8X); WName(strobj^.name);
							IF strobj^.name = "" THEN OPM.ObjWNum(typ^.pvfp) END ;
							WLink(strobj)
						END
					END
				END ;
				Use(obj^.right)
			END
		END Use;

	BEGIN
		IF pc MOD 2 = 1 THEN Put(NOP) END ;
		i := (-conx) MOD 8;
		WHILE i > 0 DO constant[conx] := 0X; INC(conx); DEC(i) END ;
	(*HeaderBlk*)
		nofexp := 0; nofdesc := 0; nofcom := 0; nofptr := 0;
		OPM.ObjWNum(OPT.nofGmod-1); WLink(KNewRec); WLink(KNewSys); WLink(KNewArr);
		WLink(GlobData); OPM.ObjWNum(-sb); OPM.ObjWNum(conx); OPM.ObjWNum(pc); WriteName(OPT.SelfName);
	(*ImpBlk*)
		OPM.ObjW(81X); i := 1;
		WHILE i < OPT.nofGmod DO WriteName(OPT.GlbMod[i].name); INC(i) END ;
	(*ExpBlk*)
		OPM.ObjW(82X);
		Export(OPT.topScope^.right);	(* export objects and collect commands and pointers*)
		IF nofptr > OPM.MaxGPtr THEN OPM.err(222) END ;
		OPM.ObjW(0X);
	(*CmdBlk*)
		OPM.ObjW(83X); i := 0;
		WHILE i < nofcom DO
			obj := ComTab[i]; WriteName(obj^.name); OPM.ObjWNum(obj^.adr); INC(i)
		END ; 
	(*PtrBlk*)
		OPM.ObjW(84X); i := 0;
		WHILE i < nofptr DO OPM.ObjWNum(ptrTab[i]); INC(i) END ;
	(*ConstBlk*)
		OPM.ObjW(87X); OPM.ObjWBytes(constant, conx);
	(*CodeBlk*)
		OPM.ObjW(88X); i := 0;
		WHILE i < pc DO OPM.ObjWLInt(code[i]); INC(i) END ;
	(*UseBlk*)
		OPM.ObjW(89X); i := 1;
		WHILE i < OPT.nofGmod DO Use(OPT.GlbMod[i].right); OPM.ObjW(0X); INC(i) END;
	(*RefBlk written in OPM.RegisterRefObj*)
		IF OPM.noerr THEN OPM.RegisterRefObj(nofexp, nofdesc, nofcom, nofptr) END;
		OPM.pc:=pc; OPM.sb:=sb;
	END OutCode;

	PROCEDURE Init*(opt: SET);
		CONST intprinf = 6; cendian = 10;
	BEGIN
		InterProcInf := intprinf IN opt;
		pc := 0; level := 0; sb := 0; conx := 0; shiftx := 0; curshiftx := NoShift;
		CodeOvF := FALSE; RegsSaved := FALSE; stackExt := 0;
		KNewRec.linkadr := 0; KNewSys.linkadr := 0; KNewArr.linkadr := 0; GlobData.linkadr := 0
	END Init;

	PROCEDURE Close*;
	END Close;
	
BEGIN
	NEW(KNewRec); NEW(KNewSys); NEW(KNewArr); NEW(GlobData);
	defaultCalleeUsed.r := CallerSavedR;
	defaultCalleeUsed.f := CallerSavedF;
	loadOp[Byte] := LBU;
	loadOp[Bool] := LB;
	loadOp[Char] := LBU;
	loadOp[SInt] := LB;
	loadOp[Int] := LH;
	loadOp[LInt] := LW;
	loadOp[Real] := LWC1;
	loadOp[LReal] := LDC1;
	loadOp[Set] := LW;
	loadOp[String] := NOP;
	loadOp[NilTyp] := NOP;
	loadOp[NoTyp] := LWC0;
	loadOp[ProcTyp] := LW;
	loadOp[Pointer] := LW;
	loadOp[Comp] := LW;
	storeOp[Byte] := SB;
	storeOp[Bool] := SB;
	storeOp[Char] := SB;
	storeOp[SInt] := SB;
	storeOp[Int] := SH;
	storeOp[LInt] := SW;
	storeOp[Real] := SWC1;
	storeOp[LReal] := SDC1;
	storeOp[Set] := SW;
	storeOp[String] := NOP;
	storeOp[NilTyp] := NOP;
	storeOp[NoTyp] := SWC0;
	storeOp[ProcTyp] := SW;
	storeOp[Pointer] := SW;
	storeOp[Comp] := SW;
	COfmt[Byte] := CO + 4*FMT;
	COfmt[Char] := CO + 4*FMT;
	COfmt[SInt] := CO + 4*FMT;
	COfmt[Int] := CO + 4*FMT;
	COfmt[LInt] := CO + 4*FMT;
	COfmt[Real] := CO + 0*FMT;
	COfmt[LReal] := CO + 1*FMT;
END MOPL.
