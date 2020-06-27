MODULE Linux0;	(* rc/ard/nm/jm/devil/pjm/rml*)

(*  Kernel interface for MIPS 32  *)

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

(*	Peter Matthias
	2015-12-09	split OLR.Kernel.Mod to OLR.ARM.Linux0.Mod and OLR.MIPS.Linux0.Mod
	2016-04-07	OLR.MIPS.Linux0.Mod: Fixed Open flags
	2016-04-07	OLR.*.Linux0.Mod: added ODSYNC* open flag
	2016-04-15	added Exit0 Fork0 Execve0 Waitpid0
	2016-08-06	implemented Openat0, UTimensat0, Renameat0, UnLinkat0, FStatat0, removed Open0, UTime0, Rename0, UnLink0, Stat0 not teseted
	2016-10-11	using rt_sigaction

ToDo: MIPS: save r7 during syscall

	SetClock not implemented ( only superuser can change time)
	reboot does not work
	
Wrapper Procedure for SYSCALL:

PROCEDURE SysCall( a, b, c, d, e, f, g: LONGINT): LONGINT;
BEGIN
	SYSTEM.PUTREG( 2, 4009);				(* Syscall nr to R2 *)
	SYSTEM.CODE( 12);							(* SYSCALL *)
	SYSTEM.CODE( 10070004H);			(* BEQ R7, R0, +16*)
	SYSTEM.CODE( 0);							(* NOP , branch delay slot*)	(*  MOVZ/MOVN would not be faster *)
	SYSTEM.CODE( 10000002H);				(* B +8 *)
	SYSTEM.CODE( 00021022H);				(* SUB R2, 0, R2, branch delay slot	*)
END SysCall;

Error is in R7.

*)

IMPORT SYSTEM;

CONST
	ARCH*="MIPS";
	ObjPrefix*="mips/";
	ObjTag*=36F9H;	(* x86: 0AFX; arml: 0F5X; arm: 36FBH; mips: 36F9H; mipst: 36FAH *)
	RegSize*=32;
	PageSize*=1000H;

	(* registers for MIPS *)
	SP*=29; FP*=30; LR*=31; ARI*=4;	XTRAP*=0; (* dummy *)

	ATFDCWD*=-100;	(* use current directory *)

	(** Open( .. ) flags *)	(* old values: OCREAT*= 100H;	OEXCL*= 400H;	OAPPEND*=8H; *)(* same on ARM, MIPS, x86 *)
	ORDonly*= 0;	OWRonly*= 1;	ORDWR*=2;	OCREAT*= 100H;(* was 40H *)	OEXCL*= 80H;	OTRUNC*= 200H;	OAPPEND*=400H;	ODSYNC*=1000H;
	ODirectory*=0;
	(** FLock( .. ) *)
	LOCKEX*= 2;	LOCKNB*= 4;	LOCKUN*= 8;
	(** LSeek *)
	SEEKSET*=0;	SEEKCURRENT*=1;	SEEKEND*=2;
	(** Mmap *)
	MAPSHARED*=1; MAPPRIVATE*=2; MAPANONYMOUS*=800H;	(* ARM: 20H; MIPS: 800H *)

(*	PROTEXEC= PROTREAD=1	; PROTWRITE=2	PROTNONE=	*)

	(* Termios used in Input (FB) *)
(* MIPS *)
	VMIN*=4;
	TCGETS*= 540DH;
	TCSETSF*=5410H;

	(** Socket *)
	SOCKSTREAM*=2;		(* was 1 for X86 and ARM, 2 for MIPS *)

