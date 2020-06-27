MODULE Kernel;	(* rc/ard/nm/jm/devil/pjm/rml*)

(* common Kernel for MIPS 32, ARMv7 and RISC-V *)

(* OBERON System 3, Release 2.2.

Copyright 1997 Team of the Institute of Computer Systems of ETH Zuerich,
ETH Center, CH-8092 Zuerich, e-mail: oberon@inf.ethz.ch.

This module may be used under the conditions of the general Oberon 
System 3 license contract.  The full text can be requested from the 
above-mentioned address, or downloaded from

	"ftp://ftp.inf.ethz.ch/pub/software/Oberon/System3/license.txt;A"

Under the license terms stated it is in particular (a) prohibited to modify
the interface of this module in any way that disagrees with the style
or content of the system and (b) requested to provide all conversions
of the source code to another platform with the name OBERON. *)

(** Module Kernel is responsible for memory allocation, garbage collection and other run-time 
support for the Oberon language, as well as interfacing to the underlying machine.  Using features 
exported from module Kernel may result in an unportable module, as not all Oberon Kernels are 
the same. This module is of little importance to most Oberon programmers. *)

(*	Peter Matthias
	2014-11-07	started MIPS version, arguments of syscalls changed, Module description according to BootLinker, 
	2014-11-28	GetTimer returns only positive time value 
	2015-01-26	fixed GetTimeOfDay,  GetTimer uses GetTimeOfDay
	2015-01-27	implemented Kernel interface for all modules
	2015-01-28	removed Assert in NewArr
	2015-03-20	implemented TermHandler, fixed Shmdt
	2015-03-26	implemented Readv0, Writev0
	2015-04-12	removed select0
	2015-04-14	renamed GetEnv to GetConfig
	2015-04-21	implemented trace
	2015-05-07	implemented SysHalt, removed DefaultTrapHandler, SigReturn; made SignalHandler working 
							implemented GetFrame
	2015-05-24	fixed Open Flag numbering 
	2015-06-12	fixed system call return codes
	2015-06-13	made GetConfig using stack
	2015-06-29	removed ASSERT(eltag^.ptroff#-4); in NewArr for allocating POINTER TO ARRAY OF RECORD 
	2015-07-05	MBootLinker, Kernel, Modules: static core initialization done in Kernel
	2015-07-09	NewSys: uncommented init^.z3 := 0; NewBlock: added heap growing
	2015-07-18	exported NoOfArgs, GetArg, Static
	2015-07-31	changed SysCall code; 
	2015-09-25	changed prot argument in Mprotect0-- reverted, does only run on qemu
	2015-11-13	added ARM system call code, types and constants
	2015-12-09	moved Linux interface procedures to OLR.ARM.Linux0.Mod and OLR.MIPS.Linux0.Mod
	2016-06-12	initialized Kernel.modules in RBootLinker.InitKernel
	2016-08-16	using WriteInt from OLR.X86.Kernel.Mod
	2016-08-26	fixed GetConfig
	2016-10-05	moved signal handling to Linux0
	2017-02-17	moved signal handling back to Kernel
	2017-03-24	WIP changing data layout
	2017-05-03	removed FP
	2017-05-09	added Div at runtime; only execute body of module Modules

	SetClock not implemented ( only superuser can change time)
	reboot does not work
	
*)

IMPORT Linux0, SYSTEM;

CONST
	version*="ETH Oberon / Linux ";
	DATE*=" 2017-05-03";

	TRACE= "Kernel.Log";
	ARMv7="ARMv7";
	RISCV="RISC-V";
	MIPS="MIPS";

	NEWrecord= 0; NEWarray= 1; SYSTEMNEW= 2;
	deallocRECORD= 3; deallocARRAY= 4; deallocSYSBLK= 5;
	finalisation= 6; freePages= 7; showFreeBlocks= 8;
	(*newDMA= 9;*) memory= 10; livedead= 11; getConfig=12; showState= 13;
(*	traceheap=  {0..31};*)
	traceheap=  {getConfig, showState, NEWarray};
(*	traceheap=  {getConfig, showState, NEWarray};*)

	TimeAdjust=1;	(* adjust for local time *)

		(* heap/GC *)
	B = 32;	(* heap block size, must be a multiple of 32 *)
	NFL = 9;	(* number of free lists - 1 *)
	nil = 0;
	MarkBit = 0; ArrayBit = 1;  FreeBit = 2;  SubObjBit = 3; 
	mark = {MarkBit}; array = {ArrayBit};  free = {FreeBit};  subobj = {SubObjBit};
	ReserveSize = 65536-8;	(* bytes reserved for "Out of memory" trap handling *)
 
		(* timer *)
	TimeUnit* = 1000;	(* timer ticks per second, returned by GetTimer *)

TYPE
	ADDRESS = LONGINT;
	Name* = ARRAY 32 OF CHAR;	(* module name *)
	Proc* = Linux0.Proc;

	Export* = RECORD
			name*: Name;
			fprint*: LONGINT;
			adr*: ADDRESS;
			mode*: INTEGER
		END ;
		
	Cmd* = RECORD
		name*: Name;
		adr*: ADDRESS;
	END;

	Bytes* = POINTER TO ARRAY OF CHAR;
		
	Module* = POINTER TO ModuleDesc;	(* module descriptor *)
	ModuleDesc* = RECORD	(* Note: if this is changed, also update the static Linker *)(* Note: for all hard-coded array limits, see Compiler *)
			next*: Module;
			name*: Name;
			refcnt*, sb*, cb*: LONGINT;	(* refcnt=-1 is not initialized; static base; code base for compatibility *)
			exports*: POINTER TO ARRAY OF Export;
			tdescs*: POINTER TO ARRAY OF (* Kernel.Tag *) ADDRESS;
			cmds*: POINTER TO ARRAY OF Cmd;
			ptrTab*: POINTER TO ARRAY OF ADDRESS;
			imports*: POINTER TO ARRAY OF (* Module *) ADDRESS;
			data0*: POINTER TO ARRAY OF LONGINT;	(* data0 is consts, vars, code *)
			refs*: Bytes;
			term: Proc;
	END;

		(* type descriptors *)
	Tag = POINTER TO TypeDesc;
	TypeDesc = RECORD
		size: LONGINT;
		ptroff: LONGINT;
	END;

		(* heap/GC *)
	FreeBlockPtr = POINTER TO FreeBlock;
	FreeBlock = RECORD
		(* off-4 *) tag: Tag;
		(* off0 *) size: LONGINT;	(* field size aligned to 8-byte boundary, size MOD B = B-4 *)
		(* off4 *) next: ADDRESS
	END;
	BlockPtr* = POINTER TO Block;
	Block = RECORD
		lastElemToMark, currElem, firstElem: BlockPtr
	END;
	Blockm4Ptr = POINTER TO Blockm4;
	Blockm4 = RECORD
		tag: Tag;
		lastElemToMark, currElem, firstElem: LONGINT
	END;
	InitPtr = POINTER TO RECORD tag: Tag; z0, z1, z2, z3, z4, z5, z6, z7: LONGINT END;
		(*	the following type is used indirectly in InitHeap	*)
	PtrElemDesc = RECORD a: SYSTEM.PTR END;	(* has same type descriptor as element of ARRAY OF POINTER *)
	
	Finalizer* = PROCEDURE (obj: SYSTEM.PTR);
	FinObj = POINTER TO FinObjNode;
	FinObjNode = RECORD
		next: FinObj;
		obj: LONGINT;
		marked: BOOLEAN;
		fin: Finalizer;
	END;

	Timeval = RECORD sec, usec: LONGINT END;

		(* interrupt handling *)					(*						32,  33,	34		, 35	*)

	TrapHandler = PROCEDURE ( trap, sp, pc, page: LONGINT);

VAR
		(* exported variables *)
	modules* : Module;	(** list of modules, patched by Linker, currently modules must be first variable (at adress m.sb-4)! *)
	EnableGC*, DisableGC*: Proc;	(** Enable or Disable the GC *)
	runtime*: ARRAY 4 OF LONGINT;	(** for internal use *)
	trace*: ARRAY 35 OF CHAR;

(*	dynModBase*: LONGINT;*)

	Idle*: PROCEDURE(code: LONGINT);
	
		(* heap/GC *)
	firstBlock*, endBlock: (*FreeBlockPtr*) ADDRESS;
	FA: ARRAY NFL+1 OF (*FreeBlockPtr*) ADDRESS;
	reserve: BlockPtr;	(* reserved memory for out of memory trap *)
	ptrElemTag*: ADDRESS;
	candidates: ARRAY 1024 OF ADDRESS;	(* stack pointer candidates *)
	nofcand: INTEGER;
	firstTry: BOOLEAN;	(* used with GC & reserve *)
	GCstack: BOOLEAN;
	FinObjs: FinObj;

 	GClevel: LONGINT;
	
		(* interrupt handling/memory management *)
	handlingtrap: BOOLEAN;

(* OLR *)
	NoOfArgs*: LONGINT;
	Static*: BOOLEAN;	(* is programm completely statically linked? *)
	tracefd: LONGINT;
	startTime: Timeval;
(*	mod: Module;*)
	fsize, carea, savef, saver: LONGINT; 

(* Oberon Procedures *)
(** -- Low-level tracing support -- *)
(** WriteChar - Write a character to the trace output *)

	StackOrg*, siglevel: LONGINT;
	break*, 	(** has ctrl-break been pressed? *)
	inGC: BOOLEAN;	(** executing inside GC? *)
	traphandler, defaulttraphandler: TrapHandler;
	loop: Proc;
	SigTab: ARRAY 32 OF LONGINT;

PROCEDURE WriteChar*(c: CHAR);
BEGIN
	IF Linux0.Write0(  tracefd, SYSTEM.ADR(c), 1)#1 THEN HALT(99H) END;
END WriteChar;

(** WriteString - Write a string *)

PROCEDURE WriteString*( s: ARRAY OF CHAR);
VAR l: LONGINT;
BEGIN
	l:=0;
	WHILE (l< LEN(s)) & (s[l]# 0X ) DO INC( l) END;
	IF Linux0.Write0( tracefd, SYSTEM.ADR(s), l)# l THEN HALT(93H) END;
END WriteString;

(** WriteLn - Skip to the next line on trace output *)

PROCEDURE WriteLn*;
BEGIN WriteChar( 0AX);
END WriteLn;

(** WriteInt - Write "x" as a decimal number.  "w" is the field width. *)

PROCEDURE WriteInt*(x, w: LONGINT);
VAR
	i: LONGINT;
	x0: LONGINT;
	a: ARRAY 12 OF CHAR;
BEGIN
	IF x < 0 THEN
		IF x = MIN(LONGINT) THEN
			WriteString( "-2147483648");
			RETURN
		ELSE
			DEC(w); x0 := -x
		END
	ELSE
		x0 := x
	END;
	i := 0;
	REPEAT
		a[i] := CHR(x0 MOD 10 + 30H); x0 := x0 DIV 10; INC(i)
	UNTIL x0 = 0;
	WHILE w > i DO WriteChar( " "); DEC(w) END;
	IF x < 0 THEN WriteChar( "-") END;
	REPEAT DEC(i); WriteChar( a[i]) UNTIL i = 0
END WriteInt;

(** WriteHex - Write "x" as a hexadecimal number.
	The absolute value of "w" is the field width.  If "w" is negative, two
	hex digits are printed (x MOD 100H), otherwise 8 digits are printed. *)

PROCEDURE WriteHex*(x, w: LONGINT);
VAR
	buf: ARRAY 10 OF CHAR;
	c: CHAR;
	i, j: LONGINT;
BEGIN
	c:=" ";
	IF w >= 0 THEN j := 8 ELSE j := 2; w := -w END;
	FOR i := j+1 TO w DO WriteChar( c) END;
	FOR i := j-1 TO 0 BY -1 DO
		buf[i] := CHR(x MOD 10H + 48);
		IF buf[i] > "9" THEN
			buf[i] := CHR(ORD(buf[i]) - 48 + 65 - 10);
		END;
		x := x DIV 10H;
	END;
	buf[j] := 0X;
	WriteString( buf);
END WriteHex;

(** WriteMemory - Display a block of memory. *)

PROCEDURE WriteMemory*(adr, size: LONGINT);
VAR
	i, j: LONGINT;
	buf: ARRAY 4 OF CHAR;
BEGIN
	buf[1] := 0X;
	size := adr+size-1;
	FOR i := adr TO size BY 16 DO
		WriteHex(i, 9);
		FOR j := i TO i+15 DO
			IF j <= size THEN
				SYSTEM.GET(j, buf[0]);
				WriteHex(ORD(buf[0]), -3)
			ELSE
				buf := "   ";  WriteString(buf);  buf[1] := 0X
			END
		END;
		buf[0] := " ";	WriteString(buf);
		FOR j := i TO i+15 DO
			IF j <= size THEN
				SYSTEM.GET(j, buf[0]);
				IF (buf[0] < " ") OR (buf[0] >= CHR(127)) THEN
					buf[0] := "."
				END;
				WriteString(buf)
			END
		END;
		WriteLn
	END
END WriteMemory;

PROCEDURE^ GC*;
		
(** Shutdown - Terminate Oberon after executing all module terminators.  If code = 0, perform a soft reboot. *)

PROCEDURE Shutdown*(code: LONGINT);
VAR h: Proc;  t: LONGINT; m: Module;
BEGIN
	m:= modules;
(* no termination tested in this version *)
	WHILE (m#NIL) DO
		IF m.term # NIL THEN h := m.term; m.term := NIL;  h  END;
		m := m.next;
	END;
	WHILE (modules#NIL) & (modules.name#"Objects") DO
		modules := modules.next;
	END;
	GC;	(* close temporary files *)
	t:=Linux0.Close0( tracefd);
	IF (code = 1) THEN Linux0.Exit0( 0) END;	(* code=0: reboot; code=1: normal termination *)
	Linux0.Exit0( code);
END Shutdown;

PROCEDURE Halt(msg: ARRAY OF CHAR;  err: LONGINT);
BEGIN
	WriteString("Halt ");  WriteInt(err, 1);  WriteString(" - ");  WriteString(msg);  WriteLn;
	Shutdown( 1);
END Halt;

(** -- Trap handling -- *)

(** GetMod - Return the loaded module that contains code address pc. *)

PROCEDURE GetMod*(pc : LONGINT): Module;
VAR m: Module;
BEGIN
	m := modules;
	WHILE m # NIL DO 
		IF (pc>=m.cb) & (pc< (SYSTEM.ADR(m.data0[LEN(m.data0^)-1]))) THEN RETURN m
(*		IF (m.addr <= pc) & (pc < m.addr + m.size+3) THEN RETURN m*)
		ELSE m := m.next
		END
	END;
	RETURN NIL
END GetMod;

PROCEDURE GetNum*(refs: Bytes;  VAR i, num: LONGINT);
VAR n, s: LONGINT;  x: CHAR;
BEGIN
	s := 0;  n := 0;  x := refs[i];  INC(i);
	WHILE ORD(x) >= 128 DO
		INC(n, ASH(ORD(x) - 128, s));  INC(s, 7);  x := refs[i];  INC(i)
	END;
	num := n + ASH(ORD(x) MOD 64 - ORD(x) DIV 64 * 64, s)
END GetNum;

(*
	Reference = {OldRef | ProcRef} .
	OldRef = 0F8X offset/n name/s {Variable} .
	ProcRef = 0F9X offset/n nofPars/n RetType procLev/1 slFlag/1 name/s {Variable} .
	RetType = 0X | Var | ArrayType | Record .
	ArrayType = 12X | 14X | 15X .	(* static array, dynamic array, open array *)
	Record = 16X .
	Variable = VarMode (Var | ArrayVar | RecordVar ) offset/n name/s .
	VarMode = 1X | 3X .	(* direct, indirect *)
	Var = 1X .. 0FX .	(* byte, boolean, char, shortint, integer, longint, real, longreal, set, ptr, proc, string *)
	ArrayVar = (81X .. 8EX) dim/n .	(* byte, boolean, char, shortint, integer, longint, real, longreal, set, ptr, proc *)
	RecordVar = (16X | 1DX) tdadr/n .	(* record, recordpointer *)
*)

(* FindProc - Find a procedure in the reference block.  Return index of name, or -1 if not found. *)

PROCEDURE FindProc*(refs: Bytes;  ofs: LONGINT; update: BOOLEAN): LONGINT;
VAR i, m, pofs, t0, proc: LONGINT;  ch: CHAR;
BEGIN
	ofs:=ofs DIV 4;	(* only for ROP2 *)
	proc := -1;  i := 0;  m := LEN(refs^);
	ch := refs[i];  INC(i);
	WHILE (i < m) & ((ch = 0F8X) OR (ch = 0F9X)) DO	(* proc *)
		GetNum(refs, i, pofs);	(* pofs *)
		IF update THEN GetNum(refs, i, saver); GetNum(refs, i, savef); GetNum(refs, i, fsize); GetNum(refs, i, carea);
		ELSE GetNum(refs, i, t0); GetNum(refs, i, t0); GetNum(refs, i, t0); GetNum(refs, i, t0);
		END;
		proc := i;
		IF pofs > ofs THEN	(* previous procedure was the one *)
			ch := 0X	(* stop search *)
		ELSE	(* ~found *)
			IF ch = 0F9X THEN
				GetNum(refs, i, pofs);	(* nofPars *)
				INC(i, 3)	(* RetType, procLev, slFlag *)
			END;
			proc := i;	(* remember this position, just before the name *)
			REPEAT ch := refs[i];  INC(i) UNTIL ch = 0X;	(* pname *)
			IF i < m THEN
				ch := refs[i];  INC(i);	(* 1X | 3X | 0F8X | 0F9X *)
				WHILE (i < m) & (ch >= 1X) & (ch <= 3X) DO	(* var *)
					ch := refs[i];  INC(i);	(* type *)
					IF (ch >= 81X) OR (ch = 16X) OR (ch = 1DX) THEN
						GetNum(refs, i, pofs)	(* dim/tdadr *)
					END;
					GetNum(refs, i, pofs);	(* vofs *)
					REPEAT ch := refs[i];  INC(i) UNTIL ch = 0X;	(* vname *)
					IF i < m THEN ch := refs[i];  INC(i) END	(* 1X | 3X | 0F8X | 0F9X *)
				END
			END;
		END;
	END;
	IF (proc = -1) & (i # 0) THEN proc := i END;	(* first procedure *)
	RETURN proc
END FindProc;

PROCEDURE GetFrame0*(VAR fp: LONGINT);
BEGIN
	IF ODD(ASH(saver, -Linux0.FP)) THEN fp:=Linux0.Regs[ Linux0.FP]
	ELSE INC( fp, fsize); 
	END;
END GetFrame0;

PROCEDURE GetFrame*( fp: LONGINT; VAR pc: LONGINT);
VAR i, adr: LONGINT;
BEGIN
	WriteString("Getframe :"); WriteHex( fp, 8); WriteHex( fsize, 9); WriteHex( carea, 9); WriteHex( savef, 9); WriteHex( pc, 9); WriteLn;
	adr:=fp-fsize+carea;
	IF Linux0.ARCH=ARMv7 THEN i:=0;
		REPEAT
			IF ODD(ASH(savef, -i)) THEN
				SYSTEM.GET( adr, Linux0.FRegs[ i]); INC(adr, 4);
				SYSTEM.GET( adr, Linux0.FRegs[ i+1]); INC(adr, 4);
			 END;
			INC(i, 2);
		UNTIL i=32;
		i:=0;
		REPEAT
			IF ODD(ASH(saver, -i)) THEN SYSTEM.GET( adr, Linux0.Regs[ i]); INC(adr, 4); END;
			INC(i);
		UNTIL i=15;
	ELSE i:=31;	(* MIPS, only MOPL.CalleeSavedR *)
		adr:=fp-fsize+carea;
		REPEAT
			IF ODD(ASH(saver, -i)) THEN SYSTEM.GET( adr, Linux0.Regs[ i]); INC(adr, 4); END;
			DEC(i);
		UNTIL i=0;
	END;
	pc:=Linux0.Regs[ Linux0.LR];
END GetFrame;

(* DefaultTrapHandler - This handler is installed if nothing better is available... *)

PROCEDURE DefaultTrapHandler ( trap, sp, pc, page: LONGINT);
VAR mod: Module; refpos, n: LONGINT; c: CHAR; 
BEGIN
	IF siglevel >1 THEN
		IF siglevel >2 THEN Linux0.Exit0(1); Halt("Recursive trap", siglevel) END;
		WriteString("Error: Signal while handling Signal"); WriteLn;
	END;
	WriteString("DefaultTH, Trap: "); WriteInt( trap, 1);  WriteLn;
	n:=0;
	WHILE (sp<StackOrg) & (n<10) DO
		WriteHex( sp, 8);
		mod:=GetMod(pc);
		WriteString(" PC="); 
		IF mod=NIL THEN WriteHex( pc, 8); WriteString(" unknown Module"); WriteLn; RETURN END;
		WriteHex( pc-mod.cb, 8); WriteChar(" ");
		refpos:=FindProc(mod.refs, pc-mod.cb, TRUE);
		WriteString(mod.name);
		WriteChar(".");
		c:=mod.refs[refpos]; INC(refpos);
		WHILE c#0X DO
			WriteChar(c); 
			c:=mod.refs[refpos]; INC(refpos);
		END;
		WriteLn;
		INC(n);
		GetFrame0( sp);
		GetFrame( sp, pc);
	END;
END DefaultTrapHandler;

PROCEDURE SignalHandler;
CONST IMM12=1000H; IMM20=100000H;
VAR trap, j, adr: LONGINT; sinfo: Linux0.SigInfo; SC: Linux0.SigContext;
BEGIN
	SYSTEM.GETREG( Linux0.ARI, trap);	(* trap is 1st parameter in REG 0; Attention: might be overwritten by SignalHandler!*)
	IF Linux0.ARCH=ARMv7 THEN
		SYSTEM.GETREG( Linux0.SP, j); SC:=SYSTEM.VAL(Linux0.SigContext, j+64);	(* sc is on stack, distance is stack directly before SignalHandler *)
	ELSE
		SYSTEM.GETREG( Linux0.ARI+1, sinfo);	(* siginfo is 2nd parameter *)
		SYSTEM.GETREG( Linux0.ARI+2, SC);	(* sigcontext is 3rd parameter of handler *)
	END;
	INC( siglevel);
	IF Linux0.ARCH=MIPS THEN adr:=sinfo.adr ELSE adr:=0 END;
	WriteHex( trap, 6);		trap:=SigTab[ trap];	WriteHex( trap, 9);
	WriteHex( SYSTEM.VAL( LONGINT, SC), 9);	WriteHex( SC.pc, 9);

(* only used to get distance from sc to fp; trap with SYSTEM.PUTREG(1, 1236H);*)
(*
	WriteLn;
	j:=0; adr:=SYSTEM.VAL( LONGINT, SC);
	REPEAT
		INC(j, 4); INC( adr, 4);
		SYSTEM.GET( adr, trap);
		WriteHex( trap, 9);
		SC:= SYSTEM.VAL(Linux0.SigContext, adr);
	UNTIL (SC.regs[1]=1236H) OR (j>1000H);
	WriteLn; WriteString("success: "); WriteHex(j, 9); WriteLn;
	Linux0.Exit0(1);
*)
	j:=0;
	REPEAT
		IF j DIV Linux0.RegDist MOD 8 =0 THEN WriteLn; END;
		WriteHex(SC.regs[j], 9);
		INC( j, Linux0.RegDist);
	UNTIL j=LEN(SC.regs);
	WriteHex(SC.pc, 9); WriteLn;

	IF (trap= 13) & inGC THEN break:=TRUE; DEC( siglevel); RETURN END;	(* ctrl-c from terminal  *)
	IF Linux0.ARCH=MIPS THEN
		IF (trap=-Linux0.SIGTRAP) THEN SYSTEM.GET( SC.pc, trap);	(* Traps only for MIPS *)
			IF trap DIV 8 MOD 8 = 6 THEN trap:=ASH(trap, -6) MOD 1024;
				IF trap=1023 THEN trap:=MAX(INTEGER) END;
			END;
		END;
	ELSIF trap= 28 THEN SYSTEM.GET(SC.pc, j);	(* Invalid instruction used as TRAP *)
		WriteHex( j, 9); WriteLn;
		IF Linux0.ARCH=ARMv7 THEN
			IF j DIV IMM20= Linux0.XTRAP DIV IMM20 THEN trap:= j DIV 100H MOD IMM12; IF trap=255 THEN trap:=MAX(INTEGER) END END;
		ELSIF Linux0.ARCH=RISCV THEN
			IF j MOD 8000H= Linux0.XTRAP THEN trap:= ASH(j, -15) END;
		END;
	END;

	Linux0.CopyRegs(SC); 
	IF (defaulttraphandler # NIL) THEN defaulttraphandler( trap, Linux0.Regs[ Linux0.SP], SC.pc, adr ) END;
	IF inGC THEN Halt("Trap in GC", trap); (* Linux0.Exit0(1);*) END;

	Linux0.CopyRegs(SC); 
	IF (traphandler # NIL) & (traphandler#defaulttraphandler) THEN traphandler( trap, Linux0.Regs[Linux0.SP], SC.pc, adr ) END;	(* was: handler |trap 16: Disk full *)

	IF trap=MAX(INTEGER) THEN INC(SC.pc, 4);	(* ! *)
	ELSE
		SC.regs[Linux0.SP*Linux0.RegDist]:= StackOrg;
(*		SC.regs[Linux0.FP*Linux0.RegDist]:= StackOrg;*)
		SC.pc:=SYSTEM.VAL( LONGINT, loop);
		IF loop=NIL THEN Linux0.Exit0( 1) END;
	END;
	DEC( siglevel);
END SignalHandler;

(*
PROCEDURE SysHalt( );	(* RISC-V, trap no. in R10, not used because of leaf procedures with traps *)
VAR pc, sp, trap: LONGINT;
BEGIN
	SYSTEM.GETREG(Linux0.SP, sp);
	SYSTEM.GETREG(Linux0.ARI, trap);
	SYSTEM.GETREG(Linux0.LR, pc);
	WriteString("SysHalt Trap nr. "); WriteInt( trap, 3);  WriteHex( pc, 9); WriteLn;
	DefaultTrapHandler( trap, sp+48, pc, 0);
(*	handler( trap, fp, pc, 0);*)
	IF trap#MAX(INTEGER) THEN
		SYSTEM.PUTREG(Linux0.SP, StackOrg);	(* callers FP *)
		SYSTEM.PUTREG(Linux0.FP, StackOrg);	(* callers FP *)
		Linux0.loop;
	END;
END SysHalt;
*)
PROCEDURE SignalQuitHandler;
VAR sig: LONGINT;
BEGIN
	SYSTEM.GETREG( Linux0.ARI, sig);	(* sig is parameter of handler *)
	INC( siglevel);
	WriteString("Recived signal nr. "); WriteInt( sig, 3); WriteLn;
	WriteString("Terminating Oberon! "); WriteLn;
	Shutdown( 0);
END SignalQuitHandler;

(** InstallTrap - Install the trap handler *)

PROCEDURE InstallTrap*(p: TrapHandler);
BEGIN
	IF p# NIL THEN
		traphandler := p;
	END;
END InstallTrap;

(** InstallLoop - Install procedure to which control is transferred after a trap *)

PROCEDURE InstallLoop*(p: Proc);
BEGIN	loop := p
END InstallLoop;

(** -- Memory/Object management -- *)

(** Available - Return the size in bytes of the remaining free heap space *)

PROCEDURE Available*(): LONGINT;
	VAR i, avail: LONGINT; ptr: FreeBlockPtr;
BEGIN
	avail := 0; i := 0;
	WHILE i <= NFL DO
		ptr := SYSTEM.VAL(FreeBlockPtr, FA[i]);
		WHILE ptr # NIL DO
			INC(avail, ptr^.size); ptr := SYSTEM.VAL(FreeBlockPtr, ptr^.next)
		END;
		INC(i)
	END;
	RETURN avail
END Available;

(** LargestAvailable - Return the size in bytes of the largest free available memory block. 
Allocating objects with a size greater than this size will cause the memory allocation to fail. *) 

PROCEDURE LargestAvailable*(): LONGINT;
	VAR i, max: LONGINT; ptr: FreeBlockPtr;
BEGIN
	i := NFL; max := 0;
	WHILE (i >= 0) & (max = 0) DO
		ptr := SYSTEM.VAL(FreeBlockPtr, FA[i]);
		WHILE ptr # NIL DO
			IF ptr^.size > max THEN max := ptr^.size END;
			ptr := SYSTEM.VAL(FreeBlockPtr, ptr^.next)
		END;
		DEC(i)
	END;
	RETURN max
END LargestAvailable;

(** Used - Return the size in bytes of the amount of memory currently in use in the heap. *) 

PROCEDURE Used*(): LONGINT;
BEGIN
	RETURN endBlock - firstBlock - Available()
END Used;

PROCEDURE Mark* (block: BlockPtr);
	TYPE Tag0 = POINTER TO RECORD (*size,*) ptroff: SET END;
		(* size skipped, because accessed via tag = actual tag + 4 *)
	VAR father, field, currElem: BlockPtr; offset: LONGINT; tag, downtag, marked: Tag0; arraybit: SET;
BEGIN
	SYSTEM.GET(SYSTEM.VAL(ADDRESS, block)-4, tag);
	IF ~(SubObjBit IN SYSTEM.VAL(SET, block)) THEN	(* not a subobject *)
		marked := SYSTEM.VAL(Tag0, SYSTEM.VAL(SET, tag) + mark);
		IF tag # marked THEN
			SYSTEM.PUT(SYSTEM.VAL(ADDRESS, block)-4, marked);
			SYSTEM.GET(SYSTEM.VAL(ADDRESS, SYSTEM.VAL(SET, tag) - array)-4, marked);
			EXCL(SYSTEM.VAL(SET, marked), MarkBit); (* necessary to mask mark bit *)
			SYSTEM.GET(SYSTEM.VAL(ADDRESS, marked)-4, arraybit);
			INCL(arraybit, MarkBit);
			SYSTEM.PUT(SYSTEM.VAL(ADDRESS, marked)-4, arraybit);
			arraybit := SYSTEM.VAL(SET, tag) * array;
			IF arraybit # {} THEN currElem := block^.firstElem;
				tag := SYSTEM.VAL(Tag0, SYSTEM.VAL(SET, tag) - arraybit)
			ELSE currElem := block
			END;
			father := NIL;
			LOOP
				INC(SYSTEM.VAL(ADDRESS, tag), 4);	(* step through rec fields by modifying tag (locally only) *)
				offset := SYSTEM.VAL(LONGINT, tag^.ptroff - {ArrayBit});	(* strip deep copy flag *)
				IF offset < 0 THEN
					INC(SYSTEM.VAL(ADDRESS, tag), offset);
					IF (arraybit # {}) & (currElem # block^.lastElemToMark) THEN
						INC(SYSTEM.VAL(ADDRESS, currElem), SYSTEM.VAL(LONGINT, tag^.ptroff - {ArrayBit}))
					ELSE (* up *)
							(* here the tag is modified to store the state of the traversal.  bits 2- are changed *)
						SYSTEM.PUT(SYSTEM.VAL(ADDRESS, block)-4, SYSTEM.VAL(SET, tag) + arraybit + mark);
						IF father = NIL THEN EXIT END;
						SYSTEM.GET(SYSTEM.VAL(ADDRESS, father)-4, tag);
						arraybit := SYSTEM.VAL(SET, tag) * array;
						tag := SYSTEM.VAL(Tag0, SYSTEM.VAL(SET, tag) - (array + mark));
						IF arraybit # {} THEN currElem := father^.currElem
						ELSE currElem := father
						END;
						offset (*field address*) := SYSTEM.VAL(ADDRESS, currElem) + SYSTEM.VAL(LONGINT, tag^.ptroff - {ArrayBit});
						SYSTEM.GET(offset, field);
						SYSTEM.PUT(offset, block);
						block := father;
						father := field
					END
				ELSE
					offset (*field address*) := SYSTEM.VAL(ADDRESS, currElem) + offset;
					SYSTEM.GET(offset, field);
					IF field#NIL THEN	(* SYSTEM.VAL(LONGINT, field)> firstBlock-8 was: field#NIL *)
						SYSTEM.GET(SYSTEM.VAL(ADDRESS, field)-4, downtag);
						IF subobj * SYSTEM.VAL(SET, field) = {} THEN	(* not a subobject *)
							marked := SYSTEM.VAL(Tag0, SYSTEM.VAL(SET, downtag) + mark);
							IF downtag # marked THEN (* down *)
								SYSTEM.PUT(SYSTEM.VAL(ADDRESS, field)-4, marked);
									(* here the tag is modified.  bits 2- are changed *)
								SYSTEM.PUT(SYSTEM.VAL(ADDRESS, block)-4, SYSTEM.VAL(SET, tag) + arraybit + mark);
								IF arraybit # {} THEN block^.currElem:= currElem END;
								SYSTEM.GET(SYSTEM.VAL(ADDRESS, SYSTEM.VAL(SET, downtag) - array)-4, marked);
								EXCL(SYSTEM.VAL(SET, marked), MarkBit); (* necessary to mask mark bit *)
								SYSTEM.GET(SYSTEM.VAL(ADDRESS, marked)-4, arraybit);
								INCL(arraybit, MarkBit);
								SYSTEM.PUT(SYSTEM.VAL(ADDRESS, marked)-4, arraybit);
								arraybit := SYSTEM.VAL(SET, downtag) * array;
								IF arraybit # {} THEN currElem := field^.firstElem ELSE currElem := field END;
								SYSTEM.PUT(offset, father);
								father := block;
								block := field;
								tag := SYSTEM.VAL(Tag0, SYSTEM.VAL(SET, downtag) - arraybit)
							END
						ELSE	(* do not mark subobject *)
							SYSTEM.GET(SYSTEM.VAL(ADDRESS, SYSTEM.VAL(SET, downtag) - array)-4, marked);
							EXCL(SYSTEM.VAL(SET, marked), MarkBit);
							SYSTEM.GET(SYSTEM.VAL(ADDRESS, marked)-4, downtag);
							INCL(SYSTEM.VAL(SET, downtag), MarkBit);
							SYSTEM.PUT(SYSTEM.VAL(ADDRESS, marked)-4, downtag)
						END
					END
				END;
			END;	(* LOOP *)
		END;
	ELSE (* do not mark subobject, subobjects are not traced *)
			(* remove array bit because of array subobjects in module block *)
		SYSTEM.GET(SYSTEM.VAL(ADDRESS, SYSTEM.VAL(SET, tag) - array)-4, tag);
		EXCL(SYSTEM.VAL(SET, tag), MarkBit);
		SYSTEM.GET(SYSTEM.VAL(ADDRESS, tag)-4, arraybit);
		INCL(arraybit, MarkBit);
		SYSTEM.PUT(SYSTEM.VAL(ADDRESS, tag)-4, arraybit);
	END
END Mark;

PROCEDURE CheckFinObjs;
	VAR n: FinObj; tag: LONGINT;
BEGIN
	n := FinObjs;
	WHILE n # NIL DO
		SYSTEM.GET(n.obj - 4, tag);
		n.marked := MarkBit IN SYSTEM.VAL(SET, tag);
		n := n.next
	END;
	n := FinObjs;	(* now mark all objects reachable from the unmarked checked objects *)
		(* they will be freed at the next GC, unless the checked object is ressurrected *)
	WHILE n # NIL DO
		IF ~n.marked THEN Mark(SYSTEM.VAL(BlockPtr, n.obj)) END;
		n := n.next
	END
END CheckFinObjs;

PROCEDURE WriteType(t: ADDRESS);	(* t is tdesc *)
VAR m: LONGINT;  name: ARRAY 32 OF CHAR;
BEGIN
	SYSTEM.GET(t-4, t);
	SYSTEM.GET(t+48, m);
	SYSTEM.MOVE(m+4, SYSTEM.ADR(name[0]), 32);
	WriteString(name);  WriteChar(".");
	SYSTEM.MOVE(t+16, SYSTEM.ADR(name[0]), 32);
	IF name = "" THEN WriteString("<anon>")
	ELSE WriteString(name)
	END
END WriteType;

PROCEDURE Sweep;
	VAR p, end: Blockm4Ptr; lastp: FreeBlockPtr; tag, notmarked, tdesc: Tag; size, lastsize, i: LONGINT;
		lastA: ARRAY NFL+1 OF ADDRESS;
		t: LONGINT;  live, dead, lsize, ssize: LONGINT;
BEGIN
	i := 0;
	WHILE i <= NFL DO FA[i] := nil; lastA[i] := SYSTEM.ADR(FA[i]); INC(i) END;
	p := SYSTEM.VAL(Blockm4Ptr, firstBlock);
	end := SYSTEM.VAL(Blockm4Ptr, endBlock);
	lastsize := 0;  live := 0;  dead := 0;  lsize := 0;
	WHILE p # end DO
		tag := SYSTEM.VAL(Tag, SYSTEM.VAL(SET, p^.tag) - free);
		notmarked := SYSTEM.VAL(Tag, SYSTEM.VAL(SET, tag) - mark);
		tdesc := SYSTEM.VAL(Tag, SYSTEM.VAL(SET, notmarked) - array);
		IF notmarked # tdesc THEN (* array block *) size := p^.lastElemToMark + tdesc^.size - SYSTEM.VAL(ADDRESS, p)
		ELSE size := tdesc^.size + 4
		END;
		ssize := size;
		size := SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, size + B-1)-SYSTEM.VAL(SET, B-1));
		IF tag = notmarked THEN (* collect *)
			IF traceheap * {3..8, 11} # {} THEN
				IF 11 IN traceheap THEN INC(dead) END;
				IF notmarked # tdesc THEN
					IF 4 IN traceheap THEN
						WriteString("[DA ");  WriteHex(SYSTEM.VAL(LONGINT, p)+4, 8);
						SYSTEM.GET(SYSTEM.ADR(p.lastElemToMark)+12, t);
						WriteChar(" ");  WriteInt(t, 1); WriteChar(" ");  WriteType(SYSTEM.VAL(LONGINT, tdesc));
						WriteString("] ")
					END
				ELSIF SYSTEM.VAL(LONGINT, tdesc) = SYSTEM.VAL(LONGINT, p)+4 THEN
					IF traceheap * {5,8} # {} THEN
						IF FreeBit IN SYSTEM.VAL(SET, p^.tag) THEN
							IF 8 IN traceheap THEN
								WriteString("[FB ");  WriteHex(SYSTEM.VAL(LONGINT, p), 8);
								SYSTEM.GET(SYSTEM.ADR(p.lastElemToMark), t);
								WriteChar(" ");  WriteInt(t, 1);  WriteString("] ")
							END
						ELSE
							IF 5 IN traceheap THEN
								WriteString("[DS ");  WriteHex(SYSTEM.VAL(LONGINT, p), 8);
								SYSTEM.GET(SYSTEM.ADR(p.lastElemToMark), t);
								WriteChar(" ");  WriteInt(t, 1);  WriteString("] ")
							END
						END
					END
				ELSE
					IF 3 IN traceheap THEN
						WriteString("[DR ");  WriteHex(SYSTEM.VAL(LONGINT, p)+4, 8);
						WriteHex(SYSTEM.VAL(LONGINT, tdesc), 9);  WriteChar(" ");
						WriteType(SYSTEM.VAL(LONGINT, tdesc));  WriteString("] ")
					END
				END
			END;
			IF lastsize = 0 THEN lastp := SYSTEM.VAL(FreeBlockPtr, p) END;
			INC(lastsize, size)
		ELSE
			IF (11 IN traceheap) THEN 
				INC(live); INC(lsize, ssize)
			END;
			p^.tag := notmarked;
			IF lastsize > 0 THEN
				lastp^.size := lastsize - 4;
				lastp^.tag := SYSTEM.VAL(Tag, SYSTEM.VAL(SET, SYSTEM.ADR(lastp^.size)) + free);
				i := lastsize DIV B;
				IF i > NFL THEN i := NFL END;
				lastp^.next := nil;
				SYSTEM.PUT(lastA[i], lastp);
				lastA[i] := SYSTEM.ADR(lastp^.next);
				lastsize := 0
			END
		END;
		INC(SYSTEM.VAL(ADDRESS, p), size)
	END;
	(* last collected block: *)
	IF lastsize > 0 THEN
		lastp^.size := lastsize - 4;
		lastp^.tag := SYSTEM.VAL(Tag, SYSTEM.VAL(SET, SYSTEM.ADR(lastp^.size)) + free);
		i := lastsize DIV B;
		IF i > NFL THEN i := NFL END;
		lastp^.next := nil;
		SYSTEM.PUT(lastA[i], lastp);
		lastA[i] := SYSTEM.ADR(lastp^.next)
	END;
	IF 11 IN traceheap THEN
		WriteString("[");  WriteInt(live, 1);  WriteString(" live (");
		IF lsize # 0 THEN WriteInt(lsize DIV live, 1) END;
		WriteString("), ");
		WriteInt(dead, 1);  WriteString(" dead]")
	END
END Sweep;

PROCEDURE CheckHeap(msg: ARRAY OF CHAR);	(* check heap consistency *)
VAR tag: Tag;  p, end: Blockm4Ptr; size, i: LONGINT;
BEGIN
	WriteString(msg);  WriteLn;
	p := SYSTEM.VAL(Blockm4Ptr, firstBlock);
	end := SYSTEM.VAL(Blockm4Ptr, endBlock);
	i := 0;
	WHILE SYSTEM.VAL(LONGINT, p) < SYSTEM.VAL(LONGINT, end) DO
		WriteHex(SYSTEM.VAL(LONGINT, p), 9);  WriteChar(".");
		WriteHex(SYSTEM.VAL(LONGINT, p^.tag), 8);
		tag := SYSTEM.VAL(Tag, SYSTEM.VAL(SET, p^.tag) - {MarkBit,ArrayBit,FreeBit});
		ASSERT(tag # NIL);
		IF ArrayBit IN SYSTEM.VAL(SET, p^.tag) THEN
			size := p^.lastElemToMark + tag^.size - SYSTEM.VAL(LONGINT, p)
		ELSE
			size := tag^.size + 4
		END;
		WriteChar(".");  WriteHex(size, 8);
		INC(i);  IF i MOD 3 = 0 THEN WriteLn END;
		size := SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, size + B-1)-SYSTEM.VAL(SET, B-1));
		INC(SYSTEM.VAL(LONGINT, p), size)
	END;
	WriteString(" p, end: "); WriteHex( SYSTEM.VAL(LONGINT, p), 9); WriteHex(SYSTEM.VAL(LONGINT, end), 9); WriteLn;
END CheckHeap;

PROCEDURE CheckCandidates;	(* nofcand > 0 *)
	VAR i, j, h, p: LONGINT; block: Blockm4Ptr; tag, notmarked, tdesc: Tag;
BEGIN
	(* first sort them in increasing order using shellsort *)
	h := 1; REPEAT h := h*3 + 1 UNTIL h > nofcand;
	REPEAT h := h DIV 3; i := h;
		WHILE i < nofcand DO p := candidates[i]; j := i;
			WHILE (j >= h) & (candidates[j-h] > p) DO
				candidates[j] := candidates[j-h]; j := j-h;
			END;
			candidates[j] := p; INC(i)
		END
	UNTIL h = 1;
	(* sweep phase *)
	block := SYSTEM.VAL(Blockm4Ptr, firstBlock);
	i := 0; p := candidates[i];
	LOOP
		IF p <= SYSTEM.VAL(ADDRESS, block) + 4 THEN
			IF p = SYSTEM.VAL(ADDRESS, block) + 4 THEN Mark(SYSTEM.VAL(BlockPtr, p)) END;
			INC(i);
			IF i = nofcand THEN EXIT END;
			p := candidates[i]
		ELSIF p <= SYSTEM.VAL(ADDRESS, block) + 28 THEN (* system block *)
			IF p = SYSTEM.VAL(ADDRESS, block) + 28 THEN Mark(SYSTEM.VAL(BlockPtr, SYSTEM.VAL(ADDRESS, block)+4)) END;
			INC(i);
			IF i = nofcand THEN EXIT END;
			p := candidates[i]
		ELSE
			tag := block^.tag;
			notmarked := SYSTEM.VAL(Tag, SYSTEM.VAL(SET, tag) - (mark + free));
			tdesc := SYSTEM.VAL(Tag, SYSTEM.VAL(SET, notmarked) - array);
			IF notmarked # tdesc THEN (* array block *) h := block^.lastElemToMark + tdesc^.size - SYSTEM.VAL(ADDRESS, block)
			ELSE h := tdesc^.size + 4
			END;
			INC(SYSTEM.VAL(ADDRESS, block), SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, h + B-1)-SYSTEM.VAL(SET, B-1)));
			IF block = SYSTEM.VAL(Blockm4Ptr, endBlock) THEN EXIT END
		END
	END;
	nofcand := 0
END CheckCandidates;

PROCEDURE Candidate(p: LONGINT);
	VAR tag, tag0: LONGINT;
BEGIN
	IF ((p > firstBlock) & (p < endBlock)) THEN
		IF p MOD B = 0 THEN
			SYSTEM.GET(p-4, tag);
			IF tag MOD 8 IN {0, 2} THEN	(* array or record, not yet marked, not free *)
				candidates[nofcand] := p; INC(nofcand);
				IF nofcand = LEN(candidates) THEN CheckCandidates END
			END
		ELSIF p MOD 16 = 8 THEN	(* subobj *)
			SYSTEM.GET(p-4, tag);
			IF (tag MOD B = 0) & (tag > firstBlock ) & (tag < endBlock) THEN
				SYSTEM.GET(tag-4, tag0);
				IF tag0 = tag THEN
					candidates[nofcand] := p; INC(nofcand);
					IF nofcand = LEN(candidates) THEN CheckCandidates END
				END
			END
		ELSE (* skip *)
		END
	END
END Candidate;
		
PROCEDURE FinalizeObjs;
	VAR n, prev: FinObj;
BEGIN
	n := FinObjs;
	WHILE n # NIL DO
		IF ~n.marked THEN
			IF n = FinObjs THEN FinObjs := FinObjs.next ELSE prev.next := n.next END;
			IF 6 IN traceheap THEN
				WriteString("[Fin");  WriteHex(n.obj, 9);  WriteString("] ")
			END;
			n.fin(SYSTEM.VAL(SYSTEM.PTR, n.obj))
		ELSE prev := n
		END;
		n := n.next;
	END
END FinalizeObjs;

PROCEDURE ^NewSys(size: LONGINT): ADDRESS;
PROCEDURE ^GetTimer*( ):LONGINT;

(** GC - Immediately activate the garbage collector. *)

PROCEDURE GC*;
	VAR i, p, sp, ptradr: LONGINT; m: Module; ptr: BlockPtr;  avail, largest, t0, tf0, tf1, st: LONGINT;
BEGIN
	inGC := TRUE;
	IF GClevel > 0 THEN
		IF traceheap # {} THEN
			WriteString("(GC");
			IF memory IN traceheap THEN avail := Available();  largest := LargestAvailable() END;
			st := GetTimer();
		END;
		m := modules;	(* ModuleDesc and ModuleBlock are marked via Kernel.modules *)
		WHILE m # NIL DO
			Mark(SYSTEM.VAL(BlockPtr, m));	(* the code, data etc. is marked via fields of m *)
			i := LEN(m.ptrTab^); IF i > 0 THEN ptradr := SYSTEM.ADR(m.ptrTab[0]) END; 
			WHILE i > 0 DO
				SYSTEM.GET(ptradr, p); SYSTEM.GET(p, ptr);
				IF ptr # NIL THEN Mark(ptr) END;
				DEC(i); INC(ptradr, 4);
			END;
			i := LEN(m.tdescs^); IF i > 0 THEN ptradr := SYSTEM.ADR(m.tdescs[0]) END; 
			WHILE i > 0 DO
				SYSTEM.GET(ptradr, ptr); Mark(ptr);
				DEC(i); INC(ptradr, 4);
			END;
			m := m^.next;
		END;
			(* check stack *)
		IF GCstack THEN
			SYSTEM.GETREG( Linux0.SP, sp);	(* was SYSTEM.ESP *)
			ASSERT(sp <= StackOrg);

			nofcand := 0;
			WHILE sp < StackOrg DO
				SYSTEM.GET(sp, p); Candidate(p); INC(sp, 4)
			END;
			IF nofcand > 0 THEN CheckCandidates END
		END;
		CheckFinObjs;
		Sweep;
		IF (reserve = NIL) & firstTry THEN
			IF LargestAvailable() >= ReserveSize THEN p:=NewSys( ReserveSize); reserve := SYSTEM.VAL(BlockPtr, p) END
		END;
		IF 7 IN traceheap THEN
			t0 := SYSTEM.ADR(FA[NFL]);  WriteString("[FP");
			LOOP
				SYSTEM.GET(t0, t0);
				IF t0 = 0 THEN EXIT END;
				tf0 := t0+12;  SYSTEM.GET(t0+4, tf1);  tf1 := tf1-8+tf0;
				INC(tf0, (-tf0) MOD 1000H);  DEC(tf1, tf1 MOD 1000H);
				IF tf0 < tf1 THEN WriteHex(tf0, 9);  WriteChar(" ");  WriteInt((tf1-tf0) DIV 1000H, 1) END;
				t0 := t0+8
			END;
			WriteString(" PF] ")
		END;
		FinalizeObjs;
		IF traceheap # {} THEN
			st := GetTimer()-st;
			IF memory IN traceheap THEN
				avail := Available()-avail;  largest := LargestAvailable()-largest;
				WriteInt(avail, 1);  WriteString(" +");  WriteInt(largest, 1)
			END;
			WriteChar(" ");  WriteInt(st, 1);  WriteString("ms");
			WriteString(" CG)"); WriteLn;
		END;
	END;
	inGC := FALSE;
	IF break THEN
		break := FALSE;
		HALT(80H+13)	(* Keyboard interrupt *)
	END;
END GC;

PROCEDURE^ GrowHeap( size: LONGINT);

PROCEDURE NewBlock (size: LONGINT): InitPtr;	(* size MOD B = 0 *)
	VAR i, rest: LONGINT; adr, AN: ADDRESS; ptr: InitPtr; restptr: FreeBlockPtr;
BEGIN
	IF break THEN break := FALSE; HALT(80H+13) END;
	IF size < 0 (* NEW(p, MAX(LONGINT)) *) THEN HALT(80H+14) END;
	i := size DIV B;
	IF i > NFL THEN i := NFL END;
	adr := SYSTEM.ADR(FA[0]) + 4*i;
	AN := SYSTEM.ADR(FA[NFL]);	(* constant register *)
	LOOP
		SYSTEM.GET(adr, ptr);
		IF adr = AN THEN
			LOOP
				IF ptr = NIL THEN
					IF (* (TrapHandlingLevel = 0) & *) firstTry THEN
						WriteString(" NewBlock "); WriteHex( size, 8); WriteHex(LargestAvailable(), 9); WriteLn;
						GC;
						firstTry := FALSE; ptr := NewBlock(size); firstTry := TRUE;
						RETURN ptr
					ELSE
						GrowHeap(size);
						firstTry := TRUE; ptr := NewBlock(size);
						RETURN ptr;
					END
				END;
				IF ptr^.z0 + 4 >= size THEN EXIT END;
				adr := SYSTEM.ADR(ptr^.z1); SYSTEM.GET(adr, ptr)
			END;
			EXIT
		END;
		IF ptr # NIL THEN EXIT END;
		INC(adr, 4)
	END;
	(* ptr # NIL *)
	SYSTEM.PUT(adr, ptr^.z1);
	rest := ptr^.z0 + 4 - size;
	restptr := SYSTEM.VAL(FreeBlockPtr, SYSTEM.VAL(ADDRESS, ptr) + size);
	IF rest > 0 THEN	(* >= B >= 16 *)
		i := rest DIV B;
		IF i > NFL THEN i := NFL END;
		restptr^.tag := SYSTEM.VAL(Tag, SYSTEM.VAL(SET, SYSTEM.ADR(restptr^.size)) + free);
		restptr^.size := rest - 4;
		restptr^.next := FA[i]; FA[i] := SYSTEM.VAL(ADDRESS, restptr)
	END;
	RETURN ptr
END NewBlock;

(* NewRec - Implementation of NEW.  Do not call directly. *)

PROCEDURE NewRec( tag: Tag): ADDRESS;	(* implementation of NEW(ptr) *)
	VAR p, size: LONGINT; ptr, init: InitPtr; 
BEGIN (* tag^.size = rectyp^.size *)
	IF 0 IN traceheap THEN
		WriteString("[NR ");  WriteType(SYSTEM.VAL(LONGINT, tag));
	END;
	ASSERT(SYSTEM.VAL(LONGINT, tag) MOD 8 = 0);	(* no Oberon-X flags allowed *)
(*	IF tag = NIL THEN tag := SYSTEM.VAL(Tag, ptrElemTag) END;	(* descriptor for ARRAY * OF *) only in X86 Kernel ?*)
	size := SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, tag^.size + (4 (*tag*) + B-1))-SYSTEM.VAL(SET, B-1));
	ptr := NewBlock(size);
	init := SYSTEM.VAL(InitPtr, SYSTEM.VAL(ADDRESS, ptr) + size - 32);
	init^.z0 := 0; init^.z1 := 0; init^.z2 := 0; init^.z3 := 0; init^.z4 := 0; init^.z5 := 0; init^.z6 := 0;
	WHILE init # ptr DO
		DEC(SYSTEM.VAL(ADDRESS, init), 32);
		init^.z0 := 0; init^.z1 := 0; init^.z2 := 0; init^.z3 := 0; init^.z4 := 0; init^.z5 := 0; init^.z6 := 0; init^.z7 := 0
	END;
	ptr^.tag := tag;
	p := SYSTEM.VAL(ADDRESS, ptr) + 4;
	IF 0 IN traceheap THEN
		WriteHex(SYSTEM.VAL(LONGINT, p), 9);  WriteString("] "); WriteHex(LargestAvailable(), 9); 
	END;
	RETURN p;
END NewRec;

(* NewSys - Implementation of SYSTEM.NEW.  Do not call directly. *)

PROCEDURE NewSys(size: LONGINT): ADDRESS;
VAR ptr, init: InitPtr; p, bp: LONGINT;
BEGIN
	IF 2 IN traceheap THEN
		WriteString("[NS ");  WriteInt(size, 1)
	END;
	size := SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, size + (28 + B-1))-SYSTEM.VAL(SET, B-1));
	ptr := NewBlock(size);
	init := SYSTEM.VAL(InitPtr, SYSTEM.VAL(ADDRESS, ptr) + size - 32);
	WHILE init # ptr DO
		init^.tag := NIL; init^.z0 := 0; init^.z1 := 0; init^.z2 := 0; init^.z3 := 0; init^.z4 := 0; init^.z5 := 0; init^.z6 := 0;
		DEC(SYSTEM.VAL(ADDRESS, init), 32);
	END;
	ptr^.tag := SYSTEM.VAL(Tag, SYSTEM.ADR(ptr^.z0));
	ptr^.z0 := size - 4;
	ptr^.z1 := -4;
	init^.z2 := 0;
	init^.z3 := 0;
