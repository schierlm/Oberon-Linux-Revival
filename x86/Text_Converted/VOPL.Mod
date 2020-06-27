MODULE VOPL;	(* RC 14.3.90 / 8.9.93 *)	(* object model 9.2.94 *)
(* low level code generator for RISC-V *)
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
	2016-10-12	VOPL finished
	2016-11-15	uncommented code in MergedLinks
	2017-02-11	changed Load const to MOPL version; made Div OBERON compatible

ToDo: remove export of ReleaseR, ReleaseF 
 
*)

	IMPORT OPM:=ROPM, OPS:=ROPS, OPT:=ROPT, S := SYSTEM, Linux0;

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
		pcahead*=0;
		RegSize*=32;	(* integer register size *)
		FPRegDist*=2;
		ZeroTrap=7;

		(* item base modes (=object modes) *)
		Var* = 1; VarPar* = 2; Con* = 3; LProc* = 6; XProc* = 7; CProc* = 9; IProc* = 10; TProc* = 13;
		(* item modes for MIPS R2000 (must not overlap item basemodes,  > 13) *)
		Based* = 14; Cond* = 15; Reg* = 16;
		
		(* register usage *)
		T0*= 5; T1*= 6; T2*=7;	(* temporary registers *)
		ARI*=10; RRI*=10; ARF*=10+32; RRF*=10+32; (* argument reg, Return reg *)
		SP* = 2; FP* = 8; RA* = 1; VirtualFP* = OPM.MaxRegNr + 1;
		ReservedIRegs={0, RA, SP, 3, 4, T0, T1, T2, FP, 9, ARI..ARI+3};

		CallerSavedR = {10..23};	(* without register variables:{ 8..13}; with: 4..17; was: {4..15, 24, 25}; r28 can also be used*)
		CalleeSavedR = {24..31};	(* without register variables:{14..16}; with: 18..25; was: {16..23};*)
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
		Undef = 0; Byte* = 1; Bool* = 2; Char* = 3; SInt* = 4; Int* = 5; LInt* = 6;
		Real* = 7; LReal* = 8; Set* = 9; String* = 10; NilTyp* = 11; NoTyp* = 12;
		Pointer* = 13; ProcTyp* = 14; Comp* = 15;
		intSet* = {SInt..LInt}; realSet* = {Real, LReal};
		
		(* composite structure forms *)
		Basic* = 1; Array* = 2; DynArr* = 3; Record* = 4;
		
		(* object modes *)
		Fld = 4; Typ = 5; Head = 12;
		
		(* module visibility of objects *)
		internal = 0; external = 1; externalR = 2;
		
		(* history of imported objects *)
		inserted = 0; same = 1; pbmodified = 2; pvmodified = 3; removed = 4; inconsistent = 5;

		(* procedure flags (conval^.setval) *)
		hasBody = 1; isRedef = 2; slNeeded* = 3; alreadyCalled (*back-end only *) = 16;

		IMM10= 400H; IMM11= 800H; IMM12=1000H; IMM13=2000H; IMM15=8000H; IMM16 = 10000H; IMM20=100000H;
			(* instruction format *)
		
		(* register usage *)
		TempReg* = 0; VarReg* = 1; FrozenReg* = 2; (* register classes *)
		
		B32=0; (* if 8: use 32bit instructions  on risc-v64*)
		(* RV32I Base opcodes *)
		LUI=37H; AUIPC*=17H; JAL*=6FH; JALR*=67H;
		BEQ*=63H; BNE*=1063H; BLT*=4063H; BGE*=5063H; BLTU*=6063H; BGEU*=7063H;
		LB*=3H; LH*=1003H; LW*=2003H; LBU*=4003H; LHU*=5003H;
		SB*=23H; SH*=1023H; SW*=2023H;
		ADDI*= 13H+B32; SLTI*=2013H; SLTIU*=3013H; XORI*=4013H; ORI*=6013H; ANDI*=7013H;
		SLLI*= 1013H+B32; SRLI*= 5013H+B32; SRAI*=40005013H+B32;
		ADD*= 33H+B32; SUB*=40000033H+B32; SLL*=1033H+B32; SLT*=2033H; SLTU*=3033H; XOR*=4033H; SRL*=5033H+B32; SRA*=40005033H+B32;
		oR*=6033H; AND*=7033H;
		ECALL=73H; SBREAK=100073H;
		NOP* = 13H; (* ADDI  0, 0, 0 *)

		(* RV32M *)
		MUL= 02000033H+B32; MULH=02001033H; MULHSU=02004033H; MULHU=02003033H;
		DIVV=02004033H+B32; DIVU=02005033H+B32; REM=02006033H+B32; REMU=02007033H+B32;

		(* RV32F *)
		FLW=2007H; FSW= 2027H; 
		RDN= 2000H; RM=RDN; (* rounding mode down *)	RNE=0;
		FMADD= RNE+43H; FMSUB=RNE+47H; FNSUB=RNE+4BH; FNMADD=RNE+4FH;
		FADD*= RNE+53H; FSUB*= RNE+08000053H; FMUL*= RNE+10000053H; FDIV*=RNE+18000053H;
		FEQ*= 0A0002053H; FLT*= 0A0001053H; FLE*=0A0000053H;
		FCVTWF*=RM+0C0000053H; FMVXS*=0E0000053H; FCVTFX*=RM+0D0000053H; FMVSX*= 0F0000053H;
		FSGNJS*= 20000053H; FMV*=FSGNJS; FSGNJN*= 20001053H; FNEG*=FSGNJN; FSGNJX= 20002053H; FABS*=FSGNJX;
		
		(* RV32D*)
		FLD*=3007H; FSD*= 3027H; 
		fmtD=1000000H;	(* computational instructions are derived from RV32F wit fmt= fmtD *)
		FCVTSD*= RM+40100053H;	FCVTDS*= RM+42000053H;
		FCVTWD*= RM+0C2000053H;	FCVTDW*= RM+0D2000053H;
	
		XTRAP*=702BH;	(* custom extension to get SIGILL, trap no. starts at bit 15 *)
