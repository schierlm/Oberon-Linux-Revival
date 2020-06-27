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

(* Linux kernel interface for X86 *)
(*
	Peter Matthias
	2015-12-09	split OLR.Kernel.Mod to OLR.ARM.Linux0.Mod and OLR.MIPS.Linux0.Mod
	2016-04-15	added Exit0 Fork0 Execve0 Waitpid0
	2016-08-06	implemented Openat0, UTimensat0, Renameat0, UnLinkat0, FStatat0, removed Open0, UTimes0, Rename0, UnLink0, Stat0 not teseted
	2016-10-16	-connect inlined

	Syscall numbers are in /usr/src/linux/arch/x86/syscalls/syscall_32.tbl
	/usr/include/x86_64-linux-gnu/asm/unistd_32.h 
	/usr/include/x86_64-linux-gnu/asm/unistd_64.h

Calling could also be done this way:
PROCEDURE Openat0*( dirfd, name, flags, mode: LONGINT): LONGINT;
CONST OPEN= 5; OPENAT= 127H;
CODE {SYSTEM.i386}
	ADD	ESP, 8
	POP	ESI
	POP	EDX
	POP	ECX
	POP	EBX
	MOV	EAX, OPENAT
	INT	80H
END Openat0;
*)
	
IMPORT SYSTEM;

