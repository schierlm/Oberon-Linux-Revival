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
	15.05.98	p.matthias:	started LNO Version
	28.10.98	p.m.:	fixed GetTime
	19.12.98	p.m.:	tried to add heap growing; not possible because of X11 framebuffer!
	09.04.99	p.m.:	moved to 2.3.4b
	01.09.99	p.m.:	moved to 2.3.6
	10.06.00	p.m.:	added KernelLog, removed siglongjmp ( SignalHandler now left normally),
								 removed Oberon-X support ( is now somwhere else)
	14.06.00	p.m.:	programmed GetTimer in assembler; made SysCall1 inline
	30.09.00	p.m.:	RegisterObject checks whether obj is NIL
	25.12.01	p.m.:	moved to ElfLinker
	12.01.02	p.m.:	made HeapSize configurable in oberon.cnf
	2010-02-27	p.m.:	adapted for heap randomization, prepared for heap growing
	2010-02-28	p.m.:	added dynamic heap growing, misused Shutdown for GrowHeap
	2010-03-11	p.m.:	added CmdLine, made first argument DDriver parameter
	2015-02-07	OLR version started
	2015-02-08	interface changes
	2015-02-09	changed IPC
	2015-02-10	added IOCtl0 (for Framebuffer)
	2015-03-02	implemented GetEnv from /proc/self/environ, exported SigUsr1, SigUsr2
	2015-03-18	fixed overflow in WriteString
	2015-03-26	implemeted ReadV0, Writev0
	2015-04-13	renamed GetEnv to GetConfig
	2015-04-25	removed TraceLog
	2015-05-06	removed SigUsr, SigReturn; SigReturn must not have parameters
	2015-06-13	made GetConfig using stack
	2015-07-18	exported NoOfArgs, GetArg, Static
	2015-10-14	changed trap No. for SIGFPE to 10
	2015-12-11	split OLR.X86.Kernel.Mod to OLR.X86.Linux0.Mod and OLR.X86.Kernel.Mod
	2016-08-26	fixed GetConfig

ToDo: cleanup SignalHandler

	SetClock not implemented ( only superuser can change time)
	reboot does not work
	
*)

IMPORT Linux0, SYSTEM;

CONST
	version*="ETH Oberon / Linux ";
	DATE*=" 2015-12-11";
	TRACE= "Kernel.Log";
	RegSize*=Linux0.RegSize;

		(* heap/GC *)
	B = 32;	(* heap block size, must be a multiple of 32 *)
	N = 9;	(* number of free lists - 1 *)
	nil = 0;
	MarkBit = 0; ArrayBit = 1;  FreeBit = 2;  SubObjBit = 3; 
	mark = {MarkBit}; array = {ArrayBit};  free = {FreeBit};  subobj = {SubObjBit};
	ReserveSize = 65536-8;	(* bytes reserved for "Out of memory" trap handling *)


		(* timer *)
	TimeUnit* = 1000;	(* timer ticks per second, returned by GetTimer *)
	
	NEWrecord= 0; NEWarray= 1; SYSTEMNEW= 2;
	dealloRECORD= 3; deallocARRAY= 4; deallocSYSBLK= 5;
	finalisation= 6; freePages= 7; showFreeBlocks= 8;
	newDMA= 9; memory= 10; livedead= 11; getConfig=12; showState= 13;
	traceheap=  {31, getConfig, showState}; (* {31, getConfig, showState};*)
	
	TimeAdjust=1;

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
	ExportPtr* = POINTER TO ExportDesc;
	ExportDesc* = RECORD
		fp*: LONGINT; adr*: LONGINT;
		nofExp*: INTEGER; 
		dsc*: POINTER TO ARRAY OF ExportDesc
	END;
	ArrayPtr* = POINTER TO ARRAY OF LONGINT;
	ModuleDesc* = RECORD	(* Note: if this is changed, also update the static Linker *)
		next*: Module;
		name*: Name;
		init*, trapped*: BOOLEAN;
		refcnt*, sb*: LONGINT;
		entries*: POINTER TO ARRAY OF ADDRESS;
		cmds*: POINTER TO ARRAY OF Cmd;
		ptrTab*, tdescs*: POINTER TO ARRAY OF ADDRESS;
		imports*: POINTER TO ARRAY OF Module;
		data*, code*, refs*: Bytes;
		publics*, privates*: LONGINT;	(* for slim binaries *)
		nofimp*: INTEGER; import*: ArrayPtr;
		nofstrc*: INTEGER; struct*: ArrayPtr;
		nofreimp*: INTEGER; reimp*: ArrayPtr;
		export*: ExportDesc;
		term*: Proc
	END;

		(* type descriptors *)
	Tag = POINTER TO TypeDesc;
	TypeDesc = RECORD
		size: LONGINT;
		ptroff: LONGINT;
	END;

		(* interrupt handling *)
	TrapHandler* = PROCEDURE (err, fp, pc, pf: LONGINT);

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

	Timeval = RECORD sec, usec: LONGINT END;

	MilliTimer* = RECORD target: LONGINT END;

