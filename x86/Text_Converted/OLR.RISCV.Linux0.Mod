MODULE Linux0;	(* rc/ard/nm/jm/devil/pjm/rml*)

(*Linux interface for RISC-V  *)

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
	2016-05-31	ported to RISC-V
	2016-10-05	moved signal handling from Kernel

	Syscall numbers in /usr/include/asm-generic/unistd.h

	SetClock not implemented ( only superuser can change time)
	reboot does not work
	Mmap
Wrapper Procedure for SYSCALL:

PROCEDURE SysCall( a, b, c, d, e, f, g: LONGINT): LONGINT;
BEGIN
	SYSTEM.PUTREG( 25, 4009);				(* Syscall nr to R2 *)
	SYSTEM.CODE( SYSCALL);					
	SYSTEM.CODE( JALR);						(* error is in R7 *)
END SysCall;

Not fixed for ROP2 compiler; prolog and epilog still written

See setcontext.S, getcontext.S from:
https://gitlab.cs.fau.de/osek-v/riscv-gnu-toolchain/blob/1872ff6b98eeeb7a2182ef0a82a71733c79c3fec/glibc/sysdeps/unix/sysv/linux/riscv/getcontext.S
https://gitlab.cs.fau.de/osek-v/riscv-gnu-toolchain/tree/1872ff6b98eeeb7a2182ef0a82a71733c79c3fec/glibc/sysdeps/unix/sysv/linux/riscv

*)

IMPORT SYSTEM;

