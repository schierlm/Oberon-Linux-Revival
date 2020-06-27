MODULE Modules;	(** portable, except where noted *)	(* rc/mh/jm/ard/pjm 22.01.96/rml 1.5.97 / as 5.1.99 / oj 23.8.99 *)

(**
 The Modules module implements the dynamic module loader of the Oberon system. 
 It is responsible for loading and freeing modules.

CacheFlush is a very expensive procedure; Could be move to ThisMod if Body initialisation of all loaded module is done after CacheFlush


2014-03-25	p.m.: added CacheFlush because ARM needs to get I-Cache consistent with D-Cache after module loading
2014-04-11	p.m.:	fixed SWI call--> fix in OBC.MOD and Kernel!
2014-04-13			:	ExtCallFixup changed to use CC in mno 0
2014-04-22			:	ExtCallFixup changed to use Traps up to 255
2014-04-27			:	changed MaxImps = 16; MaxTypes = 32 (for Gadgets)
2014-04-28			: made import of SoftFloat non-implicit
2014-06-13			: removed Files module import
2014-06-25			: removed Read1 
2014-06-28			: minor changes
2015-04-21			disabled GC when loading modules
2015-05-10		Free: removed CacheFlush 

*)

IMPORT Linux0, Kernel, (* Kernel MUST be imported first! *) SYSTEM;

CONST
	trace = TRUE;

	done = 0;
	fileNotFound = 1;
	invalidObjFile = 2;
	keyMismatch = 3;
	corruptedObjFile = 4;
	cmdNotFound = 5;
	moduleNotFound = 6;
	notEnoughSpace = 7;
	refCntNotZero = 8;
	cyclicImport = 9;
	
	MaxImps = 64; (* was 16; = OBM.MaxImps was: 64 *)
	MaxTypes = 128; (* was 32; = OBC.MaxRecs was: 128*)
	MaxExts = 15;

TYPE
	Command* = Kernel.Proc;
	Module* = Kernel.Module;
	ModuleDesc* = Kernel.ModuleDesc;	(** non-portable *)
	ModuleName* = Kernel.Name;
	ADDRESS = LONGINT;