VAR
		(* exported variables *)
	trace*: ARRAY 35 OF CHAR;
	modules* : Module;	(** list of modules, patched by Linker *)
	EnableGC*, DisableGC*: Proc;	(** Enable or Disable the GC *)
	timer*: Proc;	(** for internal use *)
	runtime*: ARRAY 3 OF LONGINT;	(** for internal use *)
	shutdown*: LONGINT;

(*
	traceBufAdr, traceBufSize, traceHead, traceTail, traceMark: LONGINT;
	traceBufPtr: POINTER TO ARRAY OF CHAR;
*)

	Idle*: PROCEDURE(code: LONGINT);

		(* heap/GC *)
	firstBlock, endBlock: (*FreeBlockPtr*) ADDRESS;
	A: ARRAY N+1 OF (*FreeBlockPtr*) ADDRESS;
	reserve: BlockPtr;	(* reserved memory for out of memory trap *)
	initres: InitPtr;	(* root for init calls *)
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
	tracefd, siglevel: LONGINT;
	startTime: Timeval;
	Static*: BOOLEAN;	(* is programm completely statically linked? *)

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


(** -- Low-level tracing support -- *)
(** WriteChar - Write a character to the trace output *)

PROCEDURE WriteChar*(c: CHAR);
VAR i: LONGINT;
BEGIN
	IF c=0DX THEN c:= 0AX END;
	i:= Linux0.Write0( tracefd, SYSTEM.ADR(c), 1);
END WriteChar;

(** WriteString - Write a string *)