CONST
	ARCH*="RISC-V";
	ObjPrefix*="riscv/";
	ObjTag*=36FDH;	(* x86: 0AFX; arml: 0F5X; arm: 36FBH; mips: 36F9H; mipst: 36FAH *)
	RegSize*=32;
	PageSize*=1000H;
	B32=0;	(* was 8 *)

	ECALL=73H;	JALR= 8067H;	LWr14=01012703H;	LWr15= 01412783H;	FENCEI=100FH;	XTRAP=702BH;

	(* registers for RISC-V *)
	LR*=1; SP*=2; FP*=8;	ARI*=10;	T2=7;			(* mips: SP*=29; FP*=30; LR*=31;*)
	NRR=17;		(* syscall no. register *)

	ATFDCWD*=-100;	(* use current working directory *)

	(** Open( .. ) flags *)	(* old values: OCREAT*= 100H;	OEXCL*= 400H;	OAPPEND*=8H; *)(* same on ARM, MIPS, x86 *)
	ONonBlock=800H;	(* don't block on RISC-V, to be removed*)
	ORDonly*= 0;	OWRonly*= 1;	ORDWR*=2+ONonBlock;	OCREAT*= 40H;	OEXCL*= 80H;	OTRUNC*= 200H;	OAPPEND*=400H;	ODSYNC*=1000H;
	ODirectory*=10000H;
	(** FLock( .. ) *)
	LOCKEX*= 2;	LOCKNB*= 4;	LOCKUN*= 8;
	(** LSeek *)
	SEEKSET*=0;	SEEKCURRENT*=1;	SEEKEND*=2;
	(** Mmap *)
	MAPSHARED*=1; MAPPRIVATE*=2; MAPANONYMOUS*=20H;	(* ARM: 20H; MIPS: 800H *)

(*	PROTEXEC= PROTREAD=1	; PROTWRITE=2	PROTNONE=	*)

	(* Termios used in Input (FB) *)
(* MIPS *)
	VMIN*=4;
	TCGETS*= 540DH;
	TCSETSF*=5410H;

	(** Socket *)
	SOCKSTREAM*=1;		(* was 1 for X86 and ARM, 2 for MIPS *)

(* Common *)
	SIGHUP= 1;		(* Hang up ; X11 quits *)
	SIGINT= 2;			(* interrupt	 ctrl-c *)
	SIGQUIT= 3;		(* quit	ctrl-# , ctrl-4 ?, PrintScreen? *)
	SIGILL = 4;			(* invalid instruction ?*)
	SIGTRAP= 5;		(* HALT( x) not used in RISC-V *)
	SIGABRT= 6;
	SIGBUS=7;	(* dummy, not used in RISC-V *)
	SIGFPE = 8;		(* DIV 0 *)
	SIGKILL= 9;	(* kill *)
	SIGUSR1*= 10;	(*  *)
	SIGSEGV= 11;	(* segmentation fault *)
	SIGUSR2*= 12;	(* used by DisplayLinuxFB for console switching *)
	SIGPIPE= 13;	(* in KDE alt-F4 *)
	SIGALRM= 14;	(* signal  from alarm(1) *)
	SIGTERM = 15;	(* ctrl-alt-del *)
	SIGCHLD*= 17;	(* child quit *)
	SIGCONT*= 18;
	SIGSTOP= 19;
	SIGTTIN= 21;	(* virtual alarm ?? *)
	SIGTTOU= 22;	(* profile signal *)
	SIGPROF= 29;
	SIGXCPU= 30;
	SIGXFSZ= 31;

	IGNSigs={ SIGSTOP, SIGCONT, SIGKILL, SIGCHLD};	(* Ignore *)
	QUITSigs={ SIGHUP, SIGQUIT, SIGTERM};				(* Quit *)
	TRAPSigs= -{} -IGNSigs-QUITSigs ;	(* Trap *)

TYPE
	Proc*= PROCEDURE;
	TrapHandler* = PROCEDURE ( trap, fp, pc, page: LONGINT);

	Status* = RECORD	
		stdev, pad10, pad11, pad12: LONGINT;
		stino: LONGINT;
		stmode, stnlinl, stuid, stgid, rdev, pad20, pad21: LONGINT;
		size*, pad30, pad31, pad32,
		pad40, pad41, atime*, atimens,
		mtime*, mtimens,
		ctime*, ctimens, 
		blksize*, blocks*: LONGINT;
		pad4: ARRAY 14 OF LONGINT;
	END;

	SockAddrUn*= RECORD
		pf*: INTEGER;
		path*: ARRAY 64 OF CHAR;	(* was 30 for MIPS; 64 for ARM *)
	END;

(* RISC-V *)
	SigContext= POINTER TO RECORD
		dummy: ARRAY 8 OF LONGINT;
		pc: LONGINT;
		regs: ARRAY 32 OF LONGINT;
		fpregs: ARRAY 64 OF LONGINT;
	END;
(*
	SigInfo= POINTER TO RECORD
		dummy: ARRAY 24 OF LONGINT;
		signo, code, errno, adr, instr: LONGINT;
	END;
*)
VAR
	regs*, SigTab: ARRAY 32 OF LONGINT;
	fpregs*: ARRAY 32 OF LONGINT;
	StackOrg*, 	(** highest address on stack (single-process system) *)
	siglevel*: LONGINT;
	break*, 	(** has ctrl-break been pressed? *)
	inGC*: BOOLEAN;	(** executing inside GC? *)
	traphandler*, defaulttraphandler*: TrapHandler;
	loop*: Proc;

PROCEDURE Exit0*(status: LONGINT);
CONST EXIT0= 1;
BEGIN
	SYSTEM.PUTREG( NRR, 93);				(* Syscall nr to R2 EXECVE *)
	SYSTEM.CODE( ECALL);
END Exit0;
	
PROCEDURE Fork0*():LONGINT;
BEGIN
	SYSTEM.PUTREG( NRR, 57);				(* was 220 use clone syscall, ToDo: adopt arguments! *)
	SYSTEM.CODE( ECALL);
	SYSTEM.CODE( JALR);
END Fork0;

PROCEDURE Execve0*( filename, argv, envp: LONGINT):LONGINT;
BEGIN
	SYSTEM.PUTREG( NRR, 59);				(* was 221 Syscall nr to R2 EXECVE *)
	SYSTEM.CODE( ECALL);
	SYSTEM.CODE( JALR);
END Execve0;

PROCEDURE Waitid0( pid, status, options: LONGINT):LONGINT;
BEGIN
	SYSTEM.PUTREG( NRR, 247);				(* 95, WAITID Syscall nr to R2 WAITPID *)
	SYSTEM.CODE( ECALL);
	SYSTEM.CODE( JALR);
END Waitid0;

PROCEDURE Waitpid0*( pid, status, options: LONGINT):LONGINT;
BEGIN
	RETURN -1;	(* ToDo: adopt arguments to waitid *)
END Waitpid0;

PROCEDURE Openat0*( dfd, name, flags, mode: LONGINT): LONGINT;
BEGIN
	SYSTEM.PUTREG( NRR, 56);				(* 56, openat Syscall nr to R2 *)
	SYSTEM.CODE( ECALL);
	SYSTEM.CODE( JALR);
END Openat0;

PROCEDURE Close0*( fd: LONGINT): LONGINT;
BEGIN
	SYSTEM.PUTREG( NRR, 57);				(* close *)
	SYSTEM.CODE( ECALL);
	SYSTEM.CODE( JALR);
END Close0;

PROCEDURE Read0*( fd, buf, num: LONGINT): LONGINT;
BEGIN
	SYSTEM.PUTREG( NRR, 63);				(* Syscall nr to R2 *)
	SYSTEM.CODE( ECALL);
	SYSTEM.CODE( JALR);
END Read0;

PROCEDURE Readv0*( fd, vect, cnt: LONGINT): LONGINT;
BEGIN
	SYSTEM.PUTREG( NRR, 65);				(* Syscall nr to R2 *)
	SYSTEM.CODE( ECALL);
	SYSTEM.CODE( JALR);
END Readv0;

PROCEDURE Write0*( fd, buf, num: LONGINT): LONGINT;	
BEGIN
	SYSTEM.PUTREG( NRR, 64);		(* write *)
	SYSTEM.CODE( ECALL);
	SYSTEM.CODE( JALR);
END Write0;

PROCEDURE Writev0*( fd, vect, cnt: LONGINT): LONGINT;	
BEGIN
	SYSTEM.PUTREG( NRR, 66);		(* writev *)
	SYSTEM.CODE( ECALL);
	SYSTEM.CODE( JALR);
END Writev0;

PROCEDURE Brk0*( adr: LONGINT):LONGINT;
BEGIN
	SYSTEM.PUTREG( NRR, 214);		(* brk *)
	SYSTEM.CODE( ECALL);
	SYSTEM.CODE( JALR);
END Brk0;
(*
PROCEDURE Creat0*( name, mode: LONGINT): LONGINT;
BEGIN
	RETURN Open0( name, OCREAT+OWRonly+ OTRUNC, mode)
END Creat0;
*)
PROCEDURE MProtect0*( adr, len, prot: LONGINT): LONGINT;
BEGIN
	SYSTEM.PUTREG( NRR, 226);		(* mprotect *)
	SYSTEM.CODE( ECALL);
	SYSTEM.CODE( JALR);
END MProtect0;

PROCEDURE SIGAction0( signum, act, oldact: LONGINT): LONGINT;	
BEGIN
	SYSTEM.PUTREG( NRR,134);		(* sigaction was 4067*)
	SYSTEM.PUTREG( 13, 8);	(* rt_sigaction, mask size ? *)
	SYSTEM.CODE( ECALL);
	SYSTEM.CODE( JALR);
END SIGAction0;

PROCEDURE FStat0*( fd, stat: LONGINT): LONGINT;
BEGIN
	SYSTEM.PUTREG( NRR, 80);				(* 80 Syscall nr to R2 fxstat*)
	SYSTEM.CODE( ECALL);
	SYSTEM.CODE( JALR);
END FStat0;

PROCEDURE Mmap20*( addr, len, prot, flags, fd, off: LONGINT):LONGINT;
BEGIN
	SYSTEM.PUTREG( NRR, 222);				(* 222?? Syscall nr to R2 mmap64: 4210, mmap: 4090*)
	SYSTEM.CODE( LWr14);						(* LW r14, sp+16 *)
	SYSTEM.CODE( LWr15);						(* LW r15, sp+20 *)
	SYSTEM.CODE( ECALL);
	SYSTEM.CODE( JALR);
END Mmap20;

PROCEDURE Munmap0*( addr, len: LONGINT): LONGINT;
BEGIN
	SYSTEM.PUTREG( NRR, 215);				(* Syscall nr to R2 *)
	SYSTEM.CODE( ECALL);
	SYSTEM.CODE( JALR);
END Munmap0;

PROCEDURE CacheFlush0*( adr, bytes: LONGINT): LONGINT;
BEGIN
	SYSTEM.CODE( FENCEI);
	RETURN 0;
END CacheFlush0;

(* Files *)

PROCEDURE LLSeek0*( fd, offsethigh, offsetlow, resultadr, whence: LONGINT): LONGINT;
BEGIN
	SYSTEM.PUTREG( NRR, 62);				(* 62 llseek *)
	SYSTEM.CODE( LWr14);						(* LW r14, sp+16 *)
	SYSTEM.CODE( ECALL);
	SYSTEM.CODE( JALR);
END LLSeek0;

PROCEDURE LSeek0*( fd, offset, whence: LONGINT): LONGINT;
VAR a: ARRAY 2 OF LONGINT; b: LONGINT;
BEGIN
	b:=LLSeek0( fd, 0, offset, SYSTEM.ADR(a), whence);
	IF b=0 THEN RETURN a[0] END;
	RETURN b
END LSeek0;

PROCEDURE FLock0*( fd, arg: LONGINT): LONGINT;
BEGIN
	SYSTEM.PUTREG( NRR, 32);				(* Syscall nr to R2 *)
	SYSTEM.CODE( ECALL);
	SYSTEM.CODE( JALR);
END FLock0;

PROCEDURE Ftruncate0*( fd, len: LONGINT): LONGINT;
BEGIN
	SYSTEM.PUTREG( NRR, 64);				(* Syscall nr to R2 *)
	SYSTEM.CODE( ECALL);
	SYSTEM.CODE( JALR);
END Ftruncate0;

PROCEDURE UTimensat0*( dirfd, name, utimebuf, flags: LONGINT):LONGINT;
BEGIN
	SYSTEM.PUTREG( NRR, 88);
	SYSTEM.CODE( ECALL);
	SYSTEM.CODE( JALR);
END UTimensat0;

PROCEDURE GetTimeOfDay*(tv, tz: LONGINT): LONGINT;
BEGIN
	SYSTEM.PUTREG( NRR, 169);	(* GETTIMEOFDAY= 4078; TIME = 13 *)
	SYSTEM.CODE( ECALL);
	SYSTEM.CODE( JALR);
END GetTimeOfDay;

PROCEDURE Renameat0*( olddfd, old, newdfd, new, flags: LONGINT): LONGINT;
BEGIN
	SYSTEM.PUTREG( NRR, 38);				(* renameat, 38 Syscall nr to R2 *)
	SYSTEM.CODE( ECALL);
	SYSTEM.CODE( JALR);
END Renameat0;

PROCEDURE UnLinkat0*( dfd, name, flags: LONGINT): LONGINT;
BEGIN
	SYSTEM.PUTREG( NRR, 35);				(* unlinkat!! Syscall nr to R2 *)
	SYSTEM.CODE( ECALL);
	SYSTEM.CODE( JALR);
END UnLinkat0;

PROCEDURE Mremap0*( oldaddr, oldsize, newsize, flags, naddr: LONGINT): LONGINT;
(* MREMAP_MAYMOVE=1 *)
BEGIN
	SYSTEM.PUTREG( NRR, 216);				(* Syscall nr to R2 *)
	SYSTEM.CODE( ECALL);
	SYSTEM.CODE( JALR);
END Mremap0;

PROCEDURE FStatat0*( dfd, name, stat, flags: LONGINT): LONGINT;
BEGIN
	SYSTEM.PUTREG( NRR, 79);				(* Syscall nr to R2 xstat *)
	SYSTEM.CODE( ECALL);
	SYSTEM.CODE( JALR);
END FStatat0;

PROCEDURE GetDents0*( fd, bufptr, count: LONGINT): LONGINT;
BEGIN
	SYSTEM.PUTREG( NRR, 61);				(* Syscall nr to R2 *)
	SYSTEM.CODE( ECALL);
	SYSTEM.CODE( JALR);
END GetDents0;

PROCEDURE Socket0*( domain, type, protocol: LONGINT): LONGINT;
BEGIN
	SYSTEM.PUTREG( NRR, 198);				(* was 41, 198 Syscall nr to R2 *)
	SYSTEM.CODE( ECALL);
	SYSTEM.CODE( JALR);
END Socket0;

PROCEDURE Connect0*( sockfd, servaddr, addrlen: LONGINT): LONGINT;
BEGIN
	SYSTEM.PUTREG( NRR, 203);				(* was 203 Syscall nr to R2 *)
	SYSTEM.CODE( ECALL);
	SYSTEM.CODE( JALR);
END Connect0;

PROCEDURE Shmget0*( key, size, shmflag: LONGINT): LONGINT;
BEGIN
	SYSTEM.PUTREG( NRR, 194);				(* Syscall nr to R2 *)
	SYSTEM.CODE( ECALL);
	SYSTEM.CODE( JALR);
END Shmget0;

PROCEDURE Shmat0*(shmid, addr, flags: LONGINT): LONGINT;
BEGIN
	SYSTEM.PUTREG( NRR, 196);				(* Syscall nr to R2 *)
	SYSTEM.CODE( ECALL);
	SYSTEM.CODE( JALR);
END Shmat0;

PROCEDURE Shmdt0*(addr: LONGINT): LONGINT;
BEGIN
	SYSTEM.PUTREG( NRR, 197);				(* Syscall nr to R2 *)
	SYSTEM.CODE( ECALL);
	SYSTEM.CODE( JALR);
END Shmdt0;

PROCEDURE ShmCtl0*(buf, cmd, shmid: LONGINT): LONGINT;
BEGIN
	SYSTEM.PUTREG( NRR, 195);				(* Syscall nr to R2 *)
	SYSTEM.CODE( ECALL);
	SYSTEM.CODE( JALR);
END ShmCtl0;

PROCEDURE IOCtl0*( d, r1, r2: LONGINT): LONGINT;
BEGIN
	SYSTEM.PUTREG( NRR, 29);				(* Syscall nr to R2 *)
	SYSTEM.CODE( ECALL);
	SYSTEM.CODE( JALR);
END IOCtl0;

PROCEDURE Select0*( n, readfds, writefds, execptfds, timeout: LONGINT): LONGINT;
BEGIN
	SYSTEM.PUTREG( NRR, 72);				(* Syscall nr to R2 *)
	SYSTEM.CODE( LWr14);			
	SYSTEM.CODE( 6793H);		(* R15:=0 *)
	SYSTEM.CODE( ECALL);
	SYSTEM.CODE( JALR);
END Select0;

(* Linux0.Fixup and  MBootLinker.FixupV are same, don't optimize as in VDecoder.Obj  *)
PROCEDURE Fixup*( VAR code: ARRAY OF LONGINT; entry, L: LONGINT; data: BOOLEAN);	
CONST (* instruction format *)
	LB=3H; ADDI= 13H; SB=23H; LUI=37H; JALR=67H; JAL=6FH;
	IMM12=1000H;
VAR L1, c1, c2: LONGINT;
BEGIN
	IF (entry#0) & (L # 0) THEN
		REPEAT
			L1 := L; c1 := code[L1];
			IF c1 MOD 80H= JAL THEN	(* procedure call, UJ format *)	(* to be fixed in OPL.Exit, adjustLink ? *)
				L := L1 + ASH(ASH( c1, -31), 18)+ASH( c1, -22) MOD 200H+ASH( ASH(c1, -20) MOD 2, 9)+ASH( ASH(c1, -12) MOD 100H, 10)+1;
				code[L1] := LUI+ASH(T2, 7)+ASH( ASH(entry,-12)  +ASH( entry, -11) MOD 2, 12); 
				code[L1+1] := JALR+ASH(LR, 7)+ASH(T2, 15)+ASH( entry MOD IMM12, 20);
			ELSE
				L := L1  + ASH(c1, -15)+1;
				c2 := code[L1+1] + entry;
				code[L1] := LUI+ASH(T2, 7)+ASH( ASH(c2,-12)  +ASH( c2, -11) MOD 2, 12); 
				IF c1 MOD 80H DIV 8 = SB DIV 8 THEN	(* store, store fp *)
					code[L1+1] := c1 MOD 80H +ASH( c2 MOD 20H, 7)+ASH(ASH( c1, -12) MOD 8H, 12)+
						ASH( T2, 15) +ASH(ASH(c1, -7) MOD 20H, 20)+ ASH( ASH( c2, -5) MOD 80H , 25);	(* s-type *)
				ELSE														(* load, loadfp, addi *)
					code[L1+1] := ASH( c2 MOD 1000H, 20)+ ASH( T2, 15)+c1 MOD 8000H;
				END;
			END;
		UNTIL (L = L1) (*OR (L<0) OR (L>LEN(m.code^))*)
	END
END Fixup;
(*
PROCEDURE SetSignal*( nr: LONGINT; handler: Proc): LONGINT;
TYPE
	SigAction = RECORD
		handler: Proc;
		flags, mask, restorer: SET;
	END;
VAR h: SigAction;
BEGIN
	h.handler:= handler;
	h.flags:={ 30, 2};	(* 30=SA_NODEFER, 28=SARESTART *)
	h.mask:={}; h.restorer:={};
	RETURN SIGAction0( nr, SYSTEM.ADR(h), 0);
END SetSignal;
*)

PROCEDURE SetSignal*( nr: LONGINT; handler: Proc): LONGINT;
TYPE
	SigAction = RECORD
		handler: Proc;
		flags, mask: SET;
		restorer: Proc;
	END;
VAR h: SigAction;
BEGIN
	h.handler:= handler;
	h.flags:={ 30};	(* was{ 30, 2}30=SA_NODEFER, 28=SARESTART, 26=RESTORER 2=SIGINFO?*)
	h.mask:={}; h.restorer:=NIL;
	RETURN SIGAction0( nr, SYSTEM.ADR(h), 0);
END SetSignal;

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
	res:=Write0(0, SYSTEM.ADR(buf), 9);
END WriteHex;

PROCEDURE WriteDist( val: LONGINT);
VAR str: ARRAY 16 OF CHAR; res, i: LONGINT;
BEGIN
	str:= "Distance:    ";
	i:=14;
	val:=ABS(val);
	REPEAT
		str[i] := CHR(val MOD 10 + 30H); val := val DIV 10; DEC(i)
	UNTIL val = 0;
	str[15]:=0AX;
	res:=Write0(0, SYSTEM.ADR(str), 16);
END WriteDist;

PROCEDURE SignalHandler;
VAR trap, i, j, adr, si: LONGINT; sc: SigContext; ch: CHAR;
BEGIN
	INC( siglevel);
	SYSTEM.GETREG( ARI, trap);	(* trap is 1st parameter *)
	SYSTEM.GETREG( ARI+1, si);	(* si is 2nd parameter *)
	SYSTEM.GETREG( ARI+2, sc);	(* sc is 3rd parameter of handler *)
	WriteHex( trap);
	WriteHex( si);
	WriteHex( SYSTEM.VAL( LONGINT,sc));
	WriteHex( sc.pc);
	ch:=0AX; 
	trap:=SigTab[trap];
	WriteHex( trap);
(* only used to get distance from sc to fp; trap with SYSTEM.PUTREG(28, 1236H);
	j:=100;
	REPEAT
		INC(j, 4);
		sc:= SYSTEM.VAL( SigContext, fp+j);
		SYSTEM.GET(fp+j, i);
		WriteHex( i);
	UNTIL (sc.dummy=28) OR (j>1200);
(*	UNTIL (sc.regs[28]=1236H) OR (j>1000H);*)
	WriteDist( j);
	Exit0(1);
*)
	j:=Write0(0, SYSTEM.ADR(ch), 1);
	REPEAT
		IF si MOD (8*4) =0 THEN i:=Write0(0, SYSTEM.ADR(ch), 1) END;
		SYSTEM.GET(si, adr);
		WriteHex(adr ); 
		INC(si, 4);
	UNTIL si=SYSTEM.VAL( LONGINT,sc);

	j:=0;
	REPEAT
		IF j MOD 8 =0 THEN i:=Write0(0, SYSTEM.ADR(ch), 1) END;
		WriteHex(sc.dummy[ j] ); 
		INC(j);
	UNTIL j=LEN(sc.dummy);
	j:=0;
	REPEAT
		IF j MOD 8 =0 THEN i:=Write0(0, SYSTEM.ADR(ch), 1) END;
		regs[ j]:= sc.regs[ j]; WriteHex(regs[j]);
		fpregs[ j]:= sc.fpregs[ j*2 ];
		INC( j);
	UNTIL j=32;
	i:=Write0(0, SYSTEM.ADR(ch), 1);
	IF (trap=13) & inGC THEN break:=TRUE; DEC( siglevel); RETURN END;	(* ctrl-c from terminal  *)
	IF trap= 28 THEN SYSTEM.GET(sc.pc, i);	(* Invalid instruction used as TRAP *)
		IF i MOD 8000H= XTRAP THEN trap:= ASH(i, -15) END;
		WriteHex( i); 
		WriteDist( trap);
	END;

	IF (defaulttraphandler # NIL) THEN defaulttraphandler( trap, sc.regs[SP], sc.pc, adr ) END;
	IF inGC THEN (*Halt("Trap in GC", trap);*) Exit0(1); END;
	IF (traphandler # NIL) & (traphandler#defaulttraphandler) THEN traphandler( trap, sc.regs[SP], sc.pc, adr ) END;	(* was: handler |trap 16: Disk full *)
	IF trap=MAX(INTEGER) THEN INC(sc.pc, 4);	(* ! *)
	ELSE
		sc.regs[SP]:= StackOrg;
		sc.regs[FP]:= StackOrg;
		sc.pc:=SYSTEM.VAL( LONGINT, loop);
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