(*
		(* RV64I *)
		LWU*= 6003H;
*)
		(* MIPS R2000 = RISC-V implementation restrictions *)
		CodeLength =  32000; (* words *)
		CodeLim = CodeLength - 500;
		MaxEntryCode = 64;
		ConstLength = 5000;
		MaxComs = 128;
		MaxExts = 15;
		MaxLittleFrame = 512; (* 4096 - 256 (* callee-saved *) - 256 (* arguments *) - 1536 (* stack extensions *);*)

		NoShift = MAX(INTEGER);

	VAR
		locUsedR, calleesUsedR, mayBeUsedR, tempLiveR, permLiveR, frozenR: SET;	(* r IN frozenR => r IN tempLiveR *)
		locUsedF, calleesUsedF, mayBeUsedF, tempLiveF, permLiveF: SET;
		saved: RegSet;
		thisProc: INTEGER;
		NoFP, RegsSaved: BOOLEAN;
		frameSize, callArea, stackExt: LONGINT;
		loadOp, storeOp: ARRAY 16 OF INTEGER;
		conx, adjlx, lacx, shiftx, curshiftx: INTEGER;
		CodeOvF: BOOLEAN;
		code:  ARRAY CodeLength OF LONGINT;
		constant: ARRAY ConstLength OF CHAR;
		adjustLink: ARRAY 1024 OF INTEGER;
		localAccess: ARRAY 4096 OF INTEGER;
		shiftTab: ARRAY 512 OF INTEGER;	(* one for each procedure *)
		nofdesc: INTEGER;

PROCEDURE PutR*(op, rd, rs1, rs2: LONGINT);
BEGIN	code[pc] := op+ASH(rd, 7)+ASH(rs1, 15)+ASH(rs2, 20); INC(pc)
END PutR;

PROCEDURE PutR4*(op, rd, rs1, rs2, rs3: LONGINT);
BEGIN	code[pc] := op+S.LSH(rs3, 27)+ ASH(rd, 7)+ASH(rs1, 15)+ASH(rs2, 20); INC(pc)
END PutR4;

PROCEDURE PutI*( op, rd, rs1, imm: LONGINT);
BEGIN
	IF ASH(imm, -12)# ASH(imm, -11) THEN OPM.err(-909) END;
	code[pc] := op+ASH(rd, 7)+ASH(rs1, 15)+ASH(imm, 20); INC(pc)
END PutI;

PROCEDURE GetSimm(i: LONGINT): LONGINT;	(* in byte *)
BEGIN
	RETURN ASH( ASH(i, -25), 5)+ ASH(i , -7) MOD 20H;
END GetSimm;

PROCEDURE SetSimm( imm: LONGINT): LONGINT;
BEGIN	(* imm in byte *)
	IF ASH(imm, -12)# ASH(imm, -11) THEN OPM.err(-910) END;
	RETURN S.LSH(ASH( imm, -5) MOD 80H , 25)+ ASH( imm MOD 20H, 7);
END SetSimm;

PROCEDURE PutS*( op, val, adr, imm: LONGINT);
BEGIN	code[pc] := op+ASH(val, 20)+ASH(adr, 15)+SetSimm(imm); INC(pc)
END PutS;