PROCEDURE WriteString*( s: ARRAY OF CHAR);
VAR k, l, err: LONGINT;
BEGIN
	l:=0;
	WHILE (l<LEN(s)) & (s[l]# 0X) DO INC( l) END;
	err:= Linux0.Write0( tracefd, SYSTEM.ADR(s), l);
END WriteString;

(** WriteLn - Skip to the next line on trace output *)

PROCEDURE WriteLn*;
(*
VAR s: ARRAY 3 OF CHAR;
BEGIN
	s[0] := 0DX;  s[1] := 0AX;  s[2] := 0X;  WriteString( s);
*)
BEGIN WriteChar( 0DX);
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
	err, i, j: LONGINT;
	c: CHAR;
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
				WriteHex(SYSTEM.VAL(SHORTINT, buf[0]), -3)
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
(*
PROCEDURE Bits(s: ARRAY OF CHAR;  x: SET;  ofs, n: LONGINT);
BEGIN
	WriteString(s);  WriteChar("=");
	REPEAT
		DEC(n);
		IF (ofs+n) IN x THEN WriteChar("1") ELSE WriteChar("0") END
	UNTIL n = 0
END Bits;

(* WriteDesc - Write a 8-byte segment descriptor. *)

PROCEDURE WriteFlags(f: LONGINT);
VAR s, t: SET;
BEGIN
	s := SYSTEM.VAL(SET, f);
	WriteHex(f, 8);  WriteString(" (");
	t := SYSTEM.LSH(s, -6)*{5} + SYSTEM.LSH(s, 4)*{4} + SYSTEM.LSH(s, 1)*{3} + SYSTEM.LSH(s, -2)*{2} + 
		SYSTEM.LSH(s, -5)*{1} + SYSTEM.LSH(s, -7)*{0};
	Bits("OCPAZS", t, 0, 6);
	Bits(" IT", s, 8, 2);
	Bits(" D", s, 10, 1);
	Bits(" IOPL", s, 12, 2);
	Bits(" NT", s, 14, 1);
	Bits(" AC,VM,RF", s, 16, 3);
	(*Bits(" ID,VIP,VIF", s, 19, 3);*)
	WriteChar(")")
END WriteFlags;
*)
(** Shutdown - Terminate Oberon after executing all module terminators.  If code = 0, perform a soft reboot. *)

PROCEDURE Shutdown*(code: LONGINT);
CONST Exit= 1;
VAR h: Proc;  m: Module;  t: LONGINT;
BEGIN
	IF code <0 THEN GrowHeap( -code); RETURN END;		
	shutdown:= code;
	m := modules;
	WHILE m # NIL DO
		IF m.term # NIL THEN h := m.term; m.term := NIL; h END;
		m := m.next
	END;
	IF (code = 1) THEN t:= Linux0.SysCall1( Exit, 0) END;	(* code=0: reboot; code=1: normal termination *)
	t:=Linux0.SysCall1( Exit, code);
END Shutdown;

PROCEDURE Halt(msg: ARRAY OF CHAR;  err: LONGINT);
BEGIN
	WriteString("Halt ");  WriteInt(err, 1);  WriteString(" - ");  WriteString(msg);  WriteLn;
	Shutdown( 1);
END Halt;

(** -- Trap handling -- *)

(** GetMod - Return the loaded module that contains code address pc. *)

PROCEDURE GetMod*(pc : LONGINT): Module;
VAR m: Module;  base: LONGINT;
BEGIN
	m := modules;
	WHILE m # NIL DO
		base := SYSTEM.ADR(m.code[0]);	(* include 1 byte after module in module, therefore <= below *)
		IF (base <= pc) & (pc <= base + LEN(m.code)) THEN
			RETURN m
		ELSIF (SYSTEM.ADR(m.data[0]) <= pc) & (pc <= SYSTEM.ADR(m.data[0]) + LEN(m.data)) THEN
			RETURN m
		ELSE
			m := m.next
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

(* ExceptionHandler - Exception dispatcher *)
(* LNO *)
PROCEDURE SignalHandler;
VAR trap, fp: LONGINT; state: Linux0.SigCPTR;
BEGIN
	INC( siglevel);
	SYSTEM.GETREG( SYSTEM.EBP, fp);	(* EBP *)
	state:= SYSTEM.VAL( Linux0.SigCPTR, fp+12);
	SYSTEM.GET( fp+8, trap);		(* get parameter , should be same as fp.errno *)
	IF trap=Linux0.SIGINT THEN										(* ctrl-c from terminal *)
		trap:= 13;
		IF Linux0.inGC THEN Linux0.break:= TRUE; DEC( siglevel); RETURN END;
	END;
	IF trap=Linux0.SIGILL THEN trap:= -6 END;									(* invalid instruction *)
	IF trap=Linux0.SIGTRAP THEN SYSTEM.GET( state.esp, trap) END;		(* HALT *)
	IF trap=Linux0.SIGFPE THEN trap:= 10 END;									(* DIV 0 *)
	IF trap=Linux0.SIGSEGV THEN
		IF state.cflags= 10246H THEN
			IF (state.err= 4) OR (state.err=6) THEN trap:= -14;	(* stack overflow, NIL reference *)
			ELSE trap:= -13;												(* general protection fault *)
			END;
		ELSE
			trap := -4;											(* overflow *)
		END;
	END;
	(* call handler *)
	WriteString("Received signal nr. "); WriteInt( trap, 3); 
	WriteString(" at signal handling level"); WriteInt( siglevel, 2); WriteLn;
	IF Linux0.inGC & ~Linux0.break THEN
		ShowState( trap, state^);
		Halt("Trap in GC", trap);
	END;
	IF siglevel >1 THEN
		IF siglevel >2 THEN Halt("Recursive trap", siglevel) END;
		WriteString("Error: Signal while handling Signal"); WriteLn;
	END;
	IF (handler= NIL) OR (showState IN traceheap) THEN ShowState( trap, state^) END;
	IF (handler # NIL) THEN handler( trap, state.ebp, state.eip, state.cr2 ) END;	(* trap 16: Disk full *)
	DEC( siglevel);
	IF trap# MAX( INTEGER) THEN
		IF loop=NIL THEN Shutdown( 1) END;
		state.esp:= Linux0.StackOrg;
		state.ebp:= Linux0.StackOrg;
		state.eip:= SYSTEM.VAL( LONGINT, loop);
	END;
END SignalHandler;

(* LNO *)
PROCEDURE QuitSignalHandler( );
BEGIN
	INC( siglevel);
	WriteString("Recived signal nr. n/a"); WriteInt( 0, 3); WriteLn;
	WriteString("Terminating Oberon! "); WriteLn;
	Shutdown( 0);
END QuitSignalHandler;

(** InstallTrap - Install the trap handler *)

PROCEDURE InstallTrap*(p: TrapHandler);
BEGIN	handler := p
END InstallTrap;

(** InstallLoop - Install procedure to which control is transferred after a trap *)

PROCEDURE InstallLoop*(p: Proc);
BEGIN	loop := p
END InstallLoop;

(** -- Interrupt handling -- *)

(** InstallIP - Install interrupt handler & enable IRQ if necessary.
	"p" must be defined as a normal "PROCEDURE p;".  On entry to p interrupts
	are disabled and may be enabled with SYSTEM.STI().  At exit from p the
	state of interrupts are restored.  The acknowledgement of a hardware interrupt 
	is done by the Kernel.  No end-of-interrupt has to be signalled explicitly in 
	procedure p.  IRQs are mapped starting at interrupt Kernel.IRQ.

	At entry to procedure p the stack is as follows:
		56	EFLAGS''
		52	CS''
		48	EIP''	(IRETD from glue code)
		44	errorcode
		40	intnum	<-- ESP'
		36	EAX
		32	ECX
		28	EDX
		24	EBX
		20	ESP'
		16	EBP
		12	ESI
		08	EDI
		04	EIP'	(RET from p)
		00	EBP'	<-- EBP
		xx	locals	<-- ESP

	Interrupt priorities (highest to lowest):
	
	IRQ	Common use
	00	Timer
	01	Keyboard
	08	RT clock
	09	EGA/VGA retrace
	10	Ethernet or other card
	11	card
	12	PS/2 mouse or card
	13	DMA/copro
	14	Hard disk
	15	card or IRQ error
	03	COM2/4
	04	COM1/3
	05	card
	06	Diskette
	07	LPT1 or IRQ error
*)

(*
	The location of [haltcode] depends on the interrupt level, which
	can be recognised from the lower 2 bits of CS''.
	If it was an interrupt from a level 3 to level 0 the stack will be:
	64	SS3
	60	ESP3	--> [haltcode]
	If it was from level 0 to level 0, it will be:
	60	[haltcode]
	If it was from V86 mode, it will be:
	80	GS3
	76	FS3
	72	DS3
	68	ES3
	64	SS3
	60	ESP3
*)

(** -- Memory/Object management -- *)

(** Available - Return the size in bytes of the remaining free heap space *)

PROCEDURE Available*(): LONGINT;
	VAR i, avail: LONGINT; ptr: FreeBlockPtr;
BEGIN
	avail := 0; i := 0;
	WHILE i <= N DO
		ptr := SYSTEM.VAL(FreeBlockPtr, A[i]);
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
		ptr := SYSTEM.VAL(FreeBlockPtr, A[i]);
		WHILE ptr # NIL DO
			IF ptr^.size > max THEN max := ptr^.size END;
			ptr := SYSTEM.VAL(FreeBlockPtr, ptr^.next)
		END;
		DEC(i)
	END;
	RETURN max
END LargestAvailable;

PROCEDURE MapPhysical* (physAdr, size: LONGINT; VAR virtAdr: LONGINT);
BEGIN
	HALT( 101);
END MapPhysical;

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
					IF field # NIL THEN
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
	WHILE i <= N DO A[i] := nil; lastA[i] := SYSTEM.ADR(A[i]); INC(i) END;
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

PROCEDURE GC*;
	VAR m: Module; i, p, sp, ptradr: LONGINT; ptr: BlockPtr;  avail, largest, t0, tf0, tf1, st: LONGINT;
BEGIN
	Linux0.inGC := TRUE;
	IF GClevel > 0 THEN
		IF traceheap # {} THEN
			WriteString("(GC");
			IF 10 IN traceheap THEN avail := Available();  largest := LargestAvailable() END;
			st := GetTimer();
		END;
		m := modules;	(* ModuleDesc and ModuleBlock are marked via Kernel.modules *)
		WHILE m # NIL DO
			Mark(SYSTEM.VAL(BlockPtr, m));	(* the code, data etc. is marked via fields of m *)
			i := LEN(m.ptrTab); IF i > 0 THEN ptradr := SYSTEM.ADR(m.ptrTab[0]) END; 
			WHILE i > 0 DO
				SYSTEM.GET(ptradr, p); SYSTEM.GET(p, ptr);
				IF ptr # NIL THEN Mark(ptr) END;
				DEC(i); INC(ptradr, 4);
			END;
			i := LEN(m.tdescs); IF i > 0 THEN ptradr := SYSTEM.ADR(m.tdescs[0]) END; 
			WHILE i > 0 DO
				SYSTEM.GET(ptradr, ptr); Mark(ptr);
				DEC(i); INC(ptradr, 4);
			END;
			m := m^.next;
		END;
			(* check stack *)
		IF GCstack THEN
			SYSTEM.GETREG( SYSTEM.ESP, sp);
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
			t0 := SYSTEM.ADR(A[N]);  WriteString("[FP");
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
			IF 10 IN traceheap THEN
				avail := Available()-avail;  largest := LargestAvailable()-largest;
				WriteInt(avail, 1);  WriteString(" +");  WriteInt(largest, 1)
			END;
			WriteChar(" ");  WriteInt(st*1000 DIV TimeUnit, 1);  WriteString("ms");
			WriteString(" CG)"); WriteLn
		END
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
	IF size>LargestAvailable() THEN GrowHeap(size) END;
	IF Linux0.break THEN Linux0.break := FALSE; SYSTEM.HALT(13) END;
	IF size < 0 (* NEW(p, MAX(LONGINT)) *) THEN SYSTEM.HALT(14) END;
	i := size DIV B;
	IF i > N THEN i := N END;
	adr := SYSTEM.ADR(A[0]) + 4*i;
	AN := SYSTEM.ADR(A[N]);	(* constant register *)
	LOOP
		SYSTEM.GET(adr, ptr);
		IF adr = AN THEN
			LOOP
				IF ptr = NIL THEN
					IF (* (TrapHandlingLevel = 0) & *) firstTry THEN GC;
						firstTry := FALSE; ptr := NewBlock(size); firstTry := TRUE;
						RETURN ptr
					ELSE  reserve := NIL; GC; firstTry := TRUE; SYSTEM.HALT(14)
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
		restptr^.next := A[i]; A[i] := SYSTEM.VAL(ADDRESS, restptr)
	END;
	RETURN ptr
END NewBlock;

(* NewRec - Implementation of NEW.  Do not call directly. *)

PROCEDURE NewRec(VAR p: ADDRESS; tag: Tag);	(* implementation of NEW(ptr) *)
	VAR size: LONGINT; ptr, init: InitPtr; 
BEGIN (* tag^.size = rectyp^.size *)
	ASSERT(SYSTEM.VAL(LONGINT, tag) MOD 8 = 0);	(* no Oberon-X flags allowed *)
	IF tag = NIL THEN tag := SYSTEM.VAL(Tag, ptrElemTag) END;	(* descriptor for ARRAY * OF *)
	size := SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, tag^.size + (4 (*tag*) + B-1))-SYSTEM.VAL(SET, B-1));
	ptr := NewBlock(size);
	IF 0 IN traceheap THEN
		WriteString("[NR ");  WriteType(SYSTEM.VAL(LONGINT, tag));
	END;
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
	SYSTEM.GETREG( SYSTEM.EBP, bp);
	SYSTEM.GET(bp+4, init^.z3);
	init^.z4 := 0;	(* bit 1 must be 0 to distinguish from array SysBlk *)
	ptr^.z5 := SYSTEM.ADR(ptr^.z0);
	init^.z6 := 0;
	p := SYSTEM.VAL(ADDRESS, ptr) + 28;
	IF 2 IN traceheap THEN
		WriteHex(SYSTEM.VAL(LONGINT, p), 9);  WriteString("] ")
	END
