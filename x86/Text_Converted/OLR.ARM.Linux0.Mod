MODULE Linux0;	(* rc/ard/nm/jm/devil/pjm/rml*)

(* Linux kernel interface for ARM *)

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
	2015-12-09	split OLR.Kernel.Mod to OLR.ARM.Linux0.Mod and OLR.MIPS.Linux0.Mod
*)


IMPORT SYSTEM;

CONST
	ARCH*="ARMv7";
	ObjPrefix*="armv7/";
	ObjTag*=36FBH;	(* x86: 0AFX; arml: 0F5X; arm: 36FBH; mips: 36F9H; mipst: 36FAH *)
	RegSize*=32;
	PageSize*=1000H;

	(* registers for ARM 32 *)
	ARI*=0;	FP* = 12; SP* = 13; LR* = 14; PC = 15;

	LDMIA1= 0E8900001H+FP*10000H; LDMIA2=LDMIA1+2; LDMIA3= LDMIA2+4; LDMIA4=LDMIA3+8; LDMIA5=LDMIA4+16; LDMIA6=LDMIA5+32;
	NOP=0E320F000H;	SVC= 0EF000000H;	(*BX=0E12FFF1EH;*)	XTRAP=0EC1F0700H;
	BX=0EA000000H;	(* BX= 0E12FFF1EH; jump=0EA000000H (B+2)*)	

	ATFDCWD*=-100;	(* use current working directory *)

	(** Open( .. ) flags *)
	ORDonly*= 0;	OWRonly*= 1;	ORDWR*=2;	OCREAT*= 40H;	OEXCL*= 80H;	OTRUNC*= 200H;	OAPPEND*=400H;	ODSYNC*=1000H;(* from MIPS *)
	ODirectory*=0;
	(** FLock( .. ) *)
	LOCKEX*= 2;	LOCKNB*= 4;	LOCKUN*= 8;
	(** LSeek *)
	SEEKSET*=0;	SEEKCURRENT*=1;	SEEKEND*=2;
	(** Mmap *)
	MAPSHARED*=1; MAPPRIVATE*=2; MAPANONYMOUS*=20H;	(* ARM: 20H; MIPS: 800H *)

(*	PROTEXEC= PROTREAD=	; PROTWRITE=	PROTNONE=	*)

	(* Termios used in Input (FB) *)

(* ARM *)
	VMIN*= 6;
	TCGETS*= 5401H;
	TCSETSF*= 5404H;

	(** Socket *)
	SOCKSTREAM*=1;		(* was 1 for X86 and ARM, 2 for MIPS ??*)

