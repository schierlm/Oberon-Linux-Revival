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

MODULE Kernel;	(* rc/ard/nm/jm/devil/pjm/rml*)

(** Module Kernel is responsible for memory allocation, garbage collection and other run-time 
support for the Oberon language, as well as interfacing to the underlying machine.  Using features 
exported from module Kernel may result in an unportable module, as not all Oberon Kernels are 
the same. This module is of little importance to most Oberon programmers. *)

(*
	1998-05-15	p.matthias:	started LNO Version
	2012-11-23	p.m.:	started PiOberon Version based on LNO.Kernel.Mod
	2014-04-05	p.m.:	implemented Gettimer	(not according to libc... )
	2014-04-07	p.m.:	 SignalHandler working, test if heap corrupted after trap
	2014-04-09	p.m.:	added Div0 Trap
	2014-04-10	p.m.:	added SysHalt
	2014-04-11				changed signalhandler, negative traps positive signals
	2014-04-12				implemented SysHalt instead of SYSTEM.HALT
	2014-04-14				Made Procedures for Traps 1 to 12 and export via runtime, changed OCE to use runtime[ ] instead if SWI
	2014-04-20				made idle work, load is less than 1% on rk3188
	2014-04-22				made Traps 1 to 255 work; changed OCE to use runtime[ 4] instead if SWI
	2014-05-11				GetTimer timer adjusted from *5 to *10
	2014-05-31				calling GC before Shutdown to close some "anonymous" files
	2014-06-27				re-implemented ASSERT
	2014-07-02				moved signal to System, removed SetTimer, Expired
	2015-03-09				added IOCTL0, empty SigReturn (for compatibility with new Display /Input driver)
	2015-03-26				implemented Readv0, Writev0
	2015-04-14				renamed GetEnv to GetConfig
	2015-04-21				implemented trace
	2015-05-06				changed SysHalt, removed SigReturn
	2015-05-09				changed CacheFlush0 to not move 0 to R2
	2015-05-29	initialized otrace
	2015-06-07	added DivModH, not yet used as speed improvement seems to be minimal
	2015-06-13	made GetConfig using stack
	2015-12-11	split OLR.ARM.Kernel.Mod to OLR.ARMl.Linux0.Mod and OLR.ARMl.Kernel.Mod
	2016-08-26	fixed GetConfig
	2016-10-23	removed SysHalt; traps use illigal instruction iinst now
	2017-02-11	made DivMod OBERON compatible 

	SetClock not implemented ( only superuser can change time)
	reboot does not work

	Registers = "R0 R1 R2 R3 R4 R5 R6 R7 R8 R9 RA RB FP SP LR PC ";

Compiler BUG FOR i=0  TO x  BY 1 DO is not being executed ??

*)

IMPORT Linux0, SYSTEM;

CONST
	version* = "ETH Oberon / Linux ";  
	DATE*=" 2016-10-23";
	TRACE= "Kernel.Log";
	RegSize*=Linux0.RegSize;

	NEWrecord= 0; NEWarray= 1; SYSTEMNEW= 2;
	deallocRECORD= 3; deallocARRAY= 4; deallocSYSBLK= 5;
	finalisation= 6; freePages= 7; showFreeBlocks= 8;
	(*newDMA= 9;*) memory= 10; livedead= 11; getConfig=12; showState= 13;
	traceheap=  {getConfig, showState};

		(* registers *)
	RA=10; RB=11; PC = 15;

	TimeAdjust=1;	(* adjust for local time *)

		(* heap/GC *)
	B = 32;	(* heap block size, must be a multiple of 32 *)
	N = 9;	(* number of free lists - 1 *)
	nil = 0;
	MarkBit = 0; ArrayBit = 1;  FreeBit = 2;  SubObjBit = 3; 
	mark = {MarkBit}; array = {ArrayBit};  free = {FreeBit};  subobj = {SubObjBit};
	ReserveSize = 65536-8;	(* bytes reserved for "Out of memory" trap handling *)
 
		(* timer *)
	TimeUnit* = 1000;	(* timer ticks per second, returned by GetTimer *)
	iinst=0C1F0700H;

TYPE
	ADDRESS = LONGINT;
	Name* = ARRAY 32 OF CHAR;	(* module name *)
	Proc* = PROCEDURE;
	Cmd* = RECORD
		name*: Name;
		adr*: ADDRESS;
	END;

	Bytes* = POINTER TO ARRAY OF CHAR;

	Module* = POINTER TO ModuleDesc;	(* module descriptor *)
	ModuleDesc* = RECORD	(* Note: if this is changed, also update the static Linker *)
		next*: Module;				(* Note: for all hard-coded array limits, see Compiler *)
		name*: Name;
		init*, trapped*: BOOLEAN;
		key*, refcnt*, sb* : LONGINT;
		entries*: POINTER TO ARRAY OF ADDRESS; 
		cmds*: POINTER TO ARRAY OF Cmd;
		ptrTab*: POINTER TO ARRAY OF ADDRESS;
		tdescs*: POINTER TO ARRAY OF (* Tag *) ADDRESS;
		imports*: POINTER TO ARRAY OF Module;
		size* : LONGINT; (** size of code+string consts+glob vars in bytes *)
		addr*: ADDRESS;  (** virtual addr where module is loaded to (data,code,strconsts) *)
		refs* : Bytes;
		term* : Proc;
		code*, data*: POINTER TO ARRAY OF ADDRESS;
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
	BlockPtr = POINTER TO Block;
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

	SigCPTR= POINTER TO SigContext;
	SigContext= RECORD
		trapNo, errCode, oldMask: LONGINT;
		r0, r1, r2, r3, r4, r5, r6, r7, r8, r9, ra, rb, fp, sp, lr, pc : LONGINT;
		cpsr, faultAddr, signal2: LONGINT;
	END;

		(* interrupt handling *)
	TrapHandler* = PROCEDURE (error, fp, pc, page: LONGINT);

	Timeval = RECORD sec, usec: LONGINT END;