PROCEDURE GetSBimm(i: LONGINT): LONGINT;	(* in words *)
BEGIN
	RETURN ASH( ASH(i, -31), 10)+ ASH( ASH(i , -25) MOD 40H , 3)+ ASH(i , -9) MOD 8H+ ASH( ASH(i, -7) MOD 2, 9);
END GetSBimm;

PROCEDURE SetSBimm( imm: LONGINT): LONGINT;	(* imm in words *)
BEGIN	(* imm in words *)
	IF ASH(imm, -11)# ASH(imm, -10) THEN OPM.err(-911); OPM.LogWHex( imm); RETURN 0 END;
	RETURN ASH(ASH( imm, -10), 31)+ASH( ASH( imm, -3) MOD 40H, 25)+ASH(imm MOD 8H, 9)+ ASH( ASH(imm, -9) MOD 2, 7);
END SetSBimm;

PROCEDURE PutSB*( op, rs1, rs2, imm: LONGINT);
BEGIN
	code[pc] := op+ASH(rs1, 15)+ASH(rs2, 20)+ SetSBimm( imm);
	INC(pc)
END PutSB;

PROCEDURE PutU*( op, rd, imm: LONGINT);
BEGIN	code[pc] := op+ASH(rd, 7)+ASH( imm, 12); INC(pc)
END PutU;

PROCEDURE GetUJimm( op: LONGINT): LONGINT;	(* in words *)
BEGIN
	RETURN ASH(ASH( op, -31), 18)+ASH( op, -22) MOD 200H+ASH( ASH(op, -20) MOD 2, 9)+ASH( ASH(op, -12) MOD 100H, 10);
END GetUJimm;

PROCEDURE SetUJimm( imm: LONGINT): LONGINT;	(* imm in words *)
BEGIN
	IF ASH(imm, -19)# ASH(imm, -18) THEN OPM.err(-912) END;
	RETURN ASH(ASH( imm, -18), 31)+ASH( imm MOD 200H, 22)+ASH( ASH(imm, -9) MOD 2, 20)+ASH( ASH(imm, -10) MOD 100H, 12);
END SetUJimm;

PROCEDURE PutUJ*( op, rd, imm: LONGINT);
BEGIN
	code[pc] := op+ASH(rd, 7)+ SetUJimm( imm);
	INC(pc)
END PutUJ;

