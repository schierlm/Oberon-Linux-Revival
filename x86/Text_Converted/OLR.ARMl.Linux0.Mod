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

MODULE Linux0;	

(* Linux kernel interface for ARM legacy version *)

(* numbers from https://git.linux-mips.org/cgit/ralf/linux.git/tree/arch/arm/include/uapi/asm/unistd.h*)

(*	Peter Matthias
	2015-12-11	split OLR.ARM.Kernel.Mod to OLR.ARMl.Linux0.Mod and OLR.ARM.Kernel.Mod
	2016-04-15	added Exit0 Fork0 Execve0 Waitpid0
	2016-08-06	implemented Openat0, UTimensat0, Renameat0, UnLinkat0, FStatat0, removed Open0, UTimes0, Rename0, UnLink0, Stat0 not teseted

*)

IMPORT SYSTEM;

CONST
	ARCH*="ARM";
	ObjPrefix*="arm/";
	ObjTag*=0F5X;	(* x86: 0AFX; arml: 0F5X; arm: 36FBH; mips: 36F9H; mipst: 36FAH *)
	RegSize*=32;
	PageSize*=1000H;

	(* registers *)
	FP* = 12; SP* = 13; LR* = 14; PC = 15;

	ATFDCWD*=-100;	(* use current directory *)

	(** Open( .. ) flags *)(* same on ARM, MIPS, x86 *)
	ORDonly*= 0;	OWRonly*= 1;	ORDWR*=2;	OCREAT*= 40H;	OEXCL*= 80H;	OTRUNC*= 200H;	OAPPEND*=400H;	ODSYNC*=1000H;
	ODirectory*=0;	(* to be fixed *)
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
	SIGTRAP= 5;		(* HALT( x) *)
	SIGFPE* = 8;		(* DIV 0 *)
	SIGKILL= 9;	(* kill *)
	SIGSEGV= 11;	(* segmentation fault *)
	SIGPIPE= 13;	(* in KDE alt-F4 *)
	SIGALRM= 14;	(* signal  from alarm(1) *)
	SIGTERM = 15;	(* ctrl-alt-del *)
	SIGPROF= 29;
	SIGXCPU= 30;
	SIGXFSZ= 31;

(* ARM: *)
	SIGABRT= 6;
	SIGBUS = 7;	(* unused *)
	SIGUSR1*= 10;	(* used by Display for framebuffer console switching *)
	SIGUSR2*= 12;	(* used by Display for framebuffer console switching *)
	SIGSTKFLT= 16;	(* floating point stack error *)
	SIGCHLD= 17;	(* child quit *)
	SIGCONT= 18;
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
	SigHandler*= PROCEDURE;

	SigCPTR*= POINTER TO SigContext;
	SigContext*=  RECORD
		trapNo, errCode, oldMask: LONGINT;
		r0, r1, r2, r3, r4, r5, r6, r7, r8, r9, ra, rb, fp, sp, lr, pc : LONGINT;
		cpsr, faultAddr, signal2: LONGINT;
	END;

	SigAction* = RECORD
		handler: SigHandler;
		mask: SET;
		flags, restorer: LONGINT;
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

VAR
	regs*, fpregs*: ARRAY 32 OF LONGINT;
	StackOrg* : LONGINT;	(** highest address on stack (single-process system) *)
	break* : BOOLEAN;	(** has ctrl-break been pressed? *)
	inGC*: BOOLEAN;	(** executing inside GC? *)

PROCEDURE Exit0*(status: LONGINT);
CODE
	LDR	R0, [SP],4
	MOV	R7, 1	(* EXIT0 *)
	SWI	0
	MOV	PC, LR
END Exit0;
	
PROCEDURE Fork0*():LONGINT;
CODE
	MOV	R7, 2	(*FORK= 2; VFORK=190 *)
	SWI	0
	MOV	PC, LR
END Fork0;

PROCEDURE Execve0*( filename, argv, envp: LONGINT):LONGINT;
CODE
	LDR	R2, [SP],4
	LDR	R1, [SP],4
	LDR	R0, [SP],4
	MOV	R7, 11	(* EXEXVE= 11 *)
	SWI	0
	MOV	PC, LR
END Execve0;

PROCEDURE Waitpid0*( pid, status, options: LONGINT):LONGINT;
CODE
	LDR	R2, [SP],4
	LDR	R1, [SP],4
	LDR	R0, [SP],4
	MOV	R7, 7	(* WAITPID= 7 *)
	SWI	0
	MOV	PC, LR
END Waitpid0;

PROCEDURE Openat0*( dirfd, name, flags, mode: LONGINT): LONGINT;
CODE
	LDR	R3, [SP],4
	LDR	R2, [SP],4
	LDR	R1, [SP],4
	LDR	R0, [SP],4
	MOV	R7, 140H		(* OPEN=5; OPENAT=142H *)
	ADD	R7, R7, 2
	SWI	0
	MOV	PC, LR
END Openat0;

PROCEDURE Creat0*( name, mode: LONGINT): LONGINT;
CODE
	LDR	R1, [SP],4
	LDR	R0, [SP],4
	MOV	R7, 8		(* CREAT=8 *)
	SWI	0
	MOV	PC, LR
END Creat0;

PROCEDURE Close0*( fd: LONGINT): LONGINT;
CODE
	LDR	R0, [SP],4
	MOV	R7, 6		(* CLOSE= 6 *)
	SWI	0
	MOV	PC, LR
END Close0;

PROCEDURE Read0*( fd, buf, num: LONGINT): LONGINT;
CODE 
	LDR	R2, [SP],4
	LDR	R1, [SP],4
	LDR	R0, [SP],4
	MOV	R7, 3		(* READ= 3 *)
	SWI	0
	MOV	PC, LR
END Read0;

PROCEDURE Readv0*( fd, vect, cnt: LONGINT): LONGINT;
CODE 
	LDR	R2, [SP],4
	LDR	R1, [SP],4
	LDR	R0, [SP],4
	MOV	R7, 145		(* READV= 145 *)
	SWI	0
	MOV	PC, LR
END Readv0;

PROCEDURE Write0*( fd, buf, num: LONGINT): LONGINT;
CODE
	LDR	R2, [SP],4
	LDR	R1, [SP],4
	LDR	R0, [SP],4
	MOV	R7, 4		(* WRITE =4 *)
	SWI	0
	MOV	PC, LR
END Write0;

PROCEDURE Writev0*( fd, vect, cnt: LONGINT): LONGINT;
CODE
	LDR	R2, [SP],4
	LDR	R1, [SP],4
	LDR	R0, [SP],4
	MOV	R7, 146		(* WRITE =146 *)
	SWI	0
	MOV	PC, LR
END Writev0;

PROCEDURE Brk0*( adr: LONGINT):LONGINT;
CODE
	LDR	R0, [SP],4	(* adr into R0 *)
	MOV	R7, 45			(* BRK= 45 *)
	SWI	0
	MOV	PC, LR
END Brk0;

PROCEDURE MProtect0*( adr, len, prot: LONGINT): LONGINT;
(*CONST  MPROTECT= 125;*)
CODE 
	LDR	R2, [SP],4
	LDR	R1, [SP],4
	LDR	R0, [SP],4
	MOV	R7, 125
	SWI	0
	MOV	PC, LR
END MProtect0;

PROCEDURE SigAction0*( signum, act, oldact: LONGINT): LONGINT;
CODE 
	LDR	R2, [SP],4
	LDR	R1, [SP],4
	LDR	R0, [SP],4
	MOV	R7, 67		(* SIGACTION= 67 *)
	SWI	0
	MOV	PC, LR
END SigAction0;

PROCEDURE SetSignal*( nr: LONGINT; handler: SigHandler): LONGINT;
CONST SARESTART= 10000000H;
TYPE
	SigAction = RECORD
		handler: SigHandler;
		mask: SET;
		flags, restorer: LONGINT;
	END;
VAR h, d: SigAction;
BEGIN
	h.handler:= handler;
	h.mask:= {};
	h.flags:= SARESTART;
	h.restorer:= 0;
	RETURN SigAction0( nr, SYSTEM.ADR(h), SYSTEM.ADR(d));
END SetSignal;

PROCEDURE FStat0*( fd, stat: LONGINT): LONGINT;
(*CONST FSTAT= 108; FSTAT64= 197*)
CODE
	LDR	R1, [SP],4
	LDR	R0, [SP],4
	MOV	R7, 197	
	SWI	0
	MOV	PC, LR
END FStat0;

PROCEDURE FStatat0*( dirfd, name, stat, flags: LONGINT): LONGINT;
(*CONST STAT= 106; FSTATAT64=327*)
CODE
	LDR	R3, [SP],4
	LDR	R2, [SP],4
	LDR	R1, [SP],4
	LDR	R0, [SP],4
	MOV	R7, 140H
	ADD	R7, R7, 7	
	SWI	0
	MOV	PC, LR
END FStatat0;

PROCEDURE Mmap20*( adr, len, prot, flags, fd, off: LONGINT): LONGINT;
(*CONST MMAP2= 192;*)
CODE
	LDR	R5, [SP],4
	LDR	R4, [SP],4
	LDR	R3, [SP],4
	LDR	R2, [SP],4
	LDR	R1, [SP],4
	LDR	R0, [SP],4
	MOV	R7, 192
	SWI	0
	MOV	PC, LR
END Mmap20;

PROCEDURE Mremap0*( oldaddr, oldsize, newsize,  flags, naddr: LONGINT): LONGINT;
(* MREMAP_MAYMOVE=1 *)
CODE
	LDR	R4, [SP],4
	LDR	R3, [SP],4
	LDR	R2, [SP],4
	LDR	R1, [SP],4
	LDR	R0, [SP],4
	MOV	R7, 163			(* MREMAP= 163 *)
	SWI	0
	MOV	PC, LR
END Mremap0;

PROCEDURE Munmap0*( start, length: LONGINT): LONGINT;
(*CONST MUNMAP=91;*)
CODE
	LDR	R1, [SP],4
	LDR	R0, [SP],4
	MOV	R7, 91
	SWI	0
	MOV	PC, LR
END Munmap0;

PROCEDURE CacheFlush0*( adr, bytes: LONGINT): LONGINT;
CODE
	LDR	R1, [SP],4
	LDR	R0, [SP],4
	MOV	R7, 0F0000H			(* ARM_NR_cacheflush = 0F0002H *)
	ADD	R1, R1, R0			(* ARM needs beg, end adr *)
	ADD	R7,  R7, 2
	MOV	R2, 0
	SWI	0
	MOV	PC, LR
END CacheFlush0;

(* Files *)

PROCEDURE LSeek0*( fd, pos, whence: LONGINT): LONGINT;
(* CONST LSEEK = 19;*)
CODE
	LDR	R2, [SP],4
	LDR	R1, [SP],4
	LDR	R0, [SP],4
	MOV	R7, 19
	SWI	0
	MOV	PC, LR
END LSeek0;

PROCEDURE FLock0*( fd, arg: LONGINT): LONGINT;
(*CONST FLOCK = 143;*)
CODE
	LDR	R2, [SP],4
	LDR	R1, [SP],4
	LDR	R0, [SP],4
	MOV	R7, 143
	SWI	0
	MOV	PC, LR
END FLock0;

PROCEDURE Select0*( n, readfds, writefds, execptfds, timeout: LONGINT): LONGINT;
(*CONST SELECT= 142;*)
CODE
	LDR	R4, [SP],4
	LDR	R3, [SP],4
	LDR	R2, [SP],4
	LDR	R1, [SP],4
	LDR	R0, [SP],4
	MOV	R7, 142
	SWI	0
	MOV	PC, LR
END Select0;

PROCEDURE Ftruncate0*( fd, len: LONGINT): LONGINT;
(*CONST FTRUNCATE = 93;*)
CODE
	LDR	R1, [SP],4
	LDR	R0, [SP],4
	MOV	R7, 93
	SWI	0
	MOV	PC, LR
END Ftruncate0;

PROCEDURE Renameat0*( olddfd, old, newdfd, new, flags: LONGINT): LONGINT;
CODE
	LDR	R4, [SP],4
	LDR	R3, [SP],4
	LDR	R2, [SP],4
	LDR	R1, [SP],4
	LDR	R0, [SP],4
	MOV	R7, 140H			(* RENAME= 38; RENAMEAT=149H *)
	ADD	R7, R7, 9
	SWI	0
	MOV	PC, LR
END Renameat0;

PROCEDURE UnLinkat0*( dirfd, name, flags: LONGINT): LONGINT;
CODE
	LDR	R2, [SP],4
	LDR	R1, [SP],4
	LDR	R0, [SP], 4
	MOV	R7, 328			(* UNLINK= 10; UNLINKAT=328 *)
	SWI	0
	MOV	PC, LR
END UnLinkat0;

PROCEDURE GetDents0*( fd, dirptr, count: LONGINT): LONGINT;
(* CONST GETDENTS=141; GETDENTS64 = 217 *)
CODE
	LDR	R2, [SP],4
	LDR	R1, [SP],4
	LDR	R0, [SP], 4
	MOV	R7, 217			(* UNLINK= 10; UNLINKAT=328 *)
	SWI	0
	MOV	PC, LR
END GetDents0;

PROCEDURE UTimensat0*( dirfd, name, utimebuf, flags: LONGINT):LONGINT;
(*CONST UTIME= 30; UTIMENSAT=348*)
CODE
	LDR	R3, [SP],4
	LDR	R2, [SP],4
	LDR	R1, [SP],4
	LDR	R0, [SP],4
	MOV	R7, 348
	SWI	0
	MOV	PC, LR
END UTimensat0;

PROCEDURE Socket0*( n1, n2, n3: LONGINT): LONGINT;
CODE 
	LDR	R2, [SP],4
	LDR	R1, [SP],4
	LDR	R0, [SP],4
	MOV	R7, 100H			(* SYSSOCKET= 1 , 198*)
	ADD	R7, R7, 19H
	SWI	0
	MOV	PC, LR
END Socket0;

PROCEDURE Connect0*( sockfd, servaddr, addrlen: LONGINT): LONGINT;
CODE
	LDR	R2, [SP],4
	LDR	R1, [SP],4
	LDR	R0, [SP],4
	MOV	R7, 100H			(* SOCKETCALL= 102 *)
	ADD	R7, R7, 1BH
(*MOV	R0, 3				(* SYSCONNECT= 3 *) *)
	SWI	0
	MOV	PC, LR
END Connect0;

PROCEDURE Shmget0*( key, size, shmflag: LONGINT): LONGINT;
CODE
	LDR	R2, [SP],4
	LDR	R1, [SP],4
	LDR	R0, [SP],4
	MOV	R7, 100H			(* 133H ; shmget=194 *)
	ADD	R7, R7, 33H
	SWI	0
	MOV	PC, LR
END Shmget0;

PROCEDURE Shmat0*(shmid, addr, flags: LONGINT): LONGINT;
CODE
	LDR	R2, [SP],4
	LDR	R1, [SP],4
	LDR	R0, [SP],4
	MOV	R7, 100H			(* 131H shmat=196 *)
	ADD	R7, R7, 31H
	SWI	0
	MOV	PC, LR
END Shmat0;

PROCEDURE Shmdt0*(addr: LONGINT): LONGINT;
CODE
	LDR	R0, [SP],4
	MOV	R7, 100H			(* 132H shmdt=197 *)
	ADD	R7, R7, 32H
	SWI	0
	MOV	PC, LR
END Shmdt0;

PROCEDURE ShmCtl0*(shmid, cmd, buf: LONGINT): LONGINT;
CODE
	LDR	R2, [SP],4
	LDR	R1, [SP],4
	LDR	R0, [SP],4
	MOV	R7, 134H			(* 134H shmctl=196 *)
	SWI	0
	MOV	PC, LR
END ShmCtl0;

PROCEDURE IOCtl0*( d, r1, r2: LONGINT): LONGINT;
CODE
	LDR	R2, [SP],4
	LDR	R1, [SP],4
	LDR	R0, [SP],4
	MOV	R7, 54			(* ioctl=54 *)
	SWI	0
	MOV	PC, LR
END IOCtl0;

PROCEDURE GetTimeOfDay*(tv, tz: LONGINT): LONGINT;
CODE
	LDR	R1, [SP],4
	LDR	R0, [SP],4
	MOV	R7, 78			(* TIME = 13 *)
	SWI	0
	MOV	PC, LR
END GetTimeOfDay;

(*
PROCEDURE fesetround*;	(* set rounding mode; will fail on cpus without VFP; changing rounding mode permanently has side effects, don't use it *)
CODE
	DCD	0EEF10A10H	(* vmrs	r0, fpscr *)
	BIC	R0, R0, 0C00000H	(* clear RMode bits *)
	ORR	R0, R0, 0800000H	(* set round towards  minus infinity bits*)
	DCD	0EEE10A10H	(* vmsr	fpscr, r0 *)
	MOV	PC, LR
END fesetround;
*)

END Linux0.

