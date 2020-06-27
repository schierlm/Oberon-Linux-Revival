MODULE AOPL;	(* RC 14.3.90 / 8.9.93 *)	(* object model 9.2.94 *)
(* low level code generator for ARMv7 *)
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
	2016-10-28	VOPL finished, starting AOPL	(32bit ARM)
	2017-02-11	made Div OBERON compatible
	2017-04-03	using NEWDATA data layout, single data block for const, vars and code, module.SB is beginning of code	
	2017-05-05	using Div* algorithm from divcnst.pdf from Torbjrn Granlund and Peter L. Montgomery
	2017-06-04	accessing global vars of same module usually with 2 instructions
	2017-06-17	changed AddUpperToBase

ToDo: remove export of ReleaseR, ReleaseF ??

PutTrap can be optimized by putting UDF instruction after code and branching to UDF in case of a trap
 
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
		NEWDATA=TRUE;	(* New data layout; consta @ negative offset to sb; vars directly before code to simplify data access *)

		pcahead*=2;
		RegSize*=32;	(* integer register size *)
		FPRegDist*=1;
		ZeroTrap=10;
		ZeroVal=0;
		ZeroReg*=-1; 

		(* item modes for ARMv7, RISC-V, MIPS R2000 (must not overlap item basemodes in OPT,  > 13) *)
		Based* = 14; Cond* = 15; Reg* = 16;
		
		(* register usage *)
		T0*= 0; T1*= 1; TF0*=0; TF1*=1;	(* temporary registers *)
		ARI*=0; RRI*=0; ARF*=0+32; RRF*=0+32; (* argument reg, Return reg *)
		FP* = 12; SP* = 13; RA* = 14; PC*=15; VirtualFP* = OPM.MaxRegNr + 1;
		ReservedIRegs={ T0, T1, FP, SP, RA, 15..31};

		CallerSavedR = { 2..5, 7};	(* without register variables:{ 8..13}; with: 4..17; was: {4..15, 24, 25}; r28 can also be used*)
		CalleeSavedR = { 6, 8..11};	(* without register variables:{14..16}; with: 18..25; was: {16..23};*)
		CallerSavedF = { 2..9};		(* was {4..19} *)
		CalleeSavedF = { 10..15};	(* was {20..31} *)

	TYPE
		RegSet* = RECORD
			r*, f*: SET
		END ;