VAR
		(* exported variables *)
	modules* : Module;	(** list of modules, patched by Linker *)
	EnableGC*, DisableGC*: Proc;	(** Enable or Disable the GC *)
	runtime*: ARRAY 5 OF LONGINT;	(** for internal use *)
	trace*: ARRAY 35 OF CHAR;

	dynModBase*: LONGINT;

	Idle*: PROCEDURE(code: LONGINT);
	
		(* heap/GC *)
	firstBlock, endBlock: (*FreeBlockPtr*) ADDRESS;
	FA: ARRAY N+1 OF (*FreeBlockPtr*) ADDRESS;
	reserve: BlockPtr;	(* reserved memory for out of memory trap *)
	ptrElemTag: ADDRESS;
	candidates: ARRAY 1024 OF ADDRESS;	(* stack pointer candidates *)
	nofcand: INTEGER;
	firstTry: BOOLEAN;	(* used with GC & reserve *)
	GCstack: BOOLEAN;
	FinObjs: FinObj;

	GClevel: LONGINT;
	
		(* interrupt handling/memory management *)
	handler: TrapHandler;	(* trap handlers *)
	loop: Proc;	(* main loop *)
	handlingtrap: BOOLEAN;

(* OLR *)
	NoOfArgs*: LONGINT;
	Static*: BOOLEAN;

	tracefd, siglevel: LONGINT;
	startTime: Timeval;

(** -- Low-level tracing support -- *)
(** WriteChar - Write a character to the trace output *)

PROCEDURE WriteChar*(c: CHAR);
BEGIN
	IF Linux0.Write0( tracefd, SYSTEM.ADR(c),  1)#1 THEN HALT(99H) END;;
END WriteChar;

(** WriteString - Write a string *)