CONST
	ARCH*="X86";
	ObjPrefix*="x86/";
	ObjTag*=0AFX;	(* x86: 0AFX; arml: 0F5X; arm: 36FBH; mips: 36F9H; mipst: 36FAH *)
	RegSize*=32;
	PageSize*=1000H;
		
	(* OLR start *)
		VMIN*= 6;
		TCGETS*= 5401H;
		TCSETSF*= 5404H;

		SIGHUP= 1;		(* Hang up ; X11 quits *)
		SIGINT*= 2;			(* interrupt	 ctrl-c *)
		SIGQUIT= 3;		(* quit	ctrl-# , ctrl-4 ?, PrintScreen? *)
		SIGILL* = 4;			(* invalid instruction ?*)
		SIGTRAP*= 5;		(* HALT( x) *)
		SIGABRT= 6;
		SIGBUS = 7;	(* unused *)
		SIGFPE* = 8;		(* DIV 0 *)
		SIGKILL= 9;	(* kill *)
		SIGUSR1*= 10;	(* used by Input for console switching *)
		SIGSEGV*= 11;	(* segmentation fault *)
		SIGUSR2*= 12;	(* used by Input for console switching *)
		SIGPIPE= 13;	(* in KDE alt-F4 *)
		SIGALRM= 14;	(* signal  from alarm(1) *)
		SIGTERM = 15;	(* ctrl-alt-del *)
		SIGSTKFLT= 16;	(* floating point stack error *)
		SIGCHLD= 17;	(* child quit *)
		SIGCONT= 18;
		SIGSTOP= 19;
		SIGTSTP= 20;		(* tty stop *)
		SIGTTIN= 21;		(* tty *)
		SIGTTOU= 22;	(* tty *)
		SIGIO= 23;	(* io error *)
		SIGXCPU= 24;	(* cpu time limit *)
		SIGXFSZ= 25;	(* file size limit *)
		SIGVTALRM= 26;	(* virtual alarm ?? *)
		SIGPROF= 27;	(* profile signal *)
		SIGWINCH= 28;	(* window changed *)
		SIGIO2= 29;
		SIGPWR= 30;
		SIGUNUSED= 31;

		IGNSigs*={ SIGWINCH, SIGSTOP, SIGCONT, SIGKILL, SIGCHLD};	(* Ignore *)
		QUITSigs*={ SIGPIPE, SIGHUP, SIGTSTP, SIGQUIT, SIGTERM};				(* Quit *)
		TRAPSigs*= -{} -IGNSigs-QUITSigs ;	(* Trap *)
		
		TimeAdjust=1;

		ATFDCWD*=-100;	(* use current directory *)

	(** Open( .. ) flags*)(* same on ARM, MIPS, x86 *)
		ORDonly*= 0;	OWRonly*= 1;	ORDWR*=2;	OCREAT*=40H;	OEXCL*=80H;	OTRUNC*= 200H;	OAPPEND*=400H;	ODSYNC*=1000H;
		ODirectory*=10000H;
	(** FLock( .. ) *)
		LOCKEX*= 2;	LOCKNB*= 4;	LOCKUN*= 8;
	(** LSeek *)
		SEEKSET*=0;	SEEKCURRENT*=1;	SEEKEND*=2;
	(** Mmap *)
		MAPSHARED*=1; MAPPRIVATE*=2; MAPANONYMOUS*=20H;
	(*	PROTEXEC= 4 PROTREAD=	1; PROTWRITE= 2	PROTNONE=	*)
	(** Socket *)
		SOCKSTREAM*=1;

TYPE

	SigCPTR*= POINTER TO SigContext;
	SigContext*= RECORD
		gs*, fs*, es*, ds*: LONGINT;
		edi*, esi*, ebp*, esp*, ebx*, edx*, ecx*, eax*, trapno*, err*, eip*: LONGINT;
		cs*: LONGINT;
		cflags*, espAtSig: LONGINT;
		ss*: LONGINT;
		fpstate: LONGINT;	(* don't make it POINTER TO FPUStateDesc because we would get problems with GC *)
		oldmask, cr2*: LONGINT;
	END;
	
	SigHandler*= PROCEDURE( );
	SigAction* = RECORD
		handler: SigHandler;
		mask: SET;
		flags, restorer: LONGINT;
	END;

	Status* = RECORD	(* X86 *)
		stdev, pad1, pad2, stino: LONGINT;
		x1, x2, x3, x4: LONGINT;
		y1, y2, y3, size*: LONGINT;
		z1, blksize*, z3, z4: LONGINT;
		atime*, atimens,
		mtime*, mtimens,
		ctime*, ctimens: LONGINT;
		b0, b1: LONGINT;
		c1, c2, c3, c4: LONGINT;
		d1, d2, d3, d4: LONGINT;
		e1, e2, e3, e4: LONGINT;
	END;

	SockAddrUn*= RECORD
			pf*: INTEGER;
			path*: ARRAY 64 OF CHAR;
	END;

VAR StackOrg*: LONGINT;	(** highest address on stack (single-process system) *)
	break* : BOOLEAN;	(** has ctrl-break been pressed? *)
	inGC*: BOOLEAN;	(** executing inside GC? *)

PROCEDURE Exit0*(status: LONGINT);
CONST EXIT0= 1;
CODE {SYSTEM.i386}
	POP	EBX	(* adjust ESP *)
	POP	EBX	(* adjust ESP *)
	POP	EBX
	MOV	EAX, EXIT0
(*	MOV	EBX, status[ EBP]*)
	INT	80H
END Exit0;
	
PROCEDURE Fork0*():LONGINT;
CONST FORK= 2; VFORK=190;
CODE {SYSTEM.i386}
	MOV	EAX, FORK
	INT	80H
END Fork0;

PROCEDURE Execve0*( filename, argv, envp: LONGINT):LONGINT;
CONST EXECVE= 11 ;
CODE {SYSTEM.i386}
	MOV	EAX, EXECVE
	MOV	EBX, filename[ EBP]
	MOV	ECX, argv[ EBP]
	MOV	EDX, envp[ EBP]
	INT	80H
END Execve0;

PROCEDURE Waitpid0*( pid, status, options: LONGINT):LONGINT;
CONST WAITPID= 7 ;
CODE {SYSTEM.i386}
	MOV	EAX, WAITPID
	MOV	EBX, pid[ EBP]
	MOV	ECX, status[ EBP]
	MOV	EDX, options[ EBP]
	INT	80H
END Waitpid0;

PROCEDURE Openat0*( dirfd, name, flags, mode: LONGINT): LONGINT;
CONST OPEN= 5; OPENAT= 127H;
CODE {SYSTEM.i386}
	MOV	EAX, OPENAT
	MOV	EBX, dirfd[ EBP]
	MOV	ECX, name[ EBP]
	MOV	EDX, flags[ EBP]
	MOV	ESI, mode[ EBP]
	INT	80H
END Openat0;

(* use Open(.., Linux0.RDWR+Linux0.OCREAT+Linux0.OTRUNC, ...)
PROCEDURE Creat0*( name, mode: LONGINT): LONGINT;
CONST CREAT= 8;
CODE {SYSTEM.i386}
	MOV	EAX, CREAT
	MOV	EBX, name[ EBP]
	MOV	ECX, mode[ EBP]
	INT	80H
END Creat0;
*)

PROCEDURE Close0*( fd: LONGINT): LONGINT;
CONST CLOSE= 6;
CODE {SYSTEM.i386}
	MOV	EAX, CLOSE
	MOV	EBX, fd[ EBP]
	INT	80H
END Close0;

PROCEDURE Read0*( fd, buf, num: LONGINT): LONGINT;
CONST READ= 3;
CODE {SYSTEM.i386}
	MOV	EAX, READ
	MOV	EBX, fd[ EBP]
	MOV	ECX, buf[ EBP]
	MOV	EDX, num[ EBP]
	INT	80H
END Read0;

PROCEDURE Readv0*( fd, vect, cnt: LONGINT): LONGINT;
CONST READ= 91H;
CODE {SYSTEM.i386}
	MOV	EAX, READ
	MOV	EBX, fd[ EBP]
	MOV	ECX, vect[ EBP]
	MOV	EDX, cnt[ EBP]
	INT	80H
END Readv0;

PROCEDURE Write0*( fd, buf, num: LONGINT): LONGINT;
CONST WRITE= 4;
CODE { SYSTEM.i386}
	MOV	EAX, WRITE
	MOV	EBX, fd[ EBP]
	MOV	ECX, buf[ EBP]
	MOV	EDX, num[ EBP]
	INT	80H
END Write0;

PROCEDURE Writev0*( fd, vect, cnt: LONGINT): LONGINT;
CONST WRITEV= 92H;
CODE { SYSTEM.i386}
	MOV	EAX, WRITEV
	MOV	EBX, fd[ EBP]
	MOV	ECX, vect[ EBP]
	MOV	EDX, cnt[ EBP]
	INT	80H
END Writev0;

PROCEDURE -Brk*( enddatasegment: LONGINT):LONGINT;
CONST BRK= 45;
CODE {SYSTEM.i386}
	POP	EBX
	MOV	EAX, BRK
(*	MOV	EBX, enddatasegment [ EBP]*)
	INT	80H
END Brk;

(*
PROCEDURE Brk( enddatasegment: LONGINT):LONGINT;
CONST BRK= 45;
CODE {SYSTEM.i386}
	MOV	EAX, BRK
	MOV	EBX, enddatasegment [ EBP]
	INT	80H
END Brk;
*)

PROCEDURE MProtect0*( adr, len, prot: LONGINT): LONGINT;
CONST  MPROTECT= 125;
CODE {SYSTEM.i386}
	MOV	EAX, MPROTECT
	MOV	EBX, adr[ EBP]
	MOV	ECX, len[ EBP]
	MOV	EDX, prot[ EBP]
	INT	80H
END MProtect0;

PROCEDURE SigAction0*( signum, act, oldact: LONGINT): LONGINT;
CONST SIGACTION = 67;
CODE {SYSTEM.i386}
	MOV	EAX, SIGACTION
	MOV	EBX, signum[ EBP]
	MOV	ECX, act[ EBP]
	MOV	EDX, oldact[ EBP]
	INT	80H
END SigAction0;

PROCEDURE SetSignal*( nr: LONGINT; handler: SigHandler): LONGINT;
CONST SARESTART= 10000000H;
VAR h, d: SigAction;
BEGIN
	h.handler:= handler;
	h.mask:= {};
	h.flags:= SARESTART;
	h.restorer:= 0;
	RETURN SigAction0( nr, SYSTEM.ADR(h), SYSTEM.ADR(d));
END SetSignal;

PROCEDURE FStat0*( fd, stat: LONGINT): LONGINT;
CONST FSTAT= 108;  FSTATAT64= 300; FSTAT64= 197;
CODE {SYSTEM.i386}
	MOV	EAX, FSTAT64
	MOV	EBX, fd[ EBP]
	MOV	ECX, stat[ EBP]
	INT	80H
END FStat0;

PROCEDURE Mmap20*( adr, len, prot, flags, fd, off: LONGINT): LONGINT;
CONST MMAP2= 192;
CODE {SYSTEM.i386}
	PUSH	EBP
	PUSH	ESI
	PUSH	EDI
	MOV	EAX, MMAP2
	MOV	EBX, adr[ EBP]
	MOV	ECX, len[ EBP]		
	MOV	EDX, prot[ EBP]
	MOV	ESI, flags[ EBP]
	MOV	EDI, fd[ EBP]
	MOV	EBP, off[ EBP]
	INT	80H
	POP	EDI
	POP	ESI
	POP	EBP
END Mmap20;

PROCEDURE Munmap0*( start, length: LONGINT): LONGINT;
CONST MUNMAP=91;
CODE {SYSTEM.i386}
	MOV	EAX, MUNMAP
	MOV	EBX, start[ EBP]
	MOV	ECX, length[ EBP]
	INT	80H
END Munmap0;

PROCEDURE CacheFlush0*( adr, bytes: LONGINT): LONGINT;
BEGIN RETURN 0;
END CacheFlush0;

(* Files *)

PROCEDURE LSeek0*( fd, pos, whence: LONGINT): LONGINT;
CONST LSEEK = 19;
CODE {SYSTEM.i386}
	MOV	EAX, LSEEK
	MOV	EBX, fd[ EBP]
	MOV	ECX, pos[ EBP]
	MOV	EDX, whence[ EBP]
	INT	80H
END LSeek0;

PROCEDURE FLock0*( fd, arg: LONGINT): LONGINT;
CONST FLOCK = 143;
CODE {SYSTEM.i386}
	MOV	EAX, FLOCK
	MOV	EBX, fd[ EBP]
	MOV	ECX, arg[ EBP]
	INT	80H
END FLock0;

PROCEDURE Select0*( n, readfds, writefds, execptfds, timeout: LONGINT): LONGINT;
CONST SELECT= 142;
CODE {SYSTEM.i386}
	MOV	EAX, SELECT
	MOV	EBX, n[ EBP]
	MOV	ECX, readfds[ EBP]
	MOV	EDX, writefds[ EBP]
	MOV	ESI, execptfds[ EBP]
	MOV	EDI, timeout[ EBP]
	INT	80H
END Select0;

PROCEDURE Ftruncate0*( fd, len: LONGINT): LONGINT;
CONST FTRUNCATE = 93;
CODE {SYSTEM.i386}
	MOV	EAX, FTRUNCATE
	MOV	EBX, fd[ EBP]
	MOV	ECX, len[ EBP]
	INT	80H
END Ftruncate0;
(*
PROCEDURE UTime0*( name, utimebuf: LONGINT):LONGINT;
CONST UTIME= 30;
CODE {SYSTEM.i386}
	MOV	EAX, UTIME
	MOV	EBX, name[ EBP]
	MOV	ECX, utimebuf[ EBP]
	INT 80H
END UTime0;
*)

PROCEDURE UTimensat0*( dirfd, name, utimebuf, flags: LONGINT):LONGINT;
CONST UTIMENSAT= 140H;
CODE {SYSTEM.i386}
	MOV	EAX, UTIMENSAT
	MOV	EBX, dirfd[ EBP]
	MOV	ECX, name[ EBP]
	MOV	EDX, utimebuf[ EBP]
	MOV	ESI, flags[ EBP]
	INT	80H
END UTimensat0;

PROCEDURE Renameat0*(  olddfd, old, newdfd, new, flags: LONGINT): LONGINT;
CONST RENAME= 38; RENAMEAT= 12EH;
CODE {SYSTEM.i386}
	MOV	EAX, RENAMEAT
	MOV	EBX, olddfd[ EBP]
	MOV	ECX, old[ EBP]
	MOV	EDX, newdfd[ EBP]
	MOV	ESI, new[ EBP]
	MOV	EDI, flags[ EBP]
	INT 80H
END Renameat0;

PROCEDURE UnLinkat0*( dirfd, name, flags: LONGINT): LONGINT;
CONST UNLINK= 10; UNLINKAT= 12DH;
CODE {SYSTEM.i386}
	MOV	EAX, UNLINKAT
	MOV	EBX, dirfd[ EBP]
	MOV	ECX, name[ EBP]
	MOV	EDX, flags[ EBP]
	INT	80H
END UnLinkat0;

PROCEDURE Mremap0*( oldaddr, oldsize, newsize, flags, naddr: LONGINT): LONGINT;
CONST MREMAP= 163;
CODE {SYSTEM.i386}
	PUSH	EDI
	PUSH	ESI
	MOV	EAX, MREMAP
	MOV	EBX, oldaddr[ EBP]
	MOV	ECX, oldsize[ EBP]
	MOV	EDX, newsize[ EBP]
	MOV	ESI, flags[ EBP]
	MOV	EDI, naddr[ EBP]
	INT	80H
	POP	ESI
	POP	EDI
END Mremap0;

PROCEDURE FStatat0*( dirfd, name, stat, flags: LONGINT): LONGINT;
CONST STAT= 106; FSTATAT64=300;
CODE {SYSTEM.i386}
	MOV	EAX, FSTATAT64
	MOV	EBX, dirfd[ EBP]
	MOV	ECX, name[ EBP]
	MOV	EDX, stat[ EBP]
	MOV	ESI, flags[ EBP]
	INT	80H
END FStatat0;

PROCEDURE GetDents0*( fd, bufptr, count: LONGINT): LONGINT;
CONST GETDENTS = 141; GETDENTS64 = 220;
CODE {SYSTEM.i386}
	MOV	EAX, GETDENTS64
	MOV	EBX, fd[ EBP]
	MOV	ECX, bufptr[ EBP]
	MOV	EDX, count[ EBP]
	INT	80H
END GetDents0;

PROCEDURE socket( protocol, type, domain: LONGINT): LONGINT;
CONST	
	SOCKETCALL= 102;
	SYSSOCKET= 1;
CODE {SYSTEM.i386}
	MOV	EAX, SOCKETCALL
	MOV	EBX, SYSSOCKET
	LEA	ECX, domain[ EBP]
	INT	80H
END socket;

PROCEDURE Socket0*( domain, type, protocol: LONGINT): LONGINT;
BEGIN
	RETURN socket( protocol, type, domain);
END Socket0;
(*
PROCEDURE connect( addrlen, servaddr, sockfd: LONGINT): LONGINT;
CONST	SOCKETCALL= 102;	SYSCONNECT= 3;
CODE {SYSTEM.i386}
	MOV	EAX, SOCKETCALL
	MOV	EBX, SYSCONNECT	
	LEA	ECX, sockfd[ EBP]	(* address of connect parameters *)
	INT	80H
END connect;
*)

PROCEDURE -connect( addrlen, servaddr, sockfd: LONGINT): LONGINT;
CONST	SOCKETCALL= 102;	SYSCONNECT= 3;
CODE {SYSTEM.i386}
	MOV	EAX, SOCKETCALL
	MOV	EBX, SYSCONNECT	
	MOV	ECX, ESP	(* address of connect parameters (sockfd)*)
	INT	80H
END connect;

PROCEDURE Connect0*( sockfd, servaddr, addrlen: LONGINT): LONGINT;
BEGIN
	RETURN connect( addrlen, servaddr, sockfd);
END Connect0;

PROCEDURE Ipc0*( call, first, second, third, ptr, fith: LONGINT): LONGINT;
CONST IPC= 117;
CODE {SYSTEM.i386}
	PUSH	EBP
	PUSH	ESI
	PUSH	EDI
	MOV	EAX, IPC
	MOV	EBX, call[ EBP]
	MOV	ECX, first[ EBP]		
	MOV	EDX, second[ EBP]
	MOV	ESI, third[ EBP]
	MOV	EDI, ptr[ EBP]
	MOV	EBP, fith[ EBP]
	INT	80H
	POP	EDI
	POP	ESI
	POP	EBP
END Ipc0;

PROCEDURE Shmget0*( key, size, shmflag: LONGINT): LONGINT;
BEGIN
	RETURN Ipc0( 23, key, size, shmflag, 0, 0);
END Shmget0;

PROCEDURE Shmat0*( shmid, addr, flags: LONGINT): LONGINT;
VAR i: ARRAY 4 OF LONGINT; res: LONGINT;
BEGIN
	i[0]:=0; i[1]:=0; i[2]:=0; i[3]:=0;
	res:= Ipc0( 21, shmid, flags, SYSTEM.ADR( i[2]), addr, 0);
	RETURN i[2];
END Shmat0;

PROCEDURE Shmdt0*( addr: LONGINT): LONGINT;
BEGIN
	RETURN Ipc0( 22, addr, 0, 0, 0, 0);
END Shmdt0;

PROCEDURE ShmCtl0*( buf, cmd, shmid: LONGINT): LONGINT;
BEGIN
	RETURN Ipc0( 24, buf, cmd, 0, shmid, 0);
END ShmCtl0;

PROCEDURE IOCtl0*( d, r1, r2: LONGINT): LONGINT;
CONST IOCTL= 54;
CODE {SYSTEM.i386}
	MOV	EAX, IOCTL
	MOV	EBX, d[ EBP]
	MOV	ECX, r1[ EBP]
	MOV	EDX, r2[ EBP]
	INT	80H
END IOCtl0;

(*
PROCEDURE SIGProcMask( how: LONGINT; set: SET; VAR oldset: SET):LONGINT;
CONST SIGPROCMASK= 126;
CODE {SYSTEM.i386}
	MOV	EAX, SIGPROCMASK
	MOV	EBX, how[ EBP]
	LEA	ECX, set[ EBP]
	LEA	EDX, oldset[ EBP]
	INT	80H
END SIGProcMask;
*)

PROCEDURE -SysCall1*( cmd: LONGINT; arg: LONGINT): LONGINT;
CODE {SYSTEM.i386}
	POP	EBX
	POP	EAX
	INT	80H
END SysCall1;

(*
PROCEDURE SysCall1( cmd: LONGINT; arg: LONGINT): LONGINT;
CODE {SYSTEM.i386}
	MOV	EAX, cmd[ EBP]
	MOV	EBX, arg[ EBP]
	INT	80H
END SysCall1;
*)

PROCEDURE GetTimeOfDay(tv, tz: LONGINT): LONGINT;
CONST GETTIMEOFDAY= 78;
CODE {SYSTEM.i386}
	MOV	EAX, GETTIMEOFDAY
	MOV	EBX, tv[ EBP]
	MOV	ECX, tz[ EBP]
	INT 80H
END GetTimeOfDay;

(** GetClock - Return current time and date *)
(* work
PROCEDURE GetClock(VAR time, date: LONGINT);
CONST TIME= 13;
VAR t: LONGINT;
BEGIN
	t:=SysCall1( TIME, 0);		(* ToDo: use ftime *)
	IF t>0 THEN
		U2OTime( t, date, time);
	ELSE time:=0; date:=0;
	END;
END GetClock;

don't know
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

(* Fill4 - Fill "size" dwords at "dest" with "filler" *)
PROCEDURE -Fill4(dest, size, filler: LONGINT);
CODE {SYSTEM.i386}
	POP	EAX
	POP	ECX
	POP	EDI
	CLD
	REP	STOSD
END Fill4;

END Linux0.