(* Common *)
	SIGHUP= 1;		(* Hang up ; X11 quits *)
	SIGINT*= 2;			(* interrupt	 ctrl-c *)
	SIGQUIT= 3;		(* quit	ctrl-# , ctrl-4 ?, PrintScreen? *)
	SIGILL* = 4;			(* invalid instruction ?*)
	SIGTRAP*= 5;		(* HALT( x) *)
	SIGFPE* = 8;		(* DIV 0 *)
	SIGKILL= 9;	(* kill *)
	SIGSEGV*= 11;	(* segmentation fault *)
	SIGPIPE= 13;	(* in KDE alt-F4 *)
	SIGALRM= 14;	(* signal  from alarm(1) *)
	SIGTERM = 15;	(* ctrl-alt-del *)
	SIGPROF= 29;
	SIGXCPU= 30;
	SIGXFSZ= 31;

	SIGIOT= 6;
	SIGEMT = 7;	(* unused *)
	SIGBUS= 10;	(*  *)
	SIGSYS= 12;	(* used by DisplayLinuxFB for console switching *)
	SIGUSR1*= 16;	(* floating point stack error *)
	SIGUSR2*= 17;	(* child quit *)
	SIGCHLD*= 18;
	SIGPWR= 19;
	SIGWINCH= 20;		(* tty stop *)
	SIGURG= 21;		(* tty *)
	SIGIO= 22;	(* tty *)
	SIGSTOP= 23;	(* io error *)
	SIGTSTP= 24;	(* cpu time limit *)
	SIGCONT*= 25;	(* file size limit *)
	SIGTTIN= 26;	(* virtual alarm ?? *)
	SIGTTOU= 27;	(* profile signal *)
	SIGVTALRM= 28;	(* window changed *)

	RegDist*=2; (* SigContext reg distance is 64 bit *)

TYPE
	Proc*= PROCEDURE;
	TrapHandler* = PROCEDURE ( trap, fp, pc, page: LONGINT);

(* MIPS *)
	SigContext*= POINTER TO RECORD
		dummy: ARRAY 6 OF LONGINT;
		sp, signal*, pc*, pch: LONGINT;		(* regmask and status is unused, store sp and signal there... *)
		regs*: ARRAY 64 OF LONGINT;
		fpregs*: ARRAY 64 OF LONGINT;
		acx, fpccsr, fpceir, usedmath, dsp: LONGINT;
		mdhil, mdhih, mdlol, mdloh: LONGINT;
		hi1, lo1, hi2, lo2, hi3, lo3: LONGINT;		(* hi1 might be sc_cause, lo1 sc_badvaddr	*)
	END;
	SigInfo*= POINTER TO RECORD
		signo*, errno*, code*,  adr*, instr*: LONGINT;
	END;

	Status* = RECORD
		stdev, a2, a3, a4: LONGINT;
		b1, b2, b3, b4: LONGINT;
		c1, c2, c3, c4: LONGINT;
		d1, d2, size*, d4: LONGINT;
		atime*, atimens, 
		mtime*, mtimens, 
		ctime*, ctimens, blksize*, f4: LONGINT;
		g1, g2, g3, g4: LONGINT; 
	END;

	SockAddrUn*= RECORD
		pf*: INTEGER;
		path*: ARRAY 64 OF CHAR;	(* was 30 for MIPS; 64 for ARM *)
	END;

VAR
	Regs*: ARRAY 64 OF LONGINT;
	FRegs*: ARRAY 64 OF LONGINT;

(* standard code procedure does not work as it affects stack and registers:
PROCEDURE- SysCallProcEpilog 12, 0, 0, 0, 2, 0, 7, 16, 0, 0, 0, 0, 22H, 16, 2, 0;
*)

PROCEDURE Exit0*(status: LONGINT);
BEGIN
	SYSTEM.PUTREG( 2, 4001);				(* Syscall nr to R2 EXECVE *)
	SYSTEM.CODE( 12);							(* SYSCALL *)
	SYSTEM.CODE( 10070002H);			(* BEQ R7, R0, +8*)
	SYSTEM.CODE( 0);							(* NOP , branch delay slot*)
	SYSTEM.CODE( 00021022H);				(* SUB R2, 0, R2, branch delay slot	*)
END Exit0;
	
PROCEDURE Fork0*():LONGINT;
CONST FORK= 2; VFORK=190;
BEGIN
	SYSTEM.PUTREG( 2, 4002);				(* Syscall nr to R2 EXECVE *)
	SYSTEM.CODE( 12);							(* SYSCALL *)
	SYSTEM.CODE( 10070004H);			(* BEQ R7, R0, +16*)
	SYSTEM.CODE( 0);							(* NOP , branch delay slot*)
	SYSTEM.CODE( 10000002H);				(* B +8 *)
	SYSTEM.CODE( 00021022H);				(* SUB R2, 0, R2, branch delay slot	*)
END Fork0;

PROCEDURE Execve0*( filename, argv, envp: LONGINT):LONGINT;
CONST EXECVE= 11 ;
BEGIN
	SYSTEM.PUTREG( 2, 4011);				(* Syscall nr to R2 EXECVE *)
	SYSTEM.CODE( 12);							(* SYSCALL *)
	SYSTEM.CODE( 10070004H);			(* BEQ R7, R0, +16*)
	SYSTEM.CODE( 0);							(* NOP , branch delay slot*)
	SYSTEM.CODE( 10000002H);				(* B +8 *)
	SYSTEM.CODE( 00021022H);				(* SUB R2, 0, R2, branch delay slot	*)
END Execve0;

PROCEDURE Waitpid0*( pid, status, options: LONGINT):LONGINT;
CONST WAITPID= 7 ;
BEGIN
	SYSTEM.PUTREG( 2, 4007);				(* Syscall nr to R2 WAITPID *)
	SYSTEM.CODE( 12);							(* SYSCALL *)
	SYSTEM.CODE( 10070004H);			(* BEQ R7, R0, +16*)
	SYSTEM.CODE( 0);							(* NOP , branch delay slot*)
	SYSTEM.CODE( 10000002H);				(* B +8 *)
	SYSTEM.CODE( 00021022H);				(* SUB R2, 0, R2, branch delay slot	*)
END Waitpid0;
(*
PROCEDURE Open0*( name, flags, mode: LONGINT): LONGINT;
BEGIN
	SYSTEM.PUTREG( 2, 4005);				(* Syscall nr to R2 *)
	SYSTEM.CODE( 12);							(* SYSCALL *)
	SYSTEM.CODE( 10070004H);			(* BEQ R7, R0, +16*)
	SYSTEM.CODE( 0);							(* NOP , branch delay slot*)
	SYSTEM.CODE( 10000002H);				(* B +8 *)
	SYSTEM.CODE( 00021022H);				(* SUB R2, 0, R2, branch delay slot	*)
END Open0;
*)
PROCEDURE Openat0*( dfd, name, flags, mode: LONGINT): LONGINT;
BEGIN
	SYSTEM.PUTREG( 2, 4288);				(* Syscall nr to R2 *)
	SYSTEM.CODE( 12);							(* SYSCALL *)
	SYSTEM.CODE( 10070004H);			(* BEQ R7, R0, +16*)
	SYSTEM.CODE( 0);							(* NOP , branch delay slot*)
	SYSTEM.CODE( 10000002H);				(* B +8 *)
	SYSTEM.CODE( 00021022H);				(* SUB R2, 0, R2, branch delay slot	*)
END Openat0;

PROCEDURE Close0*( fd: LONGINT): LONGINT;
BEGIN
	SYSTEM.PUTREG( 2, 4006);				(* close *)
	SYSTEM.CODE( 12);							(* SYSCALL *)
	SYSTEM.CODE( 10070004H);			(* BEQ R7, R0, +16*)
	SYSTEM.CODE( 0);							(* NOP , branch delay slot*)
	SYSTEM.CODE( 10000002H);				(* B +8 *)
	SYSTEM.CODE( 00021022H);				(* SUB R2, 0, R2, branch delay slot	*)
END Close0;

PROCEDURE Read0*( fd, buf, num: LONGINT): LONGINT;
BEGIN
	SYSTEM.PUTREG( 2, 4003);				(* Syscall nr to R2 *)
	SYSTEM.CODE( 12);							(* SYSCALL *)
	SYSTEM.CODE( 10070004H);			(* BEQ R7, R0, +16*)
	SYSTEM.CODE( 0);							(* NOP , branch delay slot*)
	SYSTEM.CODE( 10000002H);				(* B +8 *)
	SYSTEM.CODE( 00021022H);				(* SUB R2, 0, R2, branch delay slot	*)
END Read0;

PROCEDURE Readv0*( fd, vect, cnt: LONGINT): LONGINT;
BEGIN
	SYSTEM.PUTREG( 2, 4145);				(* Syscall nr to R2 *)
	SYSTEM.CODE( 12);							(* SYSCALL *)
	SYSTEM.CODE( 10070004H);			(* BEQ R7, R0, +16*)
	SYSTEM.CODE( 0);							(* NOP , branch delay slot*)
	SYSTEM.CODE( 10000002H);				(* B +8 *)
	SYSTEM.CODE( 00021022H);				(* SUB R2, 0, R2, branch delay slot	*)
END Readv0;

PROCEDURE Write0*( fd, buf, num: LONGINT): LONGINT;	
BEGIN
	SYSTEM.PUTREG( 2, 4004);		(* write *)
	SYSTEM.CODE( 12);							(* SYSCALL *)
	SYSTEM.CODE( 10070004H);			(* BEQ R7, R0, +16*)
	SYSTEM.CODE( 0);							(* NOP , branch delay slot*)
	SYSTEM.CODE( 10000002H);				(* B +8 *)
	SYSTEM.CODE( 00021022H);				(* SUB R2, 0, R2, branch delay slot	*)
END Write0;

PROCEDURE Writev0*( fd, vect, cnt: LONGINT): LONGINT;	
BEGIN
	SYSTEM.PUTREG( 2, 4146);		(* writev *)
	SYSTEM.CODE( 12);							(* SYSCALL *)
	SYSTEM.CODE( 10070004H);			(* BEQ R7, R0, +16*)
	SYSTEM.CODE( 0);							(* NOP , branch delay slot*)
	SYSTEM.CODE( 10000002H);				(* B +8 *)
	SYSTEM.CODE( 00021022H);				(* SUB R2, 0, R2, branch delay slot	*)
END Writev0;

PROCEDURE Brk0*( adr: LONGINT):LONGINT;
BEGIN
	SYSTEM.PUTREG( 2, 4045);		(* brk *)
	SYSTEM.CODE( 12);							(* SYSCALL *)
	SYSTEM.CODE( 10070004H);			(* BEQ R7, R0, +16*)
	SYSTEM.CODE( 0);							(* NOP , branch delay slot*)
	SYSTEM.CODE( 10000002H);				(* B +8 *)
	SYSTEM.CODE( 00021022H);				(* SUB R2, 0, R2, branch delay slot	*)
END Brk0;

(* use Open(.., Linux0.RDWR+Linux0.OCREAT+Linux0.OTRUNC, ...) 
PROCEDURE Creat0*( name, mode: LONGINT): LONGINT;
BEGIN
	SYSTEM.PUTREG( 2, 4008);		(* creat *)
	SYSTEM.CODE( 12);							(* SYSCALL *)
	SYSTEM.CODE( 10070004H);			(* BEQ R7, R0, +16*)
	SYSTEM.CODE( 0);							(* NOP , branch delay slot*)
	SYSTEM.CODE( 10000002H);				(* B +8 *)
	SYSTEM.CODE( 00021022H);				(* SUB R2, 0, R2, branch delay slot	*)
END Creat0;
*)

PROCEDURE MProtect0*( adr, len, prot: LONGINT): LONGINT;
BEGIN
	SYSTEM.PUTREG( 2, 4125);		(* mprotect *)
	SYSTEM.CODE( 12);							(* SYSCALL *)
	SYSTEM.CODE( 10070004H);			(* BEQ R7, R0, +16*)
	SYSTEM.CODE( 0);							(* NOP , branch delay slot*)
	SYSTEM.CODE( 10000002H);				(* B +8 *)
	SYSTEM.CODE( 00021022H);				(* SUB R2, 0, R2, branch delay slot	*)
END MProtect0;

PROCEDURE SIGAction0( signum, act, oldact: LONGINT): LONGINT;	
BEGIN
	SYSTEM.PUTREG( 2, 4067);		(* rt_sigaction=4194, sigaction= 4067*)
	SYSTEM.CODE( 12);							(* SYSCALL *)
	SYSTEM.CODE( 10070004H);			(* BEQ R7, R0, +16*)
	SYSTEM.CODE( 0);							(* NOP , branch delay slot*)
	SYSTEM.CODE( 10000002H);				(* B +8 *)
	SYSTEM.CODE( 00021022H);				(* SUB R2, 0, R2, branch delay slot	*)
END SIGAction0;

PROCEDURE FStat0*( fd, stat: LONGINT): LONGINT;
BEGIN
	SYSTEM.PUTREG( 2, 4215);				(* 4108 Syscall nr to R2 fxstat*)
	SYSTEM.CODE( 12);							(* SYSCALL *)
	SYSTEM.CODE( 10070004H);			(* BEQ R7, R0, +16*)
	SYSTEM.CODE( 0);							(* NOP , branch delay slot*)
	SYSTEM.CODE( 10000002H);				(* B +8 *)
	SYSTEM.CODE( 00021022H);				(* SUB R2, 0, R2, branch delay slot	*)
END FStat0;

PROCEDURE Mmap20*( addr, len, prot, flags, fd, off: LONGINT):LONGINT;
BEGIN
	SYSTEM.PUTREG( 2, 4090);				(* Syscall nr to R2 mmap64: 4210, mmap: 4090*)
	SYSTEM.CODE( 12);							(* SYSCALL *)
	SYSTEM.CODE( 10070004H);			(* BEQ R7, R0, +16*)
	SYSTEM.CODE( 0);							(* NOP , branch delay slot*)
	SYSTEM.CODE( 10000002H);				(* B +8 *)
	SYSTEM.CODE( 00021022H);				(* SUB R2, 0, R2, branch delay slot	*)
END Mmap20;

PROCEDURE Munmap0*( addr, len: LONGINT): LONGINT;
BEGIN
	SYSTEM.PUTREG( 2, 4091);				(* Syscall nr to R2 *)
	SYSTEM.CODE( 12);							(* SYSCALL *)
	SYSTEM.CODE( 10070004H);			(* BEQ R7, R0, +16*)
	SYSTEM.CODE( 0);							(* NOP , branch delay slot*)
	SYSTEM.CODE( 10000002H);				(* B +8 *)
	SYSTEM.CODE( 00021022H);				(* SUB R2, 0, R2, branch delay slot	*)
END Munmap0;

PROCEDURE CacheFlush0*( adr, bytes: LONGINT): LONGINT;
BEGIN
	SYSTEM.PUTREG( 2, 4147);
	SYSTEM.PUTREG( 6, 3);					(* third argument always 3 *)
	SYSTEM.CODE( 12);							(* SYSCALL *)
	SYSTEM.CODE( 10070004H);			(* BEQ R7, R0, +16*)
	SYSTEM.CODE( 0);							(* NOP , branch delay slot*)
	SYSTEM.CODE( 10000002H);				(* B +8 *)
	SYSTEM.CODE( 00021022H);				(* SUB R2, 0, R2, branch delay slot	*)
END CacheFlush0;

(* Files *)
PROCEDURE LSeek0*( fd, pos, whence: LONGINT): LONGINT;
BEGIN
	SYSTEM.PUTREG( 2, 4019);				(* Syscall nr to R2 *)
	SYSTEM.CODE( 12);							(* SYSCALL *)
	SYSTEM.CODE( 10070004H);			(* BEQ R7, R0, +16*)
	SYSTEM.CODE( 0);							(* NOP , branch delay slot*)
	SYSTEM.CODE( 10000002H);				(* B +8 *)
	SYSTEM.CODE( 00021022H);				(* SUB R2, 0, R2, branch delay slot	*)
END LSeek0;

PROCEDURE FLock0*( fd, arg: LONGINT): LONGINT;
BEGIN
	SYSTEM.PUTREG( 2, 4143);				(* Syscall nr to R2 *)
	SYSTEM.CODE( 12);							(* SYSCALL *)
	SYSTEM.CODE( 10070004H);			(* BEQ R7, R0, +16*)
	SYSTEM.CODE( 0);							(* NOP , branch delay slot*)
	SYSTEM.CODE( 10000002H);				(* B +8 *)
	SYSTEM.CODE( 00021022H);				(* SUB R2, 0, R2, branch delay slot	*)
END FLock0;

PROCEDURE Ftruncate0*( fd, len: LONGINT): LONGINT;
BEGIN
	SYSTEM.PUTREG( 2, 4093);				(* Syscall nr to R2 *)
	SYSTEM.CODE( 12);							(* SYSCALL *)
	SYSTEM.CODE( 10070004H);			(* BEQ R7, R0, +16*)
	SYSTEM.CODE( 0);							(* NOP , branch delay slot*)
	SYSTEM.CODE( 10000002H);				(* B +8 *)
	SYSTEM.CODE( 00021022H);				(* SUB R2, 0, R2, branch delay slot	*)
END Ftruncate0;
(*
PROCEDURE UTime0*( name, utimebuf: LONGINT):LONGINT;
BEGIN
	SYSTEM.PUTREG( 2, 4030);				(* Syscall nr to R2 *)
	SYSTEM.CODE( 12);							(* SYSCALL *)
	SYSTEM.CODE( 10070004H);			(* BEQ R7, R0, +16*)
	SYSTEM.CODE( 0);							(* NOP , branch delay slot*)
	SYSTEM.CODE( 10000002H);				(* B +8 *)
	SYSTEM.CODE( 00021022H);				(* SUB R2, 0, R2, branch delay slot	*)
END UTime0;
*)

PROCEDURE UTimensat0*( dirfd, name, utimebuf, flags: LONGINT):LONGINT;
BEGIN
	SYSTEM.PUTREG( 2, 4316);				(* Syscall nr to R2 *)
	SYSTEM.CODE( 12);							(* SYSCALL *)
	SYSTEM.CODE( 10070004H);			(* BEQ R7, R0, +16*)
	SYSTEM.CODE( 0);							(* NOP , branch delay slot*)
	SYSTEM.CODE( 10000002H);				(* B +8 *)
	SYSTEM.CODE( 00021022H);				(* SUB R2, 0, R2, branch delay slot	*)
END UTimensat0;


PROCEDURE GetTimeOfDay*(tv, tz: LONGINT): LONGINT;
BEGIN
	SYSTEM.PUTREG( 2, 4078);	(* GETTIMEOFDAY= 4078; TIME = 13 *)
	SYSTEM.CODE( 12);							(* SYSCALL *)
	SYSTEM.CODE( 10070004H);			(* BEQ R7, R0, +16*)
	SYSTEM.CODE( 0);							(* NOP , branch delay slot*)
	SYSTEM.CODE( 10000002H);				(* B +8 *)
	SYSTEM.CODE( 00021022H);				(* SUB R2, 0, R2, branch delay slot	*)
END GetTimeOfDay;

PROCEDURE Renameat0*( olddfd, old, newdfd, new, flags: LONGINT): LONGINT;
BEGIN
	SYSTEM.PUTREG( 2, 4295);				(* Syscall nr to R2 *)
	SYSTEM.CODE( 12);							(* SYSCALL *)
	SYSTEM.CODE( 10070004H);			(* BEQ R7, R0, +16*)
	SYSTEM.CODE( 0);							(* NOP , branch delay slot*)
	SYSTEM.CODE( 10000002H);				(* B +8 *)
	SYSTEM.CODE( 00021022H);				(* SUB R2, 0, R2, branch delay slot	*)
END Renameat0;

PROCEDURE UnLinkat0*( dirfd, name, flags: LONGINT): LONGINT;
BEGIN
	SYSTEM.PUTREG( 2, 4294);				(* Syscall nr to R2 *)
	SYSTEM.CODE( 12);							(* SYSCALL *)
	SYSTEM.CODE( 10070004H);			(* BEQ R7, R0, +16*)
	SYSTEM.CODE( 0);							(* NOP , branch delay slot*)
	SYSTEM.CODE( 10000002H);				(* B +8 *)
	SYSTEM.CODE( 00021022H);				(* SUB R2, 0, R2, branch delay slot	*)
END UnLinkat0;

PROCEDURE Mremap0*( oldaddr, oldsize, newsize, flags, naddr: LONGINT): LONGINT;
(* MREMAP_MAYMOVE=1 *)
BEGIN
	SYSTEM.PUTREG( 2, 4167);				(* Syscall nr to R2 *)
	SYSTEM.CODE( 12);							(* SYSCALL *)
	SYSTEM.CODE( 10070004H);			(* BEQ R7, R0, +16*)
	SYSTEM.CODE( 0);							(* NOP , branch delay slot*)
	SYSTEM.CODE( 10000002H);				(* B +8 *)
	SYSTEM.CODE( 00021022H);				(* SUB R2, 0, R2, branch delay slot	*)
END Mremap0;

PROCEDURE FStatat0*( dirfd, name, stat, flags: LONGINT): LONGINT;
BEGIN
	SYSTEM.PUTREG( 2, 4293);				(* Syscall nr to R2 xstat *)
	SYSTEM.CODE( 12);							(* SYSCALL *)
	SYSTEM.CODE( 10070004H);			(* BEQ R7, R0, +16*)
	SYSTEM.CODE( 0);							(* NOP , branch delay slot*)
	SYSTEM.CODE( 10000002H);				(* B +8 *)
	SYSTEM.CODE( 00021022H);				(* SUB R2, 0, R2, branch delay slot	*)
END FStatat0;

PROCEDURE GetDents0*( fd, bufptr, count: LONGINT): LONGINT;
CONST GETDENTS=4141; GETDENTS64=4219;
BEGIN
	SYSTEM.PUTREG( 2, GETDENTS64);				(* was 4141; Syscall nr to R2 *)
	SYSTEM.CODE( 12);							(* SYSCALL *)
	SYSTEM.CODE( 10070004H);			(* BEQ R7, R0, +16*)
	SYSTEM.CODE( 0);							(* NOP , branch delay slot*)
	SYSTEM.CODE( 10000002H);				(* B +8 *)
	SYSTEM.CODE( 00021022H);				(* SUB R2, 0, R2, branch delay slot	*)
END GetDents0;

PROCEDURE Socket0*( n1, n2, n3: LONGINT): LONGINT;
BEGIN
	SYSTEM.PUTREG( 2, 4183);				(* Syscall nr to R2 *)
	SYSTEM.CODE( 12);							(* SYSCALL *)
	SYSTEM.CODE( 10070004H);			(* BEQ R7, R0, +16*)
	SYSTEM.CODE( 0);							(* NOP , branch delay slot*)
	SYSTEM.CODE( 10000002H);				(* B +8 *)
	SYSTEM.CODE( 00021022H);				(* SUB R2, 0, R2, branch delay slot	*)
END Socket0;

PROCEDURE Connect0*( sockfd, servaddr, addrlen: LONGINT): LONGINT;
BEGIN
	SYSTEM.PUTREG( 2, 4170);				(* Syscall nr to R2 *)
	SYSTEM.CODE( 12);							(* SYSCALL *)
	SYSTEM.CODE( 10070004H);			(* BEQ R7, R0, +16*)
	SYSTEM.CODE( 0);							(* NOP , branch delay slot*)
	SYSTEM.CODE( 10000002H);				(* B +8 *)
	SYSTEM.CODE( 00021022H);				(* SUB R2, 0, R2, branch delay slot	*)
END Connect0;

PROCEDURE Ipc0( call, first, second, third, ptr, fifth: LONGINT): LONGINT;
BEGIN
	SYSTEM.PUTREG( 2, 4117);				(* Syscall nr to R2 *)
	SYSTEM.CODE( 12);							(* SYSCALL *)
	SYSTEM.CODE( 10070004H);			(* BEQ R7, R0, +16*)
	SYSTEM.CODE( 0);							(* NOP , branch delay slot*)
	SYSTEM.CODE( 10000002H);				(* B +8 *)
	SYSTEM.CODE( 00021022H);				(* SUB R2, 0, R2, branch delay slot	*)
END Ipc0;

PROCEDURE Shmget0*( key, size, shmflag: LONGINT): LONGINT;
BEGIN
	RETURN Ipc0( 23, key, size, shmflag, 0, 0);
END Shmget0;

PROCEDURE Shmat0*(shmid, addr, flags: LONGINT): LONGINT;
VAR res: LONGINT;
BEGIN
	res:= Ipc0( 21, shmid, flags, SYSTEM.ADR(addr), addr,  0);
	RETURN addr;
END Shmat0;

PROCEDURE Shmdt0*(addr: LONGINT): LONGINT;
BEGIN
	RETURN Ipc0( 22, 0, 0, 0, addr, 0);
END Shmdt0;

PROCEDURE ShmCtl0*(buf, cmd, shmid: LONGINT): LONGINT;
BEGIN
	RETURN Ipc0( 24, buf, SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET,cmd)+{8}), 0, shmid, 0);