(* Common *)
	SIGHUP= 1;		(* Hang up ; X11 quits *)
	SIGINT*= 2;			(* interrupt	 ctrl-c *)
	SIGQUIT= 3;		(* quit	ctrl-# , ctrl-4 ?, PrintScreen? *)
	SIGILL* = 4;			(* invalid instruction ?*)
	SIGTRAP*= 5;		(* HALT( x) *)
	SIGFPE* = 8;		(* DIV 0 *)
	SIGKILL= 9;	(* kill *)
	SIGSEGV*= 11;	(* segmentation fault *)
	SIGPIPE*= 13;	(* in KDE alt-F4 *)
	SIGALRM= 14;	(* signal  from alarm(1) *)
	SIGTERM = 15;	(* ctrl-alt-del *)
	SIGPROF= 29;
	SIGXCPU= 30;
	SIGXFSZ= 31;

(* ARM: *)
	SIGABRT= 6;
	SIGBUS* = 7;	(* unused *)
	SIGUSR1*= 10;	(* used by Display for framebuffer console switching *)
	SIGUSR2*= 12;	(* used by Display for framebuffer console switching *)
	SIGSTKFLT= 16;	(* floating point stack error *)
	SIGCHLD*= 17;	(* child quit *)
	SIGCONT*= 18;
	SIGSTOP= 19;
	SIGTSTP= 20;		(* tty stop *)
	SIGTTIN= 21;		(* tty *)
	SIGTTOU= 22;	(* tty *)
	SIGIO= 23;		(* io error *)
	SIGWINCH= 28;	(* window changed *)


	IGNSigs*={ SIGWINCH, SIGSTOP, SIGCONT, SIGKILL, SIGCHLD};	(* Ignore *)
	QUITSigs*={ SIGHUP, SIGTSTP, SIGQUIT, SIGTERM};				(* Quit *)
	TRAPSigs*= -{} -IGNSigs-QUITSigs ;	(* Trap *)

TYPE
	Proc*= PROCEDURE;
	TrapHandler* = PROCEDURE ( trap, fp, pc, page: LONGINT);

(* ARM *)
	SigContext*= POINTER TO RECORD
		dummy: ARRAY 8 OF LONGINT;
(*		trapNo, errCode, oldMask: LONGINT;*)
		regs: ARRAY 16 OF LONGINT;
		cpsr, faultAddr, signal2: LONGINT;
		fpregs: ARRAY 32 OF LONGINT;
	END;

	Status* = RECORD	(* ARM*)
		a1, a2, a3, a4: LONGINT;
		b1, b2, b3, b4: LONGINT;
		c1, c2, c3, c4: LONGINT;
		size*, d2, blksize*, d4: LONGINT;
		e1, e2, atime*, atimens: LONGINT;
		mtime*, mtimens, ctime*, ctimens: LONGINT;
		g1, g2, g3, g4: LONGINT;
		h1, h2, h3, h4: LONGINT;
		i1, i2, i3, i4: LONGINT;
		j1, j2, j3, j4: LONGINT;
	END;

	SockAddrUn*= RECORD
		pf*: INTEGER;
		path*: ARRAY 64 OF CHAR;	(* was 30 for MIPS; 64 for ARM *)
	END;

	Timeval = RECORD sec, usec: LONGINT END;

VAR
	regs*, fpregs*: ARRAY 32 OF LONGINT;
	SigTab: ARRAY 32 OF LONGINT;
	StackOrg*, 	(** highest address on stack (single-process system) *)
	siglevel*: LONGINT;
	break*, 	(** has ctrl-break been pressed? *)
	inGC*: BOOLEAN;	(** executing inside GC? *)
	traphandler*, defaulttraphandler*: TrapHandler;
	loop*: Proc;

PROCEDURE Openat0*( dirfd, name, flags, mode: LONGINT): LONGINT;
BEGIN
	SYSTEM.CODE(LDMIA4);	(*LDMIA   SP!, {R0 R1 R2 } *)
	SYSTEM.PUTREG(7, 142H);				(* E3A07005	MOV   R7,5H *)
	SYSTEM.CODE(SVC);	(* EF000000	SWI	0H *)
	SYSTEM.CODE(BX);	(* E1A0F00E	MOV PC,LR *)
END Openat0;

PROCEDURE Close0*( fd: LONGINT): LONGINT;
BEGIN
	SYSTEM.CODE(LDMIA1);	(*LDMIA   SP, {R0 } *)
	SYSTEM.PUTREG(7, 6);				(* E3A07005	MOV   R7,5H *)
	SYSTEM.CODE(SVC);	(* EF000000	SWI	0H *)
	SYSTEM.CODE(BX);	(* E1A0F00E	MOV PC,LR *)
END Close0;

PROCEDURE Read0*( fd, buf, num: LONGINT): LONGINT;
BEGIN
	SYSTEM.CODE(LDMIA3);	(*LDMIA   SP, {R0 R1 R2 } *)
	SYSTEM.PUTREG(7, 3);				(* E3A07005	MOV   R7,5H *)
	SYSTEM.CODE(SVC);	(* EF000000	SWI	0H *)
	SYSTEM.CODE(BX);	(* E1A0F00E	MOV PC,LR *)
END Read0;

PROCEDURE Readv0*( fd, vect, cnt: LONGINT): LONGINT;
BEGIN
	SYSTEM.CODE(LDMIA3);	(*LDMIA   SP, {R0 R1 R2 } *)
	SYSTEM.PUTREG(7, 145);				(* E3A07005	MOV   R7,5H *)
	SYSTEM.CODE(SVC);	(* EF000000	SWI	0H *)
	SYSTEM.CODE(BX);	(* E1A0F00E	MOV PC,LR *)
END Readv0;

PROCEDURE Write0*( fd, buf, num: LONGINT): LONGINT;	
BEGIN
	SYSTEM.CODE(LDMIA3);	(*LDMIA   SP, {R0 R1 R2 } *)
	SYSTEM.PUTREG(7, 4);				(* E3A07005	MOV   R7,5H *)
	SYSTEM.CODE(SVC);	(* EF000000	SWI	0H *)
	SYSTEM.CODE(BX);	(* E1A0F00E	MOV PC,LR *)
END Write0;

PROCEDURE Writev0*( fd, vect, cnt: LONGINT): LONGINT;	
BEGIN
	SYSTEM.CODE(LDMIA3);	(*LDMIA   SP, {R0 R1 R2 } *)
	SYSTEM.PUTREG(7, 146);				(* E3A07005	MOV   R7,5H *)
	SYSTEM.CODE(SVC);	(* EF000000	SWI	0H *)
	SYSTEM.CODE(BX);	(* E1A0F00E	MOV PC,LR *)
END Writev0;

PROCEDURE Brk0*( adr: LONGINT):LONGINT;
BEGIN
	SYSTEM.CODE(LDMIA1);	(*LDMIA   SP, {R0 R1 R2 } *)
	SYSTEM.PUTREG(7, 45);				(* E3A07005	MOV   R7,5H *)
	SYSTEM.CODE(SVC);	(* EF000000	SWI	0H *)
	SYSTEM.CODE(BX);	(* E1A0F00E	MOV PC,LR *)
END Brk0;

PROCEDURE Exit0*(arg: LONGINT);
BEGIN
	SYSTEM.CODE(LDMIA1);	(*LDMIA   SP, {R0 R1 R2 } *)
	SYSTEM.PUTREG(7, 1);				(* E3A07005	MOV   R7,5H *)
	SYSTEM.CODE(SVC);	(* EF000000	SWI	0H *)
	SYSTEM.CODE(BX);	(* E1A0F00E	MOV PC,LR *)
END Exit0;

PROCEDURE Creat0*( name, mode: LONGINT): LONGINT;
BEGIN
	SYSTEM.CODE(LDMIA2);	(*LDMIA   SP, {R0 R1 R2 } *)
	SYSTEM.PUTREG(7, 8);				(* E3A07005	MOV   R7,5H *)
	SYSTEM.CODE(SVC);	(* EF000000	SWI	0H *)
	SYSTEM.CODE(BX);	(* E1A0F00E	MOV PC,LR *)
END Creat0;

PROCEDURE MProtect0*( adr, len, prot: LONGINT): LONGINT;
BEGIN
	SYSTEM.CODE(LDMIA3);	(*LDMIA   SP, {R0 R1 R2 } *)
	SYSTEM.PUTREG(7, 125);				(* E3A07005	MOV   R7,5H *)
	SYSTEM.CODE(SVC);	(* EF000000	SWI	0H *)
	SYSTEM.CODE(BX);	(* E1A0F00E	MOV PC,LR *)
END MProtect0;

PROCEDURE SIGAction0*( signum, act, oldact: LONGINT): LONGINT;	
BEGIN
	SYSTEM.CODE(LDMIA3);	(*LDMIA   SP, {R0 R1 R2 } *)
	SYSTEM.PUTREG(7, 67);				(* E3A07005	MOV   R7,5H *)
	SYSTEM.CODE(SVC);	(* EF000000	SWI	0H *)
	SYSTEM.CODE(BX);	(* E1A0F00E	MOV PC,LR *)
END SIGAction0;

PROCEDURE FStat0*( fd, stat: LONGINT): LONGINT;
BEGIN
	SYSTEM.CODE(LDMIA2);	(*LDMIA   SP, {R0 R1 R2 } *)
	SYSTEM.PUTREG(7, 197);				(* E3A07005	MOV   R7,5H *)
	SYSTEM.CODE(SVC);	(* EF000000	SWI	0H *)
	SYSTEM.CODE(BX);	(* E1A0F00E	MOV PC,LR *)
END FStat0;

PROCEDURE Mmap20       *( addr, len, prot, flags, fd, off: LONGINT):LONGINT;
BEGIN
	SYSTEM.CODE(LDMIA6);	(*LDMIA   SP, {R0 R1 R2 } *)
	SYSTEM.PUTREG(7, 192);				(* E3A07005	MOV   R7,192 *)
	SYSTEM.CODE(SVC);	(* EF000000	SWI	0H *)
	SYSTEM.CODE(BX);	(* E1A0F00E	MOV PC,LR *)
END Mmap20;

PROCEDURE Munmap0*( addr, len: LONGINT): LONGINT;
BEGIN
	SYSTEM.CODE(LDMIA2);	(*LDMIA   SP, {R0 R1 R2 } *)
	SYSTEM.PUTREG(7, 91);				(* E3A07005	MOV   R7,5H *)
	SYSTEM.CODE(SVC);	(* EF000000	SWI	0H *)
	SYSTEM.CODE(BX);	(* E1A0F00E	MOV PC,LR *)
END Munmap0;

PROCEDURE CacheFlush0*( adr, bytes: LONGINT): LONGINT;
BEGIN
	SYSTEM.CODE(LDMIA2);	(*LDMIA   SP, {R0 R1 R2 } *)
	SYSTEM.PUTREG(7, 0F0002H);				(* ARM_NR_cacheflush = 0F0002H *)
	SYSTEM.CODE(0E0811000H);	(* ADD	R1, R1, R0		 ARM needs beg, end adr *)
	SYSTEM.PUTREG(2, 0);
	SYSTEM.CODE(SVC);	(* EF000000	SWI	0H *)
	SYSTEM.CODE(BX);	(* E1A0F00E	MOV PC,LR *)
END CacheFlush0;

(* Files *)
PROCEDURE LSeek0*( fd, pos, whence: LONGINT): LONGINT;
BEGIN
	SYSTEM.CODE(LDMIA3);	(*LDMIA   SP, {R0 R1 R2 } *)
	SYSTEM.PUTREG(7, 19);				(* E3A07005	MOV   R7,5H *)
	SYSTEM.CODE(SVC);	(* EF000000	SWI	0H *)
	SYSTEM.CODE(BX);	(* E1A0F00E	MOV PC,LR *)
END LSeek0;

PROCEDURE FLock0*( fd, arg: LONGINT): LONGINT;
BEGIN
	SYSTEM.CODE(LDMIA2);	(*LDMIA   SP, {R0 R1 R2 } *)
	SYSTEM.PUTREG(7, 143);				(* E3A07005	MOV   R7,5H *)
	SYSTEM.CODE(SVC);	(* EF000000	SWI	0H *)
	SYSTEM.CODE(BX);	(* E1A0F00E	MOV PC,LR *)
END FLock0;

PROCEDURE Ftruncate0*( fd, len: LONGINT): LONGINT;
BEGIN
	SYSTEM.CODE(LDMIA2);	(*LDMIA   SP, {R0 R1 R2 } *)
	SYSTEM.PUTREG(7, 93);				(* E3A07005	MOV   R7,5H *)
	SYSTEM.CODE(SVC);	(* EF000000	SWI	0H *)
	SYSTEM.CODE(BX);	(* E1A0F00E	MOV PC,LR *)
END Ftruncate0;

PROCEDURE UTimensat0*( dirfd, name, utimebuf, flags: LONGINT):LONGINT;
BEGIN
	SYSTEM.CODE(LDMIA4);	(*LDMIA   SP, {R0 R1 R2 } *)
	SYSTEM.PUTREG(7, 348);				(* E3A07005	MOV   R7,5H *)
	SYSTEM.CODE(SVC);	(* EF000000	SWI	0H *)
	SYSTEM.CODE(BX);	(* E1A0F00E	MOV PC,LR *)
END UTimensat0;

PROCEDURE GetTimeOfDay*(tv, tz: LONGINT): LONGINT;
BEGIN
	SYSTEM.CODE(LDMIA2);	(*LDMIA   SP, {R0 R1 R2 } *)
	SYSTEM.PUTREG(7, 78);				(* E3A07005	MOV   R7,5H *)
	SYSTEM.CODE(SVC);	(* EF000000	SWI	0H *)
	SYSTEM.CODE(BX);	(* E1A0F00E	MOV PC,LR *)
END GetTimeOfDay;

PROCEDURE Renameat0*( olddfd, old, newdfd, new, flags: LONGINT): LONGINT;
BEGIN
	SYSTEM.CODE(LDMIA5);	(*LDMIA   SP, {R0 R1 R2 } *)
	SYSTEM.PUTREG(7, 149H);				(* RENAMEAT=149H *)
	SYSTEM.CODE(SVC);	(* EF000000	SWI	0H *)
	SYSTEM.CODE(BX);	(* E1A0F00E	MOV PC,LR *)
END Renameat0;

PROCEDURE UnLinkat0*( dirfd, name, flags: LONGINT): LONGINT;
BEGIN
	SYSTEM.CODE(LDMIA3);	(*LDMIA   SP, {R0 R1 R2 } *)
	SYSTEM.PUTREG(7, 328);				(* E3A07005	MOV   R7,5H *)
	SYSTEM.CODE(SVC);	(* EF000000	SWI	0H *)
	SYSTEM.CODE(BX);	(* E1A0F00E	MOV PC,LR *)
END UnLinkat0;

PROCEDURE Mremap0*( oldaddr, oldsize, newsize, flags, naddr: LONGINT): LONGINT;
(* MREMAP_MAYMOVE=1 *)
BEGIN
	SYSTEM.CODE(LDMIA5);	(*LDMIA   SP, {R0 R1 R2 } *)
	SYSTEM.PUTREG(7, 163);				(* E3A07005	MOV   R7,163 *)
	SYSTEM.CODE(SVC);	(* EF000000	SWI	0H *)
	SYSTEM.CODE(BX);	(* E1A0F00E	MOV PC,LR *)
END Mremap0;

PROCEDURE FStatat0*( dirfd, name, stat, flags: LONGINT): LONGINT;
BEGIN
	SYSTEM.CODE(LDMIA4);	(*LDMIA   SP, {R0 R1 R2 } *)
	SYSTEM.PUTREG(7, 147H);				(* E3A07005	MOV   R7,5H *)
	SYSTEM.CODE(SVC);	(* EF000000	SWI	0H *)
	SYSTEM.CODE(BX);	(* E1A0F00E	MOV PC,LR *)
END FStatat0;

PROCEDURE GetDents0*( fd, bufptr, count: LONGINT): LONGINT;
BEGIN
	SYSTEM.CODE(LDMIA3);	(*LDMIA   SP, {R0 R1 R2 } *)
	SYSTEM.PUTREG(7, 217);				(* E3A07005	MOV   R7,5H *)
	SYSTEM.CODE(SVC);	(* EF000000	SWI	0H *)
	SYSTEM.CODE(BX);	(* E1A0F00E	MOV PC,LR *)
END GetDents0;

PROCEDURE Socket0*( n1, n2, n3: LONGINT): LONGINT;
BEGIN
	SYSTEM.CODE(LDMIA3);	(*LDMIA   SP, {R0 R1 R2 } *)
	SYSTEM.PUTREG(7, 119H);				(* E3A07005	MOV   R7,119H *)
	SYSTEM.CODE(SVC);	(* EF000000	SWI	0H *)
	SYSTEM.CODE(BX);	(* E1A0F00E	MOV PC,LR *)
END Socket0;

PROCEDURE Connect0*( sockfd, servaddr, addrlen: LONGINT): LONGINT;
BEGIN
	SYSTEM.CODE(LDMIA3);	(*LDMIA   SP, {R0 R1 R2 } *)
	SYSTEM.PUTREG(7, 11BH);				(* E3A07005	MOV   R7,5H *)
	SYSTEM.CODE(SVC);	(* EF000000	SWI	0H *)
	SYSTEM.CODE(BX);	(* E1A0F00E	MOV PC,LR *)
END Connect0;

PROCEDURE Shmget0*( key, size, shmflag: LONGINT): LONGINT;
BEGIN
	SYSTEM.CODE(LDMIA3);	(*LDMIA   SP, {R0 R1 R2 } *)
	SYSTEM.PUTREG(7, 133H);				(* E3A07005	MOV   R7,5H *)
	SYSTEM.CODE(SVC);	(* EF000000	SWI	0H *)
	SYSTEM.CODE(BX);	(* E1A0F00E	MOV PC,LR *)
END Shmget0;

PROCEDURE Shmat0*(shmid, addr, flags: LONGINT): LONGINT;
BEGIN
		SYSTEM.CODE(LDMIA3);	(*LDMIA   SP, {R0 R1 R2 } *)
		SYSTEM.PUTREG(7, 131H);				(* E3A07005	MOV   R7,5H *)
		SYSTEM.CODE(SVC);	(* EF000000	SWI	0H *)
		SYSTEM.CODE(BX);	(* E1A0F00E	MOV PC,LR *)
END Shmat0;

PROCEDURE Shmdt0*(addr: LONGINT): LONGINT;
BEGIN
	SYSTEM.CODE(LDMIA1);	(*LDMIA   SP, {R0 R1 R2 } *)
	SYSTEM.PUTREG(7, 132H);				(* E3A07005	MOV   R7,5H *)
	SYSTEM.CODE(SVC);	(* EF000000	SWI	0H *)
	SYSTEM.CODE(BX);	(* E1A0F00E	MOV PC,LR *)
END Shmdt0;

PROCEDURE ShmCtl0*(buf, cmd, shmid: LONGINT): LONGINT;
BEGIN
	SYSTEM.CODE(LDMIA3);	(*LDMIA   SP, {R0 R1 R2 } *)
	SYSTEM.PUTREG(7, 134H);				(* E3A07005	MOV   R7,5H *)
	SYSTEM.CODE(SVC);	(* EF000000	SWI	0H *)
	SYSTEM.CODE(BX);	(* E1A0F00E	MOV PC,LR *)
END ShmCtl0;

PROCEDURE IOCtl0*( d, r1, r2: LONGINT): LONGINT;
BEGIN
	SYSTEM.CODE(LDMIA3);	(*LDMIA   SP, {R0 R1 R2 } *)
	SYSTEM.PUTREG(7, 54);				(* E3A07005	MOV   R7,5H *)
	SYSTEM.CODE(SVC);	(* EF000000	SWI	0H *)
	SYSTEM.CODE(BX);	(* E1A0F00E	MOV PC,LR *)
END IOCtl0;

PROCEDURE Select0*( n, reafds, writefds, execptfds, timeout: LONGINT): LONGINT;
BEGIN
	SYSTEM.CODE(LDMIA5);	(*LDMIA   SP, {R0 R1 R2 } *)
	SYSTEM.PUTREG(7, 142);				(* E3A07005	MOV   R7,5H *)
	SYSTEM.CODE(SVC);	(* EF000000	SWI	0H *)
	SYSTEM.CODE(BX);	(* E1A0F00E	MOV PC,LR *)
END Select0;

PROCEDURE WriteHex(x: LONGINT);
VAR
	buf: ARRAY 10 OF CHAR;
	i, res: LONGINT;
BEGIN
	FOR i := 7 TO 0 BY -1 DO
		buf[i] := CHR(x MOD 10H + 48);
		IF buf[i] > "9" THEN
			buf[i] := CHR(ORD(buf[i]) - 48 + 65 - 10)
		END;
		x := x DIV 10H
	END;
	buf[8] := " ";
	res:=Write0(3, SYSTEM.ADR(buf), 9);
END WriteHex;

(* Linux0.Fixup and  MBootLinker.FixupV are same, don't optimize as in VDecoder.Obj  *)
PROCEDURE Fixup*( VAR code: ARRAY OF LONGINT; entry, L: LONGINT; data: BOOLEAN);	
CONST (* instruction format *)
	BL=0EB000000H;	MOVIA2= 0E3000000H;	MOVT= 0E3400000H;
	IMM12=1000H;	IMM16=10000H;	IMM20= 100000H; IMM24=1000000H;	IMM28=10000000H;
VAR L1, c1, c2: LONGINT;
BEGIN
	IF (entry#0) & (L # 0) THEN
		REPEAT
			L1 := L; c1 := code[L1];
			IF c1 DIV IMM24= BL DIV IMM24 THEN	(* procedure call *)	(* to be fixed in OPL.Exit, adjustLink ? *)
				L := L1 + SYSTEM.LSH( c1, 8) DIV 100H+1;
				code[L1] := BL+ (entry -SYSTEM.ADR(code[L1+2])) DIV 4 MOD IMM24;
			ELSIF c1 DIV IMM20= MOVIA2 DIV IMM20 THEN		(* load, store, adr *)
				L := L1  + SYSTEM.LSH( c1, 16) DIV IMM16 +1;
				c2 := code[L1+1] + entry;
				code[L1] := MOVIA2+ c2 DIV IMM12 MOD 10H *IMM16+ c1 DIV IMM16 MOD 10H * IMM12+ c2 MOD IMM12;
				code[L1+1] := MOVT+ c2 DIV IMM28 MOD 10H *IMM16+ c1 DIV IMM16 MOD 10H * IMM12+ c2 DIV IMM16 MOD IMM12;
			ELSE WriteHex(5); WriteHex( L1); WriteHex( c1); RETURN
			END;
		UNTIL L = L1
	END
END Fixup;

(* ARM *)
PROCEDURE SetSignal*( nr: LONGINT; handler: Proc): LONGINT;
CONST SARESTART= 10000000H;
TYPE
	SigAction = RECORD
		handler: Proc;
		sigaction: LONGINT;
		mask: SET;
		flags, restorer: LONGINT;
	END;
VAR h, d: SigAction;
BEGIN
	h.handler:= handler;
	h.mask:= {};
	h.flags:= SARESTART;
	h.restorer:= 0;
	RETURN SIGAction0( nr, SYSTEM.ADR(h), SYSTEM.ADR(d));
END SetSignal;

PROCEDURE WriteDist( val: LONGINT);
VAR str: ARRAY 16 OF CHAR; res, i: LONGINT;
BEGIN
	str:= "Distance:    ";
	i:=14;
	val:=ABS(val);	(* this proc does not like neg values *)
	REPEAT
		str[i] := CHR(val MOD 10 + 30H); val := val DIV 10; DEC(i)
	UNTIL val = 0;
	str[15]:=0AX;
	res:=Write0(3, SYSTEM.ADR(str), 16);
END WriteDist;

PROCEDURE SignalHandler;
VAR trap, i, j, adr, si: LONGINT; sc: SigContext; ch: CHAR;
BEGIN
	INC( siglevel);
	SYSTEM.GETREG( ARI, trap);	(* trap is 1st parameter *)
	SYSTEM.GETREG( FP, sc);	(* si is 2nd parameter *)
	ch:=0AX;
	i:=Write0(3, SYSTEM.ADR(ch), 1);
	WriteHex( trap);
	WriteHex( SYSTEM.VAL( LONGINT,sc));
	WriteHex( sc.regs[PC]);
	trap:=SigTab[trap];
	WriteHex( trap);
(* only used to get distance from sc to fp; trap with SYSTEM.PUTREG(28, 1236H);
i:=Write0(0, SYSTEM.ADR(ch), 1);
	j:=0;
	REPEAT
		INC(j, 4);
		sc:= SYSTEM.VAL( SigContext, si+j);
		SYSTEM.GET(si+j, i);
		WriteHex( i);
	UNTIL  (j>1200);
(*	UNTIL (sc.regs[28]=1236H) OR (j>1000H);*)
	WriteDist( j);
	Exit0(1);
*)(*
	j:=0;
	REPEAT
		IF j MOD 8 =0 THEN i:=Write0(0, SYSTEM.ADR(ch), 1) END;
		WriteHex(sc.dummy[ j] ); 
		INC(j);
	UNTIL j=LEN(sc.dummy);
i:=Write0(0, SYSTEM.ADR(ch), 1);
*)
(*
	j:=0;
	REPEAT
		IF j MOD 8 =0 THEN i:=Write0(0, SYSTEM.ADR(ch), 1) END;
		regs[ j]:= sc.regs[ j]; WriteHex(sc.regs[j]);
		fpregs[ j]:= sc.fpregs[ j*2 ];
		INC( j);
	UNTIL j=32;
	i:=Write0(0, SYSTEM.ADR(ch), 1);
*)
	IF (trap=13) & inGC THEN break:=TRUE; DEC( siglevel); RETURN END;	(* ctrl-c from terminal  *)
	IF trap= 28 THEN SYSTEM.GET(sc.regs[PC], i);	(* Invalid instruction used as TRAP *)
		IF i DIV 100H= XTRAP DIV 100H THEN trap:= i MOD 100H; IF trap=255 THEN trap:=MAX(INTEGER) END END;
		WriteHex( i);
(*		WriteDist( trap);LOOP END;*)
	END;
	IF (defaulttraphandler # NIL) THEN defaulttraphandler( trap, sc.regs[SP], sc.regs[PC], adr ) END;
	IF inGC THEN (*Halt("Trap in GC", trap);*) Exit0(1); END;
	IF (traphandler # NIL) & (traphandler#defaulttraphandler) THEN traphandler( trap, sc.regs[SP], sc.regs[PC], adr ) END;	(* was: handler |trap 16: Disk full *)
	IF trap=MAX(INTEGER) THEN INC(sc.regs[PC], 4);	(* ! *)
	ELSE
		sc.regs[SP]:= StackOrg;
		sc.regs[FP]:= StackOrg;
		sc.regs[PC]:=SYSTEM.VAL( LONGINT, loop);
		IF loop=NIL THEN Exit0( 1) END;
	END;
	DEC( siglevel);
END SignalHandler;

PROCEDURE InitTrap*;
VAR i, err: LONGINT;
BEGIN
	defaulttraphandler:=NIL;
	siglevel:=0;
	i:=1;
	REPEAT SigTab[i]:=-i; INC( i) UNTIL i=32;
	SigTab[ SIGINT]:= 13;
	SigTab[ SIGFPE]:= 10;
	SigTab[ SIGILL]:= 28;
	SigTab[ SIGSEGV]:= 29;

	err:=SetSignal(SIGINT, SignalHandler);
	err:=SetSignal(SIGILL, SignalHandler);
	err:=SetSignal(SIGFPE, SignalHandler);
	err:=SetSignal(SIGSEGV, SignalHandler);
(*	err:=SetSignal(SIGPIPE, SignalHandler);*)

	err:= SetSignal(SIGCONT, SYSTEM.VAL( Proc, 1));
	err:= SetSignal(SIGCHLD, SYSTEM.VAL( Proc, 1));

END InitTrap;


END Linux0.

