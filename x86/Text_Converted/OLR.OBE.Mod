MODULE OBE;  (*NW 7.6.87 / 10.7.93 / as 1.12.98*)

(*	Peter Matthias
		2014-07-31	p.m.:	changed OBC.PutMUL(OBC.MLA to not use OBC.PC as operand, not allowed in non-cortex devices
		2016-01-13	works now with (LONG-)REALs directly loaded in FPU registers
		2016-01-15	(LONG) REAL constants directcly loaded in VFP registers; direct loading of string addresses
		2016-01-17	use VCMPZx for comparing with 0.0
		2016-03-02	fixed x DIV 1 in Op
		2016-10-24	removed code generation for OBT.FnSysEnableInterrupts OBT.FnSysDisableInterrupts OBT.FnSysRestoreInterrupts

*)

	IMPORT SYSTEM, OBS, OBT, OBC, OC := OBM;

CONST
	(*	FP operations, Vn bit 16..19, 7; Vd bit 12..15, 22; Vm bit 0..3, 5	OBC.PutVFP(opcode, Vn, Vd, Vm, nbit7, dbit22, mbit5) *)
	VMOV1S= 0EE000A10H;		(* Fx, Rx, 0 *)
	VMOV1SB= 0EE100A10H;	(* single precision to ARM; A8.8.343  (float, ARM, 0)*)	
(*	VMOV2S= 0EC400A10H;	(* 2 single precision to VFP; A8.8.344 *)*)
	VMOVD= 0EC400B10H;	(* double precision to VFP; A8.8.345 *)
	VMOVDB= 0EC500B10H;	(* double precision to ARM; A8.8.345 *)

	VPUSHS= 0ED2D0A00H;	VPUSHD= 0ED2D0B00H;
	VPOPS = 0ECBD0A00H;	VPOPD = 0ECBD0B00H;

	VADDS = 0EE300A00H;	VADDD= 0EE300B00H;
	VSUBS= 0EE300A40H;	VSUBD= 0EE300B40H;
	VMULS= 0EE200A00H;	VMULD= 0EE200B00H;
	VDIVS= 0EE800A00H;	VDIVD= 0EE800B00H;
	VNEGS = 0EEB10A40H; 	VNEGD = 0EEB10B40H;
	VCVTLS = 0EEBD0AC0H;	VCVTLD = 0EEBD0BC0H;	(* LONGINT:= ENTIER(REAL) *)
	VCVTSL = 0EEB80AC0H;	VCVTDL = 0EEB80BC0H;	(* REAL := LONGINT *)
	VCVTSD = 0EEB70BC0H;	VCVTDS = 0EEB70AC0H;
	VABSS = 0EEB00AC0H;	VABSD = 0EEB00BC0H;

	VCMPS = 0EEB40A40H;	VCMPD = 0EEB40B40H;	(* Vd, Vm; vquiet nan *)
	VCMPZS = 0EEB50A40H;	VCMPZD = 0EEB50B40H;	(* Vd, Zero ; vquiet nan *)

	VMRS = 0EEF1FA10H;	(* vmrs APSR_nzcv, FPSCR *)

	VAR inxchk*, ovfchk*: BOOLEAN;
			log: INTEGER;   (*side effect of mant*)
			intSet, realSet: SET;
			modName* : ARRAY 32 OF CHAR; (* name of module *)

	PROCEDURE mant(x: LONGINT): LONGINT;  (*x DIV 2^log*)
	BEGIN
		log := 0;
		IF x > 0 THEN
			WHILE ~ODD(x) DO x := x DIV 2; INC(log) END
		END ;
		RETURN x
	END mant;

	PROCEDURE ImportSoftfloat*;
	VAR FName : ARRAY 32 OF CHAR; impid : ARRAY 32 OF CHAR;
	BEGIN
		IF OBT.softfloatImport=NIL THEN
			impid:="SoftFloat"; 
			OBT.Import(impid, modName, impid)
		END 
	END ImportSoftfloat;
	
	PROCEDURE MakeItem*(obj : OBT.Object; VAR x : OBT.Item; level : LONGINT);
	BEGIN
		x.mode := obj.mode; x.typ := obj.typ; x.a := obj.a0; x.b := obj.a1; x.obj:=obj; x.lev:=level;
		IF x.mode=OC.Var THEN
			IF x.lev<=0 THEN x.r:=OBC.PC ELSE x.r:=OBC.FP END
		ELSIF x.mode=OC.Par THEN
			x.r:=OBC.FP
		END
	END MakeItem;

	PROCEDURE setCC*(VAR x: OBT.Item; cc: LONGINT);
	BEGIN
		OBC.Release(x);
		x.typ := OBT.booltyp; x.mode := OC.CC; x.r := cc; x.a := 0; x.b := 0
	END setCC;

	PROCEDURE AdjustBaseReg(VAR x : OBT.Item);
	VAR leveldiff, r : LONGINT;
	BEGIN
		IF x.lev<0 THEN (* imported, load extern address *)
			OBC.GetRegNoPref(x.r); OBC.LoadExtAddr(x.r,-x.lev,x.a); x.a:=0; x.lev:=OBC.level;
		ELSE
			leveldiff:=OBC.level-x.lev;
			IF (x.lev>0) & (leveldiff>0) & (x.mode IN {OC.Var,OC.Var1,OC.Par}) & (x.r=OBC.FP) THEN 
				(* local var/par of a outer procedure *)
				OBC.GetRegNoPref(r);
				OBC.PutSDT(OBC.LDR,r,x.r,8); (* Dyn. Link at [FP+8] *)
				WHILE leveldiff>1 DO OBC.PutSDT(OBC.LDR,r,r,8); DEC(leveldiff) END;
				x.r:=r;
			(* ELSE Nothing to adjust *)
			END
		END
	END AdjustBaseReg;

	PROCEDURE load*(VAR x: OBT.Item);
	VAR y: OBT.Item; xr: LONGINT;
	BEGIN
	IF (x.mode=OC.RegX) & (x.typ.form # OC.Real) THEN OBC.GetReg(xr); OBC.PutVFP( VMOV1SB, x.r, xr, 0); OBC.FreeRegF(x.r); x.r:=xr; x.mode:=OC.Reg;
	ELSE
		IF (x.mode # OC.Reg) & (x.mode # OC.RegX) THEN 
			y := x;
			IF y.mode = OC.Const THEN
				IF x.typ.form = OC.Real THEN
					OBC.GetRegF(x.r);
					OBC.LoadRConst(x.r,y.a);
					x.mode:=OC.RegX;
				ELSE
					OBC.GetReg(x.r);
					OBC.LoadConst(x.r,y.a);
					x.mode:=OC.Reg;
				END;
			ELSE 
				AdjustBaseReg(y);
				OBC.GetReg(x.r);
				IF y.mode IN {OC.Par, OC.Par1} THEN 
					OBC.PutSDT(OBC.LDR,x.r,y.r,y.a); y.a := y.b; y.b:=0; y.r:=x.r;
					IF y.mode=OC.Par1 THEN y.mode:=OC.Var1 ELSE y.mode:=OC.Var END
				END;
				x.mode:=OC.Reg;
				IF y.mode = OC.Var1 THEN 
					CASE y.typ.form OF 
						OC.Byte, OC.Char, OC.Bool : OBC.PutSDT1(OBC.LDRB,x.r,y.r,y.a,y.b*8);
						|OC.SInt : OBC.PutDP(OBC.MOV,y.a,0,y.a,y.b*8); OBC.PutHDT1(OBC.LDRSB,x.r,y.r,y.a); 
						|OC.Int : OBC.PutDP(OBC.MOV,y.a,0,y.a,y.b*8); OBC.PutHDT1(OBC.LDRSH,x.r,y.r,y.a);
						|OC.ProcTyp, OC.Pointer, OC.SysPtr, OC.LInt, OC.Set: OBC.PutSDT1(OBC.LDR, x.r, y.r, y.a,y.b*8)
						|OC.Real: OBC.FreeReg(x.r); OBC.GetRegF(x.r); 
								OBC.PutDP(OBC.ADD,y.a,y.r,y.a,y.b*8); OBC.PutFDT( OBC.VLDRS, x.r, y.a, 0); x.mode:=OC.RegX; (*OBC.PutSDT(OBC.LDR, x.r, y.a, 0)*)
						|OC.Undef :
					ELSE
					END;
					OBC.FreeReg(y.a);
				ELSE 
					CASE y.typ.form OF 
						OC.Byte, OC.Char, OC.Bool : OBC.PutSDT(OBC.LDRB,x.r,y.r,y.a)
						|OC.SInt : OBC.PutHDT(OBC.LDRSB,x.r,y.r,y.a)
						|OC.Int : OBC.PutHDT(OBC.LDRSH,x.r,y.r,y.a)
						|OC.ProcTyp, OC.Pointer, OC.SysPtr, OC.LInt, OC.Set: OBC.PutSDT(OBC.LDR, x.r, y.r, y.a)
						|OC.Real: OBC.FreeReg(x.r); OBC.GetRegF(x.r); 
								OBC.PutFDT( OBC.VLDRS, x.r, y.r, y.a); x.mode:=OC.RegX;	(*OBC.PutSDT(OBC.LDR, x.r, y.r, y.a)*)
						|OC.Undef :
					ELSE
					END
				END;
				IF (x.typ.form# OC.Real) & (y.typ.form# OC.Real) & (x.r#y.r) THEN OBC.FreeReg(y.r) END;
			END;
			x.lev:=OBC.level;
		END
	END;
	IF (x.mode=OC.Reg) & (x.typ.form = OC.Real) THEN
		OBC.GetRegF(xr); OBC.PutVFP( VMOV1S, xr, x.r, 0); OBC.FreeReg(x.r); x.r:=xr; x.mode:=OC.RegX;
	END;
	END load;

	PROCEDURE loadB*(VAR x: OBT.Item);  (*CC-Mode*)
		VAR cc : LONGINT; 
	BEGIN
		cc:=x.r; x.mode:=OC.Reg; OBC.GetReg(x.r);
		IF (x.a=0) & (x.b=0) THEN (* no fix-lists, use short version *)
			OBC.PutDP1(OBC.MOV,x.r,0,0); OBC.SetCondition(OBC.pc-1,OBC.InvertedCC(cc));
			OBC.PutDP1(OBC.MOV,x.r,0,1); OBC.SetCondition(OBC.pc-1,cc); 
		ELSE 
			DEC(OBC.allowConstFlushing);
			OBC.PutBabs(OBC.B,x.b); OBC.SetCondition(OBC.pc-1,OBC.InvertedCC(cc));  
			x.b := OBC.pc-1; 
			OBC.FixLink(x.a);
			OBC.PutDP1(OBC.MOV,x.r,0,1);
			OBC.PutB(OBC.B,OBC.pc+2);
			OBC.FixLink(x.b);
			OBC.PutDP1(OBC.MOV,x.r,0,0);
			INC(OBC.allowConstFlushing);
		END; 
		x.lev:=OBC.level;
	END loadB;

	PROCEDURE loadInto(VAR x : OBT.Item; r : LONGINT);
	(* Loads x into Register r *)
	BEGIN 
		OBC.SetPreferredReg(r); 
		IF x.mode=OC.CC THEN loadB(x) ELSE load(x) END;
		IF x.r#r THEN
			IF r IN OBC.UsedRegisters() THEN OBS.Mark(215) END; 
			OBC.PutDP(OBC.MOV,r,0,x.r,0);
			OBC.FreeRegs(OBC.UsedRegisters()-{x.r}+{r});
			x.r:=r;
		END;
		x.lev:=OBC.level;
	END loadInto;
			
	PROCEDURE loadForWriteback*(VAR x,y : OBT.Item);
	(** loads x into a register that will be described by y. Adjusts x so that a following store(x,...) will write the value to the right place *)
	VAR tmpreg : LONGINT;
	BEGIN
		IF x.mode IN {OC.Reg, OC.Const} THEN HALT(205) END;
		IF x.mode = OC.Const THEN HALT(205) END;
		AdjustBaseReg(x);
		OBC.GetReg(y.r);
		IF x.mode IN {OC.Par, OC.Par1} THEN 
			OBC.GetReg(tmpreg);
			OBC.PutSDT(OBC.LDR,tmpreg,x.r,x.a); x.a := x.b; x.b:=0; x.r:=tmpreg;
			IF x.mode=OC.Par1 THEN x.mode:=OC.Var1 ELSE x.mode:=OC.Var END
		END;
		IF x.mode = OC.Var1 THEN 
			CASE x.typ.form OF 
				OC.Byte, OC.Char, OC.Bool : OBC.PutSDT1(OBC.LDRB,y.r,x.r,x.a,x.b*8)
				|OC.Int: OBC.PutDP(OBC.MOV,x.a,0,x.a,x.b*8); OBC.PutHDT1(OBC.LDRSH,y.r,x.r,x.a)
				|OC.SInt: OBC.PutDP(OBC.MOV,x.a,0,x.a,x.b*8); OBC.PutHDT1(OBC.LDRSB,y.r,x.r,x.a)
				|OC.ProcTyp, OC.Pointer, OC.SysPtr, OC.LInt, OC.Set: OBC.PutSDT1(OBC.LDR, y.r, x.r, x.a,x.b*8)
				|OC.Real: OBS.Mark(718); OBC.PutDP(OBC.ADD,x.a,x.r,x.a,x.b*8); OBC.PutFDT( OBC.VSTRS, y.r, x.a, 0); (*OBC.PutSDT(OBC.STR, y.r,  x.a, 0)*)
				|OC.Undef :
			ELSE
			END
		ELSE
			CASE x.typ.form OF 
				OC.Byte, OC.Char, OC.Bool : OBC.PutSDT(OBC.LDRB,y.r,x.r,x.a)
				|OC.Int : OBC.PutHDT(OBC.LDRSH,y.r,x.r,x.a)
				|OC.SInt : OBC.PutHDT(OBC.LDRSB,y.r,x.r,x.a)
				|OC.ProcTyp, OC.Pointer, OC.SysPtr, OC.LInt, OC.Set: OBC.PutSDT(OBC.LDR, y.r, x.r, x.a)
				|OC.Real: OBS.Mark(719); (*OBC.PutSDT(OBC.LDR, y.r, x.r, x.a)*)
				|OC.Undef :
			ELSE
			END
		END;
		y.mode:=OC.Reg
	END loadForWriteback;

	PROCEDURE store*(VAR x,y : OBT.Item); (* x:=y *)
	VAR r2, f2, wb, wb2 : LONGINT; 
	BEGIN
		IF x.mode=OC.RegX THEN load(y); OBC.PutVFP( OBC.VMOVRD, 0, x.r, y.r);
		ELSIF x.mode=OC.Reg THEN
			OBC.FreeReg(x.r); loadInto(y,x.r);
		ELSE
			IF (y.mode#OC.Reg) & (y.mode#OC.RegX) THEN 
				IF y.mode=OC.CC THEN loadB(y) ELSE load(y) END;
			END;
			IF (x.typ.form= OC.Real) & (y.mode=OC.Reg) THEN OBC.GetRegF( f2); OBC.PutVFP( VMOV1S, f2, y.r, 0); y.r:=f2  END;
			AdjustBaseReg(x); 
			IF x.mode IN {OC.Par, OC.Par1} THEN
				OBC.GetReg(r2); OBC.PutSDT(OBC.LDR,r2,x.r,x.a); x.r:=r2; x.a:=x.b; x.b:=0;
				IF x.mode=OC.Par THEN x.mode:=OC.Var ELSE x.mode:=OC.Var1 END
			END;
			IF x.mode = OC.Var1 THEN 
				CASE x.typ.form OF
					OC.Byte, OC.Char, OC.Bool, OC.SInt : OBC.PutSDT1(OBC.STRB,y.r, x.r,x.a,x.b*8)
					|OC.Int: OBC.PutDP(OBC.MOV,x.a,0,x.a,x.b*8); OBC.PutHDT1(OBC.STRH,y.r, x.r,x.a) 
					|OC.ProcTyp, OC.Pointer, OC.SysPtr, OC.LInt, OC.Set: OBC.PutSDT1(OBC.STR, y.r, x.r, x.a, x.b*8)
					|OC.Real: OBC.PutDP(OBC.ADD,x.a,x.r,x.a,x.b*8); OBC.PutFDT( OBC.VSTRS, y.r, x.a, 0); (*OBC.PutSDT(OBC.STR, y.r,  x.a, 0)*)
					|OC.Undef :
				ELSE
				END
			ELSE
				IF x.mode = OC.Var2 THEN wb:=2; wb2:=200000H (* Set write-back bit *) ELSE wb:=0; wb2:=0 END;
				CASE x.typ.form OF
					OC.Byte, OC.Char, OC.Bool, OC.SInt : OBC.PutSDT(OBC.STRB+wb,y.r, x.r,x.a)
					|OC.Int: OBC.PutHDT(OBC.STRH+wb2,y.r, x.r,x.a) 
					|OC.ProcTyp, OC.Pointer, OC.SysPtr, OC.LInt, OC.Set : 
						IF y.mode=OC.RegX THEN OBC.PutFDT( OBC.VSTRS, y.r, x.r, x.a ) ELSE OBC.PutSDT(OBC.STR+wb, y.r, x.r, x.a) END;
					|OC.Real : OBC.PutFDT( OBC.VSTRS, y.r, x.r, x.a );	(* OBC.PutSDT(OBC.STR, y.r, x.r, x.a);*)
								 IF x.mode = OC.Var2 THEN OBC.PutDP1(OBC.ADD,x.r,x.r,x.a) END;
					|OC.Undef :
				ELSE
				END
			END
		END;
		IF x.typ.form=OC.Real THEN OBC.FreeRegF(x.r); OBC.FreeRegF(y.r);
		ELSE OBC.Release(y); OBC.Release(x)
		END;
	END store;
	
	PROCEDURE loadCC*(VAR x: OBT.Item);
	BEGIN
		IF x.typ.form = OC.Bool THEN
			IF x.mode=OC.Const THEN
				IF x.a=0 THEN setCC(x,OBC.NV) ELSE setCC(x,OBC.AL) END
				(* ARM8-Manual says that NV should not be used anymore! There should be second pass in OutCode that replaces *)
				(* every instruction with cond code NV by a NOP (= MOV R0,R0 )    *)
			ELSE load(x); OBC.PutDP1(OBC.CMP, 0, x.r, 0); OBC.Release(x); setCC(x, OBC.NE)
			END
		ELSE OBS.Mark(120); setCC(x,0);
		END
	END loadCC;

	PROCEDURE loadAdr*(VAR x: OBT.Item);
		VAR y: OBT.Item; 
	BEGIN
		IF (x.mode=OC.Const) & (x.typ.form=OC.String) THEN
			IF ~x.obj.ext.entered THEN x.obj.ext.entered:=TRUE; OBC.EnterStringConst(x) END;
			OBC.GetReg(x.r); x.mode:=OC.Reg;
			OBC.LoadStringConst(x.r,x.obj.a0);
		ELSIF x.mode=OC.LProc THEN
			OBC.GetReg(x.r); x.mode:=OC.Reg;
			IF x.lev<0 THEN
				OBC.LoadExtAddr(x.r,-x.lev,x.a); x.lev:=OBC.level;
			ELSE
				IF x.a=-1 THEN OBC.LoadUnknownProcAddr(x.r,x.obj)
				ELSE OBC.PutDP1(OBC.ADD,x.r,OBC.PC,x.a*4 - OBC.pc*4 -8)
				END
			END
		ELSE
			AdjustBaseReg(x);
			IF (x.mode IN {OC.Var, OC.Var1, OC.LProc}) & (x.r=OBC.PC) THEN x.a:=x.a - OBC.pc*4 -8 END; 
			y:=x;
			OBC.GetReg(x.r);
			CASE x.mode OF
				OC.Var: IF y.a#0 THEN OBC.PutDP1(OBC.ADD,x.r,y.r,y.a) 
							 ELSIF x.r#y.r THEN OBC.PutDP(OBC.MOV,x.r,0,y.r,0);
							 END;
				|OC.Var1: OBC.PutDP(OBC.ADD,x.r,y.r,y.a,y.b*8) (* ADD x.r, y.r, y.a LSL y.b *)
				|OC.Par: OBC.PutSDT(OBC.LDR,x.r,y.r,y.a); IF y.b#0 THEN OBC.PutDP1(OBC.ADD,x.r,x.r,y.b) END;
				|OC.Par1: OBC.PutSDT(OBC.LDR,x.r,y.r,y.a); OBC.PutDP(OBC.ADD,x.r,x.r,y.b,0);
			ELSE
			END;
			IF x.r#y.r THEN OBC.FreeReg(y.r) END;
		END;
		x.mode:=OC.Reg; x.a:=0; x.b:=0
	END loadAdr;

	PROCEDURE loadLRealF(VAR x : OBT.Item);
	VAR f1, xr, xa: LONGINT; y: OBT.Item; lr: LONGREAL;
	BEGIN
		IF x.mode#OC.RegX THEN
			OBC.GetRegF(f1);
			IF x.mode=OC.Const THEN

				SYSTEM.PUT( SYSTEM.ADR( lr)+0, x.a);
				SYSTEM.PUT( SYSTEM.ADR( lr)+4, x.b);
				OBC.LoadLRConst( f1, lr);
(*
				OBC.GetReg(xa);OBC.GetReg(xr);
				OBC.LoadConst(xr,x.a); OBC.LoadConst(xa,x.b);
				OBC.PutVFP( VMOVD, xa, xr, f1);
				OBC.FreeReg(xa);OBC.FreeReg(xr);
*)
			ELSE
				loadAdr(x);
				OBC.PutFDT( OBC.VLDRD, f1, x.r, 0);
				OBC.Release(x)
			END;
			x.r:=f1; x.mode:=OC.RegX
		END;
	END loadLRealF;
	
	PROCEDURE storeLReal*(VAR x,y : OBT.Item); (* x:=y *)
	BEGIN
		loadLRealF(y);
		IF x.mode=OC.RegX THEN
			IF x.r#y.r THEN OBC.PutVFP(OBC.VMOVRD, 0, x.r, y.r) END;
		ELSE
			loadAdr(x);
			OBC.PutFDT( OBC.VSTRD, y.r, x.r, 0);
		END;
		OBC.Release(x); OBC.Release(y)
	END storeLReal;
	
	PROCEDURE PushWord*(x : OBT.Item); (** pushs x onto the stack *)
	VAR stack : OBT.Item;
	BEGIN
		load(x); 
		IF x.typ=OBT.realtyp THEN	ASSERT(x.mode=OC.RegX);
			OBC.PutVFP( VPUSHS , 0, x.r, 1);
			OBC.Release(x)
		ELSE
			stack.mode:=OC.Var2; stack.r:=OBC.SP; stack.typ:=OBT.linttyp; stack.a:=-4;
			store(stack,x);
		END;
	END PushWord;
	
	PROCEDURE PushLReal*(x : OBT.Item); (** pushs x onto the stack *)
	VAR stack, y : OBT.Item;
	BEGIN
		ASSERT(x.typ=OBT.lrltyp);
		loadLRealF(x); ASSERT(x.mode=OC.RegX);
		OBC.PutVFP( VPUSHD , 0, x.r, 2);
		OBC.Release(x)
	END PushLReal;

	PROCEDURE OverflowCheck(x : OBT.Item);
	VAR r : LONGINT;
	BEGIN
		IF ovfchk THEN
			ASSERT(x.mode=OC.Reg); 
			CASE x.typ.form OF
				OC.SInt:
					OBC.GetReg(r);
					OBC.PutDP(OBC.MOVS,r,0,x.r,7*8+4); (* MOV r, reg, ASR 7 *)
					OBC.PutDP1(OBC.CMN,0,r,1); OBC.SetCondition(OBC.pc-1,OBC.NE);
					OBC.PutSWI(OBC.NE,OC.OverflowTrap);
					OBC.FreeReg(r);
				|OC.Int:
					OBC.GetReg(r);
					OBC.PutDP(OBC.MOVS,r,0,x.r,15*8+4); (* MOV r, reg, ASR 15 *)
					OBC.PutDP1(OBC.CMN,0,r,1); OBC.SetCondition(OBC.pc-1,OBC.NE);
					OBC.PutSWI(OBC.NE,OC.OverflowTrap);
					OBC.FreeReg(r);
				|OC.LInt:
					OBC.PutSWI(OBC.VS,OC.OverflowTrap);
				|OC.Real,OC.LReal: (* nothing to do; floating point routines catch overflows *)
				|OC.Undef : 
			END
		END
	END OverflowCheck;
	
	PROCEDURE DPInstr(op: LONGINT; VAR x, y: OBT.Item);
	BEGIN
		load(x);
		IF y.mode # OC.Const THEN load(y); OBC.PutDP(op,x.r,x.r,y.r,0); OBC.Release(y); 
		ELSE OBC.PutDP1(op,x.r,x.r,y.a)
		END
	END DPInstr;
	
	PROCEDURE DPInstrWriteback(op : LONGINT; VAR x,y : OBT.Item; ovflCheck : BOOLEAN);
	VAR res : OBT.Item;
	BEGIN
		loadForWriteback(x,res); res.typ := x.typ;
		IF y.mode # OC.Const THEN load(y); OBC.PutDP(op,res.r,res.r,y.r,0); OBC.Release(y); 
		ELSE OBC.PutDP1(op,res.r,res.r,y.a)
		END;
		IF ovflCheck THEN OverflowCheck(res) END;
		store(x,res); 
	END DPInstrWriteback;

	PROCEDURE cmp(VAR x, y : OBT.Item);
	BEGIN 
		load(x);
		IF y.mode # OC.Const THEN 
			load(y); OBC.PutDP(OBC.CMP,0,x.r,y.r,0); OBC.Release(y);
		ELSE 
			OBC.PutDP1(OBC.CMP,0,x.r,y.a);
		END
	END cmp;

	PROCEDURE Inc*(VAR x, y: OBT.Item);
	BEGIN DPInstrWriteback(OBC.ADD,x, y, TRUE);
	END Inc;

	PROCEDURE SetIntType*(VAR x: OBT.Item);
		VAR v: LONGINT;
	BEGIN v := x.a;
		IF (-80H <= v) & (v <= 7FH) THEN x.typ := OBT.sinttyp
		ELSIF (-8000H <= v) & (v <= 7FFFH) THEN x.typ := OBT.inttyp
		ELSE x.typ := OBT.linttyp
		END
	END SetIntType;

	PROCEDURE MakeConstItem*(VAR x: OBT.Item; c : LONGINT; typ : OBT.Struct);
	BEGIN
		x.mode:=OC.Const; x.a:=c; x.typ:=typ; x.obj:=NIL;
	END MakeConstItem;
	
	PROCEDURE Index*(VAR x, y: OBT.Item);
		VAR  f : INTEGER; i, n, s0, reg: LONGINT;
			eltyp: OBT.Struct; z, c : OBT.Item; 
	BEGIN
		f := y.typ.form;
		IF ~(f IN intSet) THEN OBS.Mark(80); y.typ := OBT.inttyp END ;
		IF x.typ = NIL THEN HALT(80) END ;
		IF x.lev<0 THEN loadAdr(x); x.mode:=OC.Var; x.a:=0; x.lev:=OBC.level END;
		IF x.typ.form = OC.Array THEN
			eltyp := x.typ.BaseTyp;
			IF eltyp = NIL THEN HALT(81) END ;
			n := x.typ.size DIV eltyp.size;
			IF y.mode = OC.Const THEN
				IF (0 <= y.a) & (y.a < n) THEN i := y.a * eltyp.size ELSE OBS.Mark(81); i := 0 END ;
				IF x.mode = OC.Var THEN INC(x.a, i); x.obj := NIL
				ELSIF x.mode = OC.Par THEN INC(x.b,i); x.obj := NIL;
				ELSE loadAdr(x); x.a := i; x.mode := OC.Var;
				END
			ELSE
				AdjustBaseReg(x);
				IF x.mode = OC.Par THEN
					OBC.GetReg(reg); OBC.PutSDT(OBC.LDR, reg, x.r, x.a); 
					x.mode := OC.Var; OBC.FreeReg(x.r); x.r := reg; x.a := x.b
				ELSIF x.mode = OC.Par1 THEN
					OBC.GetReg(reg); OBC.PutSDT(OBC.LDR, reg, x.r, x.a); 
					x.mode := OC.Var1; OBC.FreeReg(x.r); x.r := reg; x.a := x.b; x.b:=0;
				END;
				load(y); 
				IF inxchk THEN
					OBC.PutDP1(OBC.CMP,0,y.r,n);
					OBC.PutSWI(OBC.CS,OC.IndexTrap); (* unsigned higher or same *)
				END;
				s0 := eltyp.size; n := 0;
				WHILE ~ODD(s0) DO s0 := s0 DIV 2; INC(n) END ;
				IF s0 = 1 THEN 
					IF (x.mode = OC.Var) & (x.a=0) THEN 
					 	x.mode := OC.Var1; x.a:=y.r; x.b := n;
					 ELSIF (x.mode=OC.Var) OR (x.mode=OC.Var1) THEN
						IF x.r = OBC.PC THEN x.a:=x.a-(OBC.pc*4 + 8) END;
						OBC.PutDP(OBC.ADD,y.r,x.r,y.r, n*8); (* ADD reg,x.r,y.r LSL n *)
						OBC.FreeReg(x.r); x.r:=y.r;
					ELSE HALT(200);
					END
				ELSE
					MakeConstItem(c,eltyp.size,OBT.linttyp);
					load(c);
					IF (x.mode = OC.Var) OR (x.mode = OC.Var1) THEN
						IF x.r IN {OBC.FP, OBC.PC, OBC.SP} THEN 
							OBC.GetReg(reg); IF x.r = OBC.PC THEN x.a:=x.a-(OBC.pc*4 + 8) END
						ELSE
							reg:=x.r 
						END;
						IF x.r#OBC.PC THEN
							OBC.PutMUL(OBC.MLA, reg, c.r, y.r, x.r);
						ELSE
							OBC.PutMUL(OBC.MUL, reg, c.r, y.r, 0);
							OBC.PutDP(OBC.ADD, reg, x.r, reg, 0);
						END;
						x.r:=reg;
					ELSE HALT(203)
					END ;
					OBC.Release(y);
					OBC.Release(c);
				END 
			END ;
			x.typ := eltyp			
		ELSIF x.typ.form = OC.DynArr THEN
			AdjustBaseReg(x);
			load(y);
			IF inxchk THEN
				z.mode:=OC.Var; z.r:=x.r; z.a:=x.a+x.typ.adr; z.lev:=x.lev; z.typ:=OBT.linttyp;
				load(z); OBC.FreeRegs(OBC.UsedRegisters()+{x.r}); (* load frees x.r! *)
				OBC.PutDP(OBC.CMP,0,y.r,z.r,0);
				OBC.PutSWI(OBC.CS,OC.IndexTrap); (* unsigned higher or same *)
				OBC.Release(z);
			END;
			CASE x.mode OF
				OC.Var, OC.Par: (* First Index *)
					x.b:=y.r; x.mode:=OC.Par1;
				|OC.Par1: (* Not first index *)
					z.mode:=OC.Var; z.r:=x.r; z.a:=x.a+x.typ.adr; z.typ:=OBT.linttyp; 
					load(z); OBC.FreeRegs(OBC.UsedRegisters()+{x.r}); (* load frees x.r! *)
					IF y.r#OBC.PC THEN
						OBC.PutMUL(OBC.MLA, x.b, z.r, x.b, y.r); (* Indexreg = #Elems*Indexreg+Index *)
					ELSE
						OBC.PutMUL(OBC.MUL, x.b, z.r, x.b, 0); (* Indexreg = #Elems*Indexreg+Index *)
						OBC.PutDP(OBC.ADD, x.b, y.r, x.b, 0);
					END;
					OBC.Release(z);
					OBC.Release(y);
				(* ELSE there can't be any other addressing mode, so trap *)
			END;
			x.typ := x.typ.BaseTyp;
			IF (x.typ.form#OC.DynArr) & (x.typ.size>1) THEN
				s0 := x.typ.size; n := 0; WHILE ~ODD(s0) DO s0 := s0 DIV 2; INC(n) END ;
				IF s0=1 THEN OBC.PutDP(OBC.MOV,x.b,0,x.b,n*8); (* MOV x.b, x.b LSL n *)
				ELSE MakeConstItem(c,x.typ.size,OBT.linttyp); load(c); OBC.PutMUL(OBC.MUL,x.b,c.r,x.b,0); OBC.Release(c);
				END;
			END
		ELSE OBS.Mark(82)
		END;
	END Index;

	PROCEDURE DynArrAdr*(VAR x: OBT.Item);	(* x := ADR(x) *)
		VAR l : OBT.Item; s0,n : LONGINT;
	BEGIN
		IF x.mode IN {OC.Var,OC.Par} THEN
			ASSERT((x.mode#OC.Par) OR (x.b=0));
			(* Every Index is 0 -> load(x) will load the address *)
			x.typ:=OBT.linttyp; x.mode:=OC.Var;
			load(x); 
		ELSE (* NOT first Index *)
			ASSERT(x.mode=OC.Par1);
			WHILE x.typ.form = OC.DynArr DO	(* index with 0 *)
				l.mode:=OC.Var; l.r:=x.r; l.a:=x.a+x.typ.adr; l.typ:=OBT.linttyp; 
				load(l); OBC.FreeRegs(OBC.UsedRegisters()+{x.r}); (* load frees x.r! *)
				OBC.PutMUL(OBC.MUL,x.b,l.r,x.b,0); (* Indexreg = #Elems*Indexreg *)
				OBC.Release(l);
				x.typ := x.typ.BaseTyp;
			END;
			IF x.typ.size>1 THEN
				s0 := x.typ.size; n := 0; WHILE ~ODD(s0) DO s0 := s0 DIV 2; INC(n) END ;
				IF s0=1 THEN OBC.PutDP(OBC.MOV,x.b,0,x.b,n*8); (* MOV x.b, x.b LSL n *)
				ELSE MakeConstItem(l,x.typ.size,OBT.linttyp); load(l); OBC.PutMUL(OBC.MUL,x.b,l.r,x.b,0); OBC.Release(l)
				END
			END;
			loadAdr(x)
		END
	END DynArrAdr;
	
	PROCEDURE Field*(VAR x: OBT.Item; y: OBT.Object);
	BEGIN (*x.typ.form = OC.Record*)
		IF (y # NIL) & (y.mode = OC.Fld) THEN
			IF x.lev<0 THEN 
				loadAdr(x); x.mode:=OC.Var; x.a:=0; x.lev:=OBC.level;
			END; 
			IF x.mode = OC.Var THEN INC(x.a, y.a0)
			ELSIF x.mode = OC.Par THEN INC(x.b, y.a0)
			ELSIF y.a0#0 THEN loadAdr(x); x.mode := OC.Var; x.a := y.a0
			END ;
			x.typ := y.typ; x.obj := NIL
		ELSE OBS.Mark(83); x.typ := OBT.undftyp; x.mode := OC.Var
		END;
	END Field;

	PROCEDURE DeRef*(VAR x: OBT.Item);
	BEGIN
		IF x.typ.form = OC.Pointer THEN
			IF x.typ.BaseTyp.form=OC.DynArr THEN
				load(x); 
				IF OBT.HasPtr(x.typ.BaseTyp) THEN (* x.r contains now start addr of ArrBlk, but we want start addr of array desc *)
					OBC.PutDP1(OBC.ADD,x.r,x.r,8)
				END;
				x.mode:=OC.Var; x.a:=0
			ELSIF (x.typ.BaseTyp.form=OC.Array) & OBT.HasPtr(x.typ.BaseTyp) THEN
				load(x); (* x.r contains now start addr of ArrBlk, but we want first array elem *)
				x.mode:=OC.Par; x.a:=8; x.b:=0;
			ELSE
				IF x.mode=OC.Var THEN x.mode:=OC.Par; x.b:=0;
				ELSE load(x); 
					IF x.mode=OC.Reg THEN x.mode := OC.Var; x.a := 0
					ELSIF x.mode=OC.Var THEN (* was imported pointer! *) x.mode:=OC.Par; x.b:=0; 
					ELSE HALT(213)
					END
				END;
			END;
			x.obj:=OBC.wasderef;
			x.typ:=x.typ.BaseTyp;
		ELSE OBS.Mark(84)
		END ;
	END DeRef;

	PROCEDURE TypTest*(VAR x, y: OBT.Item; test: BOOLEAN; trapNo : INTEGER);

		PROCEDURE GTT(t0, t1: OBT.Struct; varpar, sysPtr: BOOLEAN; trapNo : INTEGER);
		VAR t: OBT.Struct; xt, tdes : OBT.Item;
		BEGIN
			t := t0;
			WHILE (t # NIL) & (t # t1) DO t := t.BaseTyp END ;
			IF t # t1 THEN 
				t := t1;
				REPEAT t := t.BaseTyp UNTIL (t = NIL) OR (t = t0);
				IF (t # NIL) OR sysPtr THEN 
					x.typ := y.typ;
					IF OBC.typchk OR test THEN 
						xt := x;
						IF varpar THEN 
							xt.mode := OC.Var; xt.a := x.a+4; xt.typ:=OBT.linttyp;
							load(xt); (* Adresse des Typ-Descriptors *) 
							OBC.FreeRegs(OBC.UsedRegisters()+{x.r}); (* load(xt) frees x.r! *)
						ELSE
							load(xt); 
							OBC.FreeRegs(OBC.UsedRegisters()+{x.r}); (* load(xt) frees x.r! *)
							xt.mode:=OC.Var; xt.a:=-4; xt.typ:=OBT.linttyp; xt.lev:=OBC.level;
							load(xt); (* Adresse des Typ-Descriptors *)
							OBC.FreeRegs(OBC.UsedRegisters()+{x.r}); (* load(xt) frees x.r! *)
						END;
						xt.mode:=OC.Var; xt.a:=-4-4*(t1.extlev+1); 
						tdes.mode:=OC.Var; tdes.lev:=-t1.mno; tdes.a:=t1.adr; tdes.r:=OBC.PC; tdes.typ:=OBT.linttyp;
						load(xt); 
						OBC.FreeRegs(OBC.UsedRegisters()+{x.r}); (* load(xt) frees x.r! *)
						load(tdes);
						OBC.PutDP(OBC.CMP,0,xt.r,tdes.r,0);
						OBC.Release(xt); OBC.Release(tdes);						
						IF ~test THEN OBC.PutSWI(OBC.NE,trapNo);
						ELSE setCC(x, OBC.EQ)
						END						
					END				
				ELSE
					OBS.Mark(85);
					IF test THEN x.typ := OBT.booltyp END
				END
			ELSIF test THEN setCC(x, OBC.AL)
			END
		END GTT;

	BEGIN
		IF (x.typ.form = OC.Pointer) OR (x.typ.form=OC.SysPtr) THEN
			IF y.typ.form = OC.Pointer THEN GTT(x.typ.BaseTyp, y.typ.BaseTyp, FALSE,x.typ.form=OC.SysPtr,trapNo)
			ELSE OBS.Mark(86)
			END
		ELSIF (x.typ.form = OC.Record) & (x.mode = OC.Par) & (x.obj # NIL) & (x.obj # OBC.wasderef) & (y.typ.form = OC.Record) THEN
			GTT(x.typ, y.typ, TRUE,FALSE,trapNo)
		ELSE OBS.Mark(87)
		END;
	END TypTest;

	PROCEDURE In*(VAR x, y: OBT.Item);
		VAR r, one : LONGINT;
	BEGIN
		IF (x.typ.form IN intSet) & (y.typ.form = OC.Set) THEN
			IF (x.mode = OC.Const) & (y.mode = OC.Const) THEN
				IF x.a IN SYSTEM.VAL(SET,y.a) THEN setCC(x,OBC.AL) ELSE setCC(x,OBC.NV) END
			ELSIF x.mode = OC.Const THEN
				IF (x.a<0) OR (x.a>32) THEN setCC(x,OBC.NV)
				ELSE load(y); one:=1; OBC.PutDP1(OBC.TST,0,y.r,SYSTEM.LSH(one,x.a)); OBC.Release(y); setCC(x,OBC.NE);
				END
			ELSE
				load(x); load(y); OBC.GetReg(r);
				OBC.PutDP1(OBC.MOV,r,0,1);
				OBC.PutDP(OBC.TST,0,y.r,r,x.r*10H+1); (* TST y.r, r LSL x.r *)
				OBC.Release(y);OBC. Release(x); OBC.FreeReg(r);
				setCC(x,OBC.NE);
			END;
		ELSE OBS.Mark(92); MakeConstItem(x,0,OBT.booltyp)
		END ;
		x.typ := OBT.booltyp; 
	END In;

	PROCEDURE Set0*(VAR x, y: OBT.Item);
		VAR one: LONGINT;
	BEGIN
		x.mode := OC.Reg; x.r := 0; x.typ := OBT.settyp;
		IF y.typ.form IN intSet THEN
			IF y.mode = OC.Const THEN 
				x.mode := OC.Const;
				IF (0 <= y.a) & (y.a < 32) THEN one := 1; x.a := SYSTEM.LSH(one, y.a)
				ELSE OBS.Mark(202)
				END
			ELSE
				OBC.GetReg(x.r); OBC.PutDP1(OBC.MOV,x.r,0,1);
				load(y); OBC.PutDP(OBC.MOV,x.r,0,x.r,y.r*10H+1); (* MOV x.r, x.r LSL y.r *)
				OBC.Release(y)
			END ;
		ELSE OBS.Mark(93)
		END
	END Set0;

	PROCEDURE Set1*(VAR x, y, z: OBT.Item);
		VAR s1, s2, r: LONGINT;
	BEGIN 
		x.mode := OC.Reg; x.a := 0; x.typ := OBT.settyp;
		IF (y.typ.form IN intSet) & (z.typ.form IN intSet) THEN
			IF (y.mode = OC.Const ) & (z.mode = OC.Const) THEN
				x.mode:=OC.Const;
				IF (0 <= y.a) & (y.a < 32) & (0 <= z.a) & (z.a < 32) THEN
					IF y.a <= z.a THEN
						s1 := -1; s2 := -2; x.a := SYSTEM.LSH(s1, y.a)-SYSTEM.LSH(s2, z.a)
					ELSE OBS.Mark(201); x.a := 0
					END
				ELSE OBS.Mark(202); x.a := 0
				END
			ELSE
				IF y.mode=OC.Const THEN 
					s1:=-1; y.a:=SYSTEM.LSH(s1,y.a);
					load(y);
					x.r:=y.r
				ELSE
					OBC.GetReg(x.r);
					OBC.PutDP1(OBC.MVN,x.r,0,0); (* = MOV x.r,-1 !*)
					load(y);
					OBC.PutDP(OBC.MOV,x.r,0,x.r,y.r*10H+1); (* MOV x.r, -1 LSL y.r *)
				END;
				IF x.r#y.r THEN OBC.Release(y) END;
				IF z.mode=OC.Const THEN 
					s1:=-2;
					OBC.PutDP1(OBC.BIC,x.r,x.r,SYSTEM.LSH(s1,z.a)); (* BIC x.r, x.r, z *)
				ELSE
					OBC.GetReg(r);
					OBC.PutDP1(OBC.MVN,r,0,1); (* = MOV r,-2 !*)
					load(z);
					OBC.PutDP(OBC.BIC,x.r,x.r,r,z.r*10H+1); (* BIC x.r, x.r, -2 LSL z.r *)
					OBC.Release(z); OBC.FreeReg(r);
				END;
			END
		ELSE OBS.Mark(93)
		END
	END Set1;

	PROCEDURE RealOpH(VAR x,y : OBT.Item; op : LONGINT; restyp: INTEGER);
	BEGIN
		IF x.typ.form=OC.LReal THEN
(*
			loadLRealF(x); loadLRealF(y);
			IF restyp=OC.Bool THEN OBC.PutVFP( VCMPD, 0, x.r, y.r); 
			ELSE OBC.PutVFP( op, x.r, x.r, y.r);
			END;
*)
			IF restyp=OC.Bool THEN
				IF (x.mode=OC.Const) & (x.a=0) & (x.b=0) THEN loadLRealF(y); x:=y; OBC.PutVFP( VCMPZD, 0, x.r, 0); op:=OBC.InvertedCC(op);
				ELSIF (y.mode=OC.Const) & (y.a=0) & (y.b=0) THEN loadLRealF(x); OBC.PutVFP( VCMPZD, 0, x.r, 0);
				ELSE
					loadLRealF(x); loadLRealF(y); OBC.PutVFP( VCMPD, 0, x.r, y.r);
				END;
			ELSE loadLRealF(x); loadLRealF(y); OBC.PutVFP( op, x.r, x.r, y.r);
			END;
		ELSE
			IF restyp=OC.Bool THEN
				IF (x.mode=OC.Const) & (x.a=0) THEN load(y); x:=y; OBC.PutVFP( VCMPZS, 0, x.r, 0); op:=OBC.InvertedCC(op);
				ELSIF (y.mode=OC.Const) & (y.a=0) THEN load(x); OBC.PutVFP( VCMPZS, 0, x.r, 0);
				ELSE
					load(x); load(y); OBC.PutVFP( VCMPS, 0, x.r, y.r);
				END;
			ELSE load(x); load(y); OBC.PutVFP( op, x.r, x.r, y.r);
			END;
		END;
		IF y.r#x.r THEN OBC.Release( y) END;
		IF restyp=OC.Bool THEN
			OBC.PutVFP( VMRS, 0, 0, 0);
			setCC(x, op);
		END;
		y.mode:=OC.Const (* regs are already freed *)
	END RealOpH;

	PROCEDURE RealMOpH(VAR x : OBT.Item; op: LONGINT; restyp: INTEGER);
	VAR xr: LONGINT;
	BEGIN
		IF x.typ.form=OC.LReal THEN
			loadLRealF(x);
			IF restyp= OC.LInt THEN OBC.PutVFP( VCMPZD, 0, x.r, 0) END;
		ELSE
			load(x);
			IF restyp= OC.LInt THEN OBC.PutVFP( VCMPZS, 0, x.r, 0) END;
			IF x.typ.form IN intSet THEN OBC.GetRegF(xr); OBC.PutVFP( VMOV1S, xr, x.r, 0); OBC.FreeReg(x.r); x.r:=xr; x.mode:=OC.RegX;
			END;
		END;
		OBC.PutVFP( op, 0, x.r, x.r );
		IF restyp=OC.LInt THEN		(* ENTIER, adjust rounding... *)
			x.mode:=OC.Reg; x.typ:= OBT.linttyp;
			OBC.PutVFP( VMRS, 0, 0, 0);
			OBC.GetReg( xr);
			OBC.PutVFP( VMOV1SB, x.r, xr, 0);
			OBC.FreeRegF( x.r); x.r:=xr;
			OBC.PutDP1( 5*100H+OBC.SUB , xr, xr, 1); (* 5 is CC +2; 2 is subtracted always *)
		ELSE x.mode:=OC.RegX;
			IF restyp=OC.LReal THEN x.typ:=OBT.lrltyp
			ELSE x.typ:=OBT.realtyp
			END;
		END;
	END RealMOpH;
	
	PROCEDURE MOp*(op: INTEGER; VAR x: OBT.Item);
		VAR f: INTEGER; a: LONGINT; set : SET; r : REAL; lr : LONGREAL;
	BEGIN f := x.typ.form; 
		CASE op OF
			OC.and: (*&*)
			IF x.mode # OC.CC THEN loadCC(x) END;
			OBC.PutBabs(OBC.B,x.b); OBC.SetCondition(OBC.pc-1,OBC.InvertedCC(x.r));  x.b := OBC.pc-1; OBC.FixLink(x.a)
		| OC.plus: (*+*)
			IF ~(f IN intSet + realSet) THEN OBS.Mark(96) END
		| OC.minus: (*-*)
			IF f IN intSet THEN
				IF x.mode = OC.Const THEN x.a := -x.a; SetIntType(x)
				ELSE load(x); OBC.PutDP1(OBC.RSB,x.r,x.r,0); (* RSB *) OverflowCheck(x);
				END
			ELSIF f = OC.Real THEN 
				IF x.mode = OC.Const THEN x.a:=SYSTEM.VAL(LONGINT,-SYSTEM.VAL(REAL,x.a))
				ELSE RealMOpH(x, VNEGS, OC.Real)	(*RealMOp(x,"RealNeg")*)
				END;
			ELSIF f = OC.LReal THEN 
				IF x.mode = OC.Const THEN SYSTEM.GET(SYSTEM.ADR(x.a),lr); SYSTEM.PUT(SYSTEM.ADR(x.a),-lr)
				ELSE RealMOpH(x, VNEGD, OC.LReal)	(*RealMOp(x, "LRealNeg")*)
				END
			ELSIF f = OC.Set  THEN 
				IF x.mode = OC.Const THEN set:=SYSTEM.VAL(SET,x.a); x.a:=SYSTEM.VAL(LONGINT,-set);
				ELSE load(x); OBC.PutDP(OBC.MVN,x.r,0,x.r,0); 
				END;
			ELSE OBS.Mark(97)
			END
		| OC.or: (*OR*)
			IF x.mode#OC.CC THEN loadCC(x) END;
			OBC.PutBabs(OBC.B,x.a); OBC.SetCondition(OBC.pc-1,x.r); x.a:=OBC.pc-1; OBC.FixLink(x.b); x.b:=0;
		| OC.eql .. OC.geq: (*relations*)
			IF x.mode = OC.CC THEN loadB(x) END
		| OC.not: (*~*)
			IF x.mode # OC.CC THEN loadCC(x) END;
			x.r := OBC.InvertedCC(x.r); a := x.a; x.a := x.b; x.b := a
		END
	END MOp;

	PROCEDURE convertIntToReal*(VAR x: OBT.Item; typ: OBT.Struct);
	VAR  r: REAL; lr: LONGREAL;
	BEGIN
		IF typ.form=OC.Real THEN
			IF x.mode = OC.Const THEN
				r := x.a; x.a := SYSTEM.VAL(LONGINT, r); x.typ := typ
			ELSE RealMOpH(x,VCVTSL, OC.Real)	(*RealMOp(x,"LIntToReal")*)
			END
		ELSE 
			IF x.mode = OC.Const THEN
				lr := x.a; SYSTEM.MOVE(SYSTEM.ADR(lr), SYSTEM.ADR(x.a), 8); x.typ := typ
			ELSE RealMOpH(x,VCVTDL, OC.LReal)	(*RealMOp(x,"LIntToLReal")*)
			END
		END
	END convertIntToReal;

	PROCEDURE convertRealToLReal*(VAR x: OBT.Item);
	VAR lr: LONGREAL;
	BEGIN
		IF x.mode = OC.Const THEN
			lr := SYSTEM.VAL(REAL, x.a); SYSTEM.MOVE(SYSTEM.ADR(lr), SYSTEM.ADR(x.a), 8); x.typ := OBT.lrltyp
		ELSE RealMOpH(x,VCVTDS, OC.LReal)	(*RealMOp(x,"RealToLReal")*)
		END
	END convertRealToLReal;

	PROCEDURE convertLRealToReal(VAR x: OBT.Item);
	VAR r:REAL; lr: LONGREAL;
	BEGIN
		IF x.mode = OC.Const THEN
			SYSTEM.MOVE(SYSTEM.ADR(x.a), SYSTEM.ADR(lr), 8);
			r := SHORT(lr);  x.a := SYSTEM.VAL(LONGINT, r); x.typ := OBT.realtyp
		ELSE RealMOpH(x,VCVTSD, OC.Real)	(*RealMOp(x,"LRealToReal")*)
		END
	END convertLRealToReal;

	PROCEDURE ConstCharToString*(VAR x : OBT.Item);
	BEGIN
		IF (x.typ.form = OC.Char) & (x.mode=OC.Const) THEN
			x.typ := OBT.stringtyp;  NEW(x.obj); NEW(x.obj.ext); 
			x.obj.ext.entered:=FALSE; x.obj.ext.str[0]:=CHR(x.a); x.obj.ext.str[1]:=0X; x.b:=2; 
		END
	END ConstCharToString;
	
	PROCEDURE CompStrings(VAR x, y: OBT.Item; f, g: INTEGER);
		VAR r1, r2 : LONGINT;
	BEGIN
		ConstCharToString(x); f := x.typ.form;
		ConstCharToString(y); g := y.typ.form;
		IF f = OC.DynArr THEN DynArrAdr(x)
		ELSE loadAdr(x)
		END;
		IF g = OC.DynArr THEN DynArrAdr(y)
		ELSE loadAdr(y);
		END ;
		OBC.GetReg(r1); OBC.GetReg(r2);
		DEC(OBC.allowConstFlushing);
		OBC.PutSDT(OBC.LDRBpost,r1,x.r,1);
		OBC.PutSDT(OBC.LDRBpost,r2,y.r,1);
		OBC.PutDP1(OBC.CMP,0,r1,0);
		OBC.PutB(OBC.B,OBC.pc+3); OBC.SetCondition(OBC.pc-1,OBC.EQ); 
		OBC.PutDP(OBC.CMP,0,r1,r2,0);
		OBC.PutB(OBC.B,OBC.pc-5); OBC.SetCondition(OBC.pc-1,OBC.EQ);
		OBC.PutDP(OBC.CMP,0,r1,r2,0); (* Comparison must be done because we could have left the loop because of r1==0 *)
		INC(OBC.allowConstFlushing);
		OBC.FreeReg(r1);
		OBC.FreeReg(r2);
		OBC.Release(x);
		OBC.Release(y);
	END CompStrings;

	PROCEDURE DivMod(VAR x,y : OBT.Item; isDiv : BOOLEAN);
	VAR oldy, r : LONGINT; r0Save, r1Save : LONGINT;
	BEGIN
		r0Save:=-1; r1Save:=-1;
		
		(* load R0 *)
		IF (x.mode=OC.Reg) & (x.r=0) THEN (* Make Room for y *)
			OBC.SetPreferredReg(1); (* x should be loaded into R1, if possible *)
			OBC.GetReg(x.r); OBC.PutDP(OBC.MOV,x.r,0,0,0); OBC.FreeReg(0);
		ELSIF 0 IN OBC.UsedRegisters() THEN (* R0 still used, perhaps a result of a procedure call *)
			OBC.GetReg(r0Save); OBC.PutDP(OBC.MOV,r0Save,0,0,0); OBC.FreeReg(0)
		END;
		loadInto(y,0);
		
		(* Load R1 *)
		IF (1 IN OBC.UsedRegisters()) & ~( (x.mode=OC.Reg) & (x.r=1)) THEN
			OBC.GetReg(r1Save); OBC.PutDP(OBC.MOV,r1Save,0,1,0); OBC.FreeReg(1)
		END;
		loadInto(x,1);
		
		OBC.PutBext(0,3); (* Call Kernel.DivMod *)
		OBC.Release(x); y.mode := OC.Const; (* prevent y from being released! *)
		x.mode:=OC.Reg;
		IF isDiv THEN x.r:=0; ELSE x.r:=1 END;
		OBC.FreeRegs(OBC.UsedRegisters()+{x.r}); 
		OBC.SetPreferredReg(-1);

		(* restore save R0 and R1, if necessary *)
		IF r0Save#-1 THEN
			IF x.r=0 THEN OBC.GetReg(r); OBC.PutDP(OBC.MOV,r,0,x.r,0); OBC.FreeReg(x.r); x.r:=r END;
			OBC.PutDP(OBC.MOV,0,0,r0Save,0); OBC.FreeReg(r0Save); OBC.FreeRegs(OBC.UsedRegisters()+{0});
		END;
		IF r1Save#-1 THEN
			IF x.r = 1 THEN OBC.GetReg(r); OBC.PutDP(OBC.MOV,r,0,x.r,0); OBC.FreeReg(x.r); x.r:=r END;
			OBC.PutDP(OBC.MOV,1,0,r1Save,0); OBC.FreeReg(r1Save); OBC.FreeRegs(OBC.UsedRegisters()+{1});
		END
	END DivMod;
	
	PROCEDURE FJ*(VAR loc: LONGINT);
	BEGIN OBC.PutBabs(OBC.B,loc); loc:=OBC.pc-1;
	END FJ;

	PROCEDURE CFJ*(VAR x: OBT.Item; VAR loc: LONGINT);
	BEGIN
		IF x.typ.form = OC.Bool THEN
			IF x.mode # OC.CC THEN loadCC(x)  END
		ELSE OBS.Mark(120); setCC(x, 0)
		END ;
		loc:=OBC.pc;
		OBC.PutBabs(OBC.B,x.b); OBC.SetCondition(loc,OBC.InvertedCC(x.r)); OBC.FixLink(x.a);
	END CFJ;

	PROCEDURE BJ*(loc: LONGINT);
	BEGIN OBC.PutB(OBC.B,loc)
	END BJ;

	PROCEDURE CBJ*(VAR x: OBT.Item; loc: LONGINT);
	BEGIN
		IF x.typ.form = OC.Bool THEN
			IF x.mode # OC.CC THEN loadCC(x) END
		ELSE OBS.Mark(120); setCC(x, 0)
		END ;
		OBC.PutB(OBC.B,loc); OBC.SetCondition(OBC.pc-1,OBC.InvertedCC(x.r));
		OBC.FixLinkWith(x.b, loc); OBC.FixLink(x.a)
	END CBJ;

	PROCEDURE Op*(op: INTEGER; VAR x, y: OBT.Item);
		VAR f, g, L: INTEGER; p, q, r: OBT.Struct; r1,r2 : REAL; lr1,lr2 : LONGREAL; t : LONGINT;

		PROCEDURE strings(): BOOLEAN;
		BEGIN RETURN
			( (((f=OC.Array) OR (f=OC.DynArr)) & (x.typ.BaseTyp.form=OC.Char)) OR (f=OC.String) OR ((f=OC.Char) & (x.mode=OC.Const)) ) &
			( (((g=OC.Array) OR (g=OC.DynArr)) & (y.typ.BaseTyp.form=OC.Char)) OR (g=OC.String) OR ((g=OC.Char) & (y.mode=OC.Const)) ) 
		END strings;

		PROCEDURE CompBool(cc: INTEGER);
		BEGIN
			IF x.mode = OC.CC THEN loadB(x) END;
			IF y.mode = OC.CC THEN loadB(y) END;
			cmp(x,y); setCC(x,cc);
		END CompBool;

	BEGIN
		IF x.typ # y.typ THEN
			g := y.typ.form;
			CASE x.typ.form OF
				OC.Undef:
				|OC.SInt:
						IF g = OC.SInt THEN (* do nothing *)
						ELSIF (g = OC.Int) OR (g = OC.LInt) THEN IF x.mode#OC.Const THEN load(x) END; x.typ:=y.typ 
						ELSIF g IN realSet THEN convertIntToReal(x, y.typ)
						ELSE OBS.Mark(100)
						END
				|OC.Int:
						IF g = OC.SInt THEN IF y.mode#OC.Const THEN load(y) END; y.typ:=x.typ 
						ELSIF g = OC.Int THEN (* do nothing *)
						ELSIF g = OC.LInt THEN IF x.mode#OC.Const THEN load(x) END; x.typ:=y.typ
						ELSIF g IN realSet THEN convertIntToReal(x, y.typ)
						ELSE OBS.Mark(100)
						END
				|OC.LInt:
						IF g = OC.SInt THEN IF y.mode#OC.Const THEN load(y) END; y.typ:=x.typ 
						ELSIF g = OC.Int THEN IF y.mode#OC.Const THEN load(y) END; y.typ:=x.typ
						ELSIF g = OC.LInt THEN (* do nothing *)
						ELSIF g IN realSet THEN convertIntToReal(x, y.typ)
						ELSE OBS.Mark(100)
						END
				|OC.Real:
						IF g IN intSet THEN convertIntToReal(y, x.typ)
						ELSIF g = OC.LReal THEN convertRealToLReal(x)
						ELSE OBS.Mark(100)
						END
				|OC.LReal:
						IF g IN intSet THEN convertIntToReal(y, x.typ)
						ELSIF g = OC.Real THEN convertRealToLReal(y)
						ELSE OBS.Mark(100)
						END
				|OC.NilTyp: IF (g # OC.Pointer) & (g # OC.SysPtr) THEN OBS.Mark(100) END
				|OC.SysPtr: IF (g # OC.NilTyp) & (g # OC.Pointer) THEN OBS.Mark(100) END
				|OC.Pointer:
						IF g = OC.Pointer THEN
							p := x.typ.BaseTyp; q := y.typ.BaseTyp;
							IF (p.form = OC.Record) & (q.form = OC.Record) THEN
								IF p.extlev < q.extlev THEN r := p; p := q; q := r END;
								WHILE (p # q) & (p # NIL) DO p := p.BaseTyp END;
								IF p = NIL THEN OBS.Mark(100) END
							ELSE OBS.Mark(100)
							END
						ELSIF (g # OC.NilTyp) & (g # OC.SysPtr) THEN OBS.Mark(100)
						END
				|OC.ProcTyp: IF g # OC.NilTyp THEN OBS.Mark(100) END
				|OC.Array, OC.DynArr, OC.String:
				|OC.Byte, OC.Bool, OC.Char, OC.Set, OC.NoTyp, OC.Record: OBS.Mark(100)
			END
		END ;
		f := x.typ.form; g := y.typ.form; 
		CASE op OF
			 OC.times:
			 		IF f IN intSet THEN     (* * *)
						IF (x.mode = OC.Const) & (y.mode = OC.Const) THEN (*ovfl test missing*)
							x.a := x.a * y.a; SetIntType(x)
						ELSIF ovfchk THEN
							load(x); load(y); OBC.GetReg(t); OBC.PutMULL(OBC.SMULL,t,x.r,y.r,x.r);
							OBC.PutDP(OBC.CMP,0,t,x.r,15*8+4); (* CMP x.r, r, ASR 15 *)
							OBC.PutSWI(OBC.NE, OC.OverflowTrap);
							OBC.FreeReg(t); OBC.Release(y);
						ELSE
							IF (x.mode = OC.Const) & (mant(x.a) = 1) THEN
								load(y); OBC.PutDP(OBC.MOV,y.r,0,y.r,log*8);
								x := y; y.mode := OC.Const; (*prevent release of register*)
							ELSIF (y.mode = OC.Const) & (mant(y.a) = 1) THEN
							 	load(x); OBC.PutDP(OBC.MOV,x.r,0,x.r,log*8);
							ELSE 
								load(x); load(y); OBC.PutMUL(OBC.MUL,x.r,y.r,x.r,0); OBC.Release(y);
							END
						END
					 ELSIF f = OC.Real THEN 
					 	IF (x.mode = OC.Const) & (y.mode = OC.Const) THEN (*ovfl test missing *)
					 		r1:=SYSTEM.VAL(REAL,x.a); r2:=SYSTEM.VAL(REAL,y.a);
					 		x.a:=SYSTEM.VAL(LONGINT,r1*r2);
					 	ELSE RealOpH(x,y, VMULS, OC.Real)	(*RealOp(x,y,"RealMul")*)
					 	END
					 ELSIF f = OC.LReal THEN 
					 	IF (x.mode = OC.Const) & (y.mode = OC.Const) THEN (*ovfl test missing *)
					 		SYSTEM.GET(SYSTEM.ADR(x.a),lr1); SYSTEM.GET(SYSTEM.ADR(y.a),lr2);
					 		SYSTEM.PUT(SYSTEM.ADR(x.a),lr1*lr2);
					 	ELSE RealOpH(x,y, VMULD, OC.LReal)	(*RealOp(x,y,"LRealMul")*)
					 	END
					 ELSIF f = OC.Set THEN DPInstr(OBC.AND,x,y)
					 ELSIF f # OC.Undef THEN OBS.Mark(101)
					 END

		 | OC.slash:
		 			IF f IN intSet THEN 
		 				convertIntToReal(x, OBT.realtyp); convertIntToReal(y, OBT.realtyp);
		 				f:=OC.Real; g:=OC.Real
 					END;
 					IF f = OC.Real THEN 
					 	IF (x.mode = OC.Const) & (y.mode = OC.Const) THEN 
					 		r1:=SYSTEM.VAL(REAL,x.a); r2:=SYSTEM.VAL(REAL,y.a);
					 		x.a:=SYSTEM.VAL(LONGINT,r1/r2);
					 	ELSE RealOpH(x,y,VDIVS, OC.Real)	(*RealOp(x,y,"RealDiv")*)
					 	END
					 ELSIF f = OC.LReal THEN 
					 	IF (x.mode = OC.Const) & (y.mode = OC.Const) THEN
					 		SYSTEM.GET(SYSTEM.ADR(x.a),lr1); SYSTEM.GET(SYSTEM.ADR(y.a),lr2);
					 		SYSTEM.PUT(SYSTEM.ADR(x.a),lr1/lr2);
					 	ELSE RealOpH(x,y,VDIVD, OC.LReal)	(*RealOp(x,y,"LRealDiv")*)
					 	END
					 ELSIF f = OC.Set THEN DPInstr(OBC.EOR,x,y);
					 ELSIF f # OC.Undef THEN OBS.Mark(102)
					 END

		 | OC.div:
		 			IF f IN intSet THEN  (*DIV*)
		 				IF (y.mode=OC.Const) & (y.a=0) THEN OBS.Mark(205) 
		 				ELSE
						 	IF (x.mode = OC.Const) & (y.mode = OC.Const) THEN
							 	x.a := x.a DIV y.a; SetIntType(x)
							 ELSIF (y.mode = OC.Const) & (mant(y.a) = 1) THEN
							 	IF log#0 THEN load(x); OBC.PutDP(OBC.MOV,x.r,0,x.r,log*8+4) END; (* MOV x.r, x.r ASR log *)
							 ELSE
							 	DivMod(x,y,TRUE) (* DIV *)
							 END
						END
					 ELSIF f # OC.Undef THEN OBS.Mark(103)
					 END

		 | OC.mod:
		 			IF f IN intSet THEN  (*MOD*)
		 				IF (y.mode = OC.Const) & (y.a=0) THEN OBS.Mark(205)
		 				ELSE
							 IF (x.mode = OC.Const) & (y.mode = OC.Const) THEN
								 x.a := x.a MOD y.a; x.typ := y.typ
							 ELSIF (y.mode = OC.Const) & (mant(y.a) = 1) THEN
								 y.a := ASH(-1, log); load(x); OBC.PutDP1(OBC.BIC,x.r,x.r,y.a)   
							 ELSE DivMod(x,y,FALSE) (* MOD *)
							 END
						END
					 ELSIF f # OC.Undef THEN OBS.Mark(104)
					 END

		 | OC.and:
		 			IF y.mode # OC.CC THEN loadCC(y) END;
					x.b := OBC.MergedLinks(x.b, y.b);  x.r := y.r; x.a := y.a

		 | OC.plus:
		 			IF f IN intSet THEN (*+*)
						 IF (x.mode = OC.Const) & (y.mode = OC.Const) THEN
							 INC(x.a, y.a); SetIntType(x)  (*ovfl test missing*)
						 ELSE load(x); DPInstr(OBC.ADD,x, y); OverflowCheck(x);
						 END
 					ELSIF f = OC.Real THEN 
					 	IF (x.mode = OC.Const) & (y.mode = OC.Const) THEN (* ovfl test missing *)
					 		r1:=SYSTEM.VAL(REAL,x.a); r2:=SYSTEM.VAL(REAL,y.a);
					 		x.a:=SYSTEM.VAL(LONGINT,r1+r2);
					 	ELSE RealOpH(x,y, VADDS, OC.Real) (*RealOp(x,y,"RealAdd")*)
					 	END
					 ELSIF f = OC.LReal THEN 
					 	IF (x.mode = OC.Const) & (y.mode = OC.Const) THEN (*ovfl test missing *)
					 		SYSTEM.GET(SYSTEM.ADR(x.a),lr1); SYSTEM.GET(SYSTEM.ADR(y.a),lr2);
					 		SYSTEM.PUT(SYSTEM.ADR(x.a),lr1+lr2);
					 	ELSE RealOpH(x,y, VADDD, OC.LReal) (*RealOp(x,y,"LRealAdd")*)
					 	END
					 ELSIF f = OC.Set THEN
						 IF (x.mode = OC.Const) & (y.mode = OC.Const) THEN 
						 	x.a := SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, x.a) + SYSTEM.VAL(SET, y.a))
						 ELSE DPInstr(OBC.ORR,x,y);
						 END
					 ELSIF f # OC.Undef THEN OBS.Mark(105)
					 END

		 | OC.minus:
		 			IF f IN intSet THEN (*-*)
						 IF (x.mode = OC.Const) & (y.mode = OC.Const) THEN
							 DEC(x.a, y.a); SetIntType(x)  (*ovfl test missing*)
						 ELSE DPInstr(OBC.SUB,x, y); OverflowCheck(x)
						 END
 					ELSIF f = OC.Real THEN 
					 	IF (x.mode = OC.Const) & (y.mode = OC.Const) THEN (* ovfl test missing *)
					 		r1:=SYSTEM.VAL(REAL,x.a); r2:=SYSTEM.VAL(REAL,y.a);
					 		x.a:=SYSTEM.VAL(LONGINT,r1-r2);
					 	ELSE RealOpH(x,y, VSUBS, OC.Real) (*RealOp(x,y,"RealSub")*)
					 	END
					 ELSIF f = OC.LReal THEN 
					 	IF (x.mode = OC.Const) & (y.mode = OC.Const) THEN (*ovfl test missing *)
					 		SYSTEM.GET(SYSTEM.ADR(x.a),lr1); SYSTEM.GET(SYSTEM.ADR(y.a),lr2);
					 		SYSTEM.PUT(SYSTEM.ADR(x.a),lr1-lr2);
					 	ELSE RealOpH(x,y, VSUBD, OC.LReal) (*RealOp(x,y,"LRealSub")*)
					 	END
					 ELSIF f = OC.Set THEN 
					 	IF (x.mode=OC.Const) & (y.mode=OC.Const) THEN
					 		x.a:=SYSTEM.VAL(LONGINT,SYSTEM.VAL(SET,x.a)-SYSTEM.VAL(SET,y.a));
					 	ELSE DPInstr(OBC.BIC,x,y)
					 	END
					 ELSIF f # OC.Undef THEN OBS.Mark(106)
					 END

		 | OC.or:
		 			IF y.mode # OC.CC THEN loadCC(y) END;
		 			x.a := OBC.MergedLinks(x.a, y.a); x.b := y.b; x.r:=y.r;

		 | OC.eql:  
		 			IF f IN {OC.Undef, OC.Byte, OC.Char..OC.LInt, OC.Set, OC.NilTyp, OC.Pointer, OC.SysPtr, OC.ProcTyp} THEN (* = *)
		 				IF (x.mode=OC.Const) & (y.mode=OC.Const) THEN
		 					IF x.a=y.a THEN setCC(x,OBC.AL) ELSE setCC(x,OBC.NV) END
		 				ELSE
							 cmp(x, y); setCC(x, OBC.EQ)
						 END
					 ELSIF f = OC.Real THEN RealOpH(x,y, OBC.EQ, OC.Bool)	(*RealOp(x,y,"RealEq")*)
					 ELSIF f = OC.LReal THEN RealOpH(x,y, OBC.EQ, OC.Bool)	(*RealOp(x,y,"LRealEq")*)
					 ELSIF f = OC.Bool THEN CompBool(OBC.EQ)
					 ELSIF strings() THEN CompStrings(x, y, f, g); setCC(x, OBC.EQ)
					 ELSE OBS.Mark(107)
					 END

		 | OC.neq:
		 			IF f IN {OC.Undef, OC.Byte, OC.Char..OC.LInt, OC.Set, OC.NilTyp, OC.Pointer, OC.SysPtr, OC.ProcTyp} THEN (* # *)
		 				IF (x.mode=OC.Const) & (y.mode=OC.Const) THEN
		 					IF x.a#y.a THEN setCC(x,OBC.AL) ELSE setCC(x,OBC.NV) END
		 				ELSE
							 cmp(x, y); setCC(x, OBC.NE)
						 END
					 ELSIF f = OC.Real THEN RealOpH(x,y, OBC.NE, OC.Bool)	(*RealOp(x,y,"RealNe")*)
					 ELSIF f = OC.LReal THEN RealOpH(x,y, OBC.NE, OC.Bool)	(*RealOp(x,y,"LRealNe")*)
					 ELSIF f = OC.Bool THEN CompBool(OBC.NE)
					 ELSIF strings() THEN CompStrings(x, y, f, g); setCC(x, OBC.NE) 
					 ELSE OBS.Mark(107)
					 END

		 | OC.lss: 
		 			IF f IN intSet THEN 
		 				IF (x.mode=OC.Const) & (y.mode=OC.Const) THEN
		 					IF x.a<y.a THEN setCC(x,OBC.AL) ELSE setCC(x,OBC.NV) END
		 				ELSE
							 cmp(x, y); setCC(x, OBC.LT) (* < *)
						 END
					 ELSIF f = OC.Char THEN cmp( x, y); setCC(x, OBC.CC) (* unsigned lower! *)
					 ELSIF f = OC.Real THEN RealOpH(x,y, OBC.CC, OC.Bool)	(*RealOp(x,y,"RealLt")*)
					 ELSIF f = OC.LReal THEN RealOpH(x,y, OBC.CC, OC.Bool)	(*RealOp(x,y,"LRealLt")*)
					 ELSIF strings() THEN CompStrings(x, y, f, g); setCC(x, OBC.CC) (* unsigned lower! *) 
					 ELSE OBS.Mark(108)
					 END

		 | OC.leq:
		 			IF f IN intSet THEN 
		 				IF (x.mode=OC.Const) & (y.mode=OC.Const) THEN
		 					IF x.a<=y.a THEN setCC(x,OBC.AL) ELSE setCC(x,OBC.NV) END
		 				ELSE
							 cmp(x, y); setCC(x, OBC.LE) (* <= *)
						 END
					 ELSIF f = OC.Char THEN cmp( x, y); setCC(x, OBC.LS) (* unsigned lower or same *)
					 ELSIF f = OC.Real THEN RealOpH(x,y, OBC.LS, OC.Bool)	(*RealOp(x,y,"RealLe")*)
					 ELSIF f = OC.LReal THEN RealOpH(x,y, OBC.LS, OC.Bool)	(*RealOp(x,y,"LRealLe")*)
					 ELSIF strings() THEN CompStrings(x, y, f, g); setCC(x, OBC.LS)  (* unsigned lower or same *)
					 ELSE OBS.Mark(108)
					 END

		 | OC.gtr: IF f IN intSet THEN 
		 				IF (x.mode=OC.Const) & (y.mode=OC.Const) THEN
		 					IF x.a>y.a THEN setCC(x,OBC.AL) ELSE setCC(x,OBC.NV) END
		 				ELSE
							 cmp(x, y); setCC(x, OBC.GT) (* > *)
						 END
					 ELSIF f = OC.Char THEN cmp( x, y); setCC(x, OBC.HI) (* unsigned higher! *)
					 ELSIF f = OC.Real THEN RealOpH(x,y, OBC.GT, OC.Bool)	(*RealOp(x,y,"RealGt")*)
					 ELSIF f = OC.LReal THEN RealOpH(x,y, OBC.GT, OC.Bool)	(*RealOp(x,y,"LRealGt")*)
					 ELSIF strings() THEN CompStrings(x, y, f, g); setCC(x, OBC.HI)  (*unsigned higher *)
					 ELSE OBS.Mark(108)
					 END

		 | OC.geq: 
		 			IF f IN intSet THEN 
		 				IF (x.mode=OC.Const) & (y.mode=OC.Const) THEN
		 					IF x.a>=y.a THEN setCC(x,OBC.AL) ELSE setCC(x,OBC.NV) END
		 				ELSE
							 cmp(x, y); setCC(x, OBC.GE) (* >= *)
						 END
					 ELSIF f = OC.Char THEN cmp( x, y); setCC(x, OBC.CS) (* unsigned higher or same! *)
					 ELSIF f = OC.Real THEN RealOpH(x,y, OBC.GE, OC.Bool)	(*RealOp(x,y,"RealGe")*)
					 ELSIF f = OC.LReal THEN RealOpH(x,y, OBC.GE, OC.Bool)	(*RealOp(x,y,"LRealGe")*)
					 ELSIF strings() THEN CompStrings(x, y, f, g); setCC(x, OBC.CS) (* unsigned higher or same! *)
					 ELSE OBS.Mark(108)
					 END
		END ;
		OBC.Release(y)
	END Op;

	PROCEDURE StPar1*(VAR x: OBT.Item; fctno: LONGINT);
		VAR f : INTEGER; y: OBT.Item;  typ : OBT.Struct; L0 : LONGINT; lr : LONGREAL;
	BEGIN f := x.typ.form;
		CASE fctno OF
			 OBT.FnHalt, OBT.FnSysHalt: 
					IF (f IN intSet) & (x.mode = OC.Const) THEN
						IF ((x.a >= 20) & (x.a<256)) OR (x.a=MAX(INTEGER)) OR (fctno=OBT.FnSysHalt) THEN OBC.PutSWI(OBC.AL,x.a);
						ELSE OBS.Mark(218)
						END
					ELSE OBS.Mark(217)
					END ;
					x.typ := OBT.notyp
		|  OBT.FnNew: 
					IF f = OC.Pointer THEN
						IF x.typ.BaseTyp.form#OC.DynArr THEN
							y:=x; loadAdr(y); PushWord(y) (* push address of pointer *)
						END;
						x.typ := x.typ.BaseTyp; f := x.typ.form;
						IF f = OC.Record THEN
							x.mode := OC.Var; x.r:=OBC.PC; x.lev := -x.typ.mno; x.a := x.typ.adr; x.typ:=OBT.linttyp;
							load(x); PushWord(x); (* Push addr of type desc *)
							OBC.PutBext(0,0); (* NewRec *)
						ELSIF f = OC.Array THEN
							IF OBT.HasPtr(x.typ.BaseTyp) THEN (* Allocate a ArrBlk with one dimension *)
								typ:=x.typ.BaseTyp; WHILE typ.form=OC.Array DO typ:=typ.BaseTyp END; (* get elem type *)
								IF typ.form=OC.Pointer THEN MakeConstItem(y,0,OBT.linttyp);
								ELSE y.mode := OC.Var; y.r:=OBC.PC; y.lev := -typ.mno; y.a := typ.adr; y.typ:=OBT.linttyp; 
								END;
								PushWord(y); (* Push Elem Tag *)
								MakeConstItem(y,x.typ.size DIV typ.size, OBT.linttyp); PushWord(y); (* Push # of elems *)
								MakeConstItem(y,1,OBT.linttyp); PushWord(y); (* push # of dims *)
								OBC.PutBext(0,2); (* NewArr *)
								(* 
									We dont patch the "nth dim"-entries, because we allocated space for a static array and so all 
									index checks are done statically!
								*)
							ELSE
								(* Allocate a SysBlk *)
								MakeConstItem(x,x.typ.size,OBT.linttyp);
								PushWord(x); (* push size of array *)
								OBC.PutBext(0,1); (* NewSys *)
							END
						ELSIF f = OC.DynArr THEN
							(* this is handled separatly! *)
						ELSE OBS.Mark(111)
						END
					ELSE OBS.Mark(111)
					END ;
					x.typ := OBT.notyp
		|  OBT.FnSysCC: 
					IF (f = OC.SInt) & (x.mode = OC.Const) THEN
						IF (0 <= x.a) & (x.a < 16) THEN setCC(x, x.a) ELSE OBS.Mark(219) END
					ELSE OBS.Mark(217)
					END
		|  OBT.FnAbs: 
					y := x;  
					IF f IN intSet THEN
						IF x.mode = OC.Const THEN x.a := ABS(x.a)
						ELSE
							load(x);
							OBC.PutDP1(OBC.CMP,0,x.r,0);
							OBC.PutDP1(OBC.RSB,x.r,x.r,0); OBC.SetCondition(OBC.pc-1,OBC.LT);
						END
					ELSIF f = OC.Real THEN 
						IF x.mode = OC.Const THEN x.a:=SYSTEM.VAL(LONGINT,ABS(SYSTEM.VAL(REAL,x.a)))
						ELSE RealMOpH(x, VABSS, OC.Real)	(*RealMOp(x,"RealAbs")*)
						END;
					ELSIF f = OC.LReal THEN 
						IF x.mode = OC.Const THEN SYSTEM.GET(SYSTEM.ADR(x.a),lr); SYSTEM.PUT(SYSTEM.ADR(x.a),ABS(lr))
						ELSE RealMOpH(x, VABSD, OC.LReal)	(*RealMOp(x, "LRealAbs")*)
						END
					ELSE OBS.Mark(111)
					END
		|  OBT.FnCap: 
					IF f = OC.Char THEN load(x); OBC.PutDP1(OBC.AND,x.r,x.r,5FH);
					ELSE OBS.Mark(111); x.typ := OBT.chartyp
					END
		|  OBT.FnOrd:  
					IF (f = OC.Char) OR (f = OC.Byte) THEN
						IF x.mode # OC.Const THEN load(x); END
					ELSE OBS.Mark(111)
					END ;
					x.typ := OBT.inttyp
		|  OBT.FnEntier:
					IF f = OC.Real THEN RealMOpH(x, VCVTLS, OC.LInt)	(*RealMOp(x,"RealEntier")*)
					ELSIF f = OC.LReal THEN RealMOpH(x, VCVTLD, OC.LInt)	(*RealMOp(x,"LRealEntier")*)
					ELSE OBS.Mark(111); 
					END ;
					x.typ := OBT.linttyp
		|  OBT.FnSize: 
					IF (x.mode = OC.Typ) & (x.typ.form # OC.Undef) THEN x.a := x.typ.size
					ELSE OBS.Mark(110); x.a := 1
					END ;
					x.mode := OC.Const; SetIntType(x)
		| OBT.FnOdd: 
					IF f IN intSet THEN load(x); OBC.PutDP1(OBC.TST,0,x.r,1); OBC.Release(x);
					ELSE OBS.Mark(111)
					END ;
					setCC(x, OBC.NE);
		|  OBT.FnSysAdr: 
					IF f = OC.DynArr THEN DynArrAdr(x)
					ELSE loadAdr(x);
					END ;
					x.typ := OBT.linttyp
		| OBT.FnMin: 
					IF x.mode = OC.Typ THEN
						x.mode := OC.Const;
						CASE f OF
								OC.Bool, OC.Char:  x.a := 0
							| OC.SInt:  x.a := -80H
							| OC.Int:   x.a := -8000H
							| OC.LInt:  x.a := 80000000H
							| OC.Real:  x.a := 0FF7FFFFFH
							| OC.LReal: x.a := 0FFFFFFFFH; x.b := 0FFEFFFFFH
							| OC.Set:   x.a := 0; x.typ := OBT.inttyp
							| OC.Undef, OC.NilTyp .. OC.Record: OBS.Mark(111)
						END
					ELSE OBS.Mark(110)
					END
		| OBT.FnMax: 
					IF x.mode = OC.Typ THEN
						x.mode := OC.Const;
						CASE f OF
								OC.Bool:  x.a := 1
							| OC.Char:  x.a := 0FFH
							| OC.SInt:  x.a := 7FH
							| OC.Int:   x.a := 7FFFH
							| OC.LInt:  x.a := 7FFFFFFFH
							| OC.Real:  x.a := 7F7FFFFFH
							| OC.LReal: x.a := 0FFFFFFFFH; x.b := 7FEFFFFFH
							| OC.Set:   x.a := 31; x.typ := OBT.inttyp
							| OC.Undef, OC.NilTyp .. OC.Record: OBS.Mark(111)
						END
					ELSE OBS.Mark(110)
					END |
		| OBT.FnChr:  
					IF ~(f IN {OC.Undef, OC.Byte, OC.SInt, OC.Int, OC.LInt}) THEN OBS.Mark(111) END ;
					IF (x.mode # OC.Const) & (x.mode # OC.Reg) THEN load(x) END;
					x.typ := OBT.chartyp
		| OBT.FnShort: 
					IF f = OC.LInt THEN  
						IF x.mode = OC.Const THEN  
							SetIntType(x);
							IF x.typ.form = OC.LInt THEN OBS.Mark(203); END;
							x.typ := OBT.inttyp
						ELSE
							load(x); x.typ:=OBT.inttyp; (* OverflowCheck(x) *)
							OBC.PutDP(OBC.MOV,x.r,0,x.r,16*8); (* MOV x.r, x.r LSL 16 *)
							OBC.PutDP(OBC.MOV,x.r,0,x.r,16*8+4); (* MOV x.r, x.r ASR 16 *)
							(* these MOVs keep the sign correct!! *)
						END
					ELSIF f = OC.LReal THEN
						convertLRealToReal(x);
						x.typ:=OBT.realtyp
					ELSIF f = OC.Int THEN 
						IF x.mode = OC.Const THEN 
							SetIntType(x);
							IF x.typ.form # OC.SInt THEN OBS.Mark(203) END;
							x.typ := OBT.sinttyp;
						ELSE
							load(x); x.typ:=OBT.sinttyp; (* OverflowCheck(x); *)
							OBC.PutDP(OBC.MOV,x.r,0,x.r,24*8); (* MOV x.r, x.r LSL 24 *)
							OBC.PutDP(OBC.MOV,x.r,0,x.r,24*8+4); (* MOV x.r, x.r ASR 24 *) 
							(* these MOVs keep the sign correct!! *)
						END ;
					ELSE OBS.Mark(111); 
					END
		| OBT.FnLong: 
					IF f = OC.Int THEN 
						IF x.mode#OC.Const THEN load(x) END;
						x.typ:=OBT.linttyp;
					ELSIF f = OC.Real THEN convertRealToLReal(x)
					ELSIF f = OC.SInt THEN 
						IF x.mode#OC.Const THEN load(x) END;
						x.typ:=OBT.inttyp;
					ELSIF (f = OC.Char) OR (f = OC.Byte) THEN
						IF x.mode#OC.Const THEN load(x) END;
						x.typ:=OBT.linttyp;
					ELSE OBS.Mark(111)
					END
		| OBT.FnInc, OBT.FnDec:  
					IF x.mode >= OC.Const THEN OBS.Mark(112)
					ELSIF ~(f IN intSet) THEN OBS.Mark(111)
					END
		| OBT.FnIncl, OBT.FnExcl: 
					IF x.mode >= OC.Const THEN OBS.Mark(112)
					ELSIF x.typ.form # OC.Set THEN OBS.Mark(111); x.typ := OBT.settyp
					END
		| OBT.FnLen: 
					IF (f # OC.DynArr) & (f # OC.Array) THEN OBS.Mark(131) END
		| OBT.FnAsh: 
					IF f IN intSet THEN load(x); x.typ := OBT.linttyp
					ELSE OBS.Mark(111)
					END
		| OBT.FnSysLsh, OBT.FnSysRot: 
					IF ~(f IN {OC.Char, OC.Byte, OC.SInt, OC.Int, OC.LInt, OC.Set}) THEN OBS.Mark(111) END
		| OBT.FnSysGet, OBT.FnSysPut, OBT.FnSysBit:
					IF ((f IN intSet) & (x.mode = OC.Const)) OR (f=OC.LInt) THEN
						load(x); x.mode:=OC.Var; x.a:=0; x.lev:=OBC.level;
					ELSE OBS.Mark(111)
					END
		| OBT.FnSysGetReg, OBT.FnSysPutReg:
					IF (f IN intSet) & (x.mode=OC.Const) THEN
						IF (x.a>=0) & (x.a<=15) THEN x.mode:=OC.Reg; x.r:=x.a; x.typ:=OBT.linttyp
						ELSE OBS.Mark(219)
						END
					ELSE OBS.Mark(111)
					END
		| OBT.FnSysVal: 
					IF x.mode # OC.Typ THEN OBS.Mark(110) END
		| OBT.FnSysNew: 
					IF ((f = OC.Pointer) OR (f = OC.SysPtr)) & (x.mode < OC.Const) THEN loadAdr(x); PushWord(x); (* push addr of var *)
						ELSE OBS.Mark(111)
					END
		| OBT.FnCopy:
					ConstCharToString(x); f := x.typ.form;
					IF ~((((f=OC.Array) OR (f=OC.DynArr)) & (x.typ.BaseTyp.form = OC.Char)) OR (f = OC.String)) THEN OBS.Mark(111)
					END
		| OBT.FnSysMove: 
					IF f = OC.LInt THEN load(x)
					ELSE OBS.Mark(111)
					END				
		| OBT.FnAssert:
					MOp(OC.not,x);
					IF f # OC.Bool THEN OBS.Mark(120) END
		ELSE
			OBS.Mark(64); 
			x.typ:=OBT.notyp;
		END
	END StPar1;

	PROCEDURE StPar2*(VAR p, x: OBT.Item; fctno: LONGINT);
		VAR f : INTEGER; L, tmpreg, shiftright : LONGINT; y: OBT.Item; typ: OBT.Struct; 
	BEGIN 
		f := x.typ.form;
		CASE fctno OF
			OBT.FnInc, OBT.FnDec: 
					IF x.typ # p.typ THEN
						IF (x.mode = OC.Const) & (x.typ.form IN intSet) THEN x.typ := p.typ
						ELSE OBS.Mark(111)
						END
					END ;
					IF fctno = OBT.FnInc THEN DPInstrWriteback(OBC.ADD,p, x, TRUE) ELSE DPInstrWriteback(OBC.SUB,p, x, TRUE) END ; 
					p.typ := OBT.notyp
		| OBT.FnAssert:
					IF x.mode # OC.Const THEN OBS.Mark(50)
					ELSIF ~(x.typ.form IN intSet) THEN OBS.Mark(51)
					END;
		| OBT.FnIncl: 
					Set0(y, x); DPInstrWriteback(OBC.ORR,p,y, FALSE); p.typ := OBT.notyp 
		| OBT.FnExcl:
					Set0(y, x); DPInstrWriteback(OBC.BIC,p,y, FALSE); p.typ := OBT.notyp 
		| OBT.FnLen:
					IF (x.mode = OC.Const) & (f = OC.SInt) THEN
						L := x.a; typ := p.typ;
						WHILE (L > 0) & (typ.form IN {OC.DynArr, OC.Array}) DO typ := typ.BaseTyp; DEC(L) END;
						IF (L # 0) OR ~(typ.form IN {OC.DynArr, OC.Array}) THEN OBS.Mark(132)
						ELSE
							IF typ.form = OC.DynArr THEN 
								IF p.mode = OC.Var THEN INC(p.a,typ.adr) ELSE INC(p.b,typ.adr) END; p.typ := OBT.linttyp
							ELSE p := x; p.a := typ.size DIV typ.BaseTyp.size; SetIntType(p)
							END
						END
					ELSE OBS.Mark(111)
					END					
		| OBT.FnAsh, OBT.FnSysLsh:
					IF f IN intSet THEN
						IF fctno = OBT.FnAsh THEN shiftright:=2 (* ASR *) ELSE shiftright:=1 (* LSR *) END;
						load(p);
						IF x.mode=OC.Const THEN
							IF (ABS(x.a)>31) OR ((p.typ.size=2) & (ABS(x.a)>15)) OR ((p.typ.size=1) & (ABS(x.a)>8)) THEN 
								OBC.PutDP1(OBC.MOV,p.r,0,0) (* everything shifted out -> result 0 *)
							ELSE
								IF x.a<0 THEN (* xSR *)
									OBC.PutDP(OBC.MOV,p.r,0,p.r,-x.a*8+shiftright*2); (* MOV p.r, p.r xSR -x.a *)
								ELSE (* LSL *)
									OBC.PutDP(OBC.MOV,p.r,0,p.r,x.a*8); (* MOV p.r, p.r LSL x.a *)
									IF p.typ.size#4 THEN
										OBC.PutDP(OBC.MOV,p.r,0,p.r,(32-(p.typ.size*8))*8);  (* MOV p.r,p.r LSL 32-bitsize *)
										OBC.PutDP(OBC.MOV,p.r,0,p.r,(32-(p.typ.size*8))*8+4);  (* MOV p.r,p.r ASR 32-bitsize *)
										(* This code is necessary to keep the sign correct. the first MOV LSL could be combined with the
											actual shift instruction *)
									END
								END	
							END
						ELSE
							load(x);
							OBC.PutDP1(OBC.CMP,0,x.r,0);
							OBC.PutDP1(OBC.RSBnoflags,x.r,x.r,0); OBC.SetCondition(OBC.pc-1,OBC.LT); (* xnew:=-x if x<0; else xnew:=x *); 
							OBC.PutDP(OBC.MOV,p.r,0,p.r, x.r*16+1); OBC.SetCondition(OBC.pc-1, OBC.GE); (* LSL xnew if x>=0 *)  
							IF p.typ.size#4 THEN
								OBC.PutDP(OBC.MOV,p.r,0,p.r,(32-(p.typ.size*8))*8); OBC.SetCondition(OBC.pc-1, OBC.GE); (* MOV p.r,p.r LSL 32-bitsize *)
								OBC.PutDP(OBC.MOV,p.r,0,p.r,(32-(p.typ.size*8))*8+4); OBC.SetCondition(OBC.pc-1, OBC.GE);  (* MOV p.r,p.r ASR 32-bitsize *)
								(* This code is necessary to keep the sign correct. the first MOV LSL could be combined with the
									actual shift instruction *)
							END;
							OBC.PutDP(OBC.MOV,p.r,0,p.r, x.r*16+shiftright*2+1); OBC.SetCondition(OBC.pc-1, OBC.LT); (* xSR xnew if x<0 *)
							OBC.Release(x);
						END
					ELSE OBS.Mark(111)
					END
		| OBT.FnSysRot:
					IF f IN intSet THEN
						IF x.mode=OC.Const THEN
							IF (ABS(x.a)#p.typ.size*8) & (x.a#0) THEN
								load(p);
								IF p.typ.size#4 THEN (* clear upper bits *)
									OBC.GetReg(tmpreg);
									OBC.PutDP1(OBC.MVN,tmpreg,0,0);	(* tmpreg := 0FFFFFFFFH *)
									OBC.PutDP(OBC.AND,p.r,p.r,tmpreg,(32-8*p.typ.size)*8+2);	(* AND p.r, p.r, tmpreg LSR (32-bitsize) *)
									OBC.FreeReg(tmpreg)
								END;
								OBC.PutDP(OBC.MOV,p.r,0,p.r,((-x.a) MOD (8*p.typ.size))*8+6); (* MOV p.r, p.r ROR -x.a *)
								IF p.typ.size#4 THEN 
									OBC.PutDP(OBC.ORR,p.r,p.r,p.r,(32-(p.typ.size*8))*8+2);  (* ORR p.r, p.r LSR 32-bitsize *)
									OBC.PutDP(OBC.MOV,p.r,0,p.r,(32-(p.typ.size*8))*8);  (* MOV p.r,p.r LSL 32-bitsize *)
									OBC.PutDP(OBC.MOV,p.r,0,p.r,(32-(p.typ.size*8))*8+4)  (* MOV p.r,p.r ASR 32-bitsize *)
									(* Altough this is a lot of code, the shifts are necessary to keep the sign correct!!! *)
								END;
							END
						ELSE
							load(p);
							load(x);
							IF p.typ.size#4 THEN (* clear upper bits *)
								OBC.GetReg(tmpreg);
								OBC.PutDP1(OBC.MVN,tmpreg,0,0);	(* tmpreg := 0FFFFFFFFH *)
								OBC.PutDP(OBC.AND,p.r,p.r,tmpreg,(32-8*p.typ.size)*8+2);	(* AND p.r, p.r, tmpreg LSR (32-bitsize) *)
								OBC.FreeReg(tmpreg)
							END;
							OBC.PutDP1(OBC.RSBnoflags,x.r,x.r,0);	(* change sign *)
							OBC.PutDP1(OBC.AND,x.r,x.r, 8*p.typ.size-1); 			(* x := (-x) MOD bitsize *)
							OBC.PutDP(OBC.MOV,p.r,0,p.r, x.r*16+7);  (* MOV p.r, p.r ROR x.r *)
							IF p.typ.size # 4 THEN 
								OBC.PutDP(OBC.ORR,p.r,p.r,p.r,(32-(p.typ.size*8))*8+2);  (* ORR p.r, p.r LSR 32-bitsize *)
								OBC.PutDP(OBC.MOV,p.r,0,p.r,(32-(p.typ.size*8))*8);  (* MOV p.r,p.r LSL 32-bitsize *)
								OBC.PutDP(OBC.MOV,p.r,0,p.r,(32-(p.typ.size*8))*8+4)  (* MOV p.r,p.r ASR 32-bitsize *)
								(* Altough this is a lot of code, the shifts are necessary to keep the sign correct!!! *)
							END;
							OBC.Release(x);
						END
					ELSE OBS.Mark(111)
					END		
		| OBT.FnSysGet:
					IF x.mode >= OC.Const THEN OBS.Mark(112)
					ELSIF f IN {OC.Undef..OC.LInt, OC.Set, OC.Pointer, OC.SysPtr, OC.ProcTyp, OC.Real} THEN
						p.typ:=x.typ;
						store(x,p);
					ELSIF f = OC.LReal THEN
						p.typ:=x.typ;
						storeLReal(x,p);
					END ;
					p.typ := OBT.notyp
		| OBT.FnSysPut:
					IF f IN {OC.Undef..OC.LInt, OC.Set, OC.Pointer, OC.SysPtr, OC.ProcTyp, OC.Real} THEN 
						p.typ:=x.typ;
						store(p,x);
					ELSIF f = OC.LReal THEN
						p.typ:=x.typ;
						storeLReal(p,x)
					ELSE OBS.Mark(111)
					END ;
					p.typ := OBT.notyp
		| OBT.FnSysGetReg:
					IF x.mode >= OC.Const THEN OBS.Mark(112)
					ELSE		
						IF f = OC.Real THEN x.typ:=OBT.linttyp; f:=OC.LInt END;
						IF f IN {OC.LInt, OC.Set, OC.Pointer, OC.SysPtr, OC.ProcTyp} THEN p.typ:=x.typ; store(x,p); 
						ELSE OBS.Mark(111)
						END 
					END;
					p.typ := OBT.notyp
		| OBT.FnSysPutReg:
					IF f = OC.Real THEN x.typ:=OBT.linttyp; f:=OC.LInt END;
					IF f IN {OC.Byte..OC.Int} THEN load(x); (* Make 32bit *) f:=OC.LInt; x.typ:=OBT.linttyp END;
					IF f IN {OC.LInt, OC.Set, OC.Pointer, OC.SysPtr, OC.ProcTyp} THEN p.typ:=x.typ; store(p,x);
					ELSE OBS.Mark(111)
					END;
					p.typ := OBT.notyp
		| OBT.FnSysBit:
					IF f IN intSet THEN 
						load(p);
						IF x.mode=OC.Const THEN
							IF (x.a<0) OR (x.a>31) THEN 
								OBC.Release(p); setCC(p,OBC.NV)
							ELSE
								OBC.GetReg(tmpreg); OBC.PutDP1(OBC.MOV,tmpreg,0,1);
								OBC.PutDP(OBC.TST,0,p.r,tmpreg,x.a*8); (* TST p.r, tmpreg LSL x.a *)
								OBC.FreeReg(tmpreg); OBC.Release(p);
								setCC(p,OBC.NE);
							END
						ELSE
							load(x); OBC.GetReg(tmpreg); OBC.PutDP1(OBC.MOV,tmpreg,0,1);
							OBC.PutDP(OBC.TST,0,p.r,tmpreg,x.r*10H+1); (* TST p.r, tmpreg LSL x.r *)
							OBC.FreeReg(tmpreg); OBC.Release(x); OBC.Release(p);
							setCC(p,OBC.NE);
						END
					ELSE OBS.Mark(111); setCC(p,OBC.NE);
					END 
		| OBT.FnSysVal:
					IF (p.typ.size>x.typ.size) & (x.mode IN {OC.Var, OC.Par, OC.Var2 }) THEN (* possible alignment problem *)
						IF ((x.mode IN {OC.Var,OC.Var2}) & (x.a MOD p.typ.size # 0)) OR
							((x.mode=OC.Par) & (x.b MOD p.typ.size # 0)) THEN (* Wrong alignment! *)
							OBS.Mark(254)
						ELSE (* possibly wrong alignment *)
							OBS.Mark(-303)
						END
					END;
					x.typ := p.typ; p := x
		| OBT.FnSysNew:
					IF ~(f IN intSet) THEN OBS.Mark(111) 
					ELSE PushWord(x); (* push size *)
					END;
					OBC.PutBext(0,1); (* NewSys *)
					p.typ := OBT.notyp
		| OBT.FnCopy:
					IF ~(((f = OC.Array) OR (f = OC.DynArr)) & (x.typ.BaseTyp.form = OC.Char)) THEN OBS.Mark(111) END;
		| OBT.FnSysMove:
					IF f = OC.LInt THEN load(x);
					ELSE OBS.Mark(111)
					END
		ELSE OBS.Mark(64)
		END;
	END StPar2;

	PROCEDURE StPar3*(VAR p, x: OBT.Item; fctno: LONGINT);
	BEGIN
		IF fctno = OBT.FnSysMove THEN
			IF x.typ.form IN intSet THEN load(x)
			ELSE OBS.Mark(111)
			END ;
		ELSE OBS.Mark(64)
		END
	END StPar3;

	PROCEDURE ByteCopy*(src,dest,len : LONGINT; zeroTerminate : BOOLEAN); (** byte-by-byte copy loop; src, dest and len MUST be registers *)
	VAR loop, tmpreg : LONGINT;
	BEGIN
		OBC.GetReg(tmpreg);
		DEC(OBC.allowConstFlushing);
		IF zeroTerminate THEN
			OBC.PutDP1(OBC.CMP,0,len,1);
			OBC.PutB(OBC.B,OBC.pc+7); OBC.SetCondition(OBC.pc-1,OBC.LT);
			OBC.PutB(OBC.B,OBC.pc+3); 
			loop:=OBC.pc; OBC.PutSDT(OBC.LDRBpost,tmpreg,src,1);
			OBC.PutSDT(OBC.STRBpost,tmpreg,dest,1);
			OBC.PutDP1(OBC.SUB,len,len,1);
			OBC.PutB(OBC.B,loop); OBC.SetCondition(OBC.pc-1,OBC.NE);
			OBC.PutSDT(OBC.STRB,len,dest,0)
		ELSE
			OBC.PutDP1(OBC.CMP,0,len,0);
			OBC.PutB(OBC.B,OBC.pc+5); OBC.SetCondition(OBC.pc-1,OBC.EQ);
			loop:=OBC.pc; OBC.PutSDT(OBC.LDRBpost,tmpreg,src,1);
			OBC.PutSDT(OBC.STRBpost,tmpreg,dest,1);
			OBC.PutDP1(OBC.SUB,len,len,1);
			OBC.PutB(OBC.B,loop); OBC.SetCondition(OBC.pc-1,OBC.NE)
		END; 
		INC(OBC.allowConstFlushing);
		OBC.FreeReg(tmpreg);
	END ByteCopy;

	PROCEDURE StringCopy*(src,dest,len : LONGINT); (** string copy with zero termination. len includes terminating zero! *)
	VAR loop, cnt, tmp : LONGINT;
	BEGIN
		DEC(OBC.allowConstFlushing);
		DEC(len);
		IF len >= 0 THEN
			OBC.GetReg(cnt); OBC.LoadConst(cnt,len);
			IF len > 0 THEN 
				OBC.GetReg(tmp);
				(* no loop unrolling here. this would be better only for lengths of 1 or 2 bytes *)
				OBC.PutSDT(OBC.LDRBpost,tmp,src,1);
				OBC.PutSDT(OBC.STRBpost,tmp,dest,1);
				OBC.PutDP1(OBC.SUB,cnt,cnt,1);
				OBC.PutB(OBC.B,OBC.pc-3); OBC.SetCondition(OBC.pc-1,OBC.NE);
				OBC.FreeReg(tmp);
			END;
			OBC.PutSDT(OBC.STRB,cnt,dest,0); (* cnt is ALWAYS zero here! *)
			OBC.FreeReg(cnt)
		END;
		INC(OBC.allowConstFlushing)
	END StringCopy;

	PROCEDURE StFct*(VAR x,y,z : OBT.Item; fctno, parno: LONGINT);
	VAR srclen, destlen, t : OBT.Item; gR, gF : SET; L0: LONGINT;
	BEGIN 
		IF fctno = OBT.FnAssert THEN
			CFJ(x,L0);
			IF (parno = 1) THEN
				OBC.PutSWI(OBC.AL,OC.AssertTrap)
			ELSE
				OBC.PutSWI(OBC.AL, y.a)
			END;
			OBC.FixLink(L0);
			x.typ := OBT.notyp
		ELSIF fctno >= OBT.FnInc THEN
			IF ((fctno = OBT.FnInc) OR (fctno = OBT.FnDec)) & (parno = 1)  THEN
				MakeConstItem(t,1,OBT.linttyp);
				IF fctno=OBT.FnInc THEN DPInstrWriteback(OBC.ADD,x,t, TRUE) ELSE DPInstrWriteback(OBC.SUB,x,t, TRUE) END;
				x.typ := OBT.notyp
			ELSIF (fctno = OBT.FnLen) & (parno = 1) THEN 
				IF x.typ.form = OC.DynArr THEN
					x.mode := OC.Var; INC(x.a, x.typ.adr); x.typ := OBT.linttyp
				ELSIF x.typ.form = OC.Array THEN
					x.mode := OC.Const; x.a := x.typ.size DIV x.typ.BaseTyp.size; SetIntType(x)
				END
			ELSIF (fctno = OBT.FnCopy) & (parno = 2) THEN 
				IF x.typ.form=OC.DynArr THEN
					srclen.mode:=OC.Var; srclen.r:=x.r; srclen.a:=x.a+x.typ.adr; srclen.typ:=OBT.linttyp; srclen.lev:=x.lev;
					DynArrAdr(x);
					load(srclen)	(*do it now, otherwise the next operation may recycle the register before it's used*)
				ELSIF x.typ.form=OC.Array THEN
					MakeConstItem(srclen,x.typ.size DIV x.typ.BaseTyp.size,OBT.linttyp);
					loadAdr(x)
				ELSIF x.typ.form=OC.String THEN 
					MakeConstItem(srclen,x.b,OBT.linttyp);
					loadAdr(x)
				ELSE (* Error already marked *)
					MakeConstItem(srclen,0,OBT.linttyp);
				END;
				IF y.typ.form=OC.DynArr THEN
					destlen.mode:=OC.Var; destlen.r:=y.r; destlen.a:=y.a+y.typ.adr; destlen.typ:=OBT.linttyp; destlen.lev:=y.lev;
					DynArrAdr(y); 
					load(destlen)	(*do it now, otherwise the next operation may recycle the register before it's used*)
				ELSIF y.typ.form=OC.Array THEN
					MakeConstItem(destlen,y.typ.size DIV y.typ.BaseTyp.size,OBT.linttyp);
					loadAdr(y); 
				ELSE (* Error already marked *)
					MakeConstItem(destlen,0,OBT.linttyp);
				END;
				IF (srclen.mode=OC.Const) & (destlen.mode=OC.Const) THEN
					IF srclen.a>destlen.a THEN srclen.a:=destlen.a END;
					StringCopy(x.r,y.r,srclen.a);
				ELSE
					load(srclen);  load(destlen);
					OBC.PutDP(OBC.CMP,0,srclen.r,destlen.r,0);
					OBC.PutDP(OBC.MOV,srclen.r,0,destlen.r,0); OBC.SetCondition(OBC.pc-1,OBC.GT);
					OBC.Release(destlen);
					ByteCopy(x.r,y.r,srclen.r,TRUE(*zero terminate*));
					OBC.Release(srclen);
				END;
				x.typ:=OBT.notyp; 
			ELSIF (fctno = OBT.FnSysMove) & (parno = 3) THEN
				(* x : Address of source; y : Address of dest; z : Count *)
				ByteCopy(x.r,y.r,z.r,FALSE);
				x.typ:=OBT.notyp;
			ELSIF (parno < 2) OR (fctno = OBT.FnSysMove) & (parno < 3) THEN OBS.Mark(65); 
			END
		ELSIF parno < 1 THEN OBS.Mark(65)
		END	
	END StFct;

	PROCEDURE NewOpenArr*(ptr : OBT.Item; elemtyp : OBT.Struct; dims : ARRAY OF OBT.Item; dimcnt : LONGINT);
	VAR y,z : OBT.Item; elems, i : LONGINT; save : SET; 
	BEGIN
		save:={};
		FOR i:=0 TO dimcnt-1 DO
			IF dims[i].mode#OC.Const THEN 
				load(dims[i]); 
				OBC.PutDP1(OBC.CMP,0,dims[i].r,0);
				OBC.PutSWI(OBC.LT,OC.DimErrTrap);
				INCL(save,dims[i].r) 
			END
		END;
		IF (ptr.mode IN {OC.Var, OC.Var1, OC.Par, OC.Par1}) & (ptr.r<OBC.FP) THEN INCL(save, ptr.r) END;
		IF (ptr.mode = OC.Var1) & (ptr.a<OBC.FP) THEN INCL(save, ptr.a) 
		ELSIF (ptr.mode = OC.Par1) & (ptr.b<OBC.FP) THEN INCL(save, ptr.b) 
		END;
		IF save # {} THEN OBC.PutBDT(OBC.STMDB,OBC.SP,save,TRUE) END;
		y:=ptr; loadAdr(y); PushWord(y); (* push address of pointer *)
		IF OBT.HasPtr(elemtyp) THEN (* Allocate ArrBlk *) 
			IF elemtyp.form=OC.Pointer THEN MakeConstItem(y,0,OBT.linttyp); 
			ELSE y.mode:=OC.Var; y.r:=OBC.PC; y.lev:=-elemtyp.mno; y.a:=elemtyp.adr; y.typ:=OBT.linttyp;
			END;
			PushWord(y); (* push elem tag *)
			
			elems:=1;
			FOR i:=0 TO dimcnt-1 DO IF dims[i].mode=OC.Const THEN elems:=elems*dims[i].a END END;
			MakeConstItem(y,elems,OBT.linttyp);
			load(y);
			FOR i:=0 TO dimcnt-1 DO
				IF dims[i].mode#OC.Const THEN OBC.PutMUL(OBC.MUL,y.r,dims[i].r,y.r,0) END
			END;
			PushWord(y); (* push nofElems *)
			MakeConstItem(y,dimcnt,OBT.linttyp); PushWord(y); (* nofDims *)
		
			OBC.PutBext(0,2); (* NewArr *)
			IF save # {} THEN OBC.PutBDT(OBC.LDMIA,OBC.SP,save,TRUE); OBC.FreeRegs(OBC.UsedRegisters()+save) END;
		
			(* Now, fix the dimensions *)
			load(ptr); ptr.mode:=OC.Var; ptr.a:=12; ptr.lev:=OBC.level;
			FOR i:=dimcnt-1 TO 0 BY -1 DO
				y:=ptr; store(y,dims[i]); OBC.FreeRegs(OBC.UsedRegisters()+{y.r}); (* store frees that reg *)
				INC(ptr.a,4)
			END
		ELSE (* Allocate SysBlk *)
			elems:=1;
			FOR i:=0 TO dimcnt-1 DO IF dims[i].mode=OC.Const THEN elems:=elems*dims[i].a END END;
			MakeConstItem(y,elems,OBT.linttyp);
			FOR i:=0 TO dimcnt-1 DO
				IF dims[i].mode#OC.Const THEN 
					IF y.mode#OC.Reg THEN load(y) END;
					OBC.PutMUL(OBC.MUL,y.r,dims[i].r,y.r,0);
				END
			END;
			IF y.mode=OC.Const THEN y.a:=y.a*elemtyp.size+dimcnt*4+4 (* space for Array Descriptor *)
			ELSE 
				IF elemtyp.size#1 THEN
					MakeConstItem(z,elemtyp.size,OBT.linttyp); 
					load(z); OBC.PutMUL(OBC.MUL,y.r,z.r,y.r,0); OBC.Release(z);
				END;
				OBC.PutDP1(OBC.ADD,y.r,y.r,dimcnt*4+4)
			END;
			PushWord(y); (* push size *)
			OBC.PutBext(0,1); (* NewSys *)
			IF save # {} THEN OBC.PutBDT(OBC.LDMIA,OBC.SP,save,TRUE); OBC.FreeRegs(OBC.UsedRegisters()+save) END;
		
			(* Now, build the array descriptor *)
			load(ptr); ptr.mode:=OC.Var; ptr.a:=0; ptr.lev:=OBC.level;
			y:=ptr; z.mode:=OC.Reg; z.typ:=OBT.linttyp; OBC.GetReg(z.r); 
			OBC.PutDP1(OBC.ADD,z.r,y.r,dimcnt*4+4); store(y,z); OBC.FreeRegs(OBC.UsedRegisters()+{y.r}); (* store ptr to data *)
			FOR i:=dimcnt-1 TO 0 BY -1 DO 
				INC(ptr.a,4); 
				y:=ptr; store(y,dims[i]); OBC.FreeRegs(OBC.UsedRegisters()+{y.r}); (* store frees that reg *)
			END
		END;
	END NewOpenArr;
	
BEGIN
	intSet := {OC.SInt, OC.Int, OC.LInt}; realSet := {OC.Real, OC.LReal};
END OBE.
