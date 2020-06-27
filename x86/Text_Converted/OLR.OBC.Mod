MODULE OBC;  (*NW 30.5.87 / 28.3.93 / as 23.02.99 *)

(*	Peter Matthias
		2014-04-12	ToDo: change PutSWI to use BLCC Kernel.runtime[ nr+3]
		2014-04-22	changed PutSWI to use MOVCC , BLCC
		2014-04-26	give warning in SetCondition if CC is NV (now illegal code)!
		2014-04-30	fixed NV cc issue	NOP in OutCode
		2015-05-05	encoded MAX(INTEGER) in PutSWI
		2015-12-15	added PutVFP
		2015-12-23	added LoadConstDF, changed PutVFP; don't use it as it can only load at PC+-1020 Bytes!
		2016-01-09	works now with (LONG-)REALs directly loaded in FPU registers
		2016-01-15	(LONG) REAL constants directcly loaded in VFP registers; direct loading of string addresses; code+constants must be <256K 
		2016-01-18	fixed SetCondition 
		2016-01-19	fixed FixLink to remove now not allowed BNV; BNV is alway a forward jump (more elegant than code from 2014-04-30)
		2016-10-22	changed PutSWI to use illegal instruction LDC
		2016-11-29	optimized PutSDT, PutHDT to avoid additional load for smaller distances, put INC(constDist) inside IncPC

Todo use ARMv6T2 MOVT/MOVW for constants	(move top/move word)
*)

	IMPORT SYSTEM, Files, OBS, OBT, OC := OBM;

	CONST
		ObjMark = 0F5X; 
		CodeLength = 32768; (* 128K Code. Don't make it bigger (because of fixup list limits! *)
		ConstLength = 1024; (* was 1024 in Words *)
		StrConstLength = 4096; (* in Bytes, up to 4*4096 *)
		LRConstLength = 256;	(* length of longreal constants, up to 4096 *)
		RConstLength = 256;	(* lentgh of real constants, up to 4096 *)
		MaxConstDist = ConstLength-15; (* in Words including a safety range *)
		MaxUnknownProcs = 128;
		MaxPtrs = 512; MaxRecs = 128; MaxComs = 40; MaxExts = 15;
		iinst=0C1F0700H;	(* generate illigal instruction for traps *)
		
		(* Constants for Bit x set *)
		C22 = 400000H; C23 = 800000H; C24 = 1000000H; C25 = 2000000H; C28= 10000000H;

		NOP=0E1A00000H;

		(* Op-Codes Single Data Transfer (SDT) *)
		LDR* = 51H; (* LDR, pre-indexed, no write-back *)
		STR* = 50H; (* STR, pre-indexed, no write-back *)
		LDRB* = 55H; (* LDRB, pre-indexed, no write-back *)
		STRB* = 54H; (* STRB, pre-indexed, no write-back *)
	
		LDRpost* = 41H; (* LDR, post-indexed, no write-back-bit *)
		STRpost* = 40H; (* STR, post-indexed, no write-back-bit *)
		LDRBpost* = 45H; (* LDRB, post-indexed, no write-back-bit *)
		STRBpost* = 44H; (* STRB, post-indexed, no write-back-bit *)
	
		(* Op-Codes Halfword Data Transfer (HDT) *)
		LDRSH* = 11000F0H; (* LDRSH, pre-indexed, no write-back *)
		STRH* = 10000B0H; (* STRH, pre-indexed, no write-back *)
		LDRSB* = 11000D0H; (* LDRSB, pre-indexed, no write-back *)

		(* Op-Codes VFP Data Transfer, offset is subtracted automatically*)
		VLDRS* = 0ED900A00H;	VLDRD* = 0ED900B00H;	(* Rn, Vd, imm8 *)
		VSTRS* = 0ED800A00H;	VSTRD* = 0ED800B00H;

		(* Op-Codes VFP Data processing*)
		VMOVRD* = 0EEB00B40H;	(* move register double= single? *)

		ADR10 = 0E28F0B00H;	(* 322, A1, positive distance; last byte shifted left by 10 bits *)
		ADDADR = 0E2800F00H;

		VSUBS= 0EE300A40H;	VSUBD= 0EE300B40H;


		(* Op-Codes Block Data Transfer (BDT) *)
		LDMIA* = 89H; STMIA* = 88H; STMDB* = 90H;
		
		(* Op-Codes Data Processing: S-Bit is always set (except for MOV and RSBnoflags ) ! *)
		AND* = 1; EOR* = 3; SUB* = 5; RSBnoflags* = 6; RSB* = 7; ADD* = 9; ADC = 11; SBC = 13; RSC = 15; TST* = 17;
		TEQ = 19;
		CMP* = 21; CMN* = 23;  ORR* = 25; MOV* = 26; MOVS* = 27; BIC* = 29; MVN* = 30; MVNS = 31;

		(* Op-Codes Branch Instructions *)
		B* = 10; BL* = 11;		

		(* Op-Codes Multiplication *)
		MUL* = 0; MLA* = 200000H;
		
		(* Op-Codes Long Multiplication *)
		SMULL* = 00C00090H; 
		
		(* Conditions *)
		EQ* = 0; NE* = 1; CS* = 2; CC* = 3;  MI* = 4; PL* = 5; VS* = 6; VC* = 7;
		HI* = 8; LS* = 9; GE* = 10; LT* = 11;  GT* = 12; LE* = 13; AL* = 14; NV* = 15;
		 
		(* Register Numbers *)
		PC* = 15; LR* = 14; SP* = 13; FP* = 12; FirstUniversalReg = 11; FirstFReg = 14;

		(* Const Types *)
		Constant = 0; (*StringAddr = 1;*) ProcAddr = 2; ExtAddr = 3; 
		
	TYPE
		ConstT = RECORD
			a : LONGINT;
			type : INTEGER; (* TRUE, if constant is an address *)
			b : INTEGER; (* index into unknownProcTab, if type=ProcAddr *)
		END;
							
		LIAPtr= POINTER TO ARRAY OF LONGINT;
						
	VAR	
		pc* : LONGINT;
		moduleBody* : LONGINT; (** entry point for module body *)
		level*: INTEGER;
		typchk* : BOOLEAN;
		wasderef*: OBT.Object;
		RegSet, RegSetF: SET;
		nofrecs: INTEGER;
		extcallfixlist: LONGINT; (* Calls of imported procs  *)
		extaddrfixlist: LONGINT; (* Addresses of imported procs/vars/type-descs *)
		fixlist0 : LONGINT; (* module local fixups *)
		recTypesOffset : LONGINT;
		recTab: ARRAY MaxRecs OF OBT.Struct;
		code:  ARRAY CodeLength OF LONGINT;
		preferredReg : LONGINT;
			
		(* for constant handling *)
		constCnt, constRefChain : LONGINT;
		constBlock : ARRAY ConstLength OF ConstT;
		lrconstCnt, lrconstRefChain : LONGINT;
		lrconstBlock : ARRAY LRConstLength OF LONGREAL;

		rconstCnt, rconstRefChain : LONGINT;
		rconstBlock : ARRAY RConstLength OF LONGINT;

		constDist : LONGINT; (* maximal distance between const and its usage *)
		allowConstFlushing* : LONGINT; (* >=0 -> const flushing allowed *)
		flushing : BOOLEAN;

		(* for string const handling *)
		strConstBlock : ARRAY StrConstLength OF CHAR;
		strConstBlockCnt, 	(* in words *)
		strconstRefChain : LONGINT;
	
		(* for Fixups of forwarded proc addresses *)
		unknownProcTab : ARRAY MaxUnknownProcs OF OBT.Object;
		unknownProcCnt : INTEGER;

		(* statistics *)
		constJumpOvers* : LONGINT; (* no. of jumps over constants (words) *)
		minConstBlock* : LONGINT; (* min. size of a const block (words) *)
		maxConstBlock* : LONGINT; (* max. size of a const block (words) *)
		nofConstBlocks* : LONGINT; (* Nr. of const blocks *)
		totConsts* : LONGINT; (* tot. nr. of consts (words) *)

				
		(* debug *)
		trapPos*  : LONGINT;	(*position where a trap happened*)
				
	PROCEDURE ^FlushConsts*;
	PROCEDURE ^PutSDT*(op, dest, base, offset : LONGINT);
	PROCEDURE ^PutDP1*(op, dest, reg1, const : LONGINT); (* Data Processing with shifted constant as 2nd operand *)
	PROCEDURE ^PutB*(op,target : LONGINT);
	PROCEDURE ^fixup*(loc: LONGINT);  (*enter pc at loc*)
	PROCEDURE ^PutVFP*(op, vn, vd, vm: LONGINT);
	PROCEDURE ^PutFDT*(op, dest, base, offset: LONGINT);
	PROCEDURE ^GetReg*(VAR r: LONGINT);
	PROCEDURE ^FreeReg*(r : LONGINT);

	(* -------------------------------------------------------------------- *)
	
	PROCEDURE IncPC;
	BEGIN
		INC(pc);
		IF pc >= trapPos THEN OBS.Mark(355); trapPos := MAX(LONGINT) END;
		IF constDist>=0 THEN INC(constDist) END;
	END IncPC;
	
	(* -------------------------------------------------------------------- *)
	
	PROCEDURE AddAddrFixup(loc : LONGINT; VAR fixlist : LONGINT); (** Adds loc to the absolute fixup list fixlist *)
	BEGIN
		code[loc]:=code[loc] MOD 20000H + fixlist*20000H; fixlist:=loc; 
	END AddAddrFixup;
	
	PROCEDURE AddAbsFixup*(loc : LONGINT);
	BEGIN
		AddAddrFixup(loc,fixlist0);
	END AddAbsFixup;

	(* ----------------- Private Procedures for Constant Handling ------------------- *)
	PROCEDURE EnterConst(c : LONGINT) : LONGINT;
	(* Enters a constant and returns the offset within the constant block *)
	VAR i : LONGINT;
	BEGIN
		(* Check if const is already entered *)
		i:=0;
		WHILE (i<constCnt) & ((constBlock[i].a#c) OR (constBlock[i].type#Constant)) DO INC(i) END;
		IF i<constCnt THEN
			(* Constant already in memory *)
			RETURN i*4;
		END;
		(* Constant not in memory. Enter it. Constant block WILL NEVER overflow because we flush it before that happens! *)
		constBlock[constCnt].a:=c; constBlock[constCnt].type:=Constant;
		IF constCnt>constDist THEN constDist:=constCnt END;	
		INC(constCnt);
		RETURN (constCnt-1)*4;
	END EnterConst;

	PROCEDURE EnterRConst(const : LONGINT) : LONGINT;
	(* Enters a constant and returns the offset within the constant block *)
	VAR i : LONGINT;
	BEGIN
		(* Check if const is already entered *)
		i:=0;
		WHILE (i<rconstCnt) & (rconstBlock[i]#const) DO INC(i) END;
		IF i<rconstCnt THEN
			(* Constant already in memory *)
			RETURN i;
		END;
		(* Constant not in memory. Enter it. *)
		rconstBlock[rconstCnt]:=const;
		INC(rconstCnt);
		RETURN (rconstCnt-1);
	END EnterRConst;

	PROCEDURE EnterLRConst(const : LONGREAL) : LONGINT;
	(* Enters a constant and returns the offset within the constant block *)
	VAR i : LONGINT;
	BEGIN
		(* Check if const is already entered *)
		i:=0;
		WHILE (i<lrconstCnt) & (lrconstBlock[i]#const) DO INC(i) END;
		IF i<lrconstCnt THEN
			(* Constant already in memory *)
			RETURN i;
		END;
		(* Constant not in memory. Enter it. *)
		lrconstBlock[lrconstCnt]:=const;
		INC(lrconstCnt);
		RETURN (lrconstCnt-1);
	END EnterLRConst;
	
	PROCEDURE CheckConstReachability;
	VAR L : LONGINT;
	BEGIN
		IF allowConstFlushing<0 THEN RETURN END;
		IF constDist>=MaxConstDist THEN
			INC(constJumpOvers); (* statistics *)
			DEC(allowConstFlushing);
			L:=pc;
			PutB(B,0);
			FlushConsts;
			fixup(L);
			INC(allowConstFlushing)
		END
	END CheckConstReachability;	
		
	PROCEDURE EnterExtAddress(mno, eno : LONGINT) : LONGINT;
	(* Enters a address and returns the offset within the constant block *)
	VAR i : INTEGER; exta : LONGINT;
	BEGIN	
		exta := mno * 100H + eno;
		
		(* Check if const is already entered *)
		i:=0;
		WHILE (i<constCnt) & ~((constBlock[i].a=exta) & (constBlock[i].type=ExtAddr)) DO INC(i) END;
		IF i<constCnt THEN
			(* Constant already in memory *)
			RETURN i*4;
		END;
	
		(* Not in memory. Enter it *)
		constBlock[constCnt].a:=exta; constBlock[constCnt].type:=ExtAddr;
		IF constCnt>constDist THEN constDist:=constCnt END;	
		INC(constCnt);
		RETURN (constCnt-1)*4;
	END EnterExtAddress;
		
	PROCEDURE EnterUnknownProcAddress(proc : OBT.Object) : LONGINT;
	(* Enters a address and returns the offset within the constant block *)
	VAR i : INTEGER;
	BEGIN
		(* Find procedure in unknownProcTab *)
		i:=0;
		WHILE (i<unknownProcCnt) &  (unknownProcTab[i]#proc) DO INC(i) END;
		IF i=unknownProcCnt THEN (* not found *)
			IF unknownProcCnt=MaxUnknownProcs THEN OBS.Mark(252); unknownProcCnt:=0; i:=0 END;
			unknownProcTab[unknownProcCnt]:=proc;
			INC(unknownProcCnt)
		END;
		
		(* Enter Procedure Address *)
		constBlock[constCnt].a:=0; constBlock[constCnt].b:=i; constBlock[constCnt].type:=ProcAddr;
		IF constCnt>constDist THEN constDist:=constCnt END;	
		INC(constCnt);
		RETURN (constCnt-1)*4;
	END EnterUnknownProcAddress;
(*		
	PROCEDURE EnterStringConstAddr(a : LONGINT) : LONGINT;
	BEGIN
		constBlock[constCnt].a:=a; constBlock[constCnt].type:=StringAddr;
		IF constCnt>constDist THEN constDist:=constCnt END;
		INC(constCnt); 
		RETURN (constCnt-1)*4;
	END EnterStringConstAddr;
*)	
	(* ----------------- Public Procedures for Constant Handling ------------------- *)
	
	PROCEDURE EnterStringConst*(VAR x : OBT.Item);
	(* Enters a string constant and returns the offset within the constant block *)
	VAR l, i  : LONGINT;
	BEGIN
		l:=0; WHILE x.obj.ext.str[l]#0X DO INC(l) END; INC(l);
		x.obj.a0:=strConstBlockCnt;  x.a:=x.obj.a0;
		x.b:=l;
		IF strConstBlockCnt*4+l >= StrConstLength THEN 
			OBS.Mark(230)
		ELSE
			(*String eintragen *)
			FOR i:=0 TO l-1 DO strConstBlock[strConstBlockCnt*4+i]:=x.obj.ext.str[i] END;
			INC(strConstBlockCnt,(l+3) DIV 4 );
		END
	END EnterStringConst;
		
	PROCEDURE FlushConsts*;
	(* Writes the constants and fixes all offsets *)
	VAR tmp, tmp2, next, destreg, ofs, cnt : LONGINT;
	BEGIN
		flushing:=TRUE; 
		constDist:=-1; (* reset here so that we dont get recursive calls (because of PutSDT later on), 
								    if we are already in the "safety range" *)
								    
		(* Fix all references to a constant *)
		tmp:=constRefChain;
		IF tmp#-1 THEN INC(nofConstBlocks) END;
		cnt:=0;
		WHILE tmp#-1 DO
			INC(cnt);
			(* Extract dest reg, offset and next position that needs fixup *)
			next:=tmp-SYSTEM.LSH(code[tmp],-16); 
			destreg:=SYSTEM.LSH(code[tmp],-12) MOD 10H; ofs:=code[tmp] MOD 1000H;
			(* Adjust ofs and generate an LDR *)
			tmp2:=pc; pc:=tmp;
			PutSDT(LDR,destreg,PC, (tmp2*4+ofs));
			pc:=tmp2;
			tmp:=next;
		END;
		
		(* Emit all constants *)
		FOR tmp:=0 TO constCnt-1 DO
			code[pc]:=constBlock[tmp].a;
			CASE constBlock[tmp].type OF
				Constant: (* nothing to do *)
				|ProcAddr: AddAddrFixup(pc,unknownProcTab[constBlock[tmp].b].a2); 
	(*			|StringAddr: AddAddrFixup(pc,strfixlist); *)
				|ExtAddr: AddAddrFixup(pc,extaddrfixlist)
			END;
			IncPC
		END;
		
		constCnt:=0;
		constRefChain:=-1;
		constDist:=-1;
		flushing:=FALSE;
		
		IF cnt#0 THEN
			IF cnt<minConstBlock THEN minConstBlock:=cnt END;
			IF cnt>maxConstBlock THEN maxConstBlock:=cnt END;
			INC(totConsts,cnt)
		END
	END FlushConsts;

	PROCEDURE FlushRConsts;
	VAR tmp, tmp2, next, destreg, ofs, cnt : LONGINT;
	BEGIN
		tmp:=rconstRefChain;
		WHILE tmp#-1 DO
			(* Extract dest reg, offset and next position that needs fixup *)
			next:=tmp-SYSTEM.LSH(code[tmp],-16); 
			destreg:=SYSTEM.LSH(code[tmp],-12) MOD 10H;
			ofs:=(code[tmp] MOD 1000H)+(pc-tmp-2);
			
			(* Adjust ofs and generate an ADR *)
			tmp2:=pc; pc:=tmp;
			PutVFP( ADR10, 0, destreg, (4*ofs) DIV 400H); 
			code[ pc] :=code[pc]+ ofs  MOD 100H ;
			pc:=tmp2;
			tmp:=next;
		END;
		FOR cnt:=0 TO rconstCnt-1 DO
			code[pc]:= rconstBlock[ cnt]; INC(pc);
		END;
	END FlushRConsts;

	PROCEDURE FlushLRConsts;
	VAR tmp, tmp2, next, destreg, ofs, cnt : LONGINT;
	BEGIN
		tmp:=lrconstRefChain;
		code[pc+1]:=0;
		INC(pc, pc MOD 2);
		WHILE tmp#-1 DO
			(* Extract dest reg, offset and next position that needs fixup *)
			next:=tmp-SYSTEM.LSH(code[tmp],-16); 
			destreg:=SYSTEM.LSH(code[tmp],-12) MOD 10H;
			ofs:=(code[tmp] MOD 1000H*2)+(pc-tmp-2);
			
			(* Adjust ofs and generate an ADR *)
			tmp2:=pc; pc:=tmp;
			PutVFP( ADR10, 0, destreg, 4*ofs DIV 400H); 
			code[ pc] :=code[pc]+ ofs  MOD 100H ;
			pc:=tmp2;
			tmp:=next;
		END;
		FOR cnt:=0 TO lrconstCnt-1 DO
			SYSTEM.PUT( SYSTEM.ADR( code[pc]), lrconstBlock[ cnt]); INC(pc, 2);
		END;
	END FlushLRConsts;

	PROCEDURE FixStrAdrs;
	VAR tmp, tmp2, next, destreg, ofs, cnt : LONGINT;
	BEGIN
		tmp:=strconstRefChain;
		WHILE tmp#-1 DO
			(* Extract dest reg, offset and next position that needs fixup *)
			next:=tmp-SYSTEM.LSH(code[tmp],-16); 
			destreg:=SYSTEM.LSH(code[tmp],-12) MOD 10H;
			ofs:=(code[tmp] MOD 1000H) +(pc-tmp-2);
			
			(* Adjust ofs and generate an ADR *)
			tmp2:=pc; pc:=tmp;
			PutVFP( ADR10, 0, destreg, 4*ofs DIV 400H); 
			code[ pc] :=code[pc]+ ofs  MOD 100H ;
			pc:=tmp2;
			tmp:=next;
		END;
	END FixStrAdrs;
	
	PROCEDURE DecomposeConst*(const : LONGINT; VAR imm, rot : LONGINT) : BOOLEAN;
	(* Tries to decompose a constant into a 8bit unsigned immediate and a rotation, so that imm>>(2*rot)=const *)
	(* returns TRUE if such a combination of (imm,rot) exists *)
	BEGIN
		imm:=const; rot:=0;
		WHILE (rot<15) & ((imm<0) OR (imm>255)) DO imm:=SYSTEM.ROT(imm,2); INC(rot) END;
		RETURN (imm>=0) & (imm<=255)
	END DecomposeConst;
		
	PROCEDURE LoadConst*(reg, const : LONGINT);
	VAR ofs, imm, rot : LONGINT;
	BEGIN
		IF DecomposeConst(const,imm,rot) THEN PutDP1(MOV,reg,0,const);
		ELSIF DecomposeConst( -1-const,imm,rot) THEN PutDP1(MVN,reg,0,-1-const);
		ELSE
			ofs:=EnterConst(const); 
			code[pc]:=(pc-constRefChain)*10000H + reg*1000H + ofs;
			constRefChain:=pc; IncPC;
		END
	END LoadConst;

	PROCEDURE LoadRConst*(regf, const: LONGINT);
	VAR ofs, reg: LONGINT;
	BEGIN
		IF const=0 THEN PutVFP( VSUBS, regf, regf, regf); (* is this allowed ? *)
		ELSE
			ofs:=EnterRConst( const);
			GetReg( reg);
			code[pc]:=(pc-rconstRefChain)*10000H + reg*1000H + ofs; 	(* PC + bits 18..10 of offset *)
			rconstRefChain:=pc; IncPC;
			code[pc]:= VLDRS+reg*10000H+regf*1000H;	(* fix ADR MOD 100H, offset is in words *)
			FreeReg( reg);
			IncPC;
		END;
	END LoadRConst;

	PROCEDURE LoadLRConst*(regf: LONGINT; const: LONGREAL);
	VAR ofs, reg: LONGINT;
	BEGIN
		IF const=0.0 THEN PutVFP( VSUBD, regf, regf, regf); (* is this allowed ? *)
		ELSE
			ofs:=EnterLRConst( const);
			GetReg( reg);
			code[pc]:=(pc-lrconstRefChain)*10000H + reg*1000H + ofs; 	(* PC + bits 18..10 of offset *)
			lrconstRefChain:=pc; IncPC;
			code[pc]:= VLDRD+reg*10000H+regf*1000H;	(* fix ADR MOD 100H, offset is in doublewords *)
			FreeReg( reg);
			IncPC;
		END;
	END LoadLRConst;

	PROCEDURE LoadStringConst*(reg, ofs : LONGINT);
	BEGIN
		code[pc]:=(pc-strconstRefChain)*10000H + reg*1000H + ofs;
		strconstRefChain:=pc; IncPC;
		code[pc]:= ADDADR+reg*11000H;	(* fix ADD MOD 100H, offset is in words *)
		IncPC;
	END LoadStringConst;

	PROCEDURE LoadUnknownProcAddr*(reg : LONGINT; proc : OBT.Object);
	VAR ofs : LONGINT;
	BEGIN
		ofs:=EnterUnknownProcAddress(proc);
		code[pc]:=(pc-constRefChain)*10000H + reg*1000H + ofs; 
		constRefChain:=pc; IncPC;
	END LoadUnknownProcAddr;
	
	PROCEDURE LoadExtAddr*(reg, mno, eno : LONGINT);
	VAR ofs : LONGINT;
	BEGIN
		ofs:=EnterExtAddress(mno,eno);
		ASSERT(eno>=0);
		code[pc]:=(pc-constRefChain)*10000H + reg*1000H + ofs;
		constRefChain:=pc; IncPC;
	END LoadExtAddr;
	
	(* -------------------------------------------------------------------- *)	
	PROCEDURE SetRecTypesOffset*(o : LONGINT);
	BEGIN recTypesOffset:=o;
	END SetRecTypesOffset;
	
	PROCEDURE GetReg*(VAR r: LONGINT);
	VAR i: INTEGER;
	BEGIN 
		IF (preferredReg#-1) & ~(preferredReg IN RegSet) THEN
			r:=preferredReg; preferredReg:=-1; INCL(RegSet,r); RETURN
		END;
		i := FirstUniversalReg; 
		LOOP
			IF ~(i IN RegSet) THEN r := i; INCL(RegSet,i); EXIT END ;
			IF i <= 0 THEN r := 0; OBS.Mark(215); (* Out Of Registers *) EXIT ELSE DEC(i) END ;
		END
	END GetReg;

	PROCEDURE GetRegF*(VAR r: LONGINT);
	VAR i: INTEGER;
	BEGIN 
		i := FirstFReg; 
		LOOP
			IF ~(i IN RegSetF) THEN r := i; INCL(RegSetF,i); EXIT END ;
			IF i <= 0 THEN r := 0; OBS.Mark(216); (* Out Of Registers *) EXIT ELSE DEC(i) END ;
		END
	END GetRegF;

	PROCEDURE GetRegNoPref*(VAR r: LONGINT);
	VAR i: INTEGER; oldpreferred : LONGINT;
	BEGIN 
		oldpreferred:=preferredReg; preferredReg:=-1; GetReg(r); preferredReg:=oldpreferred;
	END GetRegNoPref;

	PROCEDURE UsedRegisters*(): SET;
	BEGIN RETURN RegSet
	END UsedRegisters;

	PROCEDURE UsedRegistersF*(): SET;
	BEGIN RETURN RegSetF
	END UsedRegistersF;

	PROCEDURE FreeReg*(r : LONGINT);
	BEGIN 
		EXCL(RegSet,r) 
	END FreeReg;

	PROCEDURE FreeRegF*(r : LONGINT);
	BEGIN 
		EXCL(RegSetF,r) 
	END FreeRegF;
	
	PROCEDURE SetPreferredReg*(r : LONGINT);
	BEGIN
		preferredReg:=r
	END SetPreferredReg;
			
	PROCEDURE FreeRegs*(keep: SET);
	BEGIN RegSet := keep; 
	END FreeRegs;

	PROCEDURE FreeRegsF*(keep: SET);
	BEGIN RegSetF := keep; 
	END FreeRegsF;

	PROCEDURE Release*(VAR x: OBT.Item);
	BEGIN
		IF ~(x.mode IN {OC.Const, OC.CC}) THEN
			IF x.mode = OC.RegX THEN FreeRegF(x.r);
			ELSE
				FreeReg(x.r);
				IF (x.mode = OC.Var1) THEN FreeReg(x.a) END
			END;
		END
	END Release;

	PROCEDURE CheckCodeSize*;
	BEGIN
		IF pc+constCnt > CodeLength - 64 (* safety range *) THEN OBS.Mark(210); pc := 0 END
	END CheckCodeSize;

	PROCEDURE PutVFP*(op, vn, vd, vm: LONGINT); (* Vector Floating Point Data Processing, 16 regs only *)
	BEGIN
		CheckConstReachability;
		code[pc]:=op+ ASH( vn, 16)+ ASH(vd, 12)+vm; IncPC;
	END PutVFP;

	PROCEDURE PutSDT1*(op, dest, base, rm, shift : LONGINT); (* SDT with Reg as Offset, rm is always added *)
	BEGIN
		ASSERT( (dest>=0) & (dest<=15) & (base>=0) & (base<=15) & (rm>=0) & (rm<=15) );
		ASSERT( (base#rm)  ); (* not really wrong, but the compiler SHOULD NOT generate such code *) 
		CheckConstReachability;
		code[pc]:=(((op*10H+base)*10H+dest)*100H+shift)*10H+rm + C25 + C23 - 20000000H; IncPC;
	END PutSDT1;
	
	PROCEDURE PutSDT*(op, dest, base, offset : LONGINT); (* Single Data Transfer: op = LDR/STR *)
	VAR r, op2: LONGINT;
	BEGIN
		ASSERT( (dest>=0) & (dest<=15) & (base>=0) & (base<=15));
		CheckConstReachability;
		IF (base = PC)  & (offset # 0) THEN offset := offset - pc*4 - 8 END ;
		IF (ABS(offset)>=100000H) THEN 
			IF flushing THEN HALT(100) END;
			DEC(allowConstFlushing);
			IF base = PC THEN DEC(offset,4) END;
			GetReg(r); LoadConst(r,offset);
			PutSDT1(op,dest,base,r,0);
			FreeReg(r);
			INC(allowConstFlushing);
		ELSE
			IF offset<0 THEN offset:=-offset; op2:=24H; (* SUBI *)
			ELSE INC(op, 8); op2:=28H; (* ADDI *)
			END;
			IF offset>=1000H THEN
				GetReg(r);
				code[pc]:=(((op2*10H+base)*10H+r)*10H+0AH)*100H+offset DIV 1000H - 20000000H; IncPC;
				FreeReg(r);
			ELSE r:=base;
			END;
			code[pc] := ((op*10H+ r)*10H + dest)*1000H + offset MOD 1000H - 20000000H; IncPC;
		END
	END PutSDT;
	
	PROCEDURE PutHDT1*(op, dest, base, rm : LONGINT); (* HDT with Reg as Offset, rm is always added *)
	BEGIN
		ASSERT ( (dest>=0) & (dest<=15) & (base>=0) & (base<=15) & (rm>=0) & (rm<=15) );
		ASSERT( base#rm ); (* not really wrong, but the compiler SHOULD NOT generate such code *)
		CheckConstReachability;
		code[pc]:= op + base*10000H + dest*1000H + rm + C23 - 20000000H; IncPC;
	END PutHDT1;
	
	PROCEDURE PutHDT*(op, dest, base, offset : LONGINT); (* Halfword Data Transfer: LDRSx/STRSx *)
	VAR r, op2: LONGINT;
	BEGIN
		ASSERT( (dest>=0) & (dest<=15) & (base>=0) & (base<=15));
		CheckConstReachability;
		IF (base = PC)  & (offset # 0) THEN offset := offset - pc*4 - 8 END ;
		IF ABS(offset)>=10000H THEN
			DEC(allowConstFlushing);
			IF base = PC THEN DEC(offset,4) END;
			GetReg(r); LoadConst(r,offset);
			PutHDT1(op,dest,base,r);
			FreeReg(r);
			INC(allowConstFlushing);
		ELSE
			IF offset<0 THEN offset:=-offset; op2:=24H; (* SUBI *)
			ELSE INC(op, C23); op2:=28H; (* ADDI *)
			END;
			IF (offset)>=100H THEN
				GetReg(r);
				code[pc]:=(((op2*10H+base)*10H+r)*10H+0CH)*100H+offset DIV 100H - 20000000H; IncPC;
				FreeReg(r);
			ELSE r:=base;
			END;
			offset:=(offset MOD 16) + (offset DIV 16 MOD 16 * 256);
			code[pc] := op+r*10000H + dest*1000H + offset +C22 - 20000000H; IncPC;
		END
	END PutHDT;

	PROCEDURE PutDP*(op, dest, reg1, reg2, shift : LONGINT); (* Data Processing with Register as 2nd operand *)
	BEGIN
		ASSERT( (reg1>=0) & (reg1<=15) & (reg2>=0) & (reg2<=15));
		CheckConstReachability;
		code[pc]:=(((op*10H+reg1)*10H+dest)*100H+shift)*10H+reg2 - 20000000H; IncPC;
	END PutDP;

	PROCEDURE PutFDT*(op, dest, base, offset : LONGINT); (* Float Data Transfer: VLDRx/VSTRx, use only positive versions! *)
	VAR r, op2: LONGINT;
	BEGIN
		ASSERT( (dest>=0) & (dest<=15) & (base>=0) & (base<=15));
		IF offset MOD 4 #0 THEN OBS.Mark(777) END;
		CheckConstReachability;
		IF (base = PC)  & (offset # 0) THEN offset := offset - pc*4 - 8 END;
		IF offset >=40000H THEN OBS.Mark(778) END;
		op2:=ADD;
		IF offset < 0 THEN offset:=-offset; DEC(op, C23); op2:= SUB END;
		DEC(allowConstFlushing);
		r:=base;
		IF (offset)>=1024 THEN
			GetReg(r);
			PutDP1( op2, r, base, offset DIV 400H * 400H );
			FreeReg(r);
		END;
		PutVFP( op, r, dest, offset DIV 4 MOD 100H);
		INC(allowConstFlushing);
	END PutFDT;

	PROCEDURE PutBDT*(op, base : LONGINT; regs : SET; writeback : BOOLEAN);
	BEGIN
		ASSERT( (base>=0) & (base<=15) );
		CheckConstReachability;
		code[pc]:=(op*10H+base)*10000H+SYSTEM.VAL(LONGINT,regs) - 20000000H; 
		IF writeback THEN INC(code[pc],200000H) END;
		IncPC;
	END PutBDT;
		
	PROCEDURE PutDP1*(op, dest, reg1, const : LONGINT); (* Data Processing with constant as 2nd operand *)
	VAR imm, r : LONGINT;
	BEGIN
		ASSERT( (reg1>=0) & (reg1<=15));
		IF (op=ADD) & (const<0) THEN op:=SUB; const:=-const 
		ELSIF (op=SUB) & (const<0) THEN op:=ADD; const:=-const
		END;
		CheckConstReachability;
		IF DecomposeConst(const,imm,r) THEN 
			code[pc]:=(((op*10H+reg1)*10H+dest)*10H+r)*100H+imm+C25 - 20000000H; IncPC;
		ELSE 
			DEC(allowConstFlushing);
			IF reg1 = PC THEN 
				IF op=ADD THEN DEC(const,4)
				ELSIF op=SUB THEN INC(const,4)
				ELSE HALT(211)
				END
			END;
			GetReg(r);
			LoadConst(r,const);
			PutDP(op,dest,reg1,r,0);
			FreeReg(r);
			INC(allowConstFlushing);
		END; 
	END PutDP1;

	PROCEDURE PutB*(op, target : LONGINT); (** Branch instruction. Target is an absolute word address *)
	BEGIN
		CheckConstReachability;
		code[pc]:=op*1000000H+(target-pc-2) MOD C24 - 20000000H; IncPC; 
	END PutB;
	
	PROCEDURE PutBabs*(op, target : LONGINT); (** Branch instruction. Target is an absolute word address *)
	BEGIN
		CheckConstReachability;
		code[pc]:=op*C24+(target MOD C24)- 20000000H; IncPC; 
	END PutBabs;

	PROCEDURE PutBext*(mno, pno : LONGINT); (** Branch to imported procedure *)
	BEGIN
		ASSERT((mno >= 0) & (mno < OC.MaxImps));
		ASSERT((pno >= 0) & (pno < 256));
		CheckConstReachability;
		code[pc]:=extcallfixlist*20000H+mno*100H+pno (*- 20000000H*); extcallfixlist:=pc; IncPC;
		(*code[pc]:=extcallfixlist*2000H+mno*100H+pno - 20000000H; extcallfixlist:=pc; INC(pc);*)
	END PutBext;
	
	PROCEDURE PutMUL*(op, dest, r1, r2, add : LONGINT); (** Multiplication *)
	BEGIN
		ASSERT(dest#r1); 
		ASSERT(~(PC IN {dest,r1,r2})); 
		CheckConstReachability;
		code[pc]:=op+100000H+((dest*10H+add)*10H+r2)*100H+90H+r1- 20000000H; IncPC; 
	END PutMUL;	
	
	PROCEDURE PutMULL*(op, rhi,rlo, r1, r2 : LONGINT); (** Long Multiplication *)
	BEGIN
		ASSERT((rlo#r1) & (rhi#r1) & (rlo#rhi)); 
		ASSERT(~(PC IN {rhi,rlo,r1,r2})); 
		CheckConstReachability;
		code[pc]:=op+((rhi*10H+rlo)*10H+r2)*100H+r1- 20000000H; IncPC; 
	END PutMULL;
	
	PROCEDURE SetCondition*(pc,cc : LONGINT); (** Sets condition of code[pc] to cc *)
	BEGIN
		code[pc]:=SYSTEM.LSH(cc, 28)+code[pc] MOD C28;
	END SetCondition;
(*
	PROCEDURE PutSWI*(cond, nr : LONGINT);	
	BEGIN
		ASSERT( cond#NV ); 
		CheckConstReachability;
		IF nr=MAX( INTEGER) THEN nr:=0CFFH END;
		code[pc]:= cond*C28+ 03A07000H+nr;		(* r7:= nr*)
		IncPC;
		PutBext( 0, 4);		(* call Kernel.SysHalt *)
	END PutSWI;
*)
	PROCEDURE PutSWI*(cond, nr : LONGINT);	(* LDC: trap with illegal instruction exception *)
	BEGIN
		ASSERT( cond#NV ); 
		CheckConstReachability;
		IF nr=MAX( INTEGER) THEN nr:=255 END;
		code[pc]:= cond*C28+ iinst+nr MOD 100H;		(* trap with illigal instruction*)
		IncPC;
	END PutSWI;

	PROCEDURE PutWord*(word : LONGINT);
	BEGIN
		CheckConstReachability; code[pc]:=word; IncPC;
	END PutWord;
	
	PROCEDURE PutWordAt*(loc, word : LONGINT);
	BEGIN
		code[loc]:=word;
	END PutWordAt;

	PROCEDURE InvertedCC*(cc : LONGINT) : LONGINT; (*inverted sense of condition code*)
	BEGIN
		IF ODD(cc) THEN RETURN cc-1 ELSE RETURN cc+1 END
	END InvertedCC;

	PROCEDURE RegisterRecType*(typ: OBT.Struct);
	BEGIN
		IF typ.extlev > MaxExts THEN OBS.Mark(233)
		ELSIF nofrecs < MaxRecs THEN
			recTab[nofrecs] := typ; INC(nofrecs); 
			IF level > 0 THEN INC(recTypesOffset,4); typ.adr:=-recTypesOffset; END
		ELSE OBS.Mark(223)
		END
	END RegisterRecType;
(*
	PROCEDURE SaveRegisters*(VAR gR: SET; VAR x: OBT.Item);
		VAR t: SET;
	BEGIN
		t := RegSet;
		IF x.mode IN {OC.Reg, OC.Var, OC.RegX, OC.Var1, OC.Par} THEN EXCL(RegSet, x.r) END ;
		IF x.mode IN {OC.RegX} THEN EXCL(RegSet, x.a) END ;
		gR := RegSet; 
		IF RegSet # {} THEN PutBDT(STMDB,SP,RegSet,TRUE) END;
		RegSet := t - RegSet;
	END SaveRegisters;
*)
PROCEDURE PushF( regs: SET);
VAR i, k: LONGINT;
BEGIN
	i:=FirstFReg;
	k:=0;
	WHILE i>=0 DO
		IF (i IN regs) THEN
			INC( k, 8); PutVFP( VSTRD -800000H, SP, i, k DIV 4);
		END;
		DEC(i);
	END;
	PutDP1( SUB , SP, SP, k);
END PushF;

	PROCEDURE SaveRegisters*(VAR gR, gF: SET; VAR x: OBT.Item);
		VAR t, tF: SET;
	BEGIN
		t := RegSet; tF:=RegSetF;
		IF x.mode IN {OC.Reg, OC.Var, OC.Var1, OC.Par} THEN EXCL(RegSet, x.r) END ;
		IF x.mode =OC.RegX THEN EXCL(RegSetF, x.r) END;
		gR := RegSet; gF:=RegSetF;
		IF RegSet # {} THEN PutBDT(STMDB,SP,RegSet,TRUE) END;
		IF RegSetF # {} THEN PushF(RegSetF) END;
		RegSet := t - RegSet;
		RegSetF := tF - RegSetF;
	END SaveRegisters;

(*	
	PROCEDURE RestoreRegisters*(gR: SET; VAR x: OBT.Item);
	VAR r : LONGINT; 
	BEGIN
		RegSet := gR; 
		(*set result mode*)
		x.mode := OC.Reg; x.r:=0; INCL(RegSet,0);
		IF x.typ.form = OC.LReal THEN 
			x.mode := OC.RegX; x.a:=1; INCL(RegSet,1);
			IF 1 IN gR THEN GetReg(r); PutDP(MOV,r,0,x.a,0); x.a := r END; 
		END;
		IF 0 IN gR THEN GetReg(r); PutDP(MOV,r,0,x.r,0); x.r := r END;  		
		IF gR # {} THEN PutBDT(LDMIA,SP,gR,TRUE) END
	END RestoreRegisters;
*)

PROCEDURE PopF( regs: SET);
VAR i, k: LONGINT;
BEGIN
	i:=0;
	k:=0;
	WHILE i<=FirstFReg DO
		IF (i IN regs) THEN
			PutVFP( VLDRD, SP, i, k DIV 4); INC( k, 8);
		END;
		INC(i);
	END;
	PutDP1( ADD , SP, SP, k);
END PopF;

	PROCEDURE RestoreRegisters*(gR, gF: SET; VAR x: OBT.Item);
	VAR r : LONGINT; 
	BEGIN
		RegSet := gR; RegSetF := gF; 
		(*set result mode*)
		IF (x.typ.form = OC.LReal) OR (x.typ.form = OC.Real) THEN 
			x.mode := OC.RegX; x.r:=0; INCL(RegSetF,0);
			IF 0 IN gF THEN GetRegF(r); PutVFP(VMOVRD, 0, r, x.r ); x.r := r END;  	
		ELSE
			x.mode := OC.Reg; x.r:=0; INCL(RegSet,0);
			IF 0 IN gR THEN GetReg(r); PutDP(MOV,r,0,x.r,0); x.r := r END;
		END;	
		IF gF # {} THEN PopF(gF) END;
		IF gR # {} THEN PutBDT(LDMIA,SP,gR,TRUE) END;
	END RestoreRegisters;

	PROCEDURE fixup*(loc: LONGINT);  (*enter pc at loc*)
	BEGIN
 		code[loc] := code[loc] DIV C24 * C24 + ((pc - loc - 2) MOD C24)
	END fixup;

	PROCEDURE FixLink*(L: LONGINT);
		VAR L1: LONGINT;
	BEGIN 
		WHILE L # 0 DO
			L1 := code[L] MOD C24;
			IF SYSTEM.LSH( code[L], -28) MOD 10H = NV THEN code[L]:= NOP; (* since ARMv5T B(L)NV is BLX; replace with NOP *)
			ELSE fixup(L);
			END;
			L := L1
		END
	END FixLink;

	PROCEDURE FixAddr*(L, addr : LONGINT);
	VAR L1 : LONGINT;
	BEGIN
		WHILE L # 0 DO
			L1 := code[L] DIV 20000H MOD 8000H;
			code[L]:=code[L] MOD 20000H + addr;
			AddAbsFixup(L); L := L1
		END
	END FixAddr;
	
	PROCEDURE FixupWith*(L, val: LONGINT);
	BEGIN 
		IF ABS(val) >= C24 THEN OBS.Mark(1002) END ;
		code[L] := (code[L] DIV C24) * C24 + (val MOD C24)
	END FixupWith;
	
	PROCEDURE FixLinkWith*(L, val: LONGINT);
		VAR L1: LONGINT;
	BEGIN 
		WHILE L # 0 DO
			L1 := code[L] MOD C24;
			FixupWith(L, val -L -2); L := L1
		END
	END FixLinkWith;

	PROCEDURE MergedLinks*(L0, L1: LONGINT): LONGINT;
	VAR L2, L3: LONGINT;
	BEGIN (*merge chains of the two operands of AND and OR *)
		IF L0 # 0 THEN L2 := L0;
			LOOP
				L3 := code[L2] MOD C24;
				IF L3 = 0 THEN EXIT END ;
				L2 := L3
			END ;
			code[L2] := (code[L2] DIV C24) * C24 + L1;
			RETURN L0
		ELSE RETURN L1
		END
	END MergedLinks;

	PROCEDURE Init*;
	BEGIN 
		pc := 0; level := 0; nofrecs := 0; RegSet := {};   RegSetF := {};
		strConstBlockCnt:=0; unknownProcCnt:=0; fixlist0:=0;
		constCnt := 0; constRefChain := -1; allowConstFlushing := 0; constDist := -1;
		extcallfixlist:=0; extaddrfixlist:=0; preferredReg:=-1; flushing:=FALSE;
		lrconstCnt := 0; lrconstRefChain := -1; 
		rconstCnt := 0; rconstRefChain := -1;
		strconstRefChain := -1;
		constJumpOvers:=0; 
		minConstBlock := MAX(LONGINT); 
		maxConstBlock := MIN(LONGINT); 
		nofConstBlocks:=0;
		totConsts:=0;
	END Init;

	PROCEDURE FindPtrs(typ: OBT.Struct; badr: LONGINT; VAR ptab: ARRAY OF LONGINT; VAR n: LONGINT);
		(*find all pointers in typ and enter their offsets (+badr) in ptab*)
	VAR fld: OBT.Object; btyp: OBT.Struct; i, m, s: LONGINT;
	BEGIN
		IF typ.form IN {OC.Pointer, OC.SysPtr} THEN
			IF n < MaxPtrs THEN ptab[n] := badr; INC(n) ELSE OBS.Mark(222) END
		ELSIF typ.form = OC.Record THEN
			btyp := typ.BaseTyp;
			IF btyp # NIL THEN FindPtrs(btyp, badr, ptab, n) END ;
			fld := typ.link;
			WHILE fld # NIL DO
				IF fld.name # "" THEN FindPtrs(fld.typ, fld.a0 + badr, ptab, n)
				ELSIF n < MaxPtrs THEN ptab[n] := fld.a0 + badr; INC(n)
				ELSE OBS.Mark(222)
				END ;
				fld := fld.next
			END
		ELSIF typ.form = OC.Array THEN
			btyp := typ.BaseTyp; m := typ.size DIV btyp.size;
			WHILE btyp.form = OC.Array DO
				m := btyp.size DIV btyp.BaseTyp.size * m; btyp := btyp.BaseTyp
			END ;
			IF btyp.form IN {OC.Pointer, OC.SysPtr, OC.Record} THEN
				i := 0; s := btyp.size;
				WHILE i < m DO FindPtrs(btyp, i*s + badr, ptab, n); INC(i) END
			END
		END
	END FindPtrs;

	PROCEDURE OutCode*(VAR name, progid: ARRAY OF CHAR; key: LONGINT);
		VAR
			f, i, m, np : LONGINT;
			tmp : LONGINT;
			refpos: LONGINT;
			nofcom, nofptrs: LONGINT;
			obj:    OBT.Object;
			typ:    OBT.Struct;
			ObjFile:   Files.File;
			out:    Files.Rider;
			PtrTab: ARRAY MaxPtrs OF LONGINT;
			ComTab: ARRAY MaxComs OF OBT.Object;

		PROCEDURE Collect; (*collect commands, and pointers*)
		VAR obj, par: OBT.Object; 
		BEGIN 
			obj := OBT.topScope.next;
			WHILE obj # NIL DO
				IF obj.mode = OC.LProc THEN
					IF obj.a0 = -1 THEN OBS.Mark(129)
					ELSIF obj.marked & (obj.typ.form = OC.NoTyp) THEN
						par := obj.dsc;
						IF ~OBT.IsParam(par) THEN (*command*)
							IF nofcom < MaxComs THEN ComTab[nofcom] := obj; INC(nofcom)
							ELSE OBS.Mark(232); nofcom := 0
							END
						END
					END
				ELSIF obj.mode = OC.Var THEN FindPtrs(obj.typ, obj.a0, PtrTab, nofptrs)
				END ;
				obj := obj.next
			END
		END Collect;

		PROCEDURE OutBaseTypes(typ: OBT.Struct);
		BEGIN
			IF typ.BaseTyp # NIL THEN
				OutBaseTypes(typ.BaseTyp);
				IF typ.BaseTyp.adr<0 THEN Files.WriteLInt(out,typ.BaseTyp.adr)
				ELSE Files.WriteLInt(out,typ.BaseTyp.mno*100H+typ.BaseTyp.adr)
				END
			END
		END OutBaseTypes;

		PROCEDURE OutRefBlk(first: OBT.Object; pc: LONGINT; name: ARRAY OF CHAR);
			VAR obj: OBT.Object; offset : LONGINT; dim : LONGINT; mode : INTEGER;
		BEGIN 
			obj := first;
			WHILE obj # NIL DO
				IF obj.mode = OC.LProc THEN OutRefBlk(obj.dsc, obj.a0, obj.name) END ;
				obj := obj.next
			END ;
			Files.Write(out, 0F8X); Files.WriteNum(out, pc*4); Files.WriteString(out, name);
			obj := first;
			WHILE obj # NIL DO
				mode := obj.mode;
				IF (mode = OC.Var) OR (mode = OC.Par) THEN
					f := obj.typ.form;
					IF f IN {OC.Array, OC.DynArr} THEN
						offset:=128; 
						IF f = OC.Array THEN dim:=obj.typ.size DIV obj.typ.BaseTyp.size
						ELSE dim:=0; mode := OC.Par (* open arrays always indirect *)
						END;
						f := obj.typ.BaseTyp.form;
					ELSE
						offset:=0
					END;
					IF (f IN {OC.Byte .. OC.Set, OC.Pointer}) THEN
						Files.Write(out, CHR(mode)); Files.Write(out, CHR(f+offset));
						IF offset#0 THEN Files.WriteNum(out,dim) END;
						Files.WriteNum(out, obj.a0); Files.WriteString(out, obj.name)
					END
				END ;
				obj:= obj.next
			END
		END OutRefBlk;

	BEGIN
		FlushRConsts;
		FlushLRConsts;
		FixStrAdrs;
		ObjFile := Files.New(name);
		IF ObjFile # NIL THEN
			Files.Set(out, ObjFile, 0);
			nofcom := 0; nofptrs := 0;
			(* WHILE nofptrs < nofrecs DO PtrTab[nofptrs] := recTab[nofptrs].adr; INC(nofptrs) END ; *)
			Collect; 
		(*header block*)
			Files.Write(out, ObjMark); Files.Write(out, "0"); 
			Files.WriteLInt(out, refpos); (* will be fixed at the end of OutCode *)
			Files.WriteLInt(out, moduleBody*4); (* not necessary, but we don't want to scan RefBlks to get the entry point! *)
			Files.WriteInt(out, OBT.nofGmod); 
			Files.WriteInt(out, OBT.entno);
			Files.WriteInt(out, SHORT(nofptrs)); 
			Files.WriteInt(out, SHORT(nofcom));
			Files.WriteLInt(out, strConstBlockCnt*4); 
			Files.WriteLInt(out, recTypesOffset); (* data size *)
			Files.WriteLInt(out, pc*4);  (* code size *)
			Files.WriteInt(out, nofrecs);
			Files.WriteLInt(out, key); 
			Files.WriteString(out, progid);
		(*import block*)
			Files.Write(out,085X);
			i := 0;
			WHILE i < OBT.nofGmod DO
				obj := OBT.GlbMod[i];
				Files.WriteLInt(out, obj.a1);  (* key *)
				Files.WriteString(out, obj.name); 
				INC(i)
			END ;
		(*entry block*)
			Files.Write(out,082X);
			Files.WriteBytes(out, OBT.entry, 4*OBT.entno);  
		(*pointer block*) 
			Files.Write(out,084X);
			i := 0; WHILE i < nofptrs DO Files.WriteLInt(out, PtrTab[i]); INC(i) END ;
		(*command block*) 
			Files.Write(out,083X);
			i := 0;
			WHILE i < nofcom DO
				obj := ComTab[i]; Files.WriteString(out, obj.name);
				Files.WriteLInt(out, obj.a0*4); INC(i) (* proc addrs are treated as word-addrs in sym-files and the compiler, so we multiply by 4 *)
			END ;
		(*code block*)
			Files.Write(out,088X);
(*
			WHILE strfixlist#0 DO (* fixup string addr locations *)
				tmp:=code[strfixlist] DIV 20000H MOD 8000H; code[strfixlist]:=code[strfixlist] MOD 20000H+pc*4; AddAbsFixup(strfixlist);
				strfixlist:=tmp
			END;
*)
			Files.WriteBytes(out, code, pc*4);
		(*string constants block*) 
			Files.Write(out,087X);
			Files.WriteBytes(out, strConstBlock,strConstBlockCnt*4);
		(*fixups*) 
			Files.Write(out,086X);
			Files.WriteLInt(out, extcallfixlist*4); (* Now byte address! *)
			Files.WriteLInt(out, extaddrfixlist*4); (* Now byte address! *)
			Files.WriteLInt(out, fixlist0*4); (* Now byte address! *)
		(*typdesc block*) 
			Files.Write(out,089X);
			i := 0;
			WHILE i < nofrecs DO
				typ := recTab[i]; recTab[i] := NIL; INC(i);
				np := 0; 
				FindPtrs(typ, 0, PtrTab, np); 
				Files.WriteLInt(out, typ.adr);   						  (* addr of tag (tag=ptr to Type Desc) *)
				Files.WriteInt(out,SHORT(np));						(* #pointers *)
				Files.WriteLInt(out,typ.size);  							(* Record size *)
				IF typ.strobj#NIL THEN Files.WriteString(out,typ.strobj.name)  (* Type name *)
				ELSE Files.WriteString(out,"");
				END;
				Files.Write(out, CHR(typ.extlev));					(* Nr of BaseTypes *)
				OutBaseTypes(typ);
				m := 0;
				WHILE m < np DO Files.WriteLInt(out, PtrTab[m]); INC(m) END
			END ;
		(*ref block*)
			refpos := Files.Pos(out);
			Files.Write(out,08BX);
			OutRefBlk(OBT.topScope.next, moduleBody, "$$");
			Files.Set(out, ObjFile, 2); Files.WriteLInt(out, refpos);
  	  	IF ~OBS.scanerr THEN Files.Register(ObjFile) END
		ELSE OBS.Mark(153)
		END
	END OutCode;

BEGIN
	NEW(wasderef);
END OBC.
