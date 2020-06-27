(* ETH Oberon, Copyright 2001 ETH Zuerich Institut fuer Computersysteme, ETH Zentrum, CH-8092 Zuerich.
Refer to the "General ETH Oberon System Source License" contract available at: http://www.oberon.ethz.ch/ *)

MODULE Files;	(* pjm *)

(* 
	Linux-compatible Files module not based on OFS
	Peter Matthias

	2014-05-27	first version
	2014-06-04	made FileDesc.new LONGINT, fixed some filename lengths; merged CleanupOld and CleanupNew
	2014-06-16	added f.len (File length for faster writing)
	2014-06-22	mmapped files working
	2015-02-10	OLR version
	2015-04-01	open old files read only if no write permission
	2015-04-17	Close makes files anonymous
	2015-05-15	Close updates file now, changed Set
	2015-05-20	changed Set to allow pos >f.len
	2015-05-26	added check for LEN(x)< n in WriteBytes
	2015-07-31	made MAPSHARED MAPPRIVATE; SHARED might not work on NOKIA N810; ToDo Test!
	2015-12-09	imported Linux0
	2016-05-14	allowed "_" and "-"in filename
	2016-07-31	changed ReadNum to work with 64bit registers
	2016-08-29	added Files.dirfd
	2016-09-13	Close* don't write to file ToDo: don't use MAPPRIVATE

ToDo:	Register	GC on Too many open files Trap (Trap 109)

Volume:
PROCEDURE New*(name: ARRAY OF CHAR): File;
PROCEDURE Old*( name: ARRAY OF CHAR): File;
PROCEDURE Rename*(old, new: ARRAY OF CHAR; VAR res: INTEGER);
PROCEDURE Register*(f: File);
PROCEDURE Close*(f: File);

Filesystem:
PROCEDURE GetDate*(f: File; VAR t, d: LONGINT);
PROCEDURE SetDate*(f: File; t, d: LONGINT);
PROCEDURE Set*(VAR r: Rider; f: File; pos: LONGINT);	??
PROCEDURE ReadBytes*(VAR r: Rider; VAR x: ARRAY OF SYSTEM.BYTE; n: LONGINT);
PROCEDURE WriteBytes*(VAR r: Rider; VAR x: ARRAY OF SYSTEM.BYTE; n: LONGINT);
PROCEDURE Enumerate*(mask: ARRAY OF CHAR; flags: SET; proc: EntryHandler);

Volume to be added:
PROCEDURE Mount(prefix: ARRAY OF CHAR; volume: Volume): LONGINT;
PROCEDURE Unmount( volume: Volume): LONGINT;

*)

IMPORT Linux0, Kernel, SYSTEM;

CONST

	FnLength = 256;	(* includes 0X *)
	MremapMaymove = 1;

TYPE
	File* = POINTER TO FileDesc;

	FileName*= ARRAY FnLength OF CHAR;

	FileDesc = RECORD
			(** private fields for implementors *)
			Name: FileName;
			fd, addr, len, dirfd: LONGINT;
			changed: BOOLEAN;
	END;

	Rider* = RECORD
		file: File;
		apos: LONGINT;
		res*: LONGINT;	(** leftover byte count for ReadBytes/WriteBytes *)
		eof*: BOOLEAN;	(** has end of file been passed *)
	END;

	Bytes1 = ARRAY 1 OF SYSTEM.BYTE;
	Bytes2 = ARRAY 2 OF SYSTEM.BYTE;
	Bytes4 = ARRAY 4 OF SYSTEM.BYTE;
	Bytes8 = ARRAY 8 OF SYSTEM.BYTE;

	TimeSpec= RECORD  tvsec, tvnsec: LONGINT END;

VAR
	trace: BOOLEAN;
(* Check a file name. *)
	sysfd, wrkfd: LONGINT;

PROCEDURE SetSYS*( s: ARRAY OF CHAR);
BEGIN
	sysfd:=Linux0.Openat0( Linux0.ATFDCWD, SYSTEM.ADR(s[0]), Linux0.ORDonly+Linux0.ODirectory , 0);
	IF sysfd<=0 THEN Kernel.WriteString("Files.SetSYS: "); Kernel.WriteHex( -sysfd, 9); Kernel.WriteLn END;
END SetSYS;

PROCEDURE SetWRK*( s: ARRAY OF CHAR);
BEGIN
	IF s="" THEN wrkfd:=-1;
	ELSE
		wrkfd:=Linux0.Openat0( Linux0.ATFDCWD, SYSTEM.ADR(s[0]), Linux0.ORDonly+Linux0.ODirectory , 0);
		IF wrkfd<=0 THEN Kernel.WriteString("Files.SetWRK: "); Kernel.WriteHex( -wrkfd, 9); Kernel.WriteLn END;
	END;
END SetWRK;

PROCEDURE GetDirfd(VAR s: ARRAY OF CHAR): LONGINT;
VAR i, fd: LONGINT;
BEGIN
	IF (LEN(s)>4) & (s[3]=":") THEN
		s[3]:=0X;
		IF s="SYS" THEN fd:= sysfd;
		ELSIF s="WRK" THEN fd:= wrkfd;
		ELSE fd:=-1;
		END;
		i:=3;
		REPEAT
			INC(i);
			s[i-4]:=s[i];
		UNTIL s[i] =0X;
		RETURN fd;	
	END;
	IF wrkfd>0 THEN	RETURN wrkfd;
	ELSE RETURN sysfd;
	END;
END GetDirfd;		

PROCEDURE Check(VAR s, name: ARRAY OF CHAR; VAR dirfd: LONGINT; VAR res: INTEGER);
	VAR i: LONGINT; ch: CHAR;
BEGIN
	dirfd:=GetDirfd(s);
	ch := s[0]; i := 0;
	IF ("A" <= CAP(ch)) & (CAP(ch) <= "Z")OR (ch = ".") OR (ch="/") OR (ch="_") OR (ch="-") THEN
		LOOP name[i] := ch; INC(i); ch := s[i];
			IF ch = 0X THEN
				WHILE i < LEN(name) DO name[i] := 0X; INC(i) END ;
				res := 0; EXIT
			END ;
			IF ~(("A" <= CAP(ch)) & (CAP(ch) <= "Z")
				OR ("0" <= ch) & (ch <= "9") OR (ch = ".") OR (ch="/") OR (ch="_") OR (ch="-")) THEN res := 3; EXIT
			END ;
			IF i = LEN(name)-1 THEN res := 4; EXIT END
		END
	ELSIF ch = 0X THEN name[0] := 0X; res := -1
	ELSE res := 3
	END
END Check;

PROCEDURE Cleanup( f: SYSTEM.PTR);
VAR res: LONGINT; newName: FileName; f2: File;
BEGIN
	IF trace THEN Kernel.WriteString("Files.Cleanup: ") END; 
	IF f # NIL THEN
		f2:=SYSTEM.VAL(File, f);
		IF trace THEN Kernel.WriteString(f2.Name) END;
		IF f2.fd#-1 THEN res:= Linux0.Close0( f2.fd); f2.fd:=-1 END;
	END;
	IF trace THEN Kernel.WriteLn END;
END Cleanup;

(** Creates a new file with the specified name. *)
PROCEDURE New*(name: ARRAY OF CHAR): File;
VAR f: File; res: INTEGER; newName: FileName;
BEGIN
	IF trace THEN Kernel.WriteString("Files.New "); Kernel.WriteString(name); Kernel.WriteLn END;
	NEW(f);
	Check( name, f.Name, f.dirfd, res);
	IF res <=0 THEN
		f.fd:=-1;
(* MAP_SHARED=1, MAP_PRIVATE=2, MAP_ANONYMOUS=20H, 800@MIPS, RW=3 Anonymous files have to be private for mmap to work! *)
		f.addr:=Linux0.Mmap20( 0, Linux0.PageSize, 3, Linux0.MAPPRIVATE+Linux0.MAPANONYMOUS, 0, 0);
		IF (f.addr MOD 1000H) #0 THEN Kernel.WriteString("Files.New mmap failed"); Kernel.WriteHex(f.addr, 9); Kernel.WriteLn;END;
		f.len:=0;
		f.changed:=FALSE;
		Kernel.RegisterObject( f, Cleanup, FALSE);
		RETURN f;
	END;
	Kernel.WriteString("Files.New failed"); Kernel.WriteLn;
	RETURN NIL;
END New;

(** Open an existing file. The same file descriptor is returned if a file is opened multiple times. *)
PROCEDURE Old*( name: ARRAY OF CHAR): File;
VAR f: File; fd, r: LONGINT; status: Linux0.Status; res: INTEGER;
BEGIN
	NEW( f);
	IF trace THEN Kernel.WriteString("Files.Old "); Kernel.WriteString(name); Kernel.WriteLn END;
	Check( name, f.Name, f.dirfd, res);
	IF res=0 THEN
		fd:=Linux0.Openat0( f.dirfd, SYSTEM.ADR(f.Name[0]), Linux0.ORDWR , 0);	(* 0x400*O_EXCL *)
		IF -fd=0DH THEN	(* permission denied, try read only *)
			fd:=Linux0.Openat0( f.dirfd, SYSTEM.ADR(f.Name[0]), Linux0.ORDonly , 0);
		END;
		IF fd<=0 THEN
			fd:=Linux0.Openat0( sysfd, SYSTEM.ADR(f.Name[0]), Linux0.ORDWR , 0);	(* 0x400*O_EXCL *)
			IF -fd=0DH THEN	(* permission denied, try read only *)
				fd:=Linux0.Openat0( sysfd, SYSTEM.ADR(f.Name[0]), Linux0.ORDonly , 0);
			END;
		END;
		IF fd<=0 THEN
			IF fd=-2 THEN Kernel.WriteString( f.Name); Kernel.WriteString(" not present");
			ELSE Kernel.WriteString("Error: "); Kernel.WriteString(f.Name); Kernel.WriteHex(-fd, 9);
			END;
			Kernel.WriteLn;
			RETURN NIL;
		END;
		f.fd:= fd;
		r:=Linux0.FStat0( f.fd, SYSTEM.ADR(status));
		f.len:=status.size;
		IF trace THEN Kernel.WriteString(" size: "); Kernel.WriteInt(f.len, 9); Kernel.WriteLn END;

		f.addr:=Linux0.Mmap20( 0, f.len (*((f.len+bsize-1) DIV bsize)*bsize*), 3, Linux0.MAPSHARED, f.fd, 0);
		IF (f.addr MOD 1000H)#0 THEN
			Kernel.WriteString("Files.Old mmap failed"); Kernel.WriteHex(-f.addr, 9); Kernel.WriteLn;
			r:= Linux0.Close0( fd);
			RETURN NIL;
		END;
		f.changed:=FALSE;
		Kernel.RegisterObject( f, Cleanup, FALSE);
		RETURN f;
	END;
	RETURN NIL;
END Old;

(** Register a file created with New in the directory, replacing the previous file in the 
directory with the same name. The file is automatically closed. *)
PROCEDURE Register*(f: File);
BEGIN
	IF f# NIL THEN
		IF trace THEN Kernel.WriteString("Files.Register "); Kernel.WriteString(f.Name); Kernel.WriteLn END;
		IF f.Name#"" THEN
			IF f.fd=-1 THEN																	(* flags were 242H for X86 *)
				f.fd:=Linux0.Openat0( f.dirfd, SYSTEM.ADR(f.Name[0]), Linux0.ORDWR+Linux0.OTRUNC+Linux0.OCREAT, SYSTEM.VAL( LONGINT, { 8, 7, 5, 2}));
				(*   ARM: was 240H; 200H: O_DSYNC, 40H: O_CREAT MIPS: 110H*)
				IF f.fd<=0 THEN
					Kernel.WriteString("Files.Register bug"); Kernel.WriteHex(-f.fd, 9); Kernel.WriteLn;
					IF f.fd=-24 THEN		(* too many open files; must not return NIL; Bug?? *)
						(* close open files *)
						HALT( 109);
					END;
					HALT( 108);
				END;
				IF f.len#Linux0.Write0( f.fd, f.addr, f.len) THEN Kernel.WriteString("Files.Register 2"); HALT( 107) END;
			ELSE
				IF f.changed THEN
					IF f.len#Linux0.Write0( f.fd, f.addr, f.len) THEN Kernel.WriteString("Files.Register 3"); HALT( 110) END;
				END;
				IF 0#Linux0.Ftruncate0( f.fd, f.len) THEN Kernel.WriteString("Files.Register 4"); HALT(102) END;
			END;
		END;
		f:=NIL;
	END;
END Register;

(** Flushes the changes made to a file to disk. Register will automatically Close a file. *)
PROCEDURE Close*(f: File);
VAR res: LONGINT; 
BEGIN
	IF f# NIL THEN
		IF trace THEN Kernel.WriteString("Files.Close "); Kernel.WriteString(f.Name); Kernel.WriteLn END;
		IF f.fd>0 THEN
(*			res:=Linux0.LSeek0( f.fd, 0, Linux0.SEEKSET);		(* not needed (only if mmap shared??) *)
			IF res#0 THEN Kernel.WriteString("Files.Close lseek res.="); Kernel.WriteString(f.Name); Kernel.WriteHex( -res, 9); Kernel.WriteLn; HALT( 107) END;
			IF f.changed THEN
				res:=Linux0.Write0( f.fd, f.addr, f.len);
				IF f.len#res THEN Kernel.WriteString("Files.Close write res.="); Kernel.WriteHex( -res, 9); Kernel.WriteLn; HALT( 108) END;
			END;*)
		END;
(*
		IF f.addr# 0 THEN f.addr:=Kernel.Munmap0( f.addr, (f.len+bsize-1)DIV bsize*bsize) END;
		IF f.fd#-1 THEN res:= Kernel.Close0( f.fd); f.fd:=-1; END;
*)
		f.Name:="";
	END;
END Close;

(** Returns the current length of a file. *)
PROCEDURE Length*(f: File): LONGINT;
BEGIN
	IF f# NIL THEN RETURN f.len END;
	RETURN 0;
END Length;

(** Returns the time (t) and date (d) when a file was last modified. *)
PROCEDURE GetDate*(f: File; VAR t, d: LONGINT);
VAR status: Linux0.Status; res: LONGINT;
BEGIN
	res:=Linux0.FStat0( f.fd, SYSTEM.ADR(status));
	Kernel.U2OTime( status.mtime, d, t);
END GetDate;

(** Sets the modification time (t) and date (d) of a file. *)
PROCEDURE SetDate*(f: File; t, d: LONGINT);
VAR tm: LONGINT; buf: ARRAY 2 OF TimeSpec;
BEGIN
	tm:= Kernel.O2UTime( d, t);
	buf[0].tvsec:=tm; buf[0].tvnsec:=0;
	buf[1].tvsec:=tm; buf[1].tvnsec:=0;
	tm:=Linux0.UTimensat0( f.dirfd, SYSTEM.ADR( f.Name[0]), SYSTEM.ADR( buf), 0);
END SetDate;

(** Positions a Rider at a certain position in a file. Multiple Riders can be positioned 
at different locations in a file. A Rider cannot be positioned beyond the end of a file. *)
PROCEDURE Set*(VAR r: Rider; f: File; pos: LONGINT);
BEGIN
	r.file:= f;
	r.apos:= pos;
	r.res:= 0;
	r.eof:= FALSE;
	IF (f#NIL) & (pos>f.len) THEN Kernel.WriteString("Warning: Files.Set pos/f.len"); Kernel.WriteHex( pos, 9); Kernel.WriteHex( f.len, 9);Kernel.WriteLn END;
END Set;

(** Returns the offset of a Rider positioned on a file. *)
PROCEDURE Pos*(VAR r: Rider): LONGINT;
BEGIN	RETURN r.apos;
END Pos;

(** Returns the File a Rider is based on. *)
PROCEDURE Base*(VAR r: Rider): File;
BEGIN
	RETURN r.file
END Base;

(** Reads a sequence of length n bytes into the buffer x, advancing the Rider. Less bytes 
will be read when reading over the length of the file. r.res indicates the number of unread bytes. 
x must be big enough to hold n bytes. *)
PROCEDURE ReadBytes*(VAR r: Rider; VAR x: ARRAY OF SYSTEM.BYTE; n: LONGINT);
VAR f: File; res: LONGINT;
BEGIN
	f:=r.file;
	res:=r.apos+n-f.len;
	IF  res>0 THEN		(* todo: test! *)
		r.eof:= TRUE;
		r.res:= res;
		DEC(n, res);
	ELSE
		r.eof:= FALSE;
		r.res:= 0;
	END;
	IF n>0 THEN SYSTEM.MOVE( f.addr+r.apos, SYSTEM.ADR( x[0]), n) END;
	INC( r.apos, n);
END ReadBytes;

(** Read a byte from a file, advancing the Rider one byte further.  R.eof indicates if the end of the file has been passed. *)
PROCEDURE Read*(VAR r: Rider; VAR x: SYSTEM.BYTE);
BEGIN	ReadBytes( r, x, 1);
END Read;

(**
Portable routines to read the standard Oberon types.
*)

PROCEDURE ReadInt*(VAR r: Rider; VAR x: INTEGER);
BEGIN
	ReadBytes(r, SYSTEM.VAL(Bytes2, x), 2)
END ReadInt;

PROCEDURE ReadLInt*(VAR r: Rider; VAR x: LONGINT);
BEGIN
	ReadBytes(r, SYSTEM.VAL(Bytes4, x), 4)
END ReadLInt;

PROCEDURE ReadSet*(VAR r: Rider; VAR x: SET);
BEGIN
	ReadBytes(r, SYSTEM.VAL(Bytes4, x), 4)
END ReadSet;

PROCEDURE ReadBool*(VAR r: Rider; VAR x: BOOLEAN);
VAR s: SHORTINT;
BEGIN
	Read(r, s); x := s # 0
END ReadBool;

PROCEDURE ReadReal*(VAR r: Rider; VAR x: REAL);
BEGIN
	ReadBytes(r, SYSTEM.VAL(Bytes4, x), 4)
END ReadReal;

PROCEDURE ReadLReal*(VAR r: Rider; VAR x: LONGREAL);
BEGIN
	ReadBytes(r, SYSTEM.VAL(Bytes8, x), 8)
END ReadLReal;

PROCEDURE ReadString*(VAR r: Rider; VAR x: ARRAY OF CHAR);
VAR i: INTEGER; ch: CHAR;
BEGIN i := 0;
	LOOP
		Read(r, ch); x[i] := ch; INC(i);
		IF ch = 0X THEN EXIT END;
		IF i = LEN(x) THEN x[i-1] := 0X;
			REPEAT Read(r, ch) UNTIL ch = 0X;
			EXIT
		END
	END
END ReadString;

(** Reads a number in compressed variable length notation using the minimum amount of bytes. *)
PROCEDURE ReadNum*(VAR r: Rider; VAR x: LONGINT);
VAR ch: CHAR; n: INTEGER; y: LONGINT;
BEGIN
	n := 0; y := 0; Read(r, ch);
	WHILE ch >= 80X DO INC(y, SYSTEM.LSH(LONG(ch) - 128, n)); INC(n, 7); Read(r, ch) END;
	x := ASH(SYSTEM.LSH(LONG(ch), Linux0.RegSize-7), n-Linux0.RegSize + 7) + y
END ReadNum;

(** Writes the buffer x containing n bytes into a file at the Rider position. *)
PROCEDURE WriteBytes*(VAR r: Rider; VAR x: ARRAY OF SYSTEM.BYTE; n: LONGINT);
VAR f: File;  lo, ln: LONGINT;
BEGIN
	f:=r.file;
	lo:=(f.len+Linux0.PageSize-1)DIV Linux0.PageSize*Linux0.PageSize;
	IF lo=0 THEN lo:= Linux0.PageSize END;
	ln:=(r.apos+n+Linux0.PageSize-1) DIV Linux0.PageSize*Linux0.PageSize;
	IF ln> lo THEN
		IF f.fd=-1 THEN
			IF trace THEN Kernel.WriteString("mremap: "); Kernel.WriteHex(f.addr, 9); Kernel.WriteHex(ln, 9); Kernel.WriteHex(lo, 9) END;
			f.addr:=Linux0.Mremap0( f.addr, lo, ln, MremapMaymove, 0);
			IF trace OR ( f.addr<0) THEN Kernel.WriteString("mremap: "); Kernel.WriteHex(r.apos, 9); Kernel.WriteHex(n, 9); Kernel.WriteHex(-f.addr, 9); Kernel.WriteLn END;
		ELSE
			f.addr:=Linux0.Munmap0( f.addr, lo);
			IF 0#Linux0.Ftruncate0( f.fd, ln) THEN HALT(102) END;
			f.addr:=Linux0.Mmap20( 0, (ln +Linux0.PageSize-1) DIV Linux0.PageSize*Linux0.PageSize, 3, Linux0.MAPPRIVATE, f.fd, 0);
		END;
	END;
	IF LEN(x)<n THEN
		Kernel.WriteString("Files.WriteBytes: Array too small "); Kernel.WriteHex( LEN(x), 8); Kernel.WriteHex(n, 9); Kernel.WriteLn;
		HALT(103);
	END;
	SYSTEM.MOVE(SYSTEM.ADR(x[0]), f.addr+r.apos, n);
	f.changed:=TRUE;
	INC( r.apos, n);
	IF r.apos> f.len THEN f.len:=r.apos END;
	r.eof:= r.apos>= f.len;
END WriteBytes;

(* Writes a byte into the file at the Rider position, advancing the Rider by one. *)
PROCEDURE Write*(VAR r: Rider; x: SYSTEM.BYTE);
BEGIN	WriteBytes( r,  x, 1);
END Write;

(**
Portable routines to write the standard Oberon types.
*)

PROCEDURE WriteInt*(VAR r: Rider; x: INTEGER);
BEGIN
	WriteBytes(r, SYSTEM.VAL(Bytes2, x), 2)
END WriteInt;

PROCEDURE WriteLInt*(VAR r: Rider; x: LONGINT);
BEGIN
	WriteBytes(r, SYSTEM.VAL(Bytes4, x), 4)
END WriteLInt;

PROCEDURE WriteSet*(VAR r: Rider; x: SET);
BEGIN
	WriteBytes(r, SYSTEM.VAL(Bytes4, x), 4)
END WriteSet;

PROCEDURE WriteBool*(VAR r: Rider; x: BOOLEAN);
BEGIN
	IF x THEN Write(r, 1) ELSE Write(r, 0) END
END WriteBool;

PROCEDURE WriteReal*(VAR r: Rider; x: REAL);
BEGIN
	WriteBytes(r, SYSTEM.VAL(Bytes4, x), 4)
END WriteReal;

PROCEDURE WriteLReal*(VAR r: Rider; x: LONGREAL);
BEGIN
	WriteBytes(r, SYSTEM.VAL(Bytes8, x), 8)
END WriteLReal;

PROCEDURE WriteString*(VAR r: Rider; x: ARRAY OF CHAR);
VAR i: INTEGER; ch: CHAR;
BEGIN
	i := 0;
	LOOP ch := x[i]; Write(r, ch); INC(i);
		IF ch = 0X THEN EXIT END;
		IF i = LEN(x) THEN Write(r, 0X); EXIT END
	END
END WriteString;

(** Writes a number in a compressed format. *)
PROCEDURE WriteNum*(VAR r: Rider; x: LONGINT);
BEGIN
	WHILE (x < - 64) OR (x > 63) DO Write(r, CHR(x MOD 128 + 128)); x := x DIV 128 END;
	Write(r, CHR(x MOD 128))
END WriteNum;

(** Deletes a file. res = 0 indicates success. *)
PROCEDURE Delete*(name: ARRAY OF CHAR; VAR res: INTEGER);
VAR namebuf: FileName; r, dirfd: LONGINT;
BEGIN
	Check(name, namebuf, dirfd, res); 
	IF res=0 THEN
		r:= SHORT( Linux0.UnLinkat0( dirfd, SYSTEM.ADR( name[0]), 0));
		IF r#0 THEN res:=2 END;
	END;
END Delete;

(** Renames a file. res = 0 indicates success. *)
PROCEDURE Rename*(old, new: ARRAY OF CHAR; VAR res: INTEGER);
VAR olddirfd, newdirfd: LONGINT; 
BEGIN
	Check( old, old, olddirfd, res);
	Check( new, new, newdirfd, res);
	res:= SHORT( Linux0.Renameat0( olddirfd, SYSTEM.ADR( old[0]), newdirfd, SYSTEM.ADR( new[0]), 0));
END Rename;

(** Returns the full name of a file. *)
PROCEDURE GetName*(f: File; VAR name: ARRAY OF CHAR);
BEGIN
	COPY( f.Name, name);
END GetName;

BEGIN
	trace:= Kernel.trace="Files";
	SetSYS(".");
	SetWRK("");
END Files.

(** Remarks:

1. Oberon uses the little-endian byte ordering for exchanging files between different Oberon platforms.

2. Files are separate entities from directory entries. Files may be anonymous by having no name and not being registered in a
	directory. Files only become visible to other clients of the Files module by explicitly passing a File descriptor or by registering
	a file and then opening it from the other client. Deleting a file of which a file descriptor is still available, results in the file
	becoming anonymous. The deleted file may be re-registered at any time.

3. Files and their access mechanism (Riders) are separated. A file might have more than one rider operating on it at different
	offsets in the file.

4. The garbage collector will automatically close files when they are not required any more. File buffers will be discarded
	without flushing them to disk.  Use the Close procedure to update modified files on disk.

5. Relative and absolute filenames written in the directory syntax of the host operating system are used. By convention, Oberon
	filenames consists of the letters A..Z, a..z, 0..9, and ".". The directory separator is typically / or :. Oberon filenames are
	case sensitive. *)