END NewSys;

(* NewArr - Implementation of NEW.  Do not call directly. *)

PROCEDURE NewArr(VAR p: ADDRESS; eltag: Tag; nofelem, nofdim: LONGINT);
VAR size, firstElem, elSize, arrSize, vectSize: LONGINT; ptr, init: InitPtr; 
BEGIN
	ASSERT(SYSTEM.VAL(LONGINT, eltag) MOD 4 = 0);
	IF 1 IN traceheap THEN
		WriteString("[NA ");  WriteInt(nofelem, 1);  WriteChar(" ");  WriteInt(nofdim, 1)
	END;
	IF eltag = NIL THEN
		eltag := SYSTEM.VAL(Tag, ptrElemTag)	(* array of pointer to *)
	END;
	elSize := eltag^.size;
	arrSize := nofelem*elSize;
	IF arrSize=0 THEN NewSys(p, nofdim*4+12); RETURN END;
	ASSERT(arrSize > 0);
	vectSize := SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, 4*nofdim) + SYSTEM.VAL(SET, 4));	(* -> ADR(firstElem) MOD 8 = 0 *)
	IF eltag^.ptroff = -4 THEN (* no pointers in element type *)
		NewSys(p, arrSize + vectSize + 12);
		SYSTEM.PUT(p, SYSTEM.VAL(SET, arrSize + vectSize+15)-SYSTEM.VAL(SET, 3));
		RETURN
	END;
	size := SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, arrSize + vectSize + (16 + B-1))-SYSTEM.VAL(SET, B-1));
	ptr := NewBlock(size);
	init := SYSTEM.VAL(InitPtr, SYSTEM.VAL(ADDRESS, ptr) + size - 32);
	WHILE init # ptr DO
		init^.tag := NIL; init^.z0 := 0; init^.z1 := 0; init^.z2 := 0; init^.z3 := 0; init^.z4 := 0; init^.z5 := 0; init^.z6 := 0;
		DEC(SYSTEM.VAL(ADDRESS, init), 32);
	END;
	ptr^.tag := SYSTEM.VAL(Tag, SYSTEM.VAL(SET, eltag) + array);
	firstElem := SYSTEM.ADR(ptr^.z3) + vectSize;
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
*)
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