(*
	SYSTEM.GETREG( Linux0.FP, bp);	(* was SYSTEM.EBP *)
	SYSTEM.GET(bp+4, init^.z3);	(* PC where NewSys has been called. Used for debugging *)
*)
	init^.z4 := 0;	(* bit 1 must be 0 to distinguish from array SysBlk *)
	ptr^.z5 := SYSTEM.ADR(ptr^.z0);
	init^.z6 := 0;	
	p := SYSTEM.VAL(ADDRESS, ptr) + 28;
	IF 2 IN traceheap THEN
		WriteHex(SYSTEM.VAL(LONGINT, p), 9);  WriteString("] "); WriteHex(LargestAvailable(), 9);
	END;
	RETURN p;
END NewSys;

(* NewArr - Implementation of NEW.  Do not call directly. *)

PROCEDURE NewArr(eltag: Tag; nofelem, nofdim: LONGINT): ADDRESS;
VAR p, size, firstElem, elSize, arrSize, vectSize: LONGINT; ptr, init: InitPtr; 
BEGIN
	IF NEWarray IN traceheap THEN
		WriteString("[NA ");  WriteInt(nofelem, 1);  WriteChar(" ");  WriteInt(nofdim, 1)
	END;
	ASSERT(SYSTEM.VAL(LONGINT, eltag) MOD 8 IN {0,2});	(* test Oberon-X flags *)(* p.m. uncommented 2015-11-30 *)
	IF eltag = NIL THEN
		eltag := SYSTEM.VAL(Tag, ptrElemTag)	(* array of pointer to *)
	END;
	elSize := eltag^.size;
	arrSize := nofelem*elSize;
	IF arrSize = 0 THEN
		(* we need a SysBlk that looks like an ArrBlk to the compiler! *)
		p:=NewSys( 4*nofdim+12);
		ptr:=SYSTEM.VAL(InitPtr,p-4);
		ptr.z0:=0; (* no lastElemToMark *)
		ptr.z1:=0; (* reserved *)
		ptr.z2:=p+4*nofdim+12; (* firstElem *)
		RETURN p;
	END;
	ASSERT(arrSize > 0); 
	vectSize :=  4*nofdim +4;	(* -> ADR(firstElem) MOD 4 = 0; don't use x86 version *)
(*	ASSERT(eltag^.ptroff#-4); *)
	IF eltag^.ptroff = -4 THEN (* no pointers in element type *)
		p:=NewSys(arrSize + vectSize + 12);
		SYSTEM.PUT(p, SYSTEM.VAL(SET, arrSize + vectSize+15)-SYSTEM.VAL(SET, 3));
	ELSE
		size := SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, arrSize + vectSize + (12 + B-1))-SYSTEM.VAL(SET, B-1));
		ptr := NewBlock(size);
		init := SYSTEM.VAL(InitPtr, SYSTEM.VAL(ADDRESS, ptr) + size - 32);
		WHILE init # ptr DO
			init^.tag := NIL; init^.z0 := 0; init^.z1 := 0; init^.z2 := 0; init^.z3 := 0; init^.z4 := 0; init^.z5 := 0; init^.z6 := 0;
			DEC(SYSTEM.VAL(ADDRESS, init), 32);
		END;
		ptr^.tag := SYSTEM.VAL(Tag, SYSTEM.VAL(SET, eltag) + array);
		firstElem := SYSTEM.ADR(ptr^.z2) + vectSize;
		ptr^.z0 := firstElem + arrSize - elSize;
		(* ptr^.z1 is reserved for mark phase *)
		ptr^.z2 := firstElem;
		ptr^.z3 := 0; ptr^.z4 := 0; ptr^.z5 := 0; ptr^.z6 := 0;
		p := SYSTEM.VAL(ADDRESS, ptr) + 4;
	END;
	IF NEWarray IN traceheap THEN
		WriteHex(SYSTEM.VAL(LONGINT, p), 9);  WriteString("] ")
	END;
	RETURN p;
END NewArr;

(** DisableTracing - Disable the GC tracing of a record field of the specified type.  For internal use only. *)

PROCEDURE DisableTracing*(recadr, fldadr: ADDRESS);
VAR t, i, j, ofs: ADDRESS;  n: LONGINT;
BEGIN
	SYSTEM.GET(recadr-4, t);
	n := 0;  i := t+4;  SYSTEM.GET(i, ofs);  j := 0;
	WHILE ofs >= 0 DO
		IF ofs = fldadr-recadr THEN j := i END;
		INC(n);  INC(i, 4);  SYSTEM.GET(i, ofs)
	END;
	ASSERT((ofs = -4*(n+1)) & (j # 0));
	SYSTEM.GET(j+4, ofs);
	WHILE ofs >= 0 DO
		SYSTEM.PUT(j, ofs);  INC(j, 4);  SYSTEM.GET(j+4, ofs)
	END;
	SYSTEM.PUT(j, -4*n)
END DisableTracing;

PROCEDURE Idle0( code: LONGINT);
END Idle0;

(** RegisterObject - Register a record for finalization.  basic = FALSE *)

PROCEDURE RegisterObject* (obj: SYSTEM.PTR;  fin: Finalizer;  basic: BOOLEAN);
	VAR n: FinObj;
BEGIN
	IF 6 IN traceheap THEN
		WriteString("[RegObj");  WriteHex(SYSTEM.VAL(LONGINT, obj), 9);  WriteString("] ")
	END;
	IF obj#NIL THEN
		NEW(n); n.next := FinObjs; n.obj := SYSTEM.VAL(LONGINT, obj); n.marked := FALSE; n.fin := fin;
		FinObjs := n
	END;
END RegisterObject;

(** InstallTermHandler - Install a procedure to execute when a module is freed.  Normally used to uninstall
interrupt handlers or tasks and perform other cleanup duties.  Never perform upcalls in proc, because the upcalled
module will no longer be in memory! *)

PROCEDURE InstallTermHandler* (h: Proc);	(* can also be used by modules below Modules, e.g. FileDir *)
	VAR codebase, handlerAdr: LONGINT; m: Module; found: BOOLEAN;
BEGIN
(* not implemented *)
	m := modules; handlerAdr := SYSTEM.VAL(LONGINT, h); found := FALSE;
	WHILE (m # NIL) & ~found DO
(*		IF (SYSTEM.VAL(LONGINT,m.addr) <= handlerAdr) & (handlerAdr <  SYSTEM.VAL(LONGINT,m.addr)+m.size) THEN found := TRUE*)
		IF (m.cb <= handlerAdr) & (handlerAdr <=  SYSTEM.ADR(m.data0^[ LEN(m.data0^)-1])) THEN found := TRUE

		ELSE m := m.next
		END
	END;
	IF found THEN m.term := h END;
END InstallTermHandler;

(** FinalizeModule - Execute all object finalizers registered by a module, and then execute its termination handler. *)
(* 2.3.7 *)
PROCEDURE FinalizeModule*(m: Module);
VAR h: Proc;  beg, end: LONGINT;  n, prev: FinObj;
BEGIN
	WriteString("Kernel.FinalizeModule not yet implemented!"); WriteLn;
(*
	beg := SYSTEM.VAL( LONGINT,m.addr);  end := beg + m.size;
	n := FinObjs;
	WHILE n # NIL DO
		IF (beg <= SYSTEM.VAL(LONGINT, n.fin)) & (SYSTEM.VAL(LONGINT, n.fin) <= end) THEN
			IF n = FinObjs THEN FinObjs := FinObjs.next ELSE prev.next := n.next END;
			IF 6 IN traceheap THEN
				WriteString("[Fin");  WriteHex(n.obj, 9);  WriteString("] ")
			END;
			n.fin(SYSTEM.VAL(SYSTEM.PTR, n.obj))
		ELSE prev := n
		END;
		n := n.next
	END;
	IF m.term # NIL THEN
		IF 16 IN traceheap THEN
			WriteString("Calling TermHandler ");  WriteString(m.name);  WriteLn
		END;
		h := m.term; m.term := NIL; h
	END
*)
END FinalizeModule;

(** -- Clock/Timer -- *)

PROCEDURE U2OTime*( VAR clock, date, time: LONGINT);	(* convert Unix time to Oberon *)
VAR d, s, h, y, mi, mo, dij: LONGINT;
BEGIN	(* not implemented *)
		s:= clock MOD 60; clock:= clock DIV 60;
		mi:= clock MOD 60; clock:= clock DIV 60;
		INC( clock, TimeAdjust);
		h:= (clock) MOD 24; clock:= (clock) DIV 24;
		time:=( h*64+mi)*64+s;
		y:= 70; dij:= 365; (*INC( t);*)
		REPEAT
			INC( y); DEC( clock, dij);		(* is this ( v )right?? *)
			IF ( y MOD 4 =0) & ( ( y MOD 100 # 0) OR ( y MOD 400=0) )THEN dij:= 366 ELSE dij:= 365 END;
		UNTIL clock<=dij;
		IF clock<= 59 THEN
			IF clock<=31 THEN mo:=1; d:= clock;
			ELSE mo:=2; d:=clock-31;
			END;
		ELSE
			IF dij= 366 THEN mo:=2; d:= 29; DEC( clock) END;
			IF clock>59 THEN
				IF clock<= 90 THEN mo:=3; d:= clock-59;
				ELSIF clock<= 120 THEN mo:=4; d:= clock-90;
				ELSIF clock<= 151 THEN mo:=5; d:= clock-120;
				ELSIF clock<= 181 THEN mo:=6; d:= clock-151;
				ELSIF clock<= 212 THEN mo:=7; d:= clock-181;
				ELSIF clock<= 243 THEN mo:=8; d:= clock-212;
				ELSIF clock<= 273 THEN mo:=9; d:= clock-243;
				ELSIF clock<= 304 THEN mo:=10; d:= clock-273;
				ELSIF clock<= 334 THEN mo:=11; d:= clock-304;
				ELSE mo:=12; d:=clock-334;
				END;
			END;
		END;
		date:=( y*16+mo)*32+d;
END U2OTime;

PROCEDURE O2UTime*( date, time: LONGINT): LONGINT;	(* convert Oberon time to Unix *)
BEGIN
	WriteString("Kernel.O2UTime not implemeted yet"); WriteLn;
	RETURN 0;
END O2UTime;

(** GetClock - Return current time and date *)

PROCEDURE GetClock*(VAR time, date: LONGINT);
VAR i: LONGINT; j: Timeval;
BEGIN
	i:=Linux0.GetTimeOfDay(SYSTEM.ADR(j), 0);
	U2OTime(j.sec, date, time);
END GetClock;

(** SetClock - Set current time and date *)

PROCEDURE SetClock*(time, date: LONGINT);
BEGIN	HALT( 101);	(* because only superuser is allowed to do this *)
END SetClock;

(** GetTimer - Return "ticks" since initialisation (Kernel.TimeUnit ticks per second) *)

PROCEDURE GetTimer*( ): LONGINT;
VAR i: LONGINT; j: Timeval;
BEGIN
	i:=Linux0.GetTimeOfDay(SYSTEM.ADR(j), 0);
	RETURN (j.sec-startTime.sec)*1000 +(j.usec -startTime.usec) DIV 1000;
END GetTimer;

(** -- Miscellaneous -- *)

PROCEDURE DefaultEnableGC;
BEGIN	INC(GClevel) 
END DefaultEnableGC;

PROCEDURE DefaultDisableGC;
BEGIN	DEC(GClevel)
END DefaultDisableGC;

PROCEDURE GrowHeap( size: LONGINT);	
VAR
	high0, high1, i: LONGINT;
	f: FreeBlockPtr;
	first: BOOLEAN;
BEGIN
	size:= (size+0FFFFFH) DIV 100000H * 100000H;
	high0:=endBlock+4;
	high1:=high0+size;
	first:=firstBlock-B=endBlock;
	endBlock:=Linux0.Brk0(high1);	(* risc-v brk returns previous brk*)
	IF endBlock<0 THEN HALT(80H+14) END; 
	i:=Linux0.MProtect0( high0, size, 7);	(* was 7 *)
	IF traceheap # {} THEN
		WriteString("Heap growing: "); WriteHex(high0, 9);  WriteHex(high1, 9); WriteLn
	END;
	endBlock:=high1;
	DEC(endBlock, 4);
	i:=high0;
	REPEAT
		SYSTEM.PUT( i, LONG(LONG( 0))); INC (i, 4);
	UNTIL i>=high0+size;
	DEC(high0, 4);
	IF first THEN INC(high0,B) END;
	f:=SYSTEM.VAL(FreeBlockPtr, high0);
	f^.tag := SYSTEM.VAL(Tag, SYSTEM.VAL(SET, SYSTEM.ADR(f^.size)) + free);
	f^.size := high1-high0-(B+4); f^.next := 0;
		(* init free list & reserve *)
(*
CheckHeap(" Checking Heap: ");
*)	
	GClevel := 1;  GCstack := TRUE;
	GC;
	GClevel := 0;  GCstack := TRUE;
END GrowHeap;

PROCEDURE InitHeap;	(* modules already initialized *)
VAR
	c: CHAR;
	i, t: LONGINT;
	m: Module;
	td: POINTER TO RECORD filler: ARRAY 4 OF LONGINT; name: Name END;
	str: ARRAY 32 OF CHAR;
BEGIN
	inGC := FALSE;  break := FALSE;  FinObjs := NIL;
	m := modules;
	IF m = NIL THEN Halt("Modlist", 1) END;	(* modules list not there! *)
	m := modules;  WHILE m.name # "Kernel" DO m := m.next END;
	i := LEN(m.tdescs^);  ptrElemTag := 0;
	REPEAT
		DEC(i);  t := m.tdescs[i];  SYSTEM.GET(t - 4, td);
		IF td.name = "PtrElemDesc" THEN ptrElemTag := t END
	UNTIL (ptrElemTag # 0);
		(* init heap *)
	firstBlock:=Linux0.Brk0(0)+(B-4);
	endBlock:=firstBlock-B;
	reserve := NIL;  firstTry := TRUE;
	GrowHeap(1000000H);
	EnableGC := DefaultEnableGC;  DisableGC := DefaultDisableGC;
END InitHeap;

(* ------------------------------------------------------------------------------------------------*)
(* InitRuntime - Initialise runtime support. *)

PROCEDURE InitRuntime;
VAR
	nr: PROCEDURE (tag: Tag): ADDRESS;	
	ns: PROCEDURE (size: LONGINT): ADDRESS;
	na: PROCEDURE (eltag: Tag; nofelem, nofdim: LONGINT): ADDRESS;
	div: PROCEDURE;
BEGIN
	nr:=NewRec; ns:=NewSys; na:=NewArr;
	runtime[0] := SYSTEM.VAL(LONGINT, nr);	(* 253 *)
	runtime[1] := SYSTEM.VAL(LONGINT, ns);	(* 252 *)
	runtime[2] := SYSTEM.VAL(LONGINT, na);	(* 251 *)
END InitRuntime;

(* OLR *)

PROCEDURE GetArg*(n: LONGINT; VAR val: ARRAY OF CHAR);
VAR l, m: LONGINT; c: CHAR;
BEGIN
	IF (n>=0) & (n<NoOfArgs) THEN
		SYSTEM.GET( StackOrg+(n+1)*(Linux0.RegSize DIV 8), l);
		m:=0;
		REPEAT
			SYSTEM.GET( l, c);
			val[m]:=c;
			INC(l);
			INC(m);
		UNTIL (c=0X);
	END;
END GetArg;

PROCEDURE CmdLine;
VAR
	n: LONGINT;
	s: ARRAY 64 OF CHAR;
BEGIN
	WriteString("CmdLine: ");
	WriteInt( NoOfArgs, 1);
	n:=0;
	WHILE n<NoOfArgs DO
		WriteChar(" ");
		GetArg(n, s);
		WriteString(s);
		INC(n);
	END;
	WriteLn;
END CmdLine;

PROCEDURE GetConfig*(env: ARRAY OF CHAR; VAR val: ARRAY OF CHAR);
VAR sadr, j, n: LONGINT; ch: CHAR;
BEGIN	(* stack layout at http://asm.sourceforge.net/articles/startup.html *)
	WriteString(env); WriteChar("=");
	sadr:=StackOrg+(NoOfArgs+2)*(Linux0.RegSize DIV 8);
	SYSTEM.GET( sadr, n);
	WHILE n#0  DO	
		SYSTEM.GET(n, ch);
		j:=0;
		WHILE ch=env[j] DO
			INC(n); SYSTEM.GET(n, ch); INC(j);
		END;
		IF ch="=" THEN
			j:=0;
			REPEAT
				INC(n);
				SYSTEM.GET(n, ch);
				val[j]:=ch; INC(j);
			UNTIL ch=0X;
			WriteString(val); WriteLn;
			RETURN;
		END;
		INC(sadr, Linux0.RegSize DIV 8);	
		SYSTEM.GET( sadr, n);
	END;
	WriteString(" not found");WriteLn;
	val[0]:=0X;
END GetConfig;

(*	Get distance from stackpointer to number of args *)
(*
PROCEDURE GetDistance;
VAR a, b, c: LONGINT;
BEGIN
	a:=Linux0.StackOrg; b:=-4;
	REPEAT
		INC(b, 4);
		SYSTEM.GET( a+b, c);
	UNTIL c=1;				(* be sure ol? is called without args *)
	WriteString("Distance to number of args: "); WriteInt( b, 6);  WriteLn;	(* 24 *)
END GetDistance;
*)

PROCEDURE Init;
TYPE Body = PROCEDURE;
VAR i, err: LONGINT; body: Body; m: Module;
BEGIN
	err:=Linux0.SetSignal(Linux0.SIGCONT, SignalQuitHandler);
	err:=Linux0.SetSignal(Linux0.SIGCHLD, SignalQuitHandler);
	i:=Linux0.GetTimeOfDay(SYSTEM.ADR(startTime), 0);
	m:=modules;
	WHILE m#NIL DO
		WriteHex( m.cb, 8);  WriteHex( SYSTEM.ADR(m.refs^)-m.cb-24, 9); WriteChar(" "); WriteString(m.name);  WriteLn;
		IF m.name #"Kernel" THEN						(* we already are in Kernel *)
			body:=SYSTEM.VAL(Body, m.cb);
			body;
		END;
		m:=m.next;
	END;
END Init;

PROCEDURE InitTrap;
VAR i, err: LONGINT;
BEGIN
	defaulttraphandler:=DefaultTrapHandler;
	traphandler:= DefaultTrapHandler;
	siglevel:=0;
	i:=1;
	REPEAT SigTab[i]:=-i; INC( i) UNTIL i=32;
	SigTab[ Linux0.SIGINT]:= 13;
	SigTab[ Linux0.SIGFPE]:= 10;
	SigTab[ Linux0.SIGILL]:= 28;
	SigTab[ Linux0.SIGSEGV]:= 29;

	err:=Linux0.SetSignal(Linux0.SIGINT, SignalHandler);
	err:=Linux0.SetSignal(Linux0.SIGILL, SignalHandler);
	err:=Linux0.SetSignal(Linux0.SIGFPE, SignalHandler);
	err:=Linux0.SetSignal(Linux0.SIGSEGV, SignalHandler);
(*	err:=SetSignal(SIGPIPE, SignalHandler);*)

	err:= Linux0.SetSignal(Linux0.SIGCONT, SYSTEM.VAL( Linux0.Proc, 1));
	err:= Linux0.SetSignal(Linux0.SIGCHLD, SYSTEM.VAL( Linux0.Proc, 1));
END InitTrap;

BEGIN
	SYSTEM.GETREG( Linux0.SP, StackOrg);	(* SP *)
	INC(StackOrg, 18H);	(* diff between SP and FP *)
	tracefd:= Linux0.Openat0( Linux0.ATFDCWD, SYSTEM.ADR(TRACE), Linux0.ORDWR+Linux0.OCREAT+Linux0.OTRUNC, SYSTEM.VAL(LONGINT,{2, 5, 7, 8}));
	WriteString( version); WriteString( Linux0.ARCH); WriteString( DATE); WriteLn;
	Static:=TRUE;	(* Modules sets Static to FALSE *)
(*	GetDistance;*)
	IF traceheap # {} THEN
		WriteString("StackOrg "); WriteHex( StackOrg, 8);  WriteHex(SYSTEM.ADR(StackOrg), 9); WriteLn;
	END;
	SYSTEM.GET(StackOrg, NoOfArgs);
	CmdLine;
	Idle:= Idle0;
	InitRuntime;
	InitHeap;
	InitTrap; 
	GetConfig("OTRACE", trace);
	Init;
END Kernel.

(*
TraceHeap:
0	1	NEW record
1	2	NEW array
2	4	SYSTEM.NEW
3	8	deallocate record
4	16	deallocate array
5	32	deallocate sysblk
6	64	finalisation
7	128	free pages
8	256	show free blocks
9	512	NewDMA
10	1024	before/after memory
11	2048	live/dead
*)