PROCEDURE WriteString*( s: ARRAY OF CHAR);
VAR l: LONGINT;
BEGIN
	l:=0;
	WHILE (l< LEN(s)) & (s[l]# 0X ) DO INC( l) END;
	IF Linux0.Write0(tracefd, SYSTEM.ADR(s),  l)# l THEN HALT(93H) END;
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
	s: ARRAY 2 OF CHAR;
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
	s[0] := " ";  s[1] := 0X;
	WHILE w > i DO WriteString( s); DEC(w) END;
	s[0] := "-";
	IF x < 0 THEN WriteString( s) END;
	REPEAT DEC(i); s[0] := a[i]; WriteString( s) UNTIL i = 0
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
			buf[i] := CHR(ORD(buf[i]) - 48 + 65 - 10)
		END;
		x := x DIV 10H
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
	WHILE (m#NIL) DO
		IF m.term # NIL THEN h := m.term; m.term := NIL;  h  END;
		m := m.next;
	END;
	WHILE (modules.name#"Objects") DO
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
		IF (m.addr <= pc) & (pc < m.addr + m.size+3) THEN RETURN m
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

(* FindProc - Find a procedure in the reference block.  Return index of name, or -1 if not found. *)

PROCEDURE FindProc*(refs: Bytes;  ofs: LONGINT): LONGINT;
VAR i, m, t, proc: LONGINT;  ch: CHAR;
BEGIN
	proc := -1;  i := 0;  m := LEN(refs^);
	ch := refs[i];  INC(i);
	WHILE (i < m) & ((ch = 0F8X) OR (ch = 0F9X)) DO	(* proc *)
		GetNum(refs, i, t);	(* pofs *)
		IF t > ofs THEN	(* previous procedure was the one *)
			ch := 0X	(* stop search *)
		ELSE	(* ~found *)
			IF ch = 0F9X THEN
				GetNum(refs, i, t);	(* nofPars *)
				INC(i, 3)	(* RetType, procLev, slFlag *)
			END;
			proc := i;	(* remember this position, just before the name *)
			REPEAT ch := refs[i];  INC(i) UNTIL ch = 0X;	(* pname *)
			IF i < m THEN
				ch := refs[i];  INC(i);	(* 1X | 3X | 0F8X | 0F9X *)
				WHILE (i < m) & (ch >= 1X) & (ch <= 3X) DO	(* var *)
					ch := refs[i];  INC(i);	(* type *)
					IF (ch >= 81X) OR (ch = 16X) OR (ch = 1DX) THEN
						GetNum(refs, i, t)	(* dim/tdadr *)
					END;
					GetNum(refs, i, t);	(* vofs *)
					REPEAT ch := refs[i];  INC(i) UNTIL ch = 0X;	(* vname *)
					IF i < m THEN ch := refs[i];  INC(i) END	(* 1X | 3X | 0F8X | 0F9X *)
				END
			END;
		END;
	END;
	IF (proc = -1) & (i # 0) THEN proc := i END;	(* first procedure *)
	RETURN proc
END FindProc;

PROCEDURE GetFrame*( VAR fp, pc: LONGINT);
BEGIN
	SYSTEM.GET(fp+4, pc);
	SYSTEM.GET(fp, fp);
END GetFrame;

(* DefaultTrapHandler - This handler is installed if nothing better is available... *)
PROCEDURE DefaultTrapHandler(error, fp, pc, page: LONGINT);
VAR x : LONGINT;  m: Module; 
BEGIN
(*
	WriteString("Processor State:"); WriteLn;
	WriteString("R0  ="); WriteHex(state.r0,9); WriteString("H  R1  ="); WriteHex(state.r1,9); 
	WriteString("H  R2  ="); WriteHex(state.r2,9); WriteString("H  R3  ="); WriteHex(state.r2,9); WriteChar("H"); WriteLn;
	WriteString("R4  ="); WriteHex(state.r4,9); WriteString("H  R5  ="); WriteHex(state.r5,9); 
	WriteString("H  R6  ="); WriteHex(state.r6,9); WriteString("H  R7  ="); WriteHex(state.r7,9); WriteChar("H"); WriteLn;
	WriteString("R8  ="); WriteHex(state.r8,9); WriteString("H  R9  ="); WriteHex(state.r9,9); 
	WriteString("H  RA ="); WriteHex(state.ra,9); WriteString("H  RB ="); WriteHex(state.rb,9); WriteChar("H"); WriteLn;
	WriteString("FP  ="); WriteHex(state.fp,9); WriteString("H  SP  ="); WriteHex(state.sp,9); WriteString("H  LR  ="); WriteHex(state.lr,9);
	WriteString("H  CPSR="); WriteHex(state.cpsr,9); WriteChar("H");
	WriteLn;
*)
	m:=GetMod(pc);
	WriteString("DefaultTrapHandler: Received signal nr. "); WriteInt( error, 1);
	WriteString(" in "); IF m=NIL THEN WriteString("unknown module") ELSE WriteString(m.name) END;
	WriteString(" PC="); WriteHex(pc,8); WriteString("H");
	IF m#NIL THEN WriteString(" ("); WriteHex(pc-m.sb,8); WriteString("H)"); END;
	IF error=-2 THEN WriteString("  Fault Address="); WriteHex(page,8); WriteString("H"); END;
	WriteLn;
(*
	(* procedures *)
	x := 10; 
	pc:= state.pc; fp:= state.fp;
	LOOP
		m := GetMod(pc);
		IF m = NIL THEN 
			WriteString("Unknown module");  WriteLn;
			IF x#10 THEN EXIT END;
		ELSE
			WriteString(m.name);  WriteString("  PC = ");
			WriteHex(pc-m.addr, 1);  WriteLn;
		END;
        SYSTEM.GET(fp+4, pc); SYSTEM.GET(fp, fp); (* return addr from stack *)
		IF fp >= StackOrg THEN EXIT END;
		DEC(x);  IF x = 0 THEN EXIT END;
	END;
*)
END DefaultTrapHandler;

(* ExceptionHandler - Exception dispatcher *)
(* OLR *)
PROCEDURE SignalHandler;
VAR trap, fp: LONGINT; state: SigCPTR;
BEGIN
	SYSTEM.GETREG( Linux0.FP, fp);	(* EBP *)
	SYSTEM.GETREG( 0, trap);	(* EBP *)
	INC( siglevel);
(*
trap:=0;
REPEAT
	state:= SYSTEM.VAL( SigCPTR, fp+trap);
	INC(trap, 4);
UNTIL (state.r0=1236H) OR (trap>1000H);
WriteString(">>>>> i= "); WriteInt(i-4, 8); WriteLn;
*)
	state:= SYSTEM.VAL( SigCPTR, fp+28); (* 28 with "VAR trap, fp: LONGINT; state: SigCPTR;" *)

	CASE trap OF
		Linux0.SIGILL: SYSTEM.GET(state.pc, fp); 
				IF fp DIV 100H MOD 100000H= iinst DIV 100H THEN trap:=fp MOD 100H; IF trap=255 THEN trap:=MAX(INTEGER) END; END;
		| Linux0.SIGINT: trap:=13;	(* ctrl-c from terminal *)
			IF Linux0.inGC THEN Linux0.break:= TRUE; DEC( siglevel); RETURN END;
		|Linux0.SIGFPE: trap:= 7;
	ELSE
	END;

	(* call handler *)

	WriteString("Received signal no. "); WriteInt( trap, 3); WriteString(" at signal handling level"); WriteInt( siglevel, 2); WriteLn;
	IF Linux0.inGC & ~Linux0.break THEN
		DefaultTrapHandler( trap, state.fp, state.pc, state^.faultAddr);
		Halt("Trap in GC", state^.errCode);
	END;
	IF siglevel >1 THEN
		IF siglevel >2 THEN Halt("Recursive trap", siglevel) END;
		WriteString("Error: Signal while handling Signal"); WriteLn;
	END;
	IF (handler= NIL) OR (showState IN traceheap)  THEN DefaultTrapHandler( trap, state.fp, state.pc, state^.faultAddr) END;
	IF (handler # NIL) THEN handler( trap, state.fp, state^.pc, state^.faultAddr ) END;	(* was: handler |trap 16: Disk full *)
	DEC( siglevel);
	IF loop=NIL THEN Shutdown( 1) END;
	state.sp:= Linux0.StackOrg;
	state.fp:= Linux0.StackOrg;
	state.pc:= SYSTEM.VAL( LONGINT, loop);
END SignalHandler;

PROCEDURE QuitSignalHandler( );
VAR nr: LONGINT;
BEGIN
	SYSTEM.GETREG( 0, nr);	(* sig is parameter of handler *)
	INC( siglevel);
	WriteString("Recived signal nr. "); WriteInt( nr, 3); WriteLn;
	WriteString("Terminating Oberon! "); WriteLn;
	Shutdown( 0);
END QuitSignalHandler;

(** InstallTrap - Install the trap handler *)

PROCEDURE InstallTrap*(p: TrapHandler);
BEGIN	IF p# NIL THEN handler := p END;
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
	WHILE i <= N DO
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
	i := N; max := 0;
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

PROCEDURE Mark (block: BlockPtr);
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
				END
			END
		END
	ELSE (* do not mark subobject, subobjects are not traced *)
			(* remove array bit because of array subobjects in module block *)
		SYSTEM.GET(SYSTEM.VAL(ADDRESS, SYSTEM.VAL(SET, tag) - array)-4, tag);
		EXCL(SYSTEM.VAL(SET, tag), MarkBit);
		SYSTEM.GET(SYSTEM.VAL(ADDRESS, tag)-4, arraybit);
		INCL(arraybit, MarkBit);
		SYSTEM.PUT(SYSTEM.VAL(ADDRESS, tag)-4, arraybit)
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
		lastA: ARRAY N+1 OF ADDRESS;
		t: LONGINT;  live, dead, lsize, ssize: LONGINT;
BEGIN
	i := 0;
	WHILE i <= N DO FA[i] := nil; lastA[i] := SYSTEM.ADR(FA[i]); INC(i) END;
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
				IF i > N THEN i := N END;
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
		IF i > N THEN i := N END;
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

(** GC - Immediately activate the garbage collector. *)

PROCEDURE ^NewSys(VAR p: ADDRESS; size: LONGINT);
PROCEDURE ^GetTimer*():LONGINT;

PROCEDURE GC*;
	VAR m: Module; i, p, sp, ptradr: LONGINT; ptr: BlockPtr;  avail, largest, t0, tf0, tf1, st: LONGINT;
BEGIN
	Linux0.inGC := TRUE;
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
			SYSTEM.GETREG( 13, sp);	(* was SYSTEM.ESP *)
			ASSERT(sp <= Linux0.StackOrg);

			nofcand := 0;
			WHILE sp < Linux0.StackOrg DO
				SYSTEM.GET(sp, p); Candidate(p); INC(sp, 4)
			END;
			IF nofcand > 0 THEN CheckCandidates END
		END;
		CheckFinObjs;
		Sweep;
		IF (reserve = NIL) & firstTry THEN
			IF LargestAvailable() >= ReserveSize THEN NewSys(p, ReserveSize); reserve := SYSTEM.VAL(BlockPtr, p) END
		END;
		IF 7 IN traceheap THEN
			t0 := SYSTEM.ADR(FA[N]);  WriteString("[FP");
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
				WriteHex(avail, 1);  WriteString(" +");  WriteInt(largest, 1)
			END;
			WriteChar(" ");  WriteHex(st, 1);  WriteString("ms");
			WriteString(" CG)"); WriteLn;
		END;
	END;
	Linux0.inGC := FALSE;
	IF Linux0.break THEN
		Linux0.break := FALSE;
		SYSTEM.HALT(13)	(* Keyboard interrupt *)
	END;
END GC;

PROCEDURE NewBlock (size: LONGINT): InitPtr;	(* size MOD B = 0 *)
	VAR i, rest: LONGINT; adr, AN: ADDRESS; ptr: InitPtr; restptr: FreeBlockPtr;
BEGIN
	IF Linux0.break THEN Linux0.break := FALSE; SYSTEM.HALT(13) END;
	IF size < 0 (* NEW(p, MAX(LONGINT)) *) THEN SYSTEM.HALT(14) END;
	i := size DIV B;
	IF i > N THEN i := N END;
	adr := SYSTEM.ADR(FA[0]) + 4*i;
	AN := SYSTEM.ADR(FA[N]);	(* constant register *)
	LOOP
		SYSTEM.GET(adr, ptr);
		IF adr = AN THEN
			LOOP
				IF ptr = NIL THEN
					IF (* (TrapHandlingLevel = 0) & *) firstTry THEN GC;
						firstTry := FALSE; ptr := NewBlock(size); firstTry := TRUE;
						RETURN ptr
					ELSE  reserve := NIL; CheckHeap("out of mem"); GC; firstTry := TRUE; SYSTEM.HALT(14)
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
		IF i > N THEN i := N END;
		restptr^.tag := SYSTEM.VAL(Tag, SYSTEM.VAL(SET, SYSTEM.ADR(restptr^.size)) + free);
		restptr^.size := rest - 4;
		restptr^.next := FA[i]; FA[i] := SYSTEM.VAL(ADDRESS, restptr)
	END;
	RETURN ptr
END NewBlock;

(* NewRec - Implementation of NEW.  Do not call directly. *)

PROCEDURE NewRec(VAR p: ADDRESS; tag: Tag);	(* implementation of NEW(ptr) *)
	VAR size: LONGINT; ptr, init: InitPtr; 
BEGIN (* tag^.size = rectyp^.size *)
	IF 0 IN traceheap THEN
		WriteString("[NR ");  WriteType(SYSTEM.VAL(LONGINT, tag));
	END;
	ASSERT(SYSTEM.VAL(LONGINT, tag) MOD 8 = 0);	(* no Oberon-X flags allowed *)
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
		WriteHex(SYSTEM.VAL(LONGINT, p), 9);  WriteString("] ")
	END
END NewRec;

(* NewSys - Implementation of SYSTEM.NEW.  Do not call directly. *)

PROCEDURE NewSys(VAR p: ADDRESS; size: LONGINT);
VAR ptr, init: InitPtr;  bp: LONGINT;
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
	(*init^.z3 := 0;*)
	SYSTEM.GETREG( 12, bp);	(* was SYSTEM.EBP *)
	SYSTEM.GET(bp+4, init^.z3);	(* PC where NewSys has been called. Used for debugging *)
	init^.z4 := 0;	(* bit 1 must be 0 to distinguish from array SysBlk *)
	ptr^.z5 := SYSTEM.ADR(ptr^.z0);
	init^.z6 := 0;	(* WHY THAT? z6 IS FIRST DATA WORD! *)
	p := SYSTEM.VAL(ADDRESS, ptr) + 28;
	IF 2 IN traceheap THEN
		WriteHex(SYSTEM.VAL(LONGINT, p), 9);  WriteString("] ")
	END
END NewSys;

(* NewArr - Implementation of NEW.  Do not call directly. *)

PROCEDURE NewArr(VAR p: ADDRESS; eltag: Tag; nofelem, nofdim: LONGINT);
VAR size, firstElem, elSize, arrSize, vectSize: LONGINT; ptr, init: InitPtr; 
BEGIN
	IF 1 IN traceheap THEN
		WriteString("[NA ");  WriteInt(nofelem, 1);  WriteChar(" ");  WriteInt(nofdim, 1)
	END;
	ASSERT(SYSTEM.VAL(LONGINT, eltag) MOD 8 IN {0,2});	(* test Oberon-X flags *)
	IF eltag = NIL THEN
		eltag := SYSTEM.VAL(Tag, ptrElemTag)	(* array of pointer to *)
	END;
	elSize := eltag^.size;
	arrSize := nofelem*elSize;
	IF arrSize = 0 THEN
		(* we need a SysBlk that looks like an ArrBlk to the compiler! *)
		NewSys(p,size+4*nofdim+12);
		ptr:=SYSTEM.VAL(InitPtr,p-4);
		ptr.z0:=0; (* no lastElemToMark *)
		ptr.z1:=0; (* reserved *)
		ptr.z2:=p+4*nofdim+12; (* firstElem *)
		RETURN
	END;
	ASSERT(arrSize > 0); 
	vectSize := 4*nofdim+ 4;	(* -> ADR(firstElem) MOD 4 = 0 *)
	ASSERT(eltag^.ptroff#-4);  
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
	IF 1 IN traceheap THEN
		WriteHex(SYSTEM.VAL(LONGINT, p), 9);  WriteString("] ")
	END
END NewArr;
(*
PROCEDURE SysHalt( );	(* trap no. in R7 *)
VAR pc, fp, trap: LONGINT;
BEGIN
	SYSTEM.GETREG(PC, pc);
	SYSTEM.GETREG(Linux0.FP, fp);
	SYSTEM.GETREG(7, trap);
	IF trap=0FF00H THEN trap:=MAX(INTEGER) END;
	WriteString("SysHalt Trap nr. "); WriteInt( trap, 3); WriteLn;
	DefaultTrapHandler( trap, fp, pc, 0);
	handler( trap, fp, pc, 0);
	IF trap#MAX(INTEGER) THEN
		SYSTEM.PUTREG(Linux0.SP, Linux0.StackOrg);	(* callers FP *)
		SYSTEM.PUTREG(Linux0.FP, Linux0.StackOrg);	(* callers FP *)
		loop;
	END;
END SysHalt;
*)
PROCEDURE DivModH;
CODE	(* R0 = R1 DIV R0; R1 = R1 MOD R0 *)
	STMFD	SP!,{R10, R11}	(* all regs might be in use! *)
	CMP	R0, 1
	DCD	3C1F070AH	(* CC iinst; illigal instruction for trap if R0=0*) 
	MOV	R10, R0
	MOV	R11, R1
	SDIV	R0, R1, R10
	MUL	R1, R0, R10
	SUBS	R1, R11, R1
(* buggy ir r0 and r1 <0 
	ADDLT	R1,R1,R10
	SUBLT	R0,R0,1
*)
	BGE	end
	CMP	R10, 0
	ADDGE	R1, R1, R10
	SUBGE	R0, R0, 1
	SUBLT	R1, R1, R10
	ADDLT	R0, R0, 1
end
	LDMFD	SP!,{R10, R11}
	MOV	PC, LR
END DivModH;

PROCEDURE DivMod;
(* This routine has been taken from NetBSD 1.3.3 and is *VERY* slightly modified *)
CODE	(* R0 = R1 DIV R0; R1 = R1 MOD R0 *)
	STMFD	SP!,{FP,LR}
	MOV	FP,SP
	CMP	R0, 1
(*	SWICC	10 (* Div by zero *)*)
(*	MOVCC	R7, 10 *)
(*	BLCC	SysHalt *)
	DCD	3C1F070AH	(* CC iinst; illigal instruction for trap if R0=0*) 

	BNE	CONT
	MOV	R0, R1
	MOV	R1, 0
	MOV	SP, FP
	LDMFD	SP!,{FP,PC}
CONT	
	STMFD	SP!,{R2,R3,R4,R5}
	MOV	R5, R0
	ANDS	R4, R0, 80000000H	
	RSBMI	R0, R0, 0	
	ANDS	R2, R1, 80000000H	
	EOR	R4, R4, R2
	RSBMI	R1, R1, 0	
	ORR	R4, R2, R4, LSR 1	(* R4 BIT 0X40000000 = -VE DIVISION     R4 BIT 0X80000000 = -VE REMAINDER *)
LDIVIDEL1	MOV	R2, 1	MOV	R3, 0	CMP	R1, R0	BCC	LDIVIDEB0	CMP	R1, R0, LSL 1	BCC	LDIVIDEB1
	CMP	R1, R0, LSL 2	BCC	LDIVIDEB2	CMP	R1, R0, LSL 3	BCC	LDIVIDEB3	CMP	R1, R0, LSL 4	BCC	LDIVIDEB4
	CMP	R1, R0, LSL 5	BCC	LDIVIDEB5	CMP	R1, R0, LSL 6	BCC	LDIVIDEB6	CMP	R1, R0, LSL 7	BCC	LDIVIDEB7
	CMP	R1, R0, LSL 8	BCC	LDIVIDEB8	CMP	R1, R0, LSL 9	BCC	LDIVIDEB9	CMP	R1, R0, LSL 10	BCC	LDIVIDEB10
	CMP	R1, R0, LSL 11	BCC	LDIVIDEB11	CMP	R1, R0, LSL 12	BCC	LDIVIDEB12	CMP	R1, R0, LSL 13	BCC	LDIVIDEB13
	CMP	R1, R0, LSL 14	BCC	LDIVIDEB14	CMP	R1, R0, LSL 15	BCC	LDIVIDEB15	CMP	R1, R0, LSL 16	BCC	LDIVIDEB16
	CMP	R1, R0, LSL 17	BCC	LDIVIDEB17	CMP	R1, R0, LSL 18	BCC	LDIVIDEB18	CMP	R1, R0, LSL 19	BCC	LDIVIDEB19
	CMP	R1, R0, LSL 20	BCC	LDIVIDEB20	CMP	R1, R0, LSL 21	BCC	LDIVIDEB21	CMP	R1, R0, LSL 22	BCC	LDIVIDEB22
	CMP	R1, R0, LSL 23	BCC	LDIVIDEB23	CMP	R1, R0, LSL 24	BCC	LDIVIDEB24	CMP	R1, R0, LSL 25	BCC	LDIVIDEB25
	CMP	R1, R0, LSL 26	BCC	LDIVIDEB26	CMP	R1, R0, LSL 27	BCC	LDIVIDEB27	CMP	R1, R0, LSL 28	BCC	LDIVIDEB28
	CMP	R1, R0, LSL 29	BCC	LDIVIDEB29	CMP	R1, R0, LSL 30	BCC	LDIVIDEB30	CMP	R1, R0, LSL 31	SUBCS	R1, R1,R0, LSL 31
	ADDCS	R3, R3,R2, LSL 31	CMP	R1, R0, LSL 30	SUBCS	R1, R1,R0, LSL 30	ADDCS	R3, R3,R2, LSL 30LDIVIDEB30
	CMP	R1, R0, LSL 29	SUBCS	R1, R1,R0, LSL 29	ADDCS	R3, R3,R2, LSL 29
LDIVIDEB29	CMP	R1, R0, LSL 28	SUBCS	R1, R1,R0, LSL 28	ADDCS	R3, R3,R2, LSL 28
LDIVIDEB28	CMP	R1, R0, LSL 27	SUBCS	R1, R1,R0, LSL 27	ADDCS	R3, R3,R2, LSL 27
LDIVIDEB27	CMP	R1, R0, LSL 26	SUBCS	R1, R1,R0, LSL 26	ADDCS	R3, R3,R2, LSL 26
LDIVIDEB26	CMP	R1, R0, LSL 25	SUBCS	R1, R1,R0, LSL 25	ADDCS	R3, R3,R2, LSL 25
LDIVIDEB25	CMP	R1, R0, LSL 24	SUBCS	R1, R1,R0, LSL 24	ADDCS	R3, R3,R2, LSL 24
LDIVIDEB24	CMP	R1, R0, LSL 23	SUBCS	R1, R1,R0, LSL 23	ADDCS	R3, R3,R2, LSL 23
LDIVIDEB23	CMP	R1, R0, LSL 22	SUBCS	R1, R1,R0, LSL 22	ADDCS	R3, R3,R2, LSL 22
LDIVIDEB22	CMP	R1, R0, LSL 21	SUBCS	R1, R1,R0, LSL 21	ADDCS	R3, R3,R2, LSL 21
LDIVIDEB21	CMP	R1, R0, LSL 20	SUBCS	R1, R1,R0, LSL 20	ADDCS	R3, R3,R2, LSL 20
LDIVIDEB20	CMP	R1, R0, LSL 19	SUBCS	R1, R1,R0, LSL 19	ADDCS	R3, R3,R2, LSL 19
LDIVIDEB19	CMP	R1, R0, LSL 18	SUBCS	R1, R1,R0, LSL 18	ADDCS	R3, R3,R2, LSL 18
LDIVIDEB18	CMP	R1, R0, LSL 17	SUBCS	R1, R1,R0, LSL 17	ADDCS	R3, R3,R2, LSL 17
LDIVIDEB17	CMP	R1, R0, LSL 16	SUBCS	R1, R1,R0, LSL 16	ADDCS	R3, R3,R2, LSL 16
LDIVIDEB16	CMP	R1, R0, LSL 15	SUBCS	R1, R1,R0, LSL 15	ADDCS	R3, R3,R2, LSL 15
LDIVIDEB15	CMP	R1, R0, LSL 14	SUBCS	R1, R1,R0, LSL 14	ADDCS	R3, R3,R2, LSL 14
LDIVIDEB14	CMP	R1, R0, LSL 13	SUBCS	R1, R1,R0, LSL 13	ADDCS	R3, R3,R2, LSL 13
LDIVIDEB13	CMP	R1, R0, LSL 12	SUBCS	R1, R1,R0, LSL 12	ADDCS	R3, R3,R2, LSL 12
LDIVIDEB12	CMP	R1, R0, LSL 11	SUBCS	R1, R1,R0, LSL 11	ADDCS	R3, R3,R2, LSL 11
LDIVIDEB11	CMP	R1, R0, LSL 10	SUBCS	R1, R1,R0, LSL 10	ADDCS	R3, R3,R2, LSL 10
LDIVIDEB10	CMP	R1, R0, LSL 9	SUBCS	R1, R1,R0, LSL 9	ADDCS	R3, R3,R2, LSL 9
LDIVIDEB9	CMP	R1, R0, LSL 8	SUBCS	R1, R1,R0, LSL 8	ADDCS	R3, R3,R2, LSL 8
LDIVIDEB8	CMP	R1, R0, LSL 7	SUBCS	R1, R1,R0, LSL 7	ADDCS	R3, R3,R2, LSL 7
LDIVIDEB7	CMP	R1, R0, LSL 6	SUBCS	R1, R1,R0, LSL 6	ADDCS	R3, R3,R2, LSL 6
LDIVIDEB6	CMP	R1, R0, LSL 5	SUBCS	R1, R1,R0, LSL 5	ADDCS	R3, R3,R2, LSL 5
LDIVIDEB5	CMP	R1, R0, LSL 4	SUBCS	R1, R1,R0, LSL 4	ADDCS	R3, R3,R2, LSL 4
LDIVIDEB4	CMP	R1, R0, LSL 3	SUBCS	R1, R1,R0, LSL 3	ADDCS	R3, R3,R2, LSL 3
LDIVIDEB3	CMP	R1, R0, LSL 2	SUBCS	R1, R1,R0, LSL 2	ADDCS	R3, R3,R2, LSL 2
LDIVIDEB2	CMP	R1, R0, LSL 1	SUBCS	R1, R1,R0, LSL 1	ADDCS	R3, R3,R2, LSL 1
LDIVIDEB1	CMP	R1, R0	SUBCS	R1, R1, R0	ADDCS	R3, R3, R2
LDIVIDEB0	
	TST	R4, 20000000H	
	BNE	LUDIVIDEL1	
	MOV	R0, R3	
	CMP	R4, 0	
	RSBMI	R1, R1, 0	
	MOVS	R4, R4, LSL 1
	BICMI	R0, R0, 80000000H	(* FIX INCASE WE DIVIDED 0X80000000 *)
	RSBMI	R0, R0, 0
	B	GOBACK
LUDIVIDEL1
	TST	R4, 10000000H	
	MOV	R1, R1, LSL 1	
	ORRNE	R1, R1, 1	
	MOV	R3, R3, LSL 1
	CMP	R1, R0	
	SUBCS	R1, R1, R0	
	ADDCS	R3, R3, R2	
	MOV	R0, R3	
GOBACK
	(* Oberons idea of DIV and MOD is more mathematical than C's one -> do adjusments *)
(*	CMP	R1, 0 wrong code
	ADDLT	R1,R1,R5
	BGE	OK
	CMP	R0,0
	SUBLE	R0,R0,1
*)	(* bug compatible with x86 version: 
	CMP	R1, 0
	ADDLT	R1,R1,R5
	SUBLT	R0,R0,1*)
	CMP	R1, 0
	BGE	OK
	CMP	R5, 0
	ADDGE	R1, R1, R5
	SUBGE	R0, R0, 1
	SUBLT	R1, R1, R5
	ADDLT	R0, R0, 1
OK
	LDMFD	SP!,{R2,R3,R4,R5}
	MOV	SP, FP
	LDMFD	SP!,{FP,PC}
END DivMod;

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
	m := modules; handlerAdr := SYSTEM.VAL(LONGINT, h); found := FALSE;
	WHILE (m # NIL) & ~found DO
		IF (SYSTEM.VAL(LONGINT,m.addr) <= handlerAdr) & (handlerAdr <  SYSTEM.VAL(LONGINT,m.addr)+m.size) THEN found := TRUE
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
	WriteString("Kernel.FinalizeModule not yet tested!"); WriteLn;

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
END FinalizeModule;

(** -- Clock/Timer -- *)

PROCEDURE U2OTime*( VAR clock, date, time: LONGINT);	(* convert Unix time to Oberon *)
VAR d, s, h, y, mi, mo, dij: LONGINT;
BEGIN
		s:= clock MOD 60; clock:= clock DIV 60;
		mi:= clock MOD 60; clock:= clock DIV 60;
		INC( clock, TimeAdjust);
		h:= (clock) MOD 24; clock:= (clock) DIV 24;
		time:=ASH( ASH(h,6)+mi,6)+s;
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

PROCEDURE GetTimer*(): LONGINT;
VAR i: LONGINT; j: Timeval;
BEGIN
	i:=Linux0.GetTimeOfDay(SYSTEM.ADR(j), 0);
	RETURN (j.sec-startTime.sec)*1000 +(j.usec -startTime.usec) DIV 1000;
END GetTimer;

(** -- Miscellaneous -- *)
(*
PROCEDURE Cap(ch: CHAR): CHAR;
BEGIN
	IF (ch >= "a") & (ch <= "z") THEN RETURN CAP(ch)
	ELSE RETURN ch
	END
END Cap;
*)
(** GetConfig - Return value of configuration string.  Returns empty val if name not found. *)

PROCEDURE GetConfig*(env: ARRAY OF CHAR; VAR val: ARRAY OF CHAR);
VAR i, j, n: LONGINT; ch: CHAR;
BEGIN	(* stack layout at http://asm.sourceforge.net/articles/startup.html *)
	WriteString(env); WriteChar("=");
	SYSTEM.GET(Linux0.StackOrg, n);
	i:=8+4*n;
	SYSTEM.GET(Linux0.StackOrg+i, n);
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
		INC(i, 4);
		SYSTEM.GET(Linux0.StackOrg+i, n);
	END;
	WriteString(" not found"); WriteLn;
	val[0]:=0X;
END GetConfig;

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
	size:= ASH(ASH(size+0FFFFH, -16), 16);
	high0:=endBlock+4;
	high1:=high0+size;
	first:=firstBlock=endBlock+B;
	endBlock:=Linux0.Brk0(high1);
	i:=Linux0.MProtect0( high0, size, 7);
	IF traceheap # {} THEN
		WriteString("Heap growing: "); WriteHex(high0, 9);  WriteHex(high1, 9); WriteLn
	END;
	IF endBlock#high1 THEN Halt("Error: No new Heap abvailable.", 1) END;
	DEC(endBlock, 4);
	i:=high0;
	REPEAT
		SYSTEM.PUT( i, SYSTEM.VAL(LONGINT, 0)); INC (i, 4);
	UNTIL i>=high0+size;
	DEC(high0, 4);
	IF first THEN INC(high0,B) END;
	f:=SYSTEM.VAL(FreeBlockPtr, high0);
	f^.tag := SYSTEM.VAL(Tag, SYSTEM.VAL(SET, SYSTEM.ADR(f^.size)) + free);
	f^.size := high1-high0-B-4; f^.next := 0;
		(* init free list & reserve *)
(*
CheckHeap(" Checking Heap: ");
*)	
	GClevel := 1;  GCstack := TRUE;
	GC;
	GClevel := 0;  GCstack := TRUE;
END GrowHeap;

PROCEDURE InitHeap;	(* memTop and modules already initialized *)
VAR
	c: CHAR;
	i, t: LONGINT;
	m: Module;
	td: POINTER TO RECORD filler: ARRAY 4 OF LONGINT; name: Name END;
	str: ARRAY 32 OF CHAR;
BEGIN
	Linux0.inGC := FALSE;  Linux0.break := FALSE;  FinObjs := NIL;

		(* show statically linked modules *)
	m := modules;
	IF m = NIL THEN Halt("Modlist", 1) END;	(* modules list not there! *)
	WHILE m # NIL DO
		WriteHex( m.sb, 8);  WriteHex( m.size, 9); WriteChar(" "); WriteString(m.name);  WriteLn;
		m := m.next
	END;
	m := modules;  WHILE m.name # "Kernel" DO m := m.next END;
	i := LEN(m.tdescs^);  ptrElemTag := 0;
	REPEAT
		DEC(i);  t := m.tdescs[i];  SYSTEM.GET(t - 4, td);
		IF td.name = "PtrElemDesc" THEN ptrElemTag := t END
	UNTIL (ptrElemTag # 0);
	dynModBase:= Linux0.Brk0(0);
		(* init heap *)
	endBlock:=Linux0.Brk0(dynModBase+800000H) -4;
	i:=Linux0.MProtect0( dynModBase, 800000H, 7);
	firstBlock:=endBlock+B;
	reserve := NIL;  firstTry := TRUE;
	GrowHeap(1000000H);
	EnableGC := DefaultEnableGC;  DisableGC := DefaultDisableGC;
END InitHeap;

(* ------------------------------------------------------------------------------------------------*)
(* InitRuntime - Initialise runtime support. *)

PROCEDURE InitRuntime;
VAR s: ARRAY 32 OF CHAR;
BEGIN
	runtime[0] := SYSTEM.ADR( NewRec);	(* 253 *)
	runtime[1] := SYSTEM.ADR( NewSys);	(* 252 *)
	runtime[2] := SYSTEM.ADR( NewArr);	(* 251 *)
	GetConfig("OIDIV", s);
	IF s="" THEN runtime[3] := SYSTEM.ADR( DivMod);
	ELSE runtime[3] := SYSTEM.ADR( DivModH);
	END;
(*	runtime[4] := SYSTEM.ADR( SysHalt);*)
END InitRuntime;

(* LNO *)
PROCEDURE InitTrapHandling;
VAR i, err: LONGINT;
BEGIN
	FOR i:=1 TO 31 DO
		IF i IN Linux0.TRAPSigs THEN err:= Linux0.SetSignal( i, SignalHandler);
		ELSIF i IN Linux0.QUITSigs THEN err:= Linux0.SetSignal( i, QuitSignalHandler);
		ELSIF i IN Linux0.IGNSigs THEN err:= Linux0.SetSignal( i, SYSTEM.VAL( Linux0.SigHandler, 1));
		END;
	END;
END InitTrapHandling;

PROCEDURE Init;
VAR	val: ARRAY 8 OF CHAR; i: LONGINT;
BEGIN
	i:=Linux0.GetTimeOfDay(SYSTEM.ADR(startTime), 0);
	siglevel:=0;
	tracefd:= Linux0.Creat0(SYSTEM.ADR(TRACE), SYSTEM.VAL(LONGINT, {2, 5, 7, 8}));
	WriteString( version); WriteString( Linux0.ARCH); WriteString( DATE);WriteLn;
	IF traceheap # {} THEN
		WriteString("StackOrg"); WriteHex(Linux0.StackOrg, 10);  WriteLn;
	END;
	InitRuntime;
	InitHeap;
	InitTrapHandling;
END Init;

PROCEDURE GetArg*(n: LONGINT; VAR s: ARRAY OF CHAR);
VAR l, m: LONGINT; c: CHAR;
BEGIN
	IF (n>=0) & (n<NoOfArgs) THEN
		SYSTEM.GET(Linux0.StackOrg+4+n*4, l);
		m:=0;
		REPEAT
			SYSTEM.GET( l, c);
			s[m]:=c;
			INC(l);
			INC(m);
		UNTIL c=0X;
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

BEGIN
	SYSTEM.GETREG( 12, Linux0.StackOrg);	(* user stack org FP+8 = NofCmds*)
	INC(Linux0.StackOrg, 8);
	SYSTEM.PUT(Linux0.StackOrg-8, Linux0.StackOrg);	(* callers FP *)
	SYSTEM.GET(Linux0.StackOrg, NoOfArgs);
	Static:=TRUE;	(* Modules sets Static to FALSE *)
	Init;
	Idle:= Idle0;
	GetConfig("OTRACE", trace);
	CmdLine;
	handler:=DefaultTrapHandler;
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