PROCEDURE InstallTermHandler* (h: Proc);
	VAR codebase, handlerAdr: LONGINT; m: Module; found: BOOLEAN;
BEGIN
	m := modules; handlerAdr := SYSTEM.VAL(LONGINT, h); found := FALSE;
	WHILE (m # NIL) & ~found DO
		codebase := SYSTEM.ADR(m.code[0]);
		IF (codebase <= handlerAdr) & (handlerAdr <= codebase + LEN(m.code)) THEN found := TRUE
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
	beg := SYSTEM.ADR(m.code[0]);  end := beg + LEN(m.code);
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

PROCEDURE GetTimeOfDay(tv, tz: LONGINT): LONGINT;
CONST GETTIMEOFDAY= 78;
CODE {SYSTEM.i386}
	MOV	EAX, GETTIMEOFDAY
	MOV	EBX, tv[ EBP]
	MOV	ECX, tz[ EBP]
	INT 80H
END GetTimeOfDay;

(** GetClock - Return current time and date *)

PROCEDURE GetClock*(VAR time, date: LONGINT);
CONST TIME= 13;
VAR t: LONGINT;
BEGIN
	t:=Linux0.SysCall1( TIME, 0);		(* ToDo: use ftime *)
	IF t>0 THEN
		U2OTime( t, date, time);
	ELSE time:=0; date:=0;
	END;
END GetClock;
(*
PROCEDURE GetClock*(VAR time, date: LONGINT);
VAR tv: Timeval; tz: Timezone; t: Time;
BEGIN
	gettimeofday( tz, tv);
	t:= localtime( tv.sec);
	time:= t.sec+ASH( t.min, 6)+ ASH( t.hour, 12);
	date:= t.mday+ ASH( t.mon+1, 5)+ ASH( t.year, 9);
END GetClock;
*)
(** SetClock - Set current time and date *)

PROCEDURE SetClock*(time, date: LONGINT);
BEGIN	HALT( 101);	(* because only superuser is allowed to do this *)
END SetClock;

(** GetTimer - Return "ticks" since initialisation (Kernel.TimeUnit ticks per second) *)

PROCEDURE GetTimer*( ): LONGINT;
VAR i: LONGINT; j: Timeval;
BEGIN
	i:=GetTimeOfDay(SYSTEM.ADR(j), 0);
	RETURN (j.sec-startTime.sec)*1000 +(j.usec -startTime.usec) DIV 1000;
END GetTimer;

(** SetTimer - Set timer to expire in approximately "ms" milliseconds. *)

PROCEDURE SetTimer*(VAR t: MilliTimer;  ms: LONGINT);
BEGIN
	IF TimeUnit # 1000 THEN	(* convert to ticks *)
		ASSERT((ms >= 0) & (ms <= MAX(LONGINT) DIV TimeUnit));
		ms := ms * TimeUnit DIV 1000
	END;
	IF ms < 5 THEN INC(ms) END;	(* Nyquist adjustment *)
	t.target := GetTimer() + ms	(* overflow checking must be off *)
END SetTimer;

(** Expired - Test if a timer has expired.  Interrupts must be on. *)

PROCEDURE Expired*(VAR t: MilliTimer): BOOLEAN;
BEGIN
	RETURN GetTimer() - t.target >= 0	(* overflow checking must be off *)
END Expired;

(* Fill4 - Fill "size" dwords at "dest" with "filler" *)
PROCEDURE -Fill4(dest, size, filler: LONGINT);
CODE {SYSTEM.i386}
	POP	EAX
	POP	ECX
	POP	EDI
	CLD
	REP	STOSD
END Fill4;

PROCEDURE DefaultEnableGC;
BEGIN	INC(GClevel)
END DefaultEnableGC;

PROCEDURE DefaultDisableGC;
BEGIN	DEC(GClevel)
END DefaultDisableGC;

PROCEDURE GrowHeap( size: LONGINT);
VAR
	high0, high1: LONGINT;
	f: FreeBlockPtr;
	first: BOOLEAN;
BEGIN
	size:= (size+0FFFFH) DIV 10000H*10000H;
	high0:=endBlock+4;
	high1:=high0+size;
	first:=firstBlock=endBlock+B;
	endBlock:=Linux0.Brk(high1);
	IF traceheap # {} THEN
		WriteString("Heap growing: "); WriteHex(high0, 9);  WriteHex(high1, 9); WriteLn
	END;
	IF endBlock#high1 THEN Halt("Error: No new Heap abvailable.", 1) END;
	DEC(endBlock, 4);
	Fill4( high0, size DIV 4, 0);
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
		WriteHex(SYSTEM.ADR(m.code[0]), 8);  WriteChar(" ");
		WriteString(m.name);  WriteLn;
		m := m.next
	END;

	m := modules;  WHILE m.name # "Kernel" DO m := m.next END;
	i := LEN(m.tdescs);  ptrElemTag := 0;
	REPEAT
		DEC(i);  t := m.tdescs[i];  SYSTEM.GET(t - 4, td);
		IF td.name = "PtrElemDesc" THEN ptrElemTag := t END
	UNTIL (ptrElemTag # 0);
	endBlock:=Linux0.Brk(0)-4;
	firstBlock:=endBlock+B;
	reserve := NIL;  firstTry := TRUE;
	GrowHeap(1000000H);
	EnableGC := DefaultEnableGC;  DisableGC := DefaultDisableGC;
END InitHeap;

PROCEDURE Var(s : ARRAY OF CHAR; var: LONGINT);
BEGIN
	WriteChar(" ");  WriteString(s);  WriteChar("=");  WriteHex( var, 8)
END Var;

PROCEDURE VarDK(s : ARRAY OF CHAR);
BEGIN
	WriteChar(" ");  WriteString(s);  WriteString("=?------?");
END VarDK;

(* ShowState - Show machine state *)

PROCEDURE ShowState(error: LONGINT;  sc: Linux0.SigContext);
VAR fp, pc, x : LONGINT;  m: Module;

BEGIN
	IF handlingtrap THEN	
		WriteString(" [Recursive TRAP]");  WriteLn
	ELSE
		handlingtrap := TRUE;
		WriteString("TRAP "); WriteInt(error, 1); WriteLn;
			(* the registers *)
		Var("CS:", sc.cs); Var("DS:", sc.ds);  Var("ES:", sc.es);  Var("SS:", sc.ss);
		VarDK("CR0"); VarDK("FPS");  WriteLn;
		Var("EIP", sc.eip);  Var("ESI", sc.esi);  Var("EDI", sc.edi);  Var("ESP", sc.esp);
		Var("CR2", sc.cr2);  Var("SBT", Linux0.StackOrg);  WriteLn;
		Var("EAX", sc.eax);  Var("EBX", sc.ebx);  Var("ECX", sc.ecx);  Var("EDX", sc.edx);
		VarDK("CR3");  VarDK("KFL");  WriteLn;
		Var("EBP", sc.ebp);  Var("FS:", sc.fs);  Var("GS:", sc.gs);  Var("ERR", sc.err);
		VarDK("CR4");  Var("TCK", GetTimer() );  WriteLn;
(*
		IF SYSTEM.VAL(CHAR, trapDR[7]) # 0X THEN	(* some breakpoints enabled *)
			Var("DR0", trapDR[0]);  Var("DR1", trapDR[1]);  Var("DR2", trapDR[2]);  Var("DR3", trapDR[3]);
			Var("DR6", trapDR[6]);  Var("DR7", trapDR[7]);  WriteLn
		END;
		WriteString(" EFLAGS=");  WriteFlags(SYSTEM.VAL(LONGINT, flags));  WriteLn;
*)		
		IF error = -6 THEN WriteMemory( sc.eip, 16) END;	(* show bad instruction *)
		WriteLn;
			(* procedures *)
		x := 10; 
		pc:= sc.eip; fp:= sc.ebp;
		LOOP
			m := GetMod(pc);
			IF m = NIL THEN 
				WriteString("Unknown module");  WriteLn;
				IF x#10 THEN EXIT END;
			ELSE
				WriteString(m.name);  WriteString("  PC = ");
				WriteInt(pc-SYSTEM.ADR(m.code[0]), 1);  WriteLn;
			END;
	        SYSTEM.GET(fp+4, pc); SYSTEM.GET(fp, fp); (* return addr from stack *)
			IF fp >= Linux0.StackOrg THEN EXIT END;
			DEC(x);  IF x = 0 THEN EXIT END;
		END;
	END;
	handlingtrap := FALSE;
END ShowState;

(*
	---------------- Machine initialisation ----------------
	From University of Stellenbosch's Gneiss kernel (pjm)

	References:
	1. J.H. Crawford and P.P. Gelsinger, "Programming the 80386", Sybex, 1987
	2. Intel, "80386 Programmer's Reference Manual, 1986
	3. Intel, "i486(tm) Microprocessor", April 1989, #240440-001
*)

(* InterruptHandler

	Stack layout:
		72	GS
		68	FS
		64	DS
		60	ES
		-- if from VM --
		56	SS
		52	ESP
		-- if from level 3 or VM --
		48	EFLAGS
		44	CS
		40	EIP
		36	errorcode
		32	intnum
		28	EAX
		24	ECX
		20	EDX
		16	EBX
		12	ESP'
		08	EBP
		04	ESI
		00	EDI	<--- ESP
*)

(* ------------------------------------------------------------------------------------------------*)
(* Oberon-X run-time support - based on code by R. Morelli *)
(* TraverseCopyStack - Allocate stack space for dynamic array and make a deep copy *)
(* EnterCopyHandler - Software interrupt handler to make deep copy of dynamic array value parameter *)
(* TraverseCopyHeap - Allocate heap space for dynamic array and make a deep copy *)
(* Implementation of dynamic array copy.  Do not call directly. *)


(* ------------------------------------------------------------------------------------------------*)
(* InitRuntime - Initialise runtime support. *)

PROCEDURE InitRuntime;
VAR
	newRec: PROCEDURE(VAR p: ADDRESS;  tag: Tag);
	newSys: PROCEDURE(VAR p: ADDRESS;  size: LONGINT);
	newArr: PROCEDURE(VAR p: ADDRESS;  eltag: Tag;  nofelem, nofdim: LONGINT);
BEGIN
	newRec := NewRec;	(* used in Modules and Types *)
	newSys := NewSys;
	newArr := NewArr;
	runtime[0] := SYSTEM.VAL(ADDRESS, newRec);	(* 253 *)
	runtime[1] := SYSTEM.VAL(ADDRESS, newSys);	(* 252 *)
	runtime[2] := SYSTEM.VAL(ADDRESS, newArr);	(* 251 *)
END InitRuntime;

PROCEDURE CleanUp;
VAR err: LONGINT;
BEGIN
	err:= Linux0.Close0( tracefd);
END CleanUp;

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

PROCEDURE GetConfig*(env: ARRAY OF CHAR; VAR val: ARRAY OF CHAR);
VAR i, j, n: LONGINT; ch: CHAR;
BEGIN	(* stack layout at http://asm.sourceforge.net/articles/startup.html *)
	WriteString(env); WriteChar("=");
	SYSTEM.GET(Linux0.StackOrg+16, n);
	i:=24+4*n;
	SYSTEM.GET(Linux0.StackOrg+i, n);
	WHILE n#0 DO
		j:=0;
		SYSTEM.GET(n, ch);
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

PROCEDURE Init();
VAR	val: ARRAY 8 OF CHAR; i: LONGINT;
BEGIN
	i:=GetTimeOfDay(SYSTEM.ADR(startTime), 0);
	timer := NIL;
	siglevel:=0;
	tracefd:= Linux0.Openat0( Linux0.ATFDCWD, SYSTEM.ADR(TRACE), Linux0.ORDWR+Linux0.OCREAT+Linux0.OTRUNC, SYSTEM.VAL(LONGINT, {2, 5, 7, 8}));
	WriteString( version); WriteString( Linux0.ARCH); WriteString( DATE);WriteLn;
	IF traceheap # {} THEN
		WriteString("StackOrg"); WriteHex(Linux0.StackOrg, 10);  WriteLn
	END;
	InitHeap;
	InstallTermHandler( CleanUp);
	InitTrapHandling;
	handler:= NIL;
	InitRuntime;
END Init;

PROCEDURE GetArg*(n: LONGINT; VAR s: ARRAY OF CHAR);
VAR l, m: LONGINT; c: CHAR;
BEGIN
	IF (n>=0) & (n<NoOfArgs) THEN
		SYSTEM.GET(Linux0.StackOrg+20+n*4, l);
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
	shutdown:=0;
	SYSTEM.GETREG( SYSTEM.ESP, Linux0.StackOrg);	(* user stack org *)
	DEC( Linux0.StackOrg, 4);
	SYSTEM.GET(Linux0.StackOrg+16, NoOfArgs);
	Init;
	CmdLine;
	GetConfig("OTRACE", trace);
	Static:=TRUE;	(* Modules sets Static to FALSE *)
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