(* Items:

	the fields mnolev and typ are set for all modes in OPV.
	mnolev is not set for non-allocated constants.

ARMv7 :
   mode  | reg  (reg2) offset  Tjmp  Fjmp
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
14 Based | r    (reg2) offset              (r may be VirtualFP)
15 Cond  |             CC      Tjmp  Fjmp
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
		softDiv: BOOLEAN;
	
	CONST
		(* structure forms from ROPT.Mod *)
		Undef = 0; Byte* = 1; Bool* = 2; Char* = 3; SInt* = 4; Int* = 5; LInt* = 6;
		Real* = 7; LReal* = 8; Set* = 9; String* = 10; NilTyp* = 11; NoTyp* = 12;
		Pointer* = 13; ProcTyp* = 14; Comp* = 15; Adr=16;
		intSet* = {SInt..LInt}; realSet* = {Real, LReal};
		
		(* composite structure forms *)
		Basic* = 1; Array* = 2; DynArr* = 3; Record* = 4;
				
		(* module visibility of objects *)
		internal = 0; external = 1; externalR = 2;
		
		(* history of imported objects *)
		inserted = 0; same = 1; pbmodified = 2; pvmodified = 3; removed = 4; inconsistent = 5;

		(* procedure flags (conval^.setval) *)
		hasBody* = 1; isRedef* = 2; slNeeded* = 3; alreadyCalled* (*back-end only *) = 16;

		IMM10= 400H; IMM11= 800H; IMM12=1000H; IMM13=2000H; IMM15=8000H; IMM16 = 10000H;
		IMM20=100000H; IMM24=1000000H; IMM28=10000000H; 
			(* instruction format *)
		
		(* register usage *)
		TempReg* = 0; VarReg* = 1; FrozenReg* = 2; (* register classes *)
		
		(* ARMv7 Base opcodes *)
		SETFLAGS*=100000H;	IncAfter*=-1000000H; 
		B*=0EA000000H; BL*=0EB000000H; BX*= 0E12FFF10H; BLX*= 0E12FFF30H;

		EQ*=0H; NE*=10000000H; MI*=40000000H; PL*=50000000H; HI*=80000000H; LS*=90000000H; 
		GE*=0A0000000H; LT*=0B0000000H; GT*=0C0000000H; LE*=0D0000000H; AL*=0E0000000H; NV*=0F0000000H;

		(* load/store imm; *b=based*)
		LSADD*=800000H;	(* add bit *) (*  added index bit 100 0000H ! *)	LSWB*=200000H;
		LDRB*=0E5500000H+LSADD; LDRSB*=0E15000D0H+LSADD; STRB*=0E5400000H+LSADD;
		LDRSH*=0E15000F0H+LSADD; STRH*=0E14000B0H+LSADD;
		LDR*=0E5100000H+LSADD; STR*=0E5000000H+LSADD;
		LDRD = 0E14000D0H+LSADD; STRD = 0E14000F0H+LSADD;	(*  rt mut be even and ~R14 *)
		LDMIA=0E8900000H; STMIA=0E8800000H;
		LDMIAwb=0E8B00000H; STMIAwb=0E8A00000H; STMDBwb=0E9200000H;

		(* register based *)
		LDRBb=0E7500000H+LSADD; LDRSBb=0E11000D0H+LSADD; STRBb=0E7400000H+LSADD;
		LDRSHb=0E11000F0H+LSADD; STRHb=0E10000B0H+LSADD; 
		LDRb=0E7100000H+LSADD; STRb=0E7000000H+LSADD;	(* register based *)

		
		(* AR-Type arithmetic register*)
		IMM=2000000H;
		BIC*=0E1C00000H; ADD*= 0E0800000H; SUB*=0E0400000H; EOR*=0E0200000H; ORR*=0E1800000H; AND*=0E0000000H;
		BICI*=BIC+IMM; ADDI*= ADD+IMM; SUBI*=SUB+IMM; EORI*=EOR+IMM; ORI*=ORR+IMM; ANDI*=AND+IMM; RSBI*= 0E2600000H;

		MOV* = 0E1A00000H; MVN*=0E1E00000H; CMP*=0E1500000H; CMN*=0E1700000H; TEQ=0E1300000H; TST=0E1100000H;
		MOVI*= MOV+IMM; MVNI=MVN+IMM; CMPI*=CMP+IMM; CMNI*=CMN+IMM; MOVT= 0E3400000H; MOVW*= 0E3000000H;

		UBFX*= 0E7E00050H;

		LSLI*= MOV; LSRI*= LSLI+20H; ASRI*=LSLI+40H; RORI*=LSLI+60H;
		LSL*=LSLI+10H; LSR*=LSRI+10H; ASR*=ASRI+10H; ROR*=RORI+10H;

		NOP* = 0E320F000H; (* MSR? *)
		UDF= 0E7F000F0H;

		(* RV32M *)
		MUL*= 0E0000090H;	MLA*=0E0200090H; MLS= 0E0600090H;
		SDIV=0E710F010H;
		SMULL = 0E0C00090H;	SMMUL = 0E750F010H; SMMULR = 0E750F030H; 

		(* VFP *)
		VLDR*=0ED100A00H+LSADD; VSTR*=0ED000A00H+LSADD;
		VLDMIA= 0EC900B00H; VSTMIAwb*= 0ECA00B00H;
		VLDMIAwb*= 0ECB00B00H; VSTMDBwb= 0ED200B00H;
		VADD*= 0EE300A00H; VSUB*= 0EE300A40H; VMUL*= 0EE200A00H; VDIV*=0EE800A00H;
		VNEG*= 0EEB10A40H;	VABS*= 0EEB00AC0H;
		VCVTLR* = 0EEBD0A40H (*-80H*);	(* LONGINT:= ENTIER(REAL) op should be 0 for rounding mode in FPSCR! see page A8-870*)
		VCVTRL*= 0EEB80AC0H;	(* REAL := LONGINT *)
		VCVTSD*= 0EEB70BC0H;	VCVTDS*= 0EEB70AC0H;
		VMOV*=0EEB00B40H;
		VMOVA*= 0EE100A10H;	(* mov float to ARM register; single precision to ARM; A8.8.343  (float, ARM, 0)*)
		VMOVV*=0EE000A10H;	(* mov ARM register to float, single preciosion *)

		VCMP*= 0EEB40A40H;
		VMRS*= 0EEF00A10H;	(* reg=1, rt=15 *)
		VMSR*= 0EEE00A10H;

		(* MIPS R2000 = RISC-V implementation restrictions *)
		CodeLength =  32000; (* words *)
		CodeLim = CodeLength - 500;
		MaxEntryCode = 16;
		ConstLength = 5000;
		MaxComs = 128;
		MaxExts = 15;
		MaxLittleFrame = 127 ; (*255;*) (* on ARM might only work for leaf procedures *)

		NoShift = MAX(INTEGER);

	VAR
		locUsedR, calleesUsedR, mayBeUsedR, tempLiveR, permLiveR, frozenR: SET;	(* r IN frozenR => r IN tempLiveR *)
		locUsedF, calleesUsedF, mayBeUsedF, tempLiveF, permLiveF: SET;
		saved: RegSet;
		thisProc: INTEGER;
		NoFP, RegsSaved: BOOLEAN;
		frameSize, callArea, stackExt: LONGINT;
		loadOp, storeOp, loadOpB, storeOpB: ARRAY 16 OF LONGINT;
		conx, adjlx, lacx, shiftx, curshiftx: INTEGER;
		CodeOvF: BOOLEAN;
		code:  ARRAY CodeLength OF LONGINT;
		constant: ARRAY ConstLength OF CHAR;
		adjustLink: ARRAY 1024 OF INTEGER;
		localAccess: ARRAY 4096 OF INTEGER;
		shiftTab: ARRAY 512 OF INTEGER;	(* one for each procedure *)
		nofdesc: INTEGER;

PROCEDURE PutR*(op, rd, rn, rm: LONGINT);	(* arithmetic operation*)
BEGIN	code[pc] := op+ASH(rd, 12)+ASH(rn, 16)+rm; INC(pc)
END PutR;

PROCEDURE PutM*(op, rd, rn, rm: LONGINT);	(* multiplication operation*)
BEGIN
	ASSERT(rd>=0); ASSERT(rn>=0);ASSERT(rm>=0);
(*	ASSERT(rd#rn);*)
	ASSERT(~(PC IN {rd,rn,rm}));
	code[pc] := op+ASH(rd, 16)+ASH(rm, 8)+rn; INC(pc)
END PutM;

PROCEDURE PutMLA*(op, rd, rn, rm, ra: LONGINT);	(* multiplication operation*)
BEGIN
	ASSERT(rd>=0); ASSERT(rn>=0);ASSERT(rm>=0);
(*	ASSERT(rd#rn);*)
	ASSERT(~(PC IN {rd,rn,rm}));
	code[pc] := op+ASH(rd, 16)+ASH(ra, 12)+ASH(rm, 8)+rn; INC(pc)
END PutMLA;

PROCEDURE PutLS*(op, rt, rn, imm: LONGINT);	(* load/store imm*)
BEGIN
	IF imm <0 THEN DEC(op, LSADD); imm:=-imm END;
	IF (op DIV IMM24 = VLDR DIV IMM24) THEN (*ASSERT(imm <100H*4, 59);*) imm:=imm DIV 4 END;
	IF (op MOD 100H #0) THEN (*ASSERT(imm <100H, 58); *) imm:= imm DIV 10H MOD 10H * 100H +imm MOD 10H END;
	code[pc] := op+ASH(rt MOD 16, 12)+ASH(rn, 16) +imm; INC(pc);
END PutLS;

PROCEDURE PutI*( op, rd, rn, imm: LONGINT);
BEGIN
	ASSERT( rd#PC, 57);
	ASSERT(rn<16, 58);
	ASSERT( imm <1000H, 59);
	code[pc] := op+ASH(rd , 12)+ASH(rn , 16) + imm MOD IMM16; INC(pc);	(* imm is negative for links *)
END PutI;

PROCEDURE PutLink*( op, rx, imm: LONGINT);
BEGIN
	ASSERT( rx#PC, 57);
	ASSERT( ABS(imm) <8000H, 59);
	code[pc] := op+ASH(rx , 16) + imm MOD IMM16; INC(pc);	(* imm is negative for links *)
END PutLink;

PROCEDURE PutB*( op, imm: LONGINT);
BEGIN
	code[pc] := op+ imm MOD IMM24;
	INC(pc)
END PutB;

PROCEDURE PutTrap*( cc, nr: LONGINT);
BEGIN
	IF (nr=17) & (code[pc-1] DIV IMM20 = B DIV IMM20) THEN DEC(pc);	(* OPV.FuncTrap; remove branch, no trap *)
	ELSE
		IF cc#-1 THEN code[pc] := B-AL+cc; INC(pc) END;
		code[pc] := UDF+ nr*100H; INC(pc);
	END;
END PutTrap;

	PROCEDURE AllocConst(cadr, len: LONGINT; VAR adr: LONGINT; align: SHORTINT);
	BEGIN
	IF NEWDATA THEN
		WHILE ((conx-len) MOD align) #0 DO DEC(conx); constant[conx] := 0X; END ;
		IF conx < 255 THEN OPM.err(230); conx := LEN(constant)-1 END ;
		DEC(conx, SHORT(len));
		adr := conx-LEN(constant)+sb;	(* sb is negative *)
		S.MOVE(cadr, S.ADR(constant[conx]), len);
	ELSE
		WHILE (conx MOD align) #0 DO constant[conx] := 0X; INC(conx) END ;
		IF conx > LEN(constant)-255 THEN OPM.err(230); conx := 0 END ;
		adr := conx + 64;
		S.MOVE(cadr, S.ADR(constant[conx]), len);
		INC(conx, SHORT(len));
	END;
	END AllocConst;

	PROCEDURE AllocString*(VAR s: ARRAY OF CHAR; len: LONGINT; VAR adr: LONGINT);
	BEGIN AllocConst(S.ADR(s[0]), len, adr, 4)
	END AllocString;
(*
	PROCEDURE AllocReal*(r: REAL; VAR adr: LONGINT);
	BEGIN AllocConst(S.ADR( r), 4, adr, 4)
	END AllocReal;
*)
	PROCEDURE AllocLReal*(r: LONGREAL; VAR adr: LONGINT);
	BEGIN AllocConst(S.ADR( r), 8, adr, 8)
	END AllocLReal;

	PROCEDURE AllocTypDesc*(typ: OPT.Struct);   (* typ^.comp = Record *)
		VAR obj: OPT.Object; name: OPS.Name;
	BEGIN
		IF (typ^.strobj = NIL) OR (typ^.strobj^.mnolev > 0) THEN OPT.IdFPrint(typ);	(* before deleting name *)
			(* insert a global object of that type, in order to find it when in OutCode *)
			name := "@"; OPT.Insert(name, obj); obj^.name := "";	(* avoid err 1 *)
			obj^.mode := OPT.Typ; obj^.typ := typ; typ^.strobj := obj	(* obj.linkadr needed, obj^.typ^.strobj = obj else alias ! *)
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
		IF ODD(instr DIV IMM28) THEN DEC( instr, IMM28)
		ELSE INC( instr, IMM28)
		END;
	END Invert;
		
	PROCEDURE Fixup*(L: Label);	(* enter pc at L, pc > L *)
	VAR c: LONGINT;
	BEGIN
		c:=code[L];
		IF c DIV (IMM24*2) MOD 8 = B DIV (IMM24*2) MOD 8 THEN
			code[L] := c DIV IMM24*IMM24+ (pc - L -pcahead) MOD IMM24;
		ELSE OPM.err(-901);
		END;
	END Fixup;

	PROCEDURE FixLink*(L: Label);
		VAR L1: Label; c: LONGINT;
	BEGIN
		IF ~CodeOvF & (L # 0) THEN	(* fix BL ? & B *)
			REPEAT
				L1 := L; c := code[L1];
				IF c DIV IMM24 MOD 10H = B DIV IMM24 MOD 10H THEN
					L:= L1+ ASH( S.LSH(c, 8), -8)+1; 
					code[ L1]:= c DIV IMM24*IMM24+ (pc - L1 -pcahead) MOD IMM24;
				ELSE OPM.err(-918); OPM.LogWHex( c); 
				END;
			UNTIL L = L1;
		END;
	END FixLink;
	
	PROCEDURE FixLinkWith*(L, val: Label);
		VAR L1: Label; c: LONGINT;
	BEGIN
		IF ~CodeOvF & (L # 0) THEN
			REPEAT
				L1 := L; c := code[L1];
				IF c DIV IMM24 MOD 10H = B DIV IMM24 MOD 10H THEN 
					L:= L1+ASH(S.LSH(c, 8), -8)+1;
					code[L1]:= c DIV IMM24 * IMM24+  (val - L1 -1) MOD IMM24;
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
				IF c DIV IMM24 MOD 10H = B DIV IMM24 MOD 10H THEN	
					L3:= L2+ASH(S.LSH(c, 8), -8) +1;
					IF L3 = L2 THEN EXIT END ;
					L2 := L3
				ELSE OPM.err(-904); OPM.LogWHex( c); EXIT;
				END;
			END;
			code[L2] := c DIV IMM24 * IMM24+  ( L1 -1-L2) MOD IMM24;
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
				L:=L1 + ASH(S.LSH(c, 16), -16) + 1;
				IF c DIV IMM20= MOVW DIV IMM20 THEN	(* interim encoding, assign procedure var *)
					IF newL = 0 THEN link := -1;
					ELSE link := newL - L1 - 1;
					END ;
					newL := L1;
					code[L1] := c DIV IMM16*IMM16 + link MOD IMM16;
				ELSE (*OPM.err(-921); OPM.LogWHex( code[L1]);*)
					code[L1]:= c DIV IMM24 *IMM24+ (pc - L1 - pcahead) MOD IMM24;
				END ;
			UNTIL L = L1
		END ;
		proc^.linkadr := SHORT(newL)
	END FixBranches;

	PROCEDURE PickR(pool: SET; VAR r: LONGINT): BOOLEAN;	(* TRUE if found *)
		VAR i: LONGINT;
	BEGIN
		pool := pool - ReservedIRegs - tempLiveR - permLiveR;
		IF pool = {} THEN RETURN FALSE END ;
		i := 0;
		WHILE ~(i IN pool) DO INC(i) END;
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
					IF class = FrozenReg THEN INCL(frozenR, rt); END
				ELSE OPM.err(215); rt := 0
				END;
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
			ELSIF class = FrozenReg THEN INCL(tempLiveR, rt); INCL(frozenR, rt);	(* freeze function *)
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
		
	PROCEDURE PutCond*(VAR x: Item; loc: Label);
	BEGIN
		IF loc = 0 THEN (* end of chain *) loc := -1;
		ELSE loc := loc - pc -1;
		END;
		IF x.offset#NV THEN PutB( B-AL+x.offset, loc) END;
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
			sl.mode := OPT.Var; sl.mnolev := level; sl.typ := OPT.linttyp;
			sl.offset := 64; Load(sl, rt);
			WHILE lev > 1 DO DEC(lev);
				sl.mode := Based; sl.offset := ZeroVal; Load(sl, rt)
			END ;
			RETURN sl.reg
		END
	END LoadFP;

	PROCEDURE DecomposeConst*(const : LONGINT; VAR imm: LONGINT) : BOOLEAN;
	(* Tries to decompose a constant into a 8bit unsigned immediate and a rotation, so that imm>>(2*rot)=const *)
	(* returns TRUE if such a combination of (imm,rot) exists *)
	VAR rot: LONGINT; ret: BOOLEAN;
	BEGIN
		imm:=const; rot:=0;
		WHILE (rot<15) & ((imm<0) OR (imm>255)) DO imm:=S.ROT(imm,2); INC(rot) END;
		ret:=(imm>=0) & (imm<=255);
		imm:=imm+rot*100H;
		RETURN ret
	END DecomposeConst;

	PROCEDURE Base*(VAR x: Item; rt: LONGINT);		(* x.mode IN {Var, VarPar, Based}, returned x.mode = Based *)
		VAR lev: SHORTINT; typ: OPT.Struct; offset: LONGINT;
	BEGIN
		IF rt >= 32 THEN rt := -1 END ;
		lev := x.mnolev;
		CASE x.mode OF
		  OPT.Var:
				IF (x.offset >0) & (x.offset < 64) THEN OPM.err(127) END;	(* offset should be zero or adr *)
				IF x.offset >= 64 THEN DEC(x.offset, 64) END ;
				IF lev <= 0 THEN (* global or extern, Var only and string const*)
					GetR(TempReg, rt);
					PutLink(MOVW, rt, Link(x.obj));	(* replaced at load-time by MOVW rt, lower *)
					PutB(x.offset, 0);					(* replaced at load-time by MOVT rt, upper *)
					x.offset := 0; x.reg := rt
				ELSE x.reg := LoadFP(lev, rt)
				END
		| OPT.VarPar:
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

	PROCEDURE AddUpperToBase(VAR x: Item;  form: LONGINT);	(* x.mode = Based, returned x.offset is sign extended 12 bit *)
		(* the next instruction MUST use returned x.reg as base *)
		VAR offset, base, osize, cc, rt: LONGINT;
	BEGIN
		ASSERT(x.mode = Based, 32); 
		base := x.reg;
		IF base = VirtualFP THEN INC(x.offset, stackExt) END ;
		offset := x.offset;
		IF form= Adr THEN osize:= 100H; 
		ELSIF form DIV 2 = SInt DIV 2 THEN osize:=100H;	(* Sint, Int *)
		ELSIF form IN realSet THEN osize:=400H;
		ELSE osize:=1000H;
		END;
		IF ABS(offset) < osize THEN 
			IF base = VirtualFP THEN base := SP; localAccess[lacx] := pc; INC(lacx) END;
		ELSE ASSERT(base # VirtualFP, 33);
			IF  (form=Adr) & DecomposeConst( offset, cc) THEN x.offset:= cc;
			ELSIF  (form=Adr) & DecomposeConst( -offset, cc) THEN x.offset:= -cc;
			ELSE
				rt:=-1; GetR(TempReg, rt); ReleaseR(base); 	(* does not work without "rt:=-1" as rt can be reg variable *)
				IF offset>=0 THEN
					IF DecomposeConst( offset DIV osize*osize, cc) THEN PutI(ADDI, rt, base, cc);
						x.offset:= offset MOD osize;
					ELSE
						PutI(MOVW, rt, offset DIV IMM12 MOD 10H, offset MOD IMM12);
						IF offset DIV IMM16 #0 THEN PutI(MOVT, rt, offset DIV IMM28 MOD 10H, offset DIV IMM16 MOD IMM12) END;
						IF base#ZeroReg THEN PutR(ADD, rt, base, rt) END;
						x.offset := ZeroVal;
					END;
				ELSE offset:=-offset;
					IF DecomposeConst( offset DIV osize*osize, cc) THEN PutI(SUBI, rt, base, cc);
						x.offset:= -offset MOD osize;
					ELSE
						PutI(MOVW, rt, offset DIV IMM12 MOD 10H, offset MOD IMM12);
						IF offset DIV IMM16 #0 THEN PutI(MOVT, rt, offset DIV IMM28 MOD 10H, offset DIV IMM16 MOD IMM12) END;
						IF base#ZeroReg THEN PutR(SUB, rt, base, rt) END;
						x.offset := ZeroVal;
					END;
				END;
				base:=rt;
			END;
		END;
		x.reg := base; 
	END AddUpperToBase;
	
	PROCEDURE LoadAddr*(VAR x: Item; rt: LONGINT);	(* returned x.mode = Reg, x.reg # VirtualFP *)
	BEGIN
		Base(x, rt);
		IF (x.offset # ZeroVal) OR (x.reg = VirtualFP) THEN
			IF x.reg # VirtualFP THEN ReleaseR(x.reg) END;
			GetR( TempReg, rt); AddUpperToBase(x, Adr);
			IF (x.offset>=0)  THEN PutI( ADDI, rt, x.reg, x.offset);	(* must be addi for x.offset=0 because of localAccess *)
			ELSE PutI( SUBI, rt, x.reg, -x.offset);
			END;
			x.reg := rt;
		END ;
		x.mode := Reg; x.typ := OPT.linttyp
	END LoadAddr;

	PROCEDURE Load*(VAR x: Item; rt: LONGINT);	(* returned x.mode = Reg, x.typ must be defined if not Reg*)
		VAR val, lower, cc, rn: LONGINT; f: SHORTINT; y: Item;
	BEGIN
		CASE x.mode OF
		  OPT.Var:
				f := x.typ^.form; lower := x.offset; 
				IF (f#LReal )&(rt>=32) THEN f:= Real END;
				IF (lower >= ZeroVal) & (lower < 64) THEN x.mode := Reg; x.reg := lower
				ELSIF x.mnolev <= 0 THEN	(*  extern<0; global =0 *)
					IF lower >= 64 THEN DEC(x.offset, 64) END;
					IF f IN realSet THEN GetF(TempReg, rt) ELSE GetR(TempReg, rt) END;
					IF x.mnolev = 0 THEN
						cc:=LONG(pc)*4-x.offset+8;
						ASSERT( cc>0, 61);
						rn:=PC;
						IF f IN { Byte, Bool, Char, LInt, Set, ProcTyp, Pointer, Comp} THEN	(* global, pc relative *)
							IF cc>=100000H THEN HALT(80) END;
							IF cc>=1000H THEN PutI( SUBI, T1, PC, 0A00H+cc DIV 1000H); cc:=cc MOD 1000H; rn:=T1 END;
						ELSIF f IN realSet THEN
							IF cc>=40000H THEN HALT(81) END;
							IF cc>=400H THEN PutI( SUBI, T1, PC, 0B00H+cc DIV 400H); cc:=cc MOD 400H; rn:=T1 END;
						ELSE
							IF cc>=10000H THEN PutI( SUBI, T1, PC, 800H+cc DIV 10000H); rn:=T1 END;
							IF cc>=100H THEN PutI( SUBI, T1, rn, 0C00H+cc DIV 100H MOD 100H); cc:=cc MOD 100H; rn:=T1 END;
						END;
						adjustLink[ adjlx]:=pc; INC( adjlx);
						PutLS(loadOp[f]-LSADD, rt , rn, cc);
					ELSE
						PutLink( MOVW, T1, Link(x.obj));				(* must be T1!; address not to rt because of FP; interim encoding, rt<> rn *)
						PutB( x.offset, 0);								(* replaced with MOVT *)
						PutLS(loadOp[f], rt , T1, 0);
					END;

					x.mode := Reg; x.reg := rt; (*x.reg2:=ZeroReg;*)

				ELSE (* local or intermediate *)
					Base(x, rt); Load(x, rt);
				END
		| OPT.VarPar:
				Base(x, rt); Load(x, rt)
		| OPT.Con:
				val := x.offset;
(*				IF val=0 THEN rt:=ZeroReg;	(*fix PutCmp to use ZeroReg !*)
				ELSE*)

					IF (x.typ#NIL) & (x.typ.form=Real) THEN GetF(TempReg, rt);
						PutI(MOVW, T1, val DIV IMM12 MOD 10H, val MOD IMM12);
						val:=val DIV IMM16;
						PutI(MOVT, T1, val DIV IMM12 MOD 10H, val MOD IMM12);
						PutR( VMOVV, T1, rt MOD 32, 0);	(* move to rt *)
					ELSE
						GetR(TempReg, rt);
						IF DecomposeConst( val, cc) THEN PutI(MOVI, rt, 0, cc);
						ELSIF DecomposeConst( -1-val, cc) THEN PutI( MVNI, rt, 0, cc)	
						ELSE
							PutI(MOVW, rt, val DIV IMM12 MOD 10H, val MOD IMM12);
							val:=val DIV IMM16;
							IF val #0 THEN PutI(MOVT, rt, val DIV IMM12 MOD 10H, val MOD IMM12) END;
						END;
					END;
(*				END;*)
				x.mode := Reg; x.reg := rt
		| OPT.XProc, OPT.IProc:
				GetR(TempReg, rt);
				PutLink( MOVW, rt, Link(x.obj) );				(* interim encoding, rt<> rn *)
				PutB( 0, 0);								(* replaced with MOVT *)
				x.mode := Reg; x.reg := rt
		| Based:
				AddUpperToBase(x, x.typ^.form);
				f := x.typ^.form;
				ReleaseR(x.reg);
				IF f IN realSet THEN GetF(TempReg, rt) ELSE GetR(TempReg, rt) END;
				PutLS(loadOp[f], rt, x.reg, x.offset);
				x.mode := Reg; x.reg := rt; 
		| Cond:
				GetR(TempReg, rt);
				cc:=x.offset;
				IF (x.Tjmp = 0) THEN
					IF (x.Fjmp = 0) THEN PutI( MOVI-AL+cc, rt, 0, 1); Invert(cc); PutI( MOVI-AL+cc, rt, 0, 0);
					ELSE PutI( MOVI, rt, 0, 1); PutB( B-AL+cc, 2-pcahead); FixLink(x.Fjmp); PutI( MOVI, rt, 0, 0);
					END;
				ELSIF (x.Fjmp = 0) THEN  Invert(cc); PutI( MOVI, rt, 0, 0); PutB( B-AL+cc, 2-pcahead); FixLink(x.Tjmp); PutI( MOVI, rt, 0, 1);
				ELSE 
					PutB( B-AL+cc, 3-pcahead); FixLink(x.Fjmp); PutI(MOVI, rt, 0, 0); PutB( B, 2-pcahead);
					FixLink(x.Tjmp); PutI(MOVI, rt, 0, 1);
				END;
				x.mode := Reg; x.reg := rt
		| Reg:
		ELSE OPM.err(127); x.mode := Reg; x.reg := 0
		END
	END Load;
	
	PROCEDURE Move*(VAR x, y: Item; xform: SHORTINT);	(* x := y *)
		VAR rx, ry, rn, lower, cc: LONGINT; z: Item;
	BEGIN
		IF x.mode = OPT.Var THEN lower := x.offset;
			IF (lower >= ZeroVal) & (lower < 64) THEN x.mode := Reg; x.reg := lower END
		END ;
		IF y.mode # Reg THEN
			IF x.mode = Reg THEN ry := x.reg ELSE ry := -1 END ;
			Load(y, ry)
		END ;
		ry := y.reg;
		CASE x.mode OF
		  OPT.Var:
				IF x.mnolev <= 0 THEN (* global or extern *)
					IF lower >= 64 THEN DEC(lower, 64) END;
					IF x.mnolev = 0 THEN
						cc:= LONG(pc)*4-lower+8;
						ASSERT( cc>0, 62);
						rn:=PC;
						IF xform IN { Byte, Bool, Char, SInt, LInt, Set, ProcTyp, Pointer, Comp} THEN	(* global, pc relative *)
							IF cc>=100000H THEN HALT(80) END;
							IF cc>=1000H THEN PutI( SUBI, T1, PC, 0A00H+cc DIV 1000H); cc:=cc MOD 1000H; rn:=T1 END;
						ELSIF xform IN realSet THEN
							IF cc>=40000H THEN HALT(81) END;
							IF cc>=400H THEN PutI( SUBI, T1, PC, 0B00H+cc DIV 400H); cc:=cc MOD 400H; rn:=T1 END;
						ELSE
							IF cc>=10000H THEN PutI( SUBI, T1, PC, 800H+cc DIV 10000H); rn:=T1 END;
							IF cc>=100H THEN PutI( SUBI, T1, rn, 0C00H+cc DIV 100H MOD 100H); cc:=cc MOD 100H; rn:=T1 END;
						END;
						adjustLink[ adjlx]:=pc; INC( adjlx);
						PutLS(storeOp[xform]-LSADD, ry , rn, cc);
					ELSE
						PutLink( MOVW, T1, Link(x.obj) );				(* ry might be 0; interim encoding, rt<> rn *)
						PutB( lower, 0);								(* replaced at load-time by MOVT *)
						PutLS(storeOp[xform], ry , T1, 0);
					END;
					IF ry < 32 THEN ReleaseR(ry)
					ELSIF ry < 64 THEN ReleaseF(ry)
					END
				ELSE (* local or intermediate *)
					Base(x, -1); Move(x, y, xform)
				END
		| OPT.VarPar:
				Base(x, -1); Move(x, y, xform)
		| Based:
				AddUpperToBase(x, xform);
				ReleaseR(x.reg);
				PutLS(storeOp[xform], ry MOD 32 , x.reg, x.offset );
				IF ry < 32 THEN ReleaseR(ry)
				ELSIF ry < 64 THEN ReleaseF(ry)
				END
		| Reg:
				rx := x.reg;
				IF ry # rx THEN
					IF rx < 32 THEN
						IF ry < 32 THEN PutR( MOV, rx, 0, ry); ReleaseR(ry)
						ELSE OPM.err(713);
						END
					ELSIF rx < 64 THEN
						IF ry < 32 THEN OPM.err(712);
						ELSE PutR( VMOV, rx MOD 32, 0, ry MOD 32); ReleaseF(ry)	(* Mov fp *)
						END
					ELSE OPM.err(708);
					END
				END
		ELSE OPM.err(127)
		END
	END Move;

	PROCEDURE PutMV*(funct, rt: LONGINT; VAR x: Item): LONGINT;
	BEGIN
		Load(x, -1);
		ReleaseR(x.reg); GetR(TempReg, rt);
		PutR(funct, rt, 0, x.reg);
		RETURN rt
	END PutMV;

	PROCEDURE PutSPC*(funct, rt: LONGINT; VAR x, y: Item): LONGINT;
	BEGIN
		Load(x, -1); Load(y, -1);
		ReleaseR(x.reg); ReleaseR(y.reg); GetR(TempReg, rt);
		PutR(funct, rt, x.reg, y.reg);
		RETURN rt
	END PutSPC;

	PROCEDURE PutSPCS*(funct, rt: LONGINT; VAR x, y: Item): LONGINT;	(* shift *)
	BEGIN
		Load(x, -1); Load(y, -1);
		ReleaseR(x.reg); ReleaseR( y.reg); GetR(TempReg, rt);
		PutR(funct+y.reg*100H, rt, 0, x.reg);
		RETURN rt
	END PutSPCS;
	
	PROCEDURE PutIMM*(op, rt: LONGINT; VAR x: Item; imm: LONGINT): LONGINT;
	BEGIN
		IF (imm#0) OR (rt#SP) OR (op DIV IMM20 =CMPI DIV IMM20) THEN
			Load(x, -1); ReleaseR(x.reg);
			IF op DIV IMM20 #CMPI DIV IMM20 THEN GetR(TempReg, rt) END;
			PutI(op, rt, x.reg, imm);
		END;
		RETURN rt
	END PutIMM;

	PROCEDURE PutIMMS*(op, rt: LONGINT; VAR x: Item; imm: LONGINT): LONGINT;	(* shift immediate *)
	BEGIN
		Load(x, -1); ReleaseR(x.reg); GetR(TempReg, rt);
		PutI(op, rt, 0, ASH(imm, 7)+x.reg);
		RETURN rt
	END PutIMMS;

	PROCEDURE PutFPA0*(func, ft: LONGINT; VAR x: Item): LONGINT;
	BEGIN
		Load(x, -1); ReleaseF(x.reg);
		GetF( TempReg, ft); 
		ASSERT( x.reg>=32, 33 );
		PutR( func , ft MOD 32,  0, x.reg MOD 32);
		RETURN ft
	END PutFPA0;
		
	PROCEDURE PutFPA*(func, ft: LONGINT; VAR x, y: Item): LONGINT;
		VAR fx, fy: LONGINT;
	BEGIN
		Load(y, -1); fy := y.reg; 
		Load(x, -1); fx := x.reg;
		ReleaseF(fx); ReleaseF(fy);
		GetF( TempReg, ft);
		ASSERT( (fx>=32) & (fy >= 32), 33 );
		PutR( func , ft MOD 32,  fx MOD 32, fy MOD 32);
		RETURN ft
	END PutFPA;

	PROCEDURE Add*(VAR x, y: Item; rt: LONGINT; sub: BOOLEAN);	(* x := x+-y *)
		VAR z: Item; c: LONGINT; xc, yc: BOOLEAN;
	BEGIN
		xc := x.mode = OPT.Con; yc := y.mode = OPT.Con;
		IF xc & yc THEN
			IF sub THEN DEC(x.offset, y.offset) ELSE INC(x.offset, y.offset) END;
			RETURN
		END;
		IF xc & ~sub THEN z := x; x := y; y := z; yc := TRUE END;
		IF xc & sub & DecomposeConst(x.offset, c) THEN x.reg :=PutIMM( RSBI, rt, y, c); x.mode:=Reg;
		ELSIF yc THEN
			IF (y.offset # MIN(LONGINT)) & (y.offset < 0) THEN y.offset := -y.offset; sub:=~sub END;
			IF DecomposeConst(y.offset, c) THEN
				IF sub THEN x.reg :=PutIMM( SUBI, rt, x, c);
				ELSE x.reg :=PutIMM( ADDI, rt, x, c);
				END; 
			ELSE
				IF sub THEN x.reg := PutSPC( SUB, rt, x, y);
				ELSE x.reg := PutSPC( ADD, rt, x, y);
				END;
			END;
		ELSIF sub THEN x.reg := PutSPC(SUB, rt, x, y); (*ASSERT(x.reg#ZeroReg, 51);  *)
(*	x.mode must be Reg !
			IF x.reg=ZeroReg THEN x.reg:=PutIMM(RSBI, rt, y, 0); OPM.err(-703);
			ELSIF y.reg=ZeroReg THEN x.reg := PutMV(MOV, rt, x);OPM.err(-704);
			ELSE x.reg := PutSPC(SUB, rt, x, y);
			END;
*)
		ELSE x.reg := PutSPC(ADD, rt, x, y); (*ASSERT(x.reg#ZeroReg, 53);  ASSERT(y.reg#ZeroReg, 54);*)
(*
			IF x.reg=ZeroReg THEN x.reg := PutMV(MOV, rt, y); OPM.err(-705);
			ELSIF y.reg=ZeroReg THEN x.reg := PutMV(MOV, rt, x); OPM.err(-706);
			ELSE x.reg := PutSPC(ADD, rt, x, y);
			END;
*)
		END;

	END Add;

	PROCEDURE Mul*(VAR x, y: Item; rt: LONGINT);	(* x := x*y *)
		VAR c: LONGINT; xc, yc: BOOLEAN; z: Item;	
	BEGIN
(*		ASSERT(x.reg#ZeroReg, 51); ASSERT(y.reg#ZeroReg, 52);*)
(*		IF (x.reg=ZeroReg) OR (y.reg=ZeroReg) THEN x.mode:=OPT.Con; x.offset:=0; RETURN END;*)
		xc := x.mode = OPT.Con; yc := y.mode = OPT.Con;
		IF xc & yc THEN x.offset := x.offset*y.offset;
		ELSIF  xc OR yc THEN
			IF xc THEN z:=x; x := y; y:=z END;
			c := y.offset;
			IF c=0 THEN x.mode:=OPT.Con; x.offset:=0;
			ELSE
				Load(x, -1);
				IF c=1 THEN rt:=x.reg;
				ELSIF c=2 THEN ReleaseR(x.reg); GetR(TempReg, rt); PutI( LSLI, rt, 0, ASH(1, 7)+x.reg); 
				ELSIF c=3 THEN ReleaseR(x.reg); GetR(TempReg, rt); PutI( ADD, rt, x.reg, ASH(1, 7)+x.reg); 
				ELSIF c=4 THEN ReleaseR(x.reg); GetR(TempReg, rt); PutI( LSLI, rt, 0, ASH(2, 7)+x.reg); 
				ELSIF c=5 THEN ReleaseR(x.reg); GetR(TempReg, rt); PutI( ADD, rt, x.reg, ASH(2, 7)+x.reg); 
				ELSIF c=8 THEN ReleaseR(x.reg); GetR(TempReg, rt); PutI( LSLI, rt, 0, ASH(3, 7)+x.reg);
				ELSIF c=10 THEN ReleaseR(x.reg); GetR(TempReg, rt); PutI( LSLI, rt, 0, ASH(1, 7)+x.reg); PutI( ADD, rt, rt, ASH(2, 7)+rt);
				ELSE
					Load(y, -1); GetR(TempReg, rt);	(* don't release before get ??*)
					ReleaseR(x.reg); ReleaseR(y.reg);
					PutM( MUL, rt, x.reg, y.reg);
				END;
				x.mode:= Reg; x.reg:=rt;
			END;
		ELSE
			Load(x, -1); Load(y, -1); GetR(TempReg, rt);	(* don't release before get ??*)
			ReleaseR(x.reg); ReleaseR(y.reg);
			PutM( MUL, rt, x.reg, y.reg);
			x.mode:= Reg; x.reg:=rt;
		END
	END Mul;
	
	PROCEDURE Div*(VAR x, y: Item; rt: LONGINT; mod: BOOLEAN);
	VAR zeroTrap: BOOLEAN; xreg:LONGINT;
	BEGIN
		IF softDiv THEN	(* R0 = R1 DIV R0; R1 = R1 MOD R0 *)
			Load(y, T0); Load(x, T1); (* first load T0 as T1 is used in adress loading *)
			GetR(TempReg, rt);
			PutB( STMDBwb +ASH(SP, 16), 403CH);	(* we need to store LR, so store all used registers *)
			IF y.reg#T0 THEN PutR( MOV, T0, 0, y.reg) END;
			IF x.reg#T1 THEN PutR( MOV, T1, 0, x.reg) END;
			xreg:=-1; GetR( TempReg, xreg);
			PutLink( MOVW, xreg, Link(KNewRec));		(* must not be T0, T1 hold parameters *)
			PutB( MIN(LONGINT)+1, 0);								(* call SoftDiv; replaced with MOVT *)
			PutB( BLX, xreg);
			ReleaseR( xreg);
			PutB( LDMIAwb+ ASH(SP, 16), 403CH);
			IF mod THEN
				IF rt#T1 THEN PutR( MOV, rt, 0, T1) END;
			ELSE
				IF rt#T0 THEN PutR( MOV, rt, 0, T0) END;
			END;
			x.reg:=rt;
		ELSE
			zeroTrap:=(y.mode#OPT.Con);
			IF ~zeroTrap THEN ASSERT(y.offset>0, 52) END;
			Load(x, -1); Load(y, -1); 
			ASSERT(x.reg#ZeroReg, 51); ASSERT(y.reg#ZeroReg, 52);
			GetR(TempReg, rt); ReleaseR(x.reg); ReleaseR(y.reg);
			IF mod & (rt = y.reg) THEN rt:=-1; GetR(TempReg, rt) END;
			ASSERT(rt # y.reg, 53);	(* should always be TRUE *)
			xreg:=x.reg;
			IF rt=x.reg THEN xreg:=T1; PutR( MOV, xreg, 0, x.reg) END;	(* rt can be x.reg *)
			PutR( SUB+ASH(31, 7)+64, T0, x.reg, x.reg);
			PutM( SDIV, rt, T0, y.reg);
			IF zeroTrap THEN PutI( CMPI, 0, y.reg, 0); PutTrap( GT, ZeroTrap) END;	(* result only defined for y>0 *)
			PutR( ADD+ASH(31, 7)+64, rt, rt, xreg);
			IF mod THEN PutMLA( MLS, rt, rt, y.reg, xreg) END;
		END;
		x.reg:=rt;
	END Div;
	
	PROCEDURE LenDesc*(VAR x, len: Item; typ: OPT.Struct);	(* set len to LEN(x, typ^.n), x.typ^.comp = DynArr *)
	BEGIN
		len.mode := x.descmode; len.mnolev := x.mnolev; len.reg := x.reg2; len.offset := x.Tjmp; len.typ := OPT.linttyp;
		IF len.mode = Reg THEN INC(len.reg, typ^.n + 1)
		ELSIF (len.mode IN {OPT.Var, OPT.VarPar}) & (len.offset >= 0) & (len.offset < 64) THEN (* Reg *) INC(len.offset, typ^.n + 1)
		ELSE INC(len.offset, typ^.n*4 + 4)
		END
	END LenDesc;
	
	PROCEDURE Size*(VAR x, size: Item; rt: LONGINT; typ: OPT.Struct);	(* size := SIZE(x), x of type typ *)
		VAR len: Item;
	BEGIN
		IF typ^.comp # DynArr THEN size.mode := OPT.Con; size.offset := typ^.size
		ELSE Size(x, size, rt, typ^.BaseTyp); LenDesc(x, len, typ); Mul( size, len, rt)
		END
	END Size;

	PROCEDURE SetOffset(offset, base: LONGINT);
	VAR cc: LONGINT;
	BEGIN
		IF DecomposeConst( offset, cc) THEN PutI(ADDI, T1, base, cc); 
		ELSIF DecomposeConst( -offset, cc) THEN PutI(SUBI, T1, base, cc);
		ELSE
			PutI(MOVW, T1, offset DIV IMM12 MOD 10H, offset MOD IMM12);
			IF ASH(offset, -16)#0 THEN PutI(MOVT, T1, offset DIV IMM28 MOD 10H, offset DIV IMM16 MOD IMM12) END;
			PutR(ADD, T1, base, T1);
		END;
	END SetOffset;
	
	PROCEDURE SaveRegs(r, f: SET; offset: LONGINT; VAR size: LONGINT);
		VAR i, s, base, imm8, Vd: LONGINT;
	BEGIN
		ASSERT(~(SP IN r), 51);
		s:=0;
		IF f+r#{} THEN
			base:=SP;
			IF (offset#0) OR (f#{}) THEN SetOffset(offset, SP); base:=T1 END;
			imm8:=0;
			IF f#{} THEN
				i:=-1;
				REPEAT INC( i) UNTIL (i IN f);
				Vd:=i;
				REPEAT
					IF (i IN f) THEN imm8:=i END;
					INC( i);
				UNTIL i=16;
				DEC(imm8, Vd-1);
				PutB( VSTMIAwb, ASH(base, 16)+ ASH(Vd, 12)+imm8*2);
			END;
			s:=imm8*8;
			IF r#{} THEN
				i:=0;
				REPEAT 
					IF i IN r THEN INC(s, 4) END;
					INC(i);
				UNTIL i=16;
				PutB( STMIA, ASH(base, 16)+ S.VAL(LONGINT, r));
			END;
		END;
		size:=s+s MOD 8;
	END SaveRegs;
	
	PROCEDURE RestoreRegs(r, f: SET; offset, base: LONGINT; VAR size: LONGINT);
		VAR i, s, imm8, Vd: LONGINT;
	BEGIN
		ASSERT(base#T0, 50);
		ASSERT(~(SP IN r), 51);
		s:=0;
		IF f+r#{} THEN
			IF (offset#0) OR (f#{}) THEN SetOffset(offset, base); base:=T1 END;
			imm8:=0;
			IF f#{} THEN
				i:=-1;
				REPEAT INC( i) UNTIL (i IN f);
				Vd:=i;
				REPEAT
					IF (i IN f) THEN imm8:=i END;
					INC( i);
				UNTIL i=16;
				DEC(imm8, Vd-1);
				PutB( VLDMIAwb, ASH(base, 16)+ ASH(Vd, 12)+imm8*2);
			END;
			s:=imm8*8;
			IF r#{} THEN
				i:=0;
				REPEAT 
					IF i IN r THEN INC(s, 4) END;
					INC(i);
				UNTIL i=16;
				PutB( LDMIA, ASH(base, 16)+ S.VAL(LONGINT, r));
			END;
		END;
		size:=s+s MOD 8;
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
				IF (par^.mode = OPT.Var) & (par^.typ^.comp = DynArr) THEN dynArrCopied := TRUE END ;
				par := par^.link
			END ;
			LeafProc := proc^.leaf;
			NoFP := (*LeafProc &*) ~dynArrCopied & (proc^.conval^.intval - proc^.conval^.intval2 <= MaxLittleFrame);
			INC(proc^.adr, LONG(pc));	(* do not destroy mthd no *)
			FixBranches(proc)
		END ;
		thisProc := pc; INC(pc, MaxEntryCode); curshiftx := shiftx
	END Enter;

PROCEDURE AdjustLink( delta, max: LONGINT; VAR access: ARRAY OF INTEGER);	(* PC relative, always negative *)
VAR i, j, l1, instr: LONGINT;
BEGIN
	i := 0;
	WHILE i < max DO 
		l1:=0; j := access[i]; INC(i); instr := code[j];
		IF instr DIV (IMM24*2) MOD 8 = B DIV (IMM24*2) MOD 8 THEN
			code[j] := instr DIV IMM24*IMM24+ (instr+ delta DIV 4) MOD IMM24; l1:=0;
		ELSIF  (instr DIV IMM24= MOVW DIV IMM24) THEN 	(* interim encoding, adr of load /store *)
			code[j] := instr DIV IMM16 * IMM16  + (instr + delta DIV 4) MOD IMM16; l1:=0;
		ELSE
			IF ODD( ASH(instr, -23)) THEN	(* ADD*) HALT(72) END;
			IF  (instr DIV IMM24= LDRB DIV IMM24) THEN	(* 0E5H+ *)
				l1:= ( instr MOD 1000H -delta) DIV 1000H; 
				code[j] := instr DIV IMM12*IMM12+(instr-delta) MOD IMM12;
			ELSIF (instr DIV IMM24= LDRSB DIV IMM24) THEN	(* 0E15H+ *)
				l1:= instr DIV 100H MOD 10H*10H+instr MOD 10H-delta;
				instr:= instr DIV IMM12*IMM12+ instr DIV 10H MOD 10H*10H;
				code[j] := instr +l1 DIV 10H MOD 10H *100H +l1 MOD 10H;
				l1:=l1 DIV 100H;
			ELSIF  (instr DIV IMM24= VLDR DIV IMM24) THEN 	(* 0ED1H+ *)
				l1:= instr MOD 100H-delta DIV 4;
				code[j] := instr DIV 100H * 100H+l1 MOD 100H;
				l1:= l1 DIV 100H;
			ELSE OPM.err(-914); OPM.LogWHex( delta); OPM.LogWHex( instr);
			END;
		END;
		IF l1=-1 THEN
			instr:=code[ j-1];
			IF instr DIV (IMM20*2) = SUBI DIV (IMM20*2) THEN 
				IF instr MOD 100H=0 THEN
					instr:=code[ j-2];
					IF instr DIV (IMM20*2) = SUBI DIV (IMM20*2) THEN ASSERT( instr MOD 100H >0, 44); code[ j-2]:=instr-1; 
					ELSE OPM.err(-918); OPM.LogWHex( l1); OPM.LogWHex( instr);
					END;
				ELSE code[ j-1]:=instr-1;
				END;
			ELSE code[ j-1]:=instr; OPM.err(-917); OPM.LogWHex( l1); OPM.LogWHex( instr); HALT(73); 
			END;
		ELSIF l1#0 THEN OPM.err(-918); OPM.LogWHex( l1); HALT(74);
		END;
	END
END AdjustLink;
	
	PROCEDURE Exit*(proc: OPT.Object; VAR calleeUsed: RegSet; VAR pcOffset: INTEGER);
		VAR i, j, savedPC, shift: INTEGER; sp, fp, y, sl: Item;
				o2, instr, spdisp, offset, varSize, calleeSize, dummy: LONGINT;
				saveR, saveF: SET; openProc: BOOLEAN;
	BEGIN
		calleeUsed.r := locUsedR + calleesUsedR; calleeUsed.f := locUsedF + calleesUsedF;
		IF proc = NIL THEN (* module *)
			openProc := TRUE; varSize := 0
		ELSE
			openProc := (proc^.mode = OPT.XProc) (* exported or assigned *) OR (alreadyCalled IN proc^.conval^.setval);
			varSize := proc^.conval^.intval2
		END ;
		IF ~InterProcInf OR openProc THEN
			saveR := calleeUsed.r*CalleeSavedR; saveF := calleeUsed.f*CalleeSavedF;
			calleeUsed.r := calleeUsed.r*CallerSavedR; calleeUsed.f := calleeUsed.f*CallerSavedF
		ELSE
			saveR := {}; saveF := {}
		END ;
		IF dynArrCopied THEN
			IF code[resCallArea] = SUBI + (SP*16+SP)*IMM12 THEN	(* SUBI sp, sp, 0 from OPC.Enter *)
				code[resCallArea] := SUBI+ (SP*16+SP)*IMM12+ callArea; 
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
		i := 0;
		WHILE i < 32 DO
			IF i IN saveR THEN INC(calleeSize, 4) END ;
			INC(i)
		END ;
		INC(calleeSize, calleeSize MOD 8);	(* +0 or +4 *)
		frameSize := calleeSize - varSize + callArea;
		IF dynArrCopied THEN spdisp := calleeSize - varSize ELSE spdisp := frameSize END ;
		sp.mode := Reg; sp.reg := SP;
		y.mode := OPT.Con; y.offset := spdisp; 
		IF spdisp>=100H THEN Load(y, T0) END;
		Add(sp, y, SP, TRUE);
		IF dynArrCopied THEN offset := 0 ELSE offset := callArea END ;
		SaveRegs(saveR, saveF, offset, dummy);
		IF ~NoFP THEN Add(sp, y, FP, FALSE);	(* y either still const or still in T0 *)
		ELSE i := 0;
			WHILE i < lacx DO 
				j := localAccess[i]; INC(i); instr := code[j];
				IF (frameSize > 90H) THEN OPM.err(-750); OPM.LogWHex( frameSize); OPM.LogWHex( instr) END;
				IF instr DIV (IMM20*2) = ADDI DIV (IMM20*2) THEN 
					code[j] := instr + frameSize; IF instr MOD 1000H+frameSize>=100H THEN OPM.err(749) END;
				ELSIF instr DIV (IMM20*2) = SUBI DIV (IMM20*2) THEN 
					IF instr MOD 100H >=frameSize THEN
						code[j] := instr -frameSize; IF instr DIV 100H MOD 10H #0 THEN OPM.err(748); END;
					ELSE
						code[j] := instr DIV 100H *100H -SUBI+ADDI+frameSize-instr MOD IMM12; IF instr DIV 100H MOD 10H #0 THEN OPM.err(748); END;
					END;
				ELSIF  (instr DIV (IMM24 DIV 2)= LDRB DIV (IMM24 DIV 2)) THEN	(* 0E5H+ *)
					code[j] := instr +frameSize; 
				ELSIF  (instr DIV (IMM24 DIV 2)= (LDRB-LSADD) DIV (IMM24 DIV 2)) THEN	(* 0E5H- *)
					IF instr MOD 1000H >=frameSize THEN
						code[j] := instr - frameSize;
					ELSE
						code[j] := instr DIV IMM12*IMM12+LSADD+frameSize-instr MOD IMM12;
					END;
				ELSIF (instr DIV (IMM20*2)= LDRSB DIV (IMM20*2)) THEN	(* 0E15H+ *)
					o2:= frameSize+instr DIV 100H MOD 10H*10H+instr MOD 10H;
					ASSERT( o2<100H, 42);
					instr:= instr DIV IMM12*IMM12+ instr DIV 10H MOD 10H*10H;
					code[j] := instr +o2 DIV 10H MOD 10H *100H +o2 MOD 10H;
				ELSIF (instr DIV (IMM20*2)= (LDRSB-LSADD) DIV (IMM20*2)) THEN (* 0E15H- *)
					o2:= frameSize-instr DIV 100H MOD 10H*10H-instr MOD 10H;
					ASSERT( o2>=0, 40);
					instr:= instr DIV IMM12*IMM12+ instr DIV 10H MOD 10H*10H;
					code[j] := instr +o2 DIV 10H MOD 10H *100H +o2 MOD 10H+LSADD;
				ELSIF  (instr DIV (IMM20*2)= VLDR DIV (IMM20*2)) THEN 	(* 0ED1H+ *)
					ASSERT( instr MOD 100H +frameSize DIV 4 <100H, 37);
					code[j] := instr +frameSize DIV 4;
				ELSIF  (instr DIV (IMM20*2)= (VLDR-LSADD) DIV (IMM20*2)) THEN	(* 0ED1H- *)
					o2:= frameSize DIV 4-instr MOD 100H;
					ASSERT( o2>=0, 41);
					code[j] := instr DIV 100H * 100H +LSADD+o2; (*OPM.err(-754); OPM.LogWHex( o2);*)
				ELSE code[ j]:=instr; OPM.err(-914); OPM.LogWHex( frameSize); OPM.LogWHex( instr);
				END;
			END
		END ;
		shift := thisProc + MaxEntryCode - pc; pcOffset := shift;
		AdjustLink( shift*4, adjlx, adjustLink);
(*
		i := 0;
		WHILE i < adjlx DO
			j := adjustLink[i]; INC(i); instr := code[j];
			IF instr DIV (IMM24*2) MOD 8 = B DIV (IMM24*2) MOD 8 THEN
				code[j] := instr DIV IMM24*IMM24+ (instr+ shift) MOD IMM24;
			ELSIF  (instr DIV IMM24= MOVW DIV IMM24) THEN	(* interim encoding, adr of load /store *)
				code[j] := instr DIV IMM16 * IMM16  + (instr + shift) MOD IMM16;
			ELSE OPM.err( -910); OPM.LogWHex( instr); 
			END;
		END;
*)
		shiftTab[shiftx] := shift; INC(shiftx);
		i := thisProc + MaxEntryCode;
		WHILE i < savedPC DO code[i - shift] := code[i]; INC(i) END ;
		pc := savedPC - shift;
		(* exit code: *)
		IF NoFP THEN RestoreRegs(saveR, saveF, callArea, SP, dummy)
		ELSE
			fp.mode := Reg; fp.reg := FP; y.mode := Reg; y.reg := SP; Move(y, fp, LInt);
			RestoreRegs(saveR, saveF, varSize - calleeSize, SP, dummy)
		END ;
		sp.mode := Reg; sp.reg := SP;
		IF NoFP THEN
			IF (frameSize > 0) THEN y.mode := OPT.Con; y.offset := frameSize; Add(sp, y, SP, FALSE) END;
(*		ELSE y.mode := Reg; y.reg := T2; Move(sp, y, LInt)*)
		END;
		PutB(BX, RA);	(* IProc ? *)
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
				ext.mode := OPT.Con; ext.offset := 1;	(* 1 to be patched *)
				Add(sp, ext, SP, TRUE);
				patch := pc-1;
			ELSE RegsSaved := TRUE
			END ;
			SaveRegs(saved.r, saved.f, argSize, saveSize);
			tempLiveR := tempLiveR - saved.r; tempLiveF := tempLiveF - saved.f
		END ;
		INC(saveSize, argSize);
		IF saveSize > callArea THEN callArea := saveSize END; ASSERT(saveSize<256, 60);
		IF patch # 0 THEN
			IF code[patch]  = SUBI +(SP*10H+SP)*IMM12+1 THEN
				code[patch] := SUBI +(SP*10H+SP)*IMM12 +saveSize;
			ELSE OPM.err(-716); OPM.LogWHex( code[patch]);
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
				ext.mode := OPT.Con; ext.offset := saveSize;
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
			IF (obj^.mode = OPT.Var) OR (obj^.mode = OPT.VarPar) THEN
				f := obj^.typ^.form;
				IF (f IN {Byte .. Set, Pointer, ProcTyp})
					OR (obj^.typ^.comp = Array) & (obj^.typ^.BaseTyp^.form = Char) THEN
					IF obj^.mode = OPT.Var THEN OPM.RefW(1X) ELSE OPM.RefW(3X) END ;
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
			WHILE (fld # NIL) & (fld^.mode = OPT.Fld) DO
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
				IF obj^.mode = OPT.TProc THEN NewMthTab[nofnewmeth] := obj; INC(nofnewmeth) END ;
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
						IF obj^.mode = OPT.Con THEN INC(nofexp);
							OPM.ObjW(1X); WName(obj^.name); OPM.ObjWNum(obj^.fprint)
						ELSIF obj^.mode = OPT.Typ THEN INC(nofexp);
							OPM.ObjW(2X); WName(obj^.name); OPM.ObjWNum(obj^.fprint); WStruct(obj)
						ELSIF obj^.mode = OPT.Var THEN INC(nofexp);
							OPM.ObjW(3X); WName(obj^.name); OPM.ObjWNum(obj^.fprint); OPM.ObjWNum(obj^.adr);
							FindPtrs(obj^.typ, obj^.adr, ptrTab, nofptr)
						ELSIF obj^.mode IN {OPT.XProc, OPT.IProc} THEN INC(nofexp);
							OPM.ObjW(4X); WName(obj^.name); OPM.ObjWNum(obj^.fprint); OPM.ObjWNum(obj^.adr);
							IF obj^.linkadr # 0 (*assigned*) THEN OPM.ObjW(9X); OPM.ObjWNum(obj^.adr); WLink(obj) END ;
							IF (obj^.link = NIL) & (obj^.typ = OPT.notyp) THEN	(*command*)
								IF nofcom < MaxComs THEN ComTab[nofcom] := obj; INC(nofcom)
								ELSE OPM.err(232); nofcom := 0
								END
							END
						ELSIF obj^.mode = OPT.CProc THEN INC(nofexp);
							OPM.ObjW(5X); WName(obj^.name); OPM.ObjWNum(obj^.fprint)
						END
					ELSIF obj^.mode = OPT.Typ THEN WStruct(obj)
					ELSIF obj^.mode = OPT.Var THEN FindPtrs(obj^.typ, obj^.adr, ptrTab, nofptr)
					ELSIF (obj^.mode IN {OPT.XProc, OPT.IProc}) & (obj^.linkadr # 0) THEN	(* assigned *)
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
					IF obj^.mode = OPT.Con THEN
						OPM.ObjW(1X); WName(obj^.name); OPM.ObjWNum(obj^.fprint)
					ELSIF obj^.mode = OPT.Typ THEN
						OPM.ObjW(2X); WName(obj^.name); OPM.ObjWNum(obj^.fprint)
					ELSIF obj^.mode = OPT.Var THEN
						OPM.ObjW(3X); WName(obj^.name); OPM.ObjWNum(obj^.fprint); WLink(obj)
					ELSIF obj^.mode IN {OPT.XProc, OPT.IProc} THEN
						OPM.ObjW(4X); WName(obj^.name); OPM.ObjWNum(obj^.fprint); WLink(obj)
					ELSIF obj^.mode = OPT.CProc THEN
						OPM.ObjW(5X); WName(obj^.name); OPM.ObjWNum(obj^.fprint)
					END
				END ;
				IF obj^.mode = OPT.Typ THEN typ := obj^.typ; strobj := typ^.strobj;
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
		IF NEWDATA THEN
			WHILE (conx MOD 8) # 0 DO DEC(conx); constant[conx] := 0X END;
		ELSE
			WHILE (conx MOD 8) # 0 DO constant[conx] := 0X; INC(conx) END;
		END;
	(*HeaderBlk*)
		nofexp := 0; nofdesc := 0; nofcom := 0; nofptr := 0;
		OPM.ObjWNum(OPT.nofGmod-1); WLink(KNewRec); WLink(KNewSys); WLink(KNewArr);
		WLink(GlobData); OPM.ObjWNum(-sb);
		IF NEWDATA THEN OPM.ObjWNum( LEN(constant)-conx) ELSE OPM.ObjWNum(conx) END;
		OPM.ObjWNum(pc); WriteName(OPT.SelfName);
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
		OPM.ObjW(87X);
		IF NEWDATA THEN
			i:=0;
			WHILE i<LEN(constant)-conx DO
				constant[ i]:= constant[ conx+i];
				INC(i);
			END;
			OPM.ObjWBytes(constant, LEN(constant)-conx);
		ELSE OPM.ObjWBytes(constant, conx);
		END;
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
		CONST intprinf = 6; 
	BEGIN
		InterProcInf := intprinf IN opt;
		pc := 0; level := 0; sb := 0; conx := 0; shiftx := 0; curshiftx := NoShift;
		softDiv:=10 IN OPM.opt;
		IF NEWDATA THEN conx:=LEN(constant) END;
		CodeOvF := FALSE; RegsSaved := FALSE; stackExt := 0;
		KNewRec.linkadr := 0; KNewSys.linkadr := 0; KNewArr.linkadr := 0; GlobData.linkadr := 0
	END Init;

	PROCEDURE Close*;
	END Close;
	
BEGIN
	NEW(KNewRec); NEW(KNewSys); NEW(KNewArr); NEW(GlobData);
	defaultCalleeUsed.r := CallerSavedR;
	defaultCalleeUsed.f := CallerSavedF;

	loadOp[Byte] := LDRB;
	loadOp[Bool] := LDRB;
	loadOp[Char] := LDRB;
	loadOp[SInt] := LDRSB;
	loadOp[Int] := LDRSH;
	loadOp[LInt] := LDR;
	loadOp[Real] := VLDR;
	loadOp[LReal] := VLDR+100H;
	loadOp[Set] := LDR;
	loadOp[String] := NOP;
	loadOp[NilTyp] := NOP;
	loadOp[NoTyp] := 0;
	loadOp[ProcTyp] := LDR;
	loadOp[Pointer] := LDR;
	loadOp[Comp] := LDR;

	loadOpB[Byte] := LDRBb;
	loadOpB[Bool] := LDRBb;
	loadOpB[Char] := LDRBb;
	loadOpB[SInt] := LDRSBb;
	loadOpB[Int] := LDRSHb;
	loadOpB[LInt] := LDRb;
	loadOpB[Real] := 0;
	loadOpB[LReal] := 0;
	loadOpB[Set] := LDRb;
	loadOpB[String] := NOP;
	loadOpB[NilTyp] := NOP;
	loadOpB[NoTyp] := 0;
	loadOpB[ProcTyp] := LDRb;
	loadOpB[Pointer] := LDRb;
	loadOpB[Comp] := LDRb;

	storeOp[Byte] := STRB;
	storeOp[Bool] := STRB;
	storeOp[Char] := STRB;
	storeOp[SInt] := STRB;
	storeOp[Int] := STRH;
	storeOp[LInt] := STR;
	storeOp[Real] := VSTR;
	storeOp[LReal] := VSTR+100H;
	storeOp[Set] := STR;
	storeOp[String] := NOP;
	storeOp[NilTyp] := NOP;
	storeOp[NoTyp] := 0;
	storeOp[ProcTyp] := STR;
	storeOp[Pointer] := STR;
	storeOp[Comp] := STR;

	storeOpB[Byte] := STRBb;
	storeOpB[Bool] := STRBb;
	storeOpB[Char] := STRBb;
	storeOpB[SInt] := STRBb;
	storeOpB[Int] := STRHb;
	storeOpB[LInt] := STRb;
	storeOpB[Real] := 0;
	storeOpB[LReal] := 0;
	storeOpB[Set] := STRb;
	storeOpB[String] := NOP;
	storeOpB[NilTyp] := NOP;
	storeOpB[NoTyp] := 0;
	storeOpB[ProcTyp] := STRb;
	storeOpB[Pointer] := STRb;
	storeOpB[Comp] := STRb;

END AOPL.