VAR
	res*: INTEGER;	(** Error code for ThisMod and ThisCommand. res = 0 indicates success. *)
	resMsg*: ARRAY 256 OF CHAR;	(** Explanation of res, if res # 0 *)
	
	(** The res codes are listed in the table below.
		done = 0;
		fileNotFound = 1
		invalidObjFile = 2
		keyMismatch = 3
		corruptedObjFile = 4
		cmdNotFound = 5
		moduleNotFound = 6
		notEnoughSpace = 7
		refCntNotZero = 8
		cyclicImport = 9
		incompImport = 16
	*)

	loop: Command;
	imported, importing: ModuleName;	(* Specifies the modules involved in a key mismatch. *)
	modLoadAddr : LONGINT; (* virtual address where the next module is mapped to. must be initialized by boot linker *)

TYPE
	Header = RECORD (* data in object file header *)
		refpos : LONGINT;
		entrypoint : LONGINT;
		nofImports: INTEGER;
		nofEntries: INTEGER;
		nofCommands: INTEGER;
		nofPointers: INTEGER;
		nofTypes: INTEGER;
		codeSize, dataSize, refSize, strConstSize: LONGINT
	END;

	Type = RECORD
			tdaddr : LONGINT; (* Address of type desc *)
		END;

	File = RECORD
		fd, adr, adrpos, length: LONGINT;
	END;

PROCEDURE Length1(f: File): LONGINT;
VAR status: Linux0.Status; res: LONGINT;
BEGIN
	IF f.fd# 0 THEN res:=Linux0.FStat0( f.fd, SYSTEM.ADR(status)); RETURN status.size END;
	RETURN 0;
END Length1;

PROCEDURE ReadString*(VAR r: File; VAR x: ARRAY OF CHAR);
VAR i: LONGINT; ch: CHAR;
BEGIN i := 0;
	LOOP
		SYSTEM.GET( r.adrpos, ch); INC( r.adrpos); x[i] := ch; INC(i);
		IF ch = 0X THEN EXIT END;
		IF i = LEN(x) THEN x[i-1] := 0X;
			REPEAT SYSTEM.GET( r.adrpos, ch); INC( r.adrpos) UNTIL ch = 0X;
			EXIT
		END
	END
END ReadString;

PROCEDURE Find(modname: ARRAY OF CHAR; VAR m: Module);
BEGIN
	m := Kernel.modules;
	WHILE m # NIL DO
		IF m.name = modname THEN RETURN END;
		m := m.next
	END;
END Find;

PROCEDURE ErrMsg(res: INTEGER);

	PROCEDURE Append(VAR a: ARRAY OF CHAR; b: ARRAY OF CHAR);
	VAR i, j: INTEGER;
	BEGIN
		i := 0; WHILE a[i] # 0X DO INC(i) END;
		j := 0; WHILE b[j] # 0X DO a[i] := b[j]; INC(i); INC(j) END;
		a[i] := 0X
	END Append;
	
BEGIN
	IF res # 0 THEN
		resMsg := "";
		Append(resMsg, importing);
		IF (res = fileNotFound) OR (res = moduleNotFound) THEN Append(resMsg, " not found")
		ELSIF res = invalidObjFile THEN Append(resMsg, " not an obj-file")
		ELSIF res = keyMismatch THEN
			Append(resMsg, " imports "); Append(resMsg, imported); Append(resMsg, " with bad key")
		ELSIF res = corruptedObjFile THEN Append(resMsg, " corrupted obj file")
		ELSIF res = notEnoughSpace THEN Append(resMsg, " not enough space")
		ELSIF res = refCntNotZero THEN Append(resMsg, " reference count not zero")
		ELSIF res = cyclicImport THEN Append(resMsg, " cyclic import")
		ELSIF res = cmdNotFound THEN
			COPY(imported, resMsg);  Append(resMsg, ".");  Append(resMsg, importing);
			Append(resMsg, " not found");  (* assumes importing = procedure name and imported = module name *)
		ELSE resMsg := " unknown error code"
		END;
		Kernel.WriteString("Modules: ");  Kernel.WriteString(resMsg);  Kernel.WriteLn
	END
END ErrMsg;

PROCEDURE ^Load (name: ARRAY OF CHAR; VAR m: Module);
	
PROCEDURE LoadModule (VAR f : File; VAR m: Module);
	TYPE TDesc = POINTER TO RECORD word: ARRAY 32000 OF LONGINT END;
	VAR
		i, j: LONGINT; m1: Module;
		head: Header;
		e, k, t, res2: LONGINT;
		ch: CHAR;
		body: Command;
		types: ARRAY MaxTypes OF Type;
		mods: ARRAY MaxImps OF RECORD
			key: LONGINT;
			name: ModuleName
		END;

	PROCEDURE Expect (tag: CHAR): BOOLEAN;
		VAR ch: CHAR; 
	BEGIN
		SYSTEM.GET( f.adrpos, ch); INC( f.adrpos);
		IF ch # tag THEN res := corruptedObjFile; ErrMsg(res); RETURN FALSE
		ELSE RETURN TRUE
		END
	END Expect;
	
	PROCEDURE ReadTypes (VAR R: File);
		VAR i, j, t, k, tdsize, tagaddr, recordSize, offset, mno, eno: LONGINT;
			nofPointers, root : INTEGER;
			td: TDesc; name: ModuleName; ch: CHAR;
			extlev : SHORTINT;
	BEGIN
		FOR i:=0 TO LEN(m.tdescs^)-1 DO
			SYSTEM.GET( f.adrpos, tagaddr); INC( f.adrpos, 4);
			SYSTEM.GET( f.adrpos, nofPointers); INC( f.adrpos, 2);
			SYSTEM.GET( f.adrpos, recordSize); INC( f.adrpos, 4);
			ReadString(R,name); 
			SYSTEM.GET( f.adrpos, extlev); INC( f.adrpos);			
			root := 13+MaxExts+2;
			tdsize:=nofPointers*4+8+56+(MaxExts+1)*4;
			SYSTEM.NEW(td, tdsize - 24 (* overhead of SysBlk header *) );
			DEC(SYSTEM.VAL(ADDRESS, td), 24);	(* overhead of SysBlk header *)
			types[i].tdaddr := SYSTEM.ADR(td.word[root]);
			td.word[0] := tdsize;
			td.word[1] := -4; (* sentinel *)
			td.word[2] := SYSTEM.ADR(td.word[root]); (* self *)
			td.word[3] := 0; (* filler *)
			k := SYSTEM.ADR(td.word[4]); j := 0;
			REPEAT ch := name[j]; SYSTEM.PUT(k, ch); INC(j); INC(k) UNTIL ch = 0X;
			td.word[12] := SYSTEM.ADR(m^); (* mdesc *)

			FOR j:=0 TO extlev-1 DO
				SYSTEM.GET( f.adrpos, t); INC( f.adrpos, 4); (* tag *) 
				IF t<0 THEN (* non exported tag *)
					SYSTEM.GET(m.sb+t,k); td.word[13+MaxExts-j]:=k;
					ELSE (* exported or imported *)
					mno:=t DIV 100H; eno:=t MOD 100H;
					IF mno=0 THEN td.word[13+MaxExts-j]:=m.entries[eno]
					ELSE SYSTEM.GET(m.imports[mno].entries[eno],k); td.word[13+MaxExts-j]:=k;
					END
				END
			END;
			td.word[13+MaxExts-extlev]:=SYSTEM.ADR(td.word[root]);
			FOR j:=extlev+1 TO MaxExts DO td.word[13+MaxExts-j]:=0 END;
			
			td.word[root - 1] := SYSTEM.ADR(td.word[0]); (* tag of subobj *)
			td.word[root] := recordSize;
			m.tdescs[i] := SYSTEM.ADR(td.word[root]);
			j := 0;
			WHILE j < nofPointers DO
				SYSTEM.GET( f.adrpos, offset ); INC( f.adrpos, 4);
				td.word[root+1+j] := offset; 
				INC(j)
			END;
			td.word[root+1+nofPointers] := -(nofPointers+1)*4; (* sentinel *)
			
			(* Fix the tag in the global var section *)
			SYSTEM.PUT(m.sb+tagaddr,types[i].tdaddr);
		END
	END ReadTypes;

	PROCEDURE BuildModuleBlock (m: Module; VAR head: Header);
	BEGIN
(*
		Kernel.WriteString("  head.nofEntries =");  Kernel.WriteInt(head.nofEntries,1);  Kernel.WriteLn;
		Kernel.WriteString("  head.nofPointers =");  Kernel.WriteInt(head.nofPointers ,1);  Kernel.WriteLn;
		Kernel.WriteString("  head.nofTypes =");  Kernel.WriteInt(head.nofTypes,1);  Kernel.WriteLn;
		Kernel.WriteString("  head.refSize =");  Kernel.WriteInt(head.refSize,1);  Kernel.WriteLn;
		Kernel.WriteString("  head.nofCommands =");  Kernel.WriteInt(head.nofCommands,1);  Kernel.WriteLn;
		Kernel.WriteString("  head.nofImports+1 =");  Kernel.WriteInt(head.nofImports+1,1);  Kernel.WriteLn;
*)
		NEW(m.entries,head.nofEntries);
		NEW(m.ptrTab,head.nofPointers);
		NEW(m.tdescs,head.nofTypes);
		NEW(m.refs,head.refSize);
		NEW(m.cmds,head.nofCommands);
		NEW(m.imports,head.nofImports+1); (* Imports are counted from 1 to nofImports! *)
		m.size:=head.strConstSize+head.dataSize+head.codeSize;
		m.addr:=modLoadAddr;
		m.sb:=m.addr+head.dataSize;
	END BuildModuleBlock;

	PROCEDURE ExtCallFixup(fixlist : LONGINT);
	VAR pos, mno, eno, cc, cw, addr: LONGINT; 
	BEGIN
		WHILE fixlist#0 DO
			pos:=fixlist+m.sb; SYSTEM.GET( pos, cw);
			mno:=cw DIV 100H MOD 100H; eno:=cw MOD 100H;
			cc:= 0EH;	(* cc= AL *)
			IF mno=0 THEN
				addr:=Kernel.runtime[eno];
				IF eno =4 THEN SYSTEM.GET( pos-4, cc); cc:=cc DIV 10000000H MOD 10H END;	(* get condition code from previous command *)
			ELSE 
				addr:=m.imports[mno].entries[eno];
			END;
			SYSTEM.PUT(pos,SYSTEM.LSH( cc, 28)+0B000000H+((addr-pos-8) DIV 4 MOD 1000000H)); (* ExtCall is never NV and only for SWI replacement # AL *)
			fixlist:=SYSTEM.LSH(cw,-17) MOD 8000H*4;	(* 0 .. 128 KB *)
		END;
	END ExtCallFixup;
	
	PROCEDURE ExtAddrFixup(fixlist: LONGINT);
	VAR pos, mno, eno, cw : LONGINT;
	BEGIN 
		WHILE fixlist#0 DO
			pos:=fixlist+m.sb; SYSTEM.GET(pos,cw);
			mno:=cw DIV 100H MOD 100H; eno:=cw MOD 100H;
			SYSTEM.PUT(pos,m.imports[mno].entries[eno]);
			fixlist:=SYSTEM.LSH(cw,-17) MOD 8000H*4;	(* 0 .. 128 KB *)
		END;
	END ExtAddrFixup;
	
	PROCEDURE Fixup(fixlist:LONGINT);
	VAR pos, cw : LONGINT;
	BEGIN
		WHILE fixlist#0 DO
			pos:=m.sb+fixlist; SYSTEM.GET(pos,cw);
			SYSTEM.PUT(pos,cw MOD 20000H + m.sb);
			fixlist:=SYSTEM.LSH(cw,-17) MOD 8000H*4;	(* 0 .. 128 KB *)
		END
	END Fixup;	

BEGIN (* LoadModule *)
	res := done;  resMsg := "";
	NEW(m);
	m.init := FALSE; m.refcnt := 0; m.term := NIL;

	(* header *)
	SYSTEM.GET( f.adrpos, head.refpos); INC( f.adrpos, 4);
	SYSTEM.GET( f.adrpos, head.entrypoint); INC( f.adrpos, 4);
	SYSTEM.GET( f.adrpos, head.nofImports); INC( f.adrpos, 2);
	SYSTEM.GET( f.adrpos, head.nofEntries); INC( f.adrpos, 2);
	SYSTEM.GET( f.adrpos, head.nofPointers); INC( f.adrpos, 2);
	SYSTEM.GET( f.adrpos, head.nofCommands); INC( f.adrpos, 2);
	SYSTEM.GET( f.adrpos, head.strConstSize); INC( f.adrpos, 4);
	SYSTEM.GET( f.adrpos, head.dataSize); INC( f.adrpos, 4);
	SYSTEM.GET( f.adrpos, head.codeSize); INC( f.adrpos, 4);
	SYSTEM.GET( f.adrpos, head.nofTypes); INC( f.adrpos, 2);
	SYSTEM.GET( f.adrpos, m.key); INC( f.adrpos, 4);
	ReadString(f,m.name);
	head.refSize:=f.length-head.refpos;
	BuildModuleBlock(m, head);
	
	IF res # done THEN m := NIL; RETURN END;

	(* Import block *)
	IF ~Expect(085X) THEN RETURN END;
	FOR i:=1 TO head.nofImports DO
		SYSTEM.GET( f.adrpos, mods[i].key); INC( f.adrpos, 4); ReadString(f,mods[i].name); 
	END; 	
				
	(* entry block *)
	IF ~Expect(082X) THEN RETURN END;
	FOR i:=0 TO head.nofEntries-1 DO SYSTEM.GET( f.adrpos, m.entries[i]); INC( f.adrpos, 4); INC(m.entries[i],m.sb) END; 		
	(* pointer block *)
	IF ~Expect(084X) THEN RETURN END;
	FOR i:=0 TO head.nofPointers-1 DO SYSTEM.GET( f.adrpos, m.ptrTab[i]); INC( f.adrpos, 4); INC(m.ptrTab[i],m.sb) END;
			
	(* command block *)
	IF ~Expect(083X) THEN RETURN END;
	FOR i:=0 TO head.nofCommands-1 DO 
		ReadString(f,m.cmds[i].name); 
		SYSTEM.GET( f.adrpos, m.cmds[i].adr); INC( f.adrpos, 4);
		INC(m.cmds[i].adr,m.sb)
	END; 
			
	(* code & string consts block *)
	IF (m.addr+m.size > 2000000H) THEN (* 32 MByte Barrier for Branches! *)
		res:=notEnoughSpace; ErrMsg(res);
		RETURN
	END;
	i := m.addr;	(* start of module block *)
	WHILE i<m.addr+head.dataSize DO
		SYSTEM.PUT( i, LONG(LONG(0))); INC(i,4)
	END;

	INC(modLoadAddr, m.size);
	IF (res=done) & Expect(088X) THEN 
		SYSTEM.MOVE( f.adrpos, m.sb, head.codeSize);
		INC(f.adrpos, head.codeSize);
	END;
	IF (res=done) & Expect(087X) THEN
		SYSTEM.MOVE( f.adrpos, m.sb+head.codeSize, head.strConstSize);
		INC(f.adrpos, head.strConstSize);
	END;

	(* load imported modules *)
	IF res=done THEN
		m.imports[0] := m;  i := 0;
		LOOP
			IF i >= head.nofImports THEN EXIT END;
			INC(i);
			Load(mods[i].name, m1);
			IF res # done THEN EXIT END;
			IF m1.key # mods[i].key THEN
				res := keyMismatch; importing := m.name; imported := mods[i].name; ErrMsg(res);
				EXIT
			END;
			m.imports[i] := m1
		END
	END;

	(* fixups *)
	IF (res=done) & Expect(086X) THEN 
		SYSTEM.GET( f.adrpos, i); INC( f.adrpos, 4); ExtCallFixup(i);
		SYSTEM.GET( f.adrpos, i); INC( f.adrpos, 4); ExtAddrFixup(i); 
		SYSTEM.GET( f.adrpos, i); INC( f.adrpos, 4); Fixup(i);
	END;

	(*tdescs *)
	IF (res=done) & Expect(089X) THEN ReadTypes(f) END;

	(* refs *)
	i:=f.length-(f.adrpos-f.adr);
	IF (res=done) & Expect(08BX) THEN SYSTEM.MOVE( f.adrpos, SYSTEM.ADR(m.refs^[0]), i); INC( f.adrpos, i) END;
		
	IF res = done THEN
		Find(m.name, m1);
		IF m1 # NIL THEN (* cyclic load, we're done *) m := m1; RETURN END;
		body:=SYSTEM.VAL(Command, m.sb+head.entrypoint);
		res2:=Linux0.CacheFlush0(m.addr, m.size);		(* end adr is calculatet in Kernel *)

		FOR i:=1 TO head.nofImports DO INC(m.imports[i].refcnt) END; 
		m.next := Kernel.modules; Kernel.modules := m;
		m.init := TRUE;
		Kernel.WriteHex( SYSTEM.ADR(m.addr), 8); Kernel.WriteHex(m.size, 9); Kernel.WriteChar(" "); Kernel.WriteString(m.name); Kernel.WriteLn;
		body;
		res := done	(* body may contain failing call to Modules *)
	ELSE
		m := NIL
	END
END LoadModule;

PROCEDURE Load (name: ARRAY OF CHAR; VAR m: Module);
CONST PROTREAD=1; PROTWRITE=2;
VAR f: File; i, j: INTEGER; fname: ARRAY 64 OF CHAR; tag: CHAR; res2: LONGINT;
BEGIN
	Find(name, m);  res := done;  resMsg := "";
	IF m = NIL THEN
		fname[ 0]:="a"; fname[1]:="r"; fname[2]:="m"; fname[3]:="/"; 		(* ARM version, Obj files in ./arm/ *)
		i:=0; j:=4;
		WHILE name[i] # 0X DO fname[j]:= name[i]; INC(i); INC(j) END ;
		fname[j] := "."; fname[j+1] := "O"; fname[j+2] := "b"; fname[j+3] := "j"; fname[j+4] := 0X;
(*
		i := 0;  j := 0;
		j := 0;
		WHILE name[j] # 0X DO fname[i] := name[j]; INC(i); INC(j) END;
		COPY(name, importing);
			(* add ".Obj" *)
		fname[i] := "."; fname[i+1] := "O"; fname[i+2] := "b"; fname[i+3] := "j"; fname[i+4] := 0X;
*)
		f.fd:= Linux0.Openat0(Linux0.ATFDCWD, SYSTEM.ADR(fname), 0, 0);
		IF f.fd <= 0 THEN
			COPY(name, importing);  res := fileNotFound; ErrMsg(res);
			RETURN
		END;
		f.length:= Length1( f);
		f.adr:=Linux0.Mmap20(0, f.length, 1, Linux0.MAPPRIVATE, f.fd, 0);	
		f.adrpos:=f.adr;

		SYSTEM.GET(f.adrpos, tag); INC(f.adrpos);
		IF tag = 0F5X THEN
			SYSTEM.GET(f.adrpos, tag); INC(f.adrpos);
			IF tag = 030X THEN
				LoadModule(f, m)
			ELSE res := invalidObjFile; ErrMsg(res)
			END
		ELSE
			res := invalidObjFile; ErrMsg(res)
		END;
		IF f.adr#0 THEN res2:=Linux0.Munmap0(  f.adr, f.length); f.adr:=0 END;
		res2:=Linux0.Close0( f.fd)
	ELSIF ~m.init THEN res := cyclicImport; ErrMsg(res)
	END;
END Load;

(** Returns a handle to an already loaded module, or loads a module and all its imported modules. *)

PROCEDURE ThisMod* (name: ARRAY OF CHAR): Module;
	VAR mod: Module;
BEGIN
	Kernel.DisableGC;
	Load(name, mod);
	Kernel.EnableGC;
	RETURN mod
END ThisMod;

(** Returns a procedure variable representing an exported command in a module. 
Calling this procedure executes the command. *)

PROCEDURE ThisCommand* (mod: Module; name: ARRAY OF CHAR): Command;
	VAR i: LONGINT;
BEGIN
	IF mod # NIL THEN
		i := LEN(mod.cmds^);
		WHILE i > 0 DO DEC(i);
			IF mod.cmds[i].name = name THEN
				res := done;  resMsg := "";
				RETURN SYSTEM.VAL(Command, mod.cmds[i].adr)
			END
		END;
		COPY(mod.name, imported);  COPY(name, importing); res := cmdNotFound; ErrMsg(res)
	END;
	RETURN NIL
END ThisCommand;

PROCEDURE Delete (m: Module);
	VAR m1: Module;
BEGIN
	(* Remove it from the module list *)
	m1 := Kernel.modules;
	IF m = m1 THEN
		Kernel.modules := m.next
	ELSE
		WHILE m1.next # m DO m1 := m1.next END;
		m1.next := m.next
	END
END Delete;

(** Free a module from memory. Only modules with no clients can be freed. The all flag 
requests that all imported modules should be freed too (i.e. a recursive call to Free). *)

PROCEDURE Free* (name: ARRAY OF CHAR; all: BOOLEAN);
	VAR m, m1: Module; i, j: LONGINT; h: Kernel.Proc;
BEGIN
	res := done;  resMsg := "";
	Find(name, m);
	IF m = NIL THEN COPY(name, importing); res := moduleNotFound; ErrMsg(res)
	ELSIF m.refcnt # 0 THEN importing := m.name; res := refCntNotZero; ErrMsg(res)
	ELSE
		IF m.term # NIL THEN h := m.term; m.term := NIL; h END;
		i := LEN(m.imports^);
		WHILE i > 1 DO DEC(i); m1 := m.imports[i]; DEC(m1.refcnt) END;
		IF all THEN i := LEN(m.imports^);
			WHILE i > 1 DO DEC(i); m1 := m.imports[i]; Free(m1.name, TRUE) END;
		res := done;  resMsg := ""
		END;
		Delete(m);
	END;
END Free;

(** InstallTermHandler - Install a procedure to execute when a module is freed. *)

PROCEDURE InstallTermHandler*(h: Kernel.Proc);
BEGIN
	Kernel.InstallTermHandler(h)
END InstallTermHandler;

(* test FStatat0 
PROCEDURE Do;
VAR t, d, i: LONGINT; buf: ARRAY 32 OF LONGINT;
BEGIN
	FOR i:=0 TO 31 DO buf[i]:=0 END;
	i:=Linux0.FStatat0( Linux0.ATFDCWD, SYSTEM.ADR("mips/Files.Obj"), SYSTEM.ADR(buf[0]), 0);
	FOR i:=0 TO 31 DO
		Kernel.WriteInt(buf[i], 9);
		Kernel.U2OTime( buf[i], d, t);
		Kernel.WriteLn;
	END;
END Do;
*)
BEGIN
	Kernel.Static:=FALSE;
	modLoadAddr:=Kernel.dynModBase;
	Kernel.WriteString("Modules.modLoadAddr= "); Kernel.WriteHex(modLoadAddr, 8); Kernel.WriteLn;
	loop:= ThisCommand(ThisMod("System"), "Init");
	Kernel.WriteString("System.Init = "); Kernel.WriteHex(SYSTEM.VAL(LONGINT,loop), 8); Kernel.WriteLn;
	IF loop # NIL THEN loop END;	(* should never return *)
	Kernel.WriteString("Oberon.Loop terminated!");
END Modules.

(** Remarks:

1. Oberon uses reference counting to determine how many clients of a module are loaded. 
A module can only be freed when the reference count is 0.

2. The res codes are not the same numerically on all Oberon platforms. It is advisable to use 
the resMsg as a correct indication of the error condition.

3. Module and command names are single words consisting of A to Z, a to z, and 0 to 9. 
Names must not start with a digit.

4. Care should be taken freeing modules. Oberon cannot detect if a client has a procedure 
variable still "pointing" at code in a freed module. Calling such a procedure can be 
unpredictable at times, although the system generates a trap most of the time.
*)