END ShmCtl0;

PROCEDURE IOCtl0*( d, r1, r2: LONGINT): LONGINT;
BEGIN
	SYSTEM.PUTREG( 2, 4054);				(* Syscall nr to R2 *)
	SYSTEM.CODE( 12);							(* SYSCALL *)
	SYSTEM.CODE( 10070004H);			(* BEQ R7, R0, +16*)
	SYSTEM.CODE( 0);							(* NOP , branch delay slot*)
	SYSTEM.CODE( 10000002H);				(* B +8 *)
	SYSTEM.CODE( 00021022H);				(* SUB R2, 0, R2, branch delay slot	*)
END IOCtl0;

PROCEDURE Select0*( n, reafds, writefds, execptfds, timeout: LONGINT): LONGINT;
BEGIN
	SYSTEM.PUTREG( 2, 4142);				(* Syscall nr to R2 *)
	SYSTEM.CODE( 12);							(* SYSCALL *)
	SYSTEM.CODE( 10070004H);			(* BEQ R7, R0, +16*)
	SYSTEM.CODE( 0);							(* NOP , branch delay slot*)
	SYSTEM.CODE( 10000002H);				(* B +8 *)
	SYSTEM.CODE( 00021022H);				(* SUB R2, 0, R2, branch delay slot	*)