PROCEDURE PutTrap*( nr: LONGINT);
BEGIN	code[pc] := XTRAP+ASH(nr MOD 256, 15); INC(pc)
END PutTrap;

	PROCEDURE AllocConst(cadr: LONGINT; len: INTEGER; VAR adr: LONGINT; align: SHORTINT);
	BEGIN
		WHILE (conx MOD align) #0 DO constant[conx] := 0X; INC(conx) END ;
		IF conx > ConstLength-255 THEN OPM.err(230); conx := 0 END ;
		adr := conx + 64;
		S.MOVE(cadr, S.ADR(constant[conx]), len);
		INC(conx, len);
	END AllocConst;

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

	PROCEDURE Invert*(VAR instr: LONGINT);
	BEGIN
		IF instr MOD 80H = BEQ THEN
			IF ODD(instr DIV IMM12) THEN DEC( instr, IMM12)
			ELSE INC( instr, IMM12)
			END;
		ELSE OPM.err(-708);
		END;
	END Invert;
		
	PROCEDURE Fixup*(L: Label);	(* enter pc at L, pc > L *)
	VAR c: LONGINT;
	BEGIN
		c:=code[L];
		IF c MOD 80H = JAL THEN	(* rd=0 *)
			code[L] := c MOD 80H + SetUJimm(pc - L -pcahead);
		ELSE OPM.err(-901);
		END;
	END Fixup;

	PROCEDURE FixLink*(L: Label);
		VAR L1: Label; c: LONGINT;
	BEGIN
		IF ~CodeOvF & (L # 0) THEN	(* fix JAL? & Bxx *)
			REPEAT
				L1 := L; c := code[L1];
				IF c MOD 80H = BEQ THEN
					L:= L1+ GetSBimm(c)+1;
					IF (pc-L1>=-1024) & (pc-L1<1024)  THEN
						code[ L1]:= BEQ+ASH( ASH( c,-12) MOD IMM13, 12) +  SetSBimm(pc - L1 -pcahead);
					ELSE
						IF code[L1+1]=NOP THEN
							Invert( c);
							code[ L1]:= BEQ+ASH( ASH( c,-12) MOD IMM13, 12) +  SetSBimm(2);
							code[ L1+1]:= JAL +  SetUJimm(pc - L1 -1-pcahead);
						ELSE OPM.err(-917); OPM.LogWHex( c);
						END;
					END;
				ELSIF c MOD 80H= JAL THEN
					L:= L1+ GetUJimm(c)+1;
					code[ L1]:= c MOD IMM12+ SetUJimm(pc - L1 -pcahead);
				ELSIF c MOD IMM20= JALR THEN OPM.err(-707); (* TRAP no RETURN*)
				ELSE OPM.err(-918); OPM.LogWHex( c);
				END;
			UNTIL L = L1
		END
	END FixLink;
	
	PROCEDURE FixLinkWith*(L, val: Label);
		VAR L1: Label; c: LONGINT;
	BEGIN
		IF ~CodeOvF & (L # 0) THEN
			REPEAT
				L1 := L; c := code[L1];
				IF c MOD 80H = BEQ THEN 
					L:= L1+GetSBimm(c)+1;
					IF ABS(val - L1 -1)>=1024 THEN OPM.err(-922) END;
					code[L1]:= BEQ + ASH( ASH( c,-12) MOD IMM13, 12) +  SetSBimm(val - L1 -1);
				ELSE OPM.err(-903);
				END;
			UNTIL L = L1
		END
	END FixLinkWith;

	PROCEDURE MergedLinks*(L0, L1: Label): Label;
		VAR L2, L3: Label; c: LONGINT;
	BEGIN
		IF ~CodeOvF & (L0 # 0) THEN L2 := L0;
			LOOP
				c := code[L2];
				IF c MOD 80H = BEQ THEN
					L3:= L2+GetSBimm(c)+1;
					IF L3 = L2 THEN EXIT END ;
					L2 := L3
				ELSE OPM.err(-904); OPM.LogWHex( c); EXIT;
				END;
			END;
			IF ABS(L1-L2 -1)>=1024 THEN OPM.err(-923) END;
			code[L2] := BEQ + ASH( ASH( c,-12) MOD IMM13, 12) +  SetSBimm( L1 -1- L2);
			RETURN L0
		ELSE RETURN L1
		END
	END MergedLinks;

	PROCEDURE FixBranches(proc: OPT.Object);	(* don't fix proc assign *)
		VAR L, L1: Label; c: LONGINT;
	BEGIN
		L := proc.linkadr;
		IF ~CodeOvF & (L # 0) THEN
			IF proc.x < shiftx THEN DEC(L, LONG(shiftTab[proc.x])); proc.x := NoShift END ;
			REPEAT
				L1 := L; c := code[L1];
				IF c MOD 80H = BEQ  THEN
					L := L1 + GetSBimm(c) + 1;
					IF ABS(pc-L1)>=1024 THEN OPM.err(-924) END;
					code[L1] := BEQ + ASH( ASH( c,-12) MOD IMM13, 12) +  SetSBimm( pc - L1 -pcahead);
				ELSIF c MOD 80H = JAL THEN	(* forward declared procedure *)
					L := L1 + GetUJimm(c) + 1;
					code[L1] := c MOD IMM12  +  SetUJimm( pc - L1 -pcahead);
				ELSIF c MOD 80H= ADDI THEN	(* interim encoding, procedure var; on RISC-V don't link, use AUIPC *)
					L:=L1 + ASH(c, -15) + 1;					
					code[L1]:= AUIPC+ ASH(ASH(c, -7) MOD 20H, 7)+ ASH( ASH( pc - L1-pcahead, -10)+ ASH(pc - L1-pcahead, -9) MOD 2, 12); 
					code[L1+1] := c MOD IMM15+ASH(ASH(c, -7) MOD 20H, 15)+ASH((pc - L1-pcahead) MOD IMM10, 22);
				ELSE OPM.err(-905); OPM.LogWHex( c);
				END;
			UNTIL L = L1;
		END ;
		proc^.linkadr := 0;
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
		
	PROCEDURE PutCond*(VAR x: Item; loc: Label; locok: BOOLEAN);
		VAR rs, rt: LONGINT;
	BEGIN
		rs := x.reg; rt := x.reg2;
		IF loc = 0 THEN (* end of chain *) loc := -1;
		ELSIF ~locok THEN loc := loc - pc -1;
		END;
		IF loc <-400H THEN
			Invert(x.offset); PutSB(x.offset, rs, rt, 2); PutUJ( JAL,  0, loc -1);
		ELSE
			PutSB(x.offset, rs, rt, loc);
		END;
		ReleaseR(rs); ReleaseR(rt)
	END PutCond;
	
	PROCEDURE SetLink*(VAR link: LONGINT);
	BEGIN
		IF link = 0 THEN link := -1;
		ELSE
			IF link < thisProc + MaxEntryCode THEN adjustLink[adjlx] := pc; INC(adjlx) END;
			link := (link - pc -1);
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
				IF lev <= 0 THEN (* global or extern, Var only and string const*)
					GetR(TempReg, rt);
					PutI(ADDI, rt, Link(x.obj), 0);	(* replaced at load-time by LUI rt, upper adjusted *)
					PutU(x.offset, 0, 0);					(* replaced at load-time by ADDI rt, rt, lower *)
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
	
	PROCEDURE AddUpperToBase(VAR x: Item);	(* x.mode = Based, returned x.offset is sign extended 12 bit *)
		(* the next instruction MUST use returned x.reg as base *)
		VAR offset, base, rt: LONGINT;
	BEGIN
		ASSERT(x.mode = Based, 32); 
		base := x.reg;
		IF base = VirtualFP THEN INC(x.offset, stackExt) END ;
		offset := x.offset;
		IF (offset >= -800H) & (offset < 800H) THEN
			IF base = VirtualFP THEN base := SP; localAccess[lacx] := pc; INC(lacx) END;
		ELSE ASSERT(base # VirtualFP, 33);
			rt := -1; GetR(TempReg, rt); ReleaseR(base);
			PutU(LUI, rt, ASH( offset, -12)+ASH(offset, -11) MOD 2);	(* add 1 if rem is negative!  *)
			IF base # 0 THEN PutR(ADD, rt, rt, base) END;
			base := rt; x.offset := ASH(ASH( offset, Linux0.RegSize-12), 12-Linux0.RegSize);	(* keep sign for range check *)
		END ;
		x.reg := base
	END AddUpperToBase;

	PROCEDURE LoadAddr*(VAR x: Item; rt: LONGINT);	(* returned x.mode = Reg, x.reg # VirtualFP *)
	BEGIN
		Base(x, rt);
		IF (x.offset # 0) OR (x.reg = VirtualFP) THEN
			IF x.reg # VirtualFP THEN ReleaseR(x.reg) END ;
			GetR(TempReg, rt); AddUpperToBase(x);
			PutI(ADDI, rt, x.reg, x.offset); x.reg := rt
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
					PutI(loadOp[f], rt MOD 32, Link(x.obj),  0);	(* interim encoding *)
					PutU(x.offset, 0, 0); x.mode := Reg; x.reg := rt;
				ELSE (* local or intermediate *)
					Base(x, rt); Load(x, rt);
				END
		| VarPar:
				Base(x, rt); Load(x, rt)
		| Con:
				val := x.offset;
				IF val = 0 THEN rt:=0;
				ELSE GetR(TempReg, rt);
					upper := val DIV (IMM12 DIV 2); lower := val MOD IMM12;
					IF (upper = 0) OR (upper = -1) THEN PutI( ORI, rt, 0, ASH( ASH( lower, RegSize-12), 12-RegSize));	(* keep sign of const value *)
					ELSE PutU( LUI, rt, upper DIV 2 +upper MOD 2); 
						IF lower # 0 THEN PutI( ADDI, rt, rt, ASH( ASH( lower, RegSize-12), 12-RegSize)) END;
					END

				END;
				x.mode := Reg; x.reg := rt
		| XProc, IProc:
				GetR(TempReg, rt);
				PutI(ADDI, rt, Link(x.obj), 0);	(* interim encoding *)
				PutU( 0, 0,  0);
				x.mode := Reg; x.reg := rt
		| Based:
				AddUpperToBase(x);
				f := x.typ^.form;
				ReleaseR(x.reg);
				IF f IN realSet THEN GetF(TempReg, rt) ELSE GetR(TempReg, rt) END;
				PutI(loadOp[f], rt MOD 32 , x.reg, x.offset);
				x.mode := Reg; x.reg := rt; 
		| Cond:
				GetR(TempReg, rt);
				IF (x.Tjmp = 0) & (x.Fjmp = 0) THEN	(*	use SLT *)
					IF (x.offset= BLT) THEN	PutR( SLT, rt, x.reg, x.reg2);
					ELSIF (x.offset= BLTU) THEN	PutR( SLTU, rt, x.reg, x.reg2);
					ELSIF (x.offset= BNE) THEN
						IF (x.reg2#0) THEN PutR( XOR, x.reg, x.reg, x.reg2) END;
						PutR( SLTU, rt, 0, x.reg);
					ELSIF (x.offset= BEQ) THEN
						IF (x.reg2#0) THEN PutR( XOR, x.reg, x.reg, x.reg2) END;
						PutI( SLTIU, rt, x.reg, 1);
					ELSIF (x.offset= BGE) THEN PutR( SLT, rt, x.reg, x.reg2); PutI( XORI, rt, rt, -1);
					ELSIF (x.offset= BGEU) THEN PutR( SLTU, rt, x.reg, x.reg2); PutI( XORI, rt, rt, -1);
					ELSE OPM.err( 700);
					END;
				ELSIF (rt=x.reg) & (0=x.reg2) THEN FixLink(x.Fjmp); FixLink(x.Tjmp);	(* we already are bool; too agressive ? *)
				ELSIF   (rt#x.reg) & (rt#x.reg2) & (x.Tjmp = 0) THEN
					PutI( ORI, rt, 0, 1); PutCond(x, 2, TRUE); FixLink(x.Fjmp); PutI( ORI, rt, 0, 0)
				ELSIF  (rt#x.reg) & (rt#x.reg2) & (x.Fjmp = 0) THEN Invert(x.offset);
					PutI( ORI, rt, 0, 0); PutCond(x, 2, TRUE); FixLink(x.Tjmp); PutI(ORI, rt, 0, 1)
				ELSE
					PutCond(x, 3, TRUE); FixLink(x.Fjmp); PutI(ORI, rt, 0, 0); PutUJ(JAL, 0, 2);	(* might be buggy! *)
					FixLink(x.Tjmp); PutI(ORI, rt, 0, 1)
				END;
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
					IF lower >= 64 THEN DEC(lower, 64) END;
					PutI(storeOp[xform], ry MOD 32, Link(x.obj), 0);	(* interim encoding; replaced at load-time by LUI T0, upper adjusted *)
					PutU(lower, 0, 0); 
					IF ry < 32 THEN ReleaseR(ry)
					ELSIF ry < 64 THEN ReleaseF(ry)
					END
				ELSE (* local or intermediate *)
					Base(x, -1); Move(x, y, xform)
				END
		| VarPar:
				Base(x, -1); Move(x, y, xform)
		| Based:
				AddUpperToBase(x); lower := x.offset (*MOD IMM12*);
				ReleaseR(x.reg);
				PutS(storeOp[xform], ry MOD 32, x.reg, lower);
				IF ry < 32 THEN ReleaseR(ry)
				ELSIF ry < 64 THEN ReleaseF(ry)
				END
		| Reg:
				rx := x.reg;
				IF ry # rx THEN
					IF rx < 32 THEN
						IF ry < 32 THEN PutR(oR, rx, 0, ry); ReleaseR(ry)
						ELSE OPM.err(713);
						END
					ELSIF rx < 64 THEN
						IF ry < 32 THEN OPM.err(712);
						ELSE PutR( FSGNJS+ASH(xform DIV LReal, 25), rx MOD 32, ry MOD 32, ry MOD 32);	(* Mov fp *)
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
		PutR(funct, rt, rx, ry);
		RETURN rt
	END PutSPC;
	
	PROCEDURE PutIMM*(op, rt: LONGINT; VAR x: Item; imm: LONGINT): LONGINT;
		VAR rx: LONGINT;
	BEGIN
		Load(x, -1); rx := x.reg; ReleaseR(rx); GetR(TempReg, rt);
		PutI(op, rt, rx, imm);
		RETURN rt
	END PutIMM;
		
	PROCEDURE PutFPA*(func, ft: LONGINT; VAR x, y: Item): LONGINT;	(* x or y may be R0 *)
		VAR fx, fy: LONGINT;
	BEGIN
		Load(x, -1); Load(y, -1); fx := x.reg; fy := y.reg;
		IF fx # 0 THEN ReleaseF(fx) END;
		IF fy # 0 THEN ReleaseF(fy) END;
		IF (func MOD 80H= 53H) & ((ASH(func, -26) MOD 64= 28H) OR ( ASH(func, -26) MOD 64= 30H)) THEN 
			GetR(TempReg, ft); (* Fcompare / FCVTWx *) ASSERT( (ft>=0) & (ft<32));
		ELSE GetF( TempReg, ft); ASSERT( (ft>=32) & (ft<64));
		END;
		ASSERT(((fx = 0) OR (fx > 0)) & ((fy = 0) OR (fy > 31)) );
		PutR( func , ft MOD 32,  fx MOD 32, fy MOD 32);
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
				IF (c <= 7FFH) & (c >= 0FFFFF800H) THEN x.reg := PutIMM(ADDI, rt, x, c);
				ELSE x.reg := PutSPC(ADD, rt, x, y)
				END
			END
		ELSIF sub THEN x.reg := PutSPC(SUB, rt, x, y)
		ELSE x.reg := PutSPC(ADD, rt, x, y)
		END
	END Add;

	PROCEDURE Mul*(VAR x, y: Item; rt: LONGINT);	(* x := x*y *)
		VAR c, ones, shift, pos, r, acc: LONGINT; xc, yc: BOOLEAN;
		
		PROCEDURE Shift(shift, to: LONGINT);
		BEGIN
			IF (acc # 0) & (shift # 0) THEN 
				ReleaseR(acc); GetR(TempReg, to); PutI( SLLI, to, acc, shift); acc := to;
			END
		END Shift;
		
		PROCEDURE Inc(to: LONGINT);
		BEGIN
			IF acc = 0 THEN Load(x, -1); acc := x.reg
			ELSE
				ReleaseR(acc); GetR(TempReg, to); PutR(ADD, to,  acc, x.reg); acc := to
			END
		END Inc;
		
		PROCEDURE Dec(to: LONGINT);
		BEGIN
			IF acc = 0 THEN Load(x, -1) END ;
			ReleaseR(acc); GetR(TempReg, to); PutR( SUB, to,  acc, x.reg); acc := to
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
			PutR(MUL, rt, x.reg, y.reg);
			x.mode:= Reg; x.reg:=rt;
		END
	END Mul;
	
	PROCEDURE Div*(VAR x, y: Item; rt: LONGINT; mod: BOOLEAN);	
	BEGIN
		Load(x, -1); Load(y, -1); 
		ReleaseR(x.reg); GetR(TempReg, rt); ReleaseR(y.reg);
		PutSB(BNE, 0, y.reg, 2);		PutU(XTRAP+ASH( ZeroTrap, 15), 0, 0);	
		IF rt = y.reg THEN rt:=-1; GetR(TempReg, rt) END;
		ASSERT(rt # y.reg);	(* should always be TRUE *)
		IF mod THEN
			PutR( REM, rt, x.reg, y.reg);
			PutSB( BGE, rt, 0, 5);
			PutR( ADD, rt, rt, y.reg);
			PutSB( BGE, y.reg, 0, 3);
			PutR( SUB, rt, rt, y.reg);
			PutR( SUB, rt, rt, y.reg);
		ELSE
			PutR( DIVV, rt, x.reg, y.reg);
			PutR( REM, T0, x.reg, y.reg);
			PutSB( BGE, T0, 0, 4);
			PutI( ADDI, rt, rt, -1);
			PutSB( BGE, y.reg, 0, 2);
			PutI( ADDI, rt, rt, 2);
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
	BEGIN i := 0; s := 0;
		WHILE i <32 DO
			IF i IN f THEN
				rg.mode := Reg; rg.reg := i + 32; sp.mode := Based; sp.reg := SP; sp.offset := offset;
				Move(sp, rg, LReal); INC(offset, 8); INC(s, 8)
			END ;
			INC(i, FPRegDist)
		END ;
		i := 1;
		WHILE i <32 DO
			IF i IN r THEN
				rg.mode := Reg; rg.reg := i; sp.mode := Based; sp.reg := SP; sp.offset := offset;
				Move(sp, rg, LInt); INC(offset, 4); INC(s, 4)
			END ;
			INC(i)
		END ;
		size := s + s MOD 8
	END SaveRegs;
	
	PROCEDURE RestoreRegs(r, f: SET; offset, base: LONGINT; VAR size: LONGINT);
		VAR i, s: LONGINT; rg, sp: Item;
	BEGIN i := 0; s := 0;
		WHILE i <32 DO
			IF i IN f THEN
				rg.mode := Reg; rg.reg := i + 32; sp.mode := Based; sp.reg := base; sp.offset := offset;
				AddUpperToBase(sp); base := sp.reg; offset := sp.offset; sp.typ := OPT.lrltyp;
				Move(rg, sp, LReal); INC(offset, 8); INC(s, 8)
			END ;
			INC(i, FPRegDist)
		END ;
		i := 1;
		WHILE i <32 DO
			IF (i IN r) THEN
				rg.mode := Reg; rg.reg := i; sp.mode := Based; sp.reg := base; sp.offset := offset;
				AddUpperToBase(sp); base := sp.reg; offset := sp.offset; sp.typ := OPT.linttyp;
				Move(rg, sp, LInt); INC(offset, 4); INC(s, 4)
			END ;
			INC(i)
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
		IF dynArrCopied THEN
			IF code[resCallArea] MOD IMM20 =10113H+B32 THEN	(* ADDI sp, sp, 0 from OPC.Enter *)
				code[resCallArea] := 10113H+B32 - callArea * IMM20;
			ELSE OPM.err(920); OPM.LogWHex( code[resCallArea]);
			END;
		END ;
		(* entry code: *)
		savedPC := pc; pc := thisProc; curshiftx := NoShift;
		IF ~LeafProc THEN INCL(saveR, RA) END ;
		IF ~NoFP THEN INCL(saveR, FP) END ;
		calleeSize := 0; i := 0;
		WHILE i < 32 DO
			IF i IN saveF THEN INC(calleeSize, 8) END ;
			INC(i, FPRegDist)
		END ;
		i := 1;
		WHILE i < 32 DO
			IF i IN saveR THEN INC(calleeSize, 4) END ;
			INC(i)
		END ;
		INC(calleeSize, calleeSize MOD 8);	(* +0 or +4 *)
		frameSize := calleeSize - varSize + callArea;
		IF dynArrCopied THEN spdisp := calleeSize - varSize ELSE spdisp := frameSize END ;
		sp.mode := Reg; sp.reg := SP;
		IF ~NoFP & (spdisp >= 800H) THEN y.mode := Reg; y.reg := T1; Move(y, sp, LInt)
		END ;
		y.mode := Con; y.offset := spdisp; Add(sp, y, SP, TRUE);
		IF dynArrCopied THEN offset := 0 ELSE offset := callArea END ;
		SaveRegs(saveR, saveF, offset, dummy);
		IF ~NoFP THEN
			IF spdisp >= 800H THEN fp.mode := Reg; fp.reg := FP; y.mode := Reg; y.reg := T1; Move(fp, y, LInt);
			ELSE sp.mode := Reg; sp.reg := SP; y.mode := Con; y.offset := spdisp; Add(sp, y, FP, FALSE);
			END
		ELSE i := 0;
			WHILE i < lacx DO 
				j := localAccess[i]; INC(i); instr := code[j];
				IF (instr MOD 80H=ADDI) OR (instr MOD 80H DIV 8 = LB DIV 8) THEN
					code[ j]:=instr MOD IMM20+ASH(ASH(instr, -20)+ frameSize, 20);
				ELSIF (instr MOD 80H DIV 8 = SB DIV 8 ) THEN
					code[ j]:= instr MOD 80H + ASH(ASH(instr, -12) MOD IMM13, 12)+ SetSimm( GetSimm(instr)+frameSize);
				ELSIF instr MOD 80H = JAL THEN code[j] := instr MOD IMM12 +  SetUJimm( GetUJimm( instr)+frameSize);
				ELSE OPM.err(-914); OPM.LogWHex( instr);
				END;
			END
		END ;
		shift := thisProc + MaxEntryCode - pc; pcOffset := shift;
		i := 0;
		WHILE i < adjlx DO
			j := adjustLink[i]; INC(i); instr := code[j];
			IF instr MOD 80H = JAL THEN code[j] := instr MOD IMM12 +  SetUJimm( GetUJimm( instr)+shift); 
			ELSIF ( instr MOD 80H = ADDI) OR ( instr MOD 80H DIV 8= LB DIV 8) OR (instr MOD 80H DIV 8 = SB DIV 8) THEN	(* interim encoding *)
				code[j] := instr MOD IMM15 + (instr DIV IMM15+shift)*IMM15;
			ELSE OPM.err( 913); OPM.LogWHex( instr);
			END;
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
		IF NoFP THEN
			IF (frameSize > 0) THEN y.mode := Con; y.offset := frameSize; Add(sp, y, SP, FALSE) END;
		ELSE y.mode := Reg; y.reg := T0; Move(sp, y, LInt)
		END;
		PutI(JALR, 0, RA, 0);	(* IProc ? *)
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
			IF code[patch] MOD IMM20 =10113H+B32 THEN	(* was 0E8E93H ADDI sp, sp, imm  *)
				code[patch] := code[patch] MOD IMM20 - saveSize * IMM20;
				OPM.err(-715);
			ELSE OPM.err(-916); OPM.LogWHex( code[patch]);
			END;
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
		INC(pc, pc MOD 2);
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
	loadOp[Real] := FLW;
	loadOp[LReal] := FLD;
	loadOp[Set] := LW;
	loadOp[String] := NOP;
	loadOp[NilTyp] := NOP;
	loadOp[NoTyp] := 0;
	loadOp[ProcTyp] := LW;
	loadOp[Pointer] := LW;
	loadOp[Comp] := LW;
	storeOp[Byte] := SB;
	storeOp[Bool] := SB;
	storeOp[Char] := SB;
	storeOp[SInt] := SB;
	storeOp[Int] := SH;
	storeOp[LInt] := SW;
	storeOp[Real] := FSW;
	storeOp[LReal] := FSD;
	storeOp[Set] := SW;
	storeOp[String] := NOP;
	storeOp[NilTyp] := NOP;
	storeOp[NoTyp] := 0;
	storeOp[ProcTyp] := SW;
	storeOp[Pointer] := SW;
	storeOp[Comp] := SW;

END VOPL.
