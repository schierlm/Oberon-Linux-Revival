MODULE SoftFloat;

(**
===============================================================================

This C header file is part of the SoftFloat IEC/IEEE Floating-point
Arithmetic Package, Release 2a.

Written by John R. Hauser.  This work was made possible in part by the
International Computer Science Institute, located at Suite 600, 1947 Center
Street, Berkeley, California 94704.  Funding was partially provided by the
National Science Foundation under grant MIP-9311980.  The original version
of this code was written as part of a project to build a fixed-point vector
processor in collaboration with the University of California at Berkeley,
overseen by Profs. Nelson Morgan and John Wawrzynek.  More information
is available through the Web page `http://HTTP.CS.Berkeley.EDU/~jhauser/
arithmetic/SoftFloat.html'.

THIS SOFTWARE IS DISTRIBUTED AS IS, FOR FREE.  Although reasonable effort
has been made to avoid it, THIS SOFTWARE MAY CONTAIN FAULTS THAT WILL AT
TIMES RESULT IN INCORRECT BEHAVIOR.  USE OF THIS SOFTWARE IS RESTRICTED TO
PERSONS AND ORGANIZATIONS WHO CAN AND WILL TAKE FULL RESPONSIBILITY FOR ANY
AND ALL LOSSES, COSTS, OR OTHER PROBLEMS ARISING FROM ITS USE.

Derivative works are acceptable, even for commercial purposes, so long as
(1) they include prominent notice that the work is derivative, and (2) they
include prominent notice akin to these four paragraphs for those parts of
this code that are retained.

===============================================================================
*)

(*
	Peter Matthias
	2014-05-10	started HardFloat
	2015-12-13	optimized RealEntier, LRealEntier; ToDo: set rounding to FE_DOWNWARD
	fesetround below

	RealRem, LRealRem, RealRoundToInt and LRealRoundToInt don't seem to be used

	to get machine code:
		edit vfp.s
		assemble via asm -mfpu=vfp -gstabs -o test.o test.s or gcc -c -o vfp.o vfp.s
		disassemble via objdump -d test.o

		for compare instruction see 
*)

IMPORT Kernel, SYSTEM;

CONST

	(* Software IEC/IEEE floating-point underflow tininess-detection mode. *)
	TininessAfterRounding* = 0;
	TininessBeforeRounding* = 1;

	(* Software IEC/IEEE floating-point rounding mode. *)
	RoundNearestEven* = 0;
	RoundDown* = 1;
	RoundUp* = 2;
	RoundToZero* = 3;

	(* Software IEC/IEEE floating-point exception flags. *)
	Invalid* = 1;
	DivByZero* = 2;
	Overflow* = 4;
	Underflow* = 8;
	Inexact* = 16;
	
VAR
	RoundingMode* : SHORTINT; (** Software IEC/IEEE floating-point rounding mode. *)
	ExceptionFlags* : SHORTINT; (** Software IEC/IEEE floating-point exception flags. *)
	DetectTininess* : SHORTINT; (** Software IEC/IEEE floating-point underflow tininess-detection mode. *)
	OverflowExceptions* : BOOLEAN; (** FALSE -> Overflow/Underflow are ignored *)

(* Wrapper-Procedures *)

(*-------------------------------------------------------------------------------
Software IEC/IEEE integer-to-floating-point conversion routines.
-------------------------------------------------------------------------------*)
PROCEDURE LIntToReal*(i : LONGINT) : REAL;
CODE
	DCD 0ECBD0A01H		(* vldmia R13!, {s0} *)
	DCD 0EEB81AC0H		(* cvt.f32.s32 s2, s0 *)
	DCD 0EE110A10H		(* vmov r0, s2 *)
	MOV	PC, LR
END LIntToReal;

PROCEDURE LIntToLReal*(i : LONGINT) : LONGREAL;
CODE
	DCD 0ECBD0A01H		(* vldmia R13!, {s0} *)
	DCD 0EEB82BC0H		(* cvt.f64.s32 d2, s0 *)
	DCD 0EC510B12H		(* vmov r0, r1, d2 *)
	MOV	PC, LR
END LIntToLReal;

(*-------------------------------------------------------------------------------
Software IEC/IEEE single-precision conversion routines.
-------------------------------------------------------------------------------*)
PROCEDURE RealToLInt*(r : REAL) : LONGINT;
CODE
	DCD 0ECBD0A01H		(* vldmia R13!, {s0} *)
	DCD 0EEBD1AC0H		(* cvt.s32.f32 s2, s0 *)
	DCD 0EE110A10H		(* vmov r0,  s2 *)
	MOV	PC, LR
END RealToLInt;

PROCEDURE RealToLReal*(r : REAL) : LONGREAL;
CODE
	DCD 0ECBD0A01H		(* vldmia R13!, {s0} *)
	DCD 0EEB72AC0H		(* cvt.f64.f32 d2, s0 *)
	DCD 0EC510B12H		(* vmov r0, r1, d2 *)
	MOV	PC, LR
END RealToLReal;


(*-------------------------------------------------------------------------------
Software IEC/IEEE single-precision operations.
-------------------------------------------------------------------------------*)

PROCEDURE RealRoundToInt*(r : REAL) : REAL;		(* ToDo *)
CODE
	DCD 0ECBD0A01H		(* vldmia R13!, {s0} *)
	DCD 0EEBD0AC0H		(* cvt.s32.f32 s0, s0 *)
	DCD 0EEB81AC0H		(* cvt.f32.s32 s2, s0 *)
	DCD 0EE110A10H		(* vmov r0, s2 *)
	MOV	PC, LR
END RealRoundToInt;

PROCEDURE RealAdd*(r1,r2 : REAL) : REAL;
CODE
	DCD 0ECBD0A02H		(* vldmia R13, {s0, s1} *)
	DCD 0EE301A20H		(* vadd.f32 s2, s0, s1 *)
	DCD 0EE110A10H		(* vmov r0, s2 *)
	MOV	PC, LR
END RealAdd;

PROCEDURE RealSub*(r1,r2 : REAL) : REAL;
CODE
	DCD 0ECBD0A02H		(* vldmia R13, {s0, s1} *)
	DCD 0EE301AC0H		(* vsub.f32 s2, s0, s1 *)
	DCD 0EE110A10H		(* vmov r0, s2 *)
	MOV	PC, LR
END RealSub;

PROCEDURE RealMul*(r1,r2 : REAL) : REAL;
CODE
	DCD 0ECBD0A02H		(* vldmia R13, {s0, s1} *)
	DCD 0EE201A20H		(* vmul.f32 s2, s0, s1 *)
	DCD 0EE110A10H		(* vmov r0, s2 *)
	MOV	PC, LR
END RealMul;

PROCEDURE RealDiv*(r1,r2 : REAL) : REAL;
CODE
	DCD 0ECBD0A02H		(* vldmia R13, {s0, s1} *)
	DCD 0EE801A80H		(* vdiv.f32 s2, s1, s0 *)
	DCD 0EE110A10H		(* vmov r0, s2 *)
	MOV	PC, LR
END RealDiv;

PROCEDURE RealRem*(r1,r2 : REAL) : REAL;
BEGIN
	HALT(99);
END RealRem;

PROCEDURE RealSqrt*(r : REAL) : REAL;
CODE
	DCD 0ECBD0A01H		(* vldmia R13, {s0} *)
	DCD 0EEB11AC0H		(* vsqrt.f32 s2, s0 *)
	DCD 0EE110A10H		(* vmov r0, s2 *)
	MOV	PC, LR
END RealSqrt;

PROCEDURE RealEq*(r1, r2 : REAL) : BOOLEAN;
CODE
	DCD 0ECBD0A02H		(* vldmia R13, {s0, s1} *)
	DCD 0EEB40A60H		(* vcmp s0, s1 *)
	DCD 0EEF1FA10H		(* vmrs APSR_nzcv, FPSCR *)
	DCD 0E3A00000H		(* mov r0, 0 *)
	DCD 03A00001H		(* moveq r0, 1 *)
	MOV	PC, LR
END RealEq;

PROCEDURE RealLe*(r1, r2 : REAL) : BOOLEAN;
CODE
	DCD 0ECBD0A02H		(* vldmia R13, {s0, s1} *)
	DCD 0EEF40A40H		(* vcmp s1, s0 *)
	DCD 0EEF1FA10H		(* vmrs APSR_nzcv, FPSCR *)
	DCD 0E3A00000H		(* mov r0, 0 *)
	DCD 93A00001H		(* movls r0, 1 *)
	MOV	PC, LR
END RealLe;

PROCEDURE RealLt*(r1, r2 : REAL) : BOOLEAN;
CODE
	DCD 0ECBD0A02H		(* vldmia R13, {s0, s1} *)
	DCD 0EEF40A40H		(* vcmp s0, s1 *)
	DCD 0EEF1FA10H		(* vmrs APSR_nzcv, FPSCR *)
	DCD 0E3A00000H		(* mov r0, 0 *)
	DCD 33A00001H		(* movcc r0, 1 *)
	MOV	PC, LR
END RealLt;

PROCEDURE RealNe*(r1, r2 : REAL) : BOOLEAN;
CODE
	DCD 0ECBD0A02H		(* vldmia R13, {s0, s1} *)
	DCD 0EEB40A60H		(* vcmp s0, s1 *)
	DCD 0EEF1FA10H		(* vmrs APSR_nzcv, FPSCR *)
	DCD 0E3A00001H		(* mov r0, 1 *)
	DCD 03A00000H		(* moveq r0, 0 *)
	MOV	PC, LR
END RealNe;

PROCEDURE RealGe*(r1, r2 : REAL) : BOOLEAN;
CODE
	DCD 0ECBD0A02H		(* vldmia R13, {s0, s1} *)
	DCD 0EEF40A40H		(* vcmp s1, s0 *)
	DCD 0EEF1FA10H		(* vmrs APSR_nzcv, FPSCR *)
	DCD 0E3A00001H		(* mov r0, 1 *)
	DCD 33A00000H		(* movcc r0, 0 *)
	MOV	PC, LR
END RealGe;

PROCEDURE RealGt*(r1, r2 : REAL) : BOOLEAN;
CODE
	DCD 0ECBD0A02H		(* vldmia R13, {s0, s1} *)
	DCD 0EEF40A40H		(* vcmp s1, s0 *)
	DCD 0EEF1FA10H		(* vmrs APSR_nzcv, FPSCR *)
	DCD 0E3A00001H		(* mov r0, 1 *)
	DCD 93A00000H		(* movls r0, 0 *)
	MOV	PC, LR
END RealGt;


(*------------------------------------------------------------------------------
Software IEC/IEEE double-precision conversion routines.
-------------------------------------------------------------------------------*)
PROCEDURE LRealToLInt*(r : LONGREAL) : LONGINT;
CODE
	DCD	0ECBD0B02H	(* vpop {d0} *)
	DCD	0EEBD1BC0H	(* vcvt.s32.f64 s2, d0 *)
	DCD	0EE110A10H		(* vmov r0, s2 *)
	MOV	PC, LR
END LRealToLInt;

PROCEDURE LRealToReal*(r : LONGREAL) : REAL;
CODE
	DCD	0ECBD0B02H	(* vpop {d0} *)
	DCD	0EEB71BC0H	(* vcvt.f32.f64 s2, d0 *)
	DCD	0EE110A10H		(* vmov r0, s2 *)
	MOV	PC, LR
END LRealToReal;

(*
int float64_to_int32_round_to_zero( float64 );
*)

(*-------------------------------------------------------------------------------
Software IEC/IEEE double-precision operations.
-------------------------------------------------------------------------------*)

PROCEDURE LRealRoundToInt*(r : LONGREAL) : LONGREAL;	(* Todo *)
CODE
	DCD	0ECBD0B02H	(* vpop {d0} *)
	DCD	0EEBD0BC0H	(* vcvt.s32.f64 s0, d0 *)
	DCD	0EEB82BC0H	(* cvt.f64.s32 d2, s0 *)
	DCD	0EC510B12H	(* vmov r0, r1, d2 *)	
	MOV	PC, LR
END LRealRoundToInt;

PROCEDURE LRealAdd*(r1,r2 : LONGREAL) : LONGREAL;
CODE
	DCD	0ECBD0B04H	(* vpop {d0, d1} *)
	DCD	0EE312B00H	(* vadd.f64 d2, d1, d0 *)
	DCD	0EC510B12H	(* vmov r0, r1, d2 *)	
	MOV	PC, LR
END LRealAdd;

PROCEDURE LRealSub*(r1,r2 : LONGREAL) : LONGREAL;
CODE
	DCD	0ECBD0B04H	(* vpop {d0, d1} *)
	DCD	0EE312B40H	(* vsub.f64 d2, d1, d0 *)
	DCD	0EC510B12H	(* vmov r0, r1, d2 *)	
	MOV	PC, LR
END LRealSub;

PROCEDURE LRealMul*(r1,r2 : LONGREAL) : LONGREAL;
CODE
	DCD	0ECBD0B04H	(* vpop {d0, d1} *)
	DCD	0EE212B00H	(* vmul.f64 d2, d1, d0 *)
	DCD	0EC510B12H	(* vmov r0, r1, d2 *)	
	MOV	PC, LR
END LRealMul;

PROCEDURE LRealDiv*(r1,r2 : LONGREAL) : LONGREAL;
CODE
	DCD	0ECBD0B04H	(* vpop {d0, d1} *)
	DCD	0EE812B00H	(* vdiv.f64 d2, d1, d0 *)
	DCD	0EC510B12H	(* vmov r0, r1, d2 *)	
	MOV	PC, LR
END LRealDiv;

PROCEDURE LRealRem*(r1,r2 : LONGREAL) : LONGREAL;
BEGIN
	HALT(99);
END LRealRem;

PROCEDURE LRealSqrt*(r : LONGREAL) : LONGREAL;
CODE
	DCD	0ECBD0B02H	(* vpop {d0} *)
	DCD	0EEB12BC0H	(* vsqrt.f64 d2, d0 *)
	DCD	0EC510B12H	(* vmov r0, r1, d2 *)	
	MOV	PC, LR
END LRealSqrt;

PROCEDURE LRealEq*(r1, r2 : LONGREAL) : BOOLEAN;
CODE
	DCD 0ECBD0B04H	(* vpop {d0, d1} *)
	DCD 0EEB40B41H		(* vcmp d0, d1 *)
	DCD 0EEF1FA10H		(* vmrs APSR_nzcv, FPSCR *)
	DCD 0E3A00000H		(* mov r0, 0 *)
	DCD 03A00001H		(* moveq r0, 1 *)
	MOV	PC, LR
END LRealEq;

PROCEDURE LRealLe*(r1, r2 : LONGREAL) : BOOLEAN;
CODE
	DCD 0ECBD0B04H	(* vpop {d0, d1} *)
	DCD 0EEB41B40H		(* vcmp d1, d0 *)
	DCD 0EEF1FA10H		(* vmrs APSR_nzcv, FPSCR *)
	DCD 0E3A00000H		(* mov r0, 0 *)
	DCD 93A00001H	(* movls r0, 1 *)
	MOV	PC, LR
END LRealLe;

PROCEDURE LRealLt*(r1, r2 : LONGREAL) : BOOLEAN;
CODE
	DCD 0ECBD0B04H	(* vpop {d0, d1} *)
	DCD 0EEB41B40H		(* vcmp d1, d0 *)
	DCD 0EEF1FA10H		(* vmrs APSR_nzcv, FPSCR *)
	DCD 0E3A00000H		(* mov r0, 0 *)
	DCD 33A00001H	(* movcc r0, 1 *)
	MOV	PC, LR
END LRealLt;

PROCEDURE LRealNe*(r1, r2 : LONGREAL) : BOOLEAN;
CODE
	DCD 0ECBD0B04H	(* vpop {d0, d1} *)
	DCD 0EEB40B41H		(* vcmp d0, d1 *)
	DCD 0EEF1FA10H		(* vmrs APSR_nzcv, FPSCR *)
	DCD 0E3A00001H		(* mov r0, 1 *)
	DCD 03A00000H		(* moveq r0, 0 *)
	MOV	PC, LR
END LRealNe;

PROCEDURE LRealGe*(r1, r2 : LONGREAL) : BOOLEAN;
CODE
	DCD 0ECBD0B04H	(* vpop {d0, d1} *)
	DCD 0EEB41B40H		(* vcmp d1, d0 *)
	DCD 0EEF1FA10H		(* vmrs APSR_nzcv, FPSCR *)
	DCD 0E3A00001H		(* mov r0, 1 *)
	DCD 33A00000H	(* movcc r0, 0 *)
	MOV	PC, LR
END LRealGe;

PROCEDURE LRealGt*(r1, r2 : LONGREAL) : BOOLEAN;
CODE
	DCD 0ECBD0B04H	(* vpop {d0, d1} *)
	DCD 0EEB41B40H		(* vcmp d0, d1 *)
	DCD 0EEF1FA10H		(* vmrs APSR_nzcv, FPSCR *)
	DCD 0E3A00001H		(* mov r0, 1 *)
	DCD 93A00000H	(* movls r0, 0 *)
	MOV	PC, LR
END LRealGt;

PROCEDURE RealNeg*(r : REAL) : REAL;
CODE
	DCD 0ECBD0A01H		(* vldmia R13, {s0} *)
	DCD 0EEB11A40H		(* vneg.f32 s2, s0 *)
	DCD 0EE110A10H		(* vmov r0, s2 *)
	MOV	PC, LR
END RealNeg;

PROCEDURE LRealNeg*(r : LONGREAL) : LONGREAL;
CODE
	DCD	0ECBD0B02H	(* vpop {d0} *)
	DCD	0EEB12B40H	(* vneg.f64, d2, d0 *)
	DCD	0EC510B12H	(* vmov r0, r1, d2 *)	
	MOV	PC, LR
END LRealNeg;


(*------------- Diverses -----------------------*)
PROCEDURE RealEntier*(r : REAL) : LONGINT;
CODE
	DCD 0ECBD0A01H		(* vldmia R13!, {s0} *)
	DCD 0EEBD1A40H		(* vcvtr.s32.f32 s2, s0 *)
	DCD 0EE110A10H		(* vmov r0,  s2 *)
	MOV	PC, LR
END RealEntier;

PROCEDURE RealAbs*(r : REAL) : REAL;
CODE
	DCD 0ECBD0A01H		(* vldmia R13, {s0} *)
	DCD 0EEB01AC0H		(* vabs.f32 s2, s0 *)
	DCD 0EE110A10H		(* vmov r0, s2 *)
	MOV	PC, LR
END RealAbs;

PROCEDURE LRealEntier*(r : LONGREAL) : LONGINT;
CODE
	DCD	0ECBD0B02H	(* vpop {d0} *)
	DCD	0EEBD1B40H	(* vcvtr.s32.f64 s2, s0 *)
	DCD	0EE110A10H	(* vmov r0,  s2 *)
	MOV	PC, LR
END LRealEntier;

PROCEDURE LRealAbs*(r : LONGREAL) : LONGREAL;
CODE
	DCD	0ECBD0B02H	(* vpop {d0} *)
	DCD	0EEB02BC0H	(* vabs.f64, d2, d0 *)
	DCD	0EC510B12H	(* vmov r0, r1, d2 *)	
	MOV	PC, LR
END LRealAbs;

PROCEDURE fesetround;	(* see disassembled libm.a *)
CODE
	DCD	0EEF10A10H	(* vmrs	r0, fpscr *)
	BIC	R0, R0, 0C00000H	(* clear RMode bits *)
	ORR	R0, R0, 0800000H	(* set round towards  minus infinity bits*)
	DCD	0EEE10A10H	(* vmsr	fpscr, r0 *)
	MOV	PC, LR
END fesetround;

(*
00000000 <fesetround>:
   0:	e3500501 	cmp	r0, #4194304	; 0x400000
   4:	0a000008 	beq	2c <fesetround+0x2c>
   8:	da000005 	ble	24 <fesetround+0x24>
   c:	e3500502 	cmp	r0, #8388608	; 0x800000
  10:	0a000005 	beq	2c <fesetround+0x2c>
  14:	e3500503 	cmp	r0, #12582912	; 0xc00000
  18:	0a000003 	beq	2c <fesetround+0x2c>
  1c:	e3a00001 	mov	r0, #1
  20:	e12fff1e 	bx	lr
  24:	e3500000 	cmp	r0, #0
  28:	1afffffb 	bne	1c <fesetround+0x1c>
  2c:	eef13a10 	vmrs	r3, fpscr
  30:	e3c33503 	bic	r3, r3, #12582912	; 0xc00000
  34:	e1830000 	orr	r0, r3, r0
  38:	eee10a10 	vmsr	fpscr, r0
  3c:	e3a00000 	mov	r0, #0
  40:	e12fff1e 	bx	lr
*)

BEGIN
	ExceptionFlags:=0; 
	RoundingMode:=RoundNearestEven; 
	DetectTininess:=TininessBeforeRounding; 
	OverflowExceptions:=FALSE;
(*	fesetround; moved to Linux0 *)
	Kernel.WriteString("Using experimental HardFloat VFP FPU code"); Kernel.WriteLn; 
END SoftFloat.