END Select0;

PROCEDURE Fixup*(base, entry, L: LONGINT; data: BOOLEAN);
CONST	(* instruction format *)
	OP = 04000000H; JAL = 0C000000H; LUI = 03C000000H;
	RS = 200000H; RT = 10000H; IMM = 10000H; 
VAR L1, c1, c2: LONGINT;
BEGIN
	IF L # 0 THEN
		REPEAT
			L1 := L; SYSTEM.GET( base+L1*4, c1);
			L := L1 + ASH(SYSTEM.LSH(c1, 16), -16) + 1;
			IF data THEN
				SYSTEM.GET( base+L1*4+4, c2); INC(c2, entry);
				SYSTEM.PUT(base+L1*4,   LUI + RT*((c1 DIV RS) MOD 32) + (c2 DIV IMM) MOD IMM + ASH(c2, -15) MOD 2);	(* Load/Store is sign extended *)
				SYSTEM.PUT(base+L1*4+4,  (c1 DIV IMM) * IMM + c2 MOD IMM);
			ELSE	(* procedure *)
				IF c1 DIV OP = LUI DIV OP THEN 	(* proc var *)
					SYSTEM.PUT( base+L1*4, (c1 DIV IMM) * IMM + (entry DIV IMM) MOD IMM);	(* IMM part is not sign extended *)
					SYSTEM.GET( base+L1*4+4, c2); 
					SYSTEM.PUT( base+L1*4+4, (c2)+entry MOD IMM); 
(*					INC(code[L1 + 1], entry MOD IMM);	*)
				ELSE	(* external call, (c1 DIV OP) * OP = JAL *)
					(*
					IF (S.ADR(m.code[L1]) DIV 10000000H) # (procadr DIV 10000000H) THEN
						JAL over 256MB block boundary
					END ;
					*)
					SYSTEM.PUT( base+L1*4, JAL + (entry DIV 4) MOD OP);
				END
			END
		UNTIL L = L1
	END
END Fixup;

(* MIPS*)
PROCEDURE SetSignal*( nr: LONGINT; handler: Proc): LONGINT;
CONST SARESTART= 10000000H;
TYPE
	SigAction = RECORD
		flags: SET;
		handler: Proc;
		mask: SET;
	END;
VAR h: SigAction;
BEGIN
	h.flags:= {3};	(* SA_SIGINFO *)
	h.handler:= handler;
	h.mask:= {};
	RETURN SIGAction0( nr, SYSTEM.ADR(h), 0);
END SetSignal;

(*
PROCEDURE SignalHandler;	(* adr @224 *)
VAR trap, i, j: LONGINT; sc: SigContext; ch: CHAR; si: SigInfo;	(* adjust distance when size of vars changed *)
BEGIN
	INC( siglevel);
	SYSTEM.GETREG( ARI, trap);	(* trap is 1st parameter *)
	SYSTEM.GETREG( ARI+1, si);	(* si is 2nd parameter of handler *)
	SYSTEM.GETREG( ARI+2, sc);	(* sc is 3rd parameter of handler *)
	WriteHex( trap);
	WriteHex( SYSTEM.VAL( LONGINT,si));
	WriteHex( SYSTEM.VAL( LONGINT,sc));
	WriteHex( sc.pc);
	ch:=0AX; 
	trap:=SigTab[trap];
	WriteHex( trap);
(* only used to get distance from sc to fp; trap with SYSTEM.PUTREG(28, 1236H);
	j:=0;
	REPEAT
		INC(j, 4);
		sc:= SYSTEM.VAL( SigContext, sp+j);
	UNTIL (sc.regs[28*2]=1236H) OR (j>1000H);
	WriteDist( j);
	Exit0(1);
*)
	j:=0;
	REPEAT
		IF j MOD 8 =0 THEN i:=Write0(0, SYSTEM.ADR(ch), 1) END;
		WriteHex(sc.dummy[ j] ); 
		INC(j);
	UNTIL j=LEN(sc.dummy);
	j:=0;
	REPEAT
		IF j MOD 8 =0 THEN i:=Write0(0, SYSTEM.ADR(ch), 1) END;
		WriteHex(sc.regs[ j*2]);
		INC( j);
	UNTIL j>=32;
	i:=Write0(0, SYSTEM.ADR(ch), 1);
	IF (trap=13) & inGC THEN break:=TRUE; DEC( siglevel); RETURN END;	(* ctrl-c from terminal *)
	IF (trap=-SIGTRAP) THEN SYSTEM.GET( sc.pc, trap);
		IF trap DIV 8 MOD 8 = 6 THEN trap:=ASH(trap, -6) MOD 1024;
			IF trap=1023 THEN trap:=MAX(INTEGER) END;
		END;
	END;	(* only for MIPS *)
	LReg:=sc.regs[ LR*2]; FPtr:=sc.regs[ FP*2];
	IF (defaulttraphandler # NIL) THEN defaulttraphandler( trap, sc.regs[SP*2], sc.pc, si.adr ) END;
	IF inGC THEN	(* Halt("Trap in GC", trap); *) Exit0(1) END;
	FPtr:=sc.regs[FP*2];
	IF (traphandler # NIL) & (traphandler#defaulttraphandler)THEN traphandler( trap, sc.regs[SP*2], sc.pc, si.adr ) END;	 (*was: handler |trap 16: Disk full *)
	IF trap=MAX(INTEGER) THEN INC(sc.pc, 4);	(* ! *)
	ELSE
		sc.regs[SP*2]:= StackOrg;
		sc.regs[FP*2]:= StackOrg;
		sc.pc:=SYSTEM.VAL( LONGINT, loop);
		IF loop=NIL THEN Exit0( 1) END;
	END;
	DEC( siglevel);
END SignalHandler;
*)

PROCEDURE CopyRegs*( sc: SigContext);
VAR i: LONGINT;
BEGIN
	i:=32;
	REPEAT
		DEC(i);
		Regs[i]:=sc.regs[i*2];
		FRegs[i]:=sc.fpregs[i];
		FRegs[i+32]:=sc.fpregs[i+32];
	UNTIL i=0;
END CopyRegs;

END Linux0.

