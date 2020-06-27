MODULE RBootLinker;	(* RC 2.12.93 *)	(* object model *)

(* p.m.
	2014-11-09	first version, removed skip Kernel.modules initialisized hardcoded
	2014-11-14	fixup NEW in Kernel
	2015-05-23	added Term in ModuleDesc
	2015-07-05	removed InitModule; MBootLinker, Kernel, Modules: static core initialization done in Kernel
	2015-07-20	output file created with correct permissions (octal 755)
	2015-12-09	importing Linux0
	2016-06-03	removed big endian, relocatabability, added risc-v
	2016-06-05	cleaned up
	2016-06-12	initialized Kernel.modules in InitKernel
	2016-11-22	added ARMv7 target, renamed to RBootLinker
	2017-04-03	not yet adapted to AOPL.NEWDATA=TRUE
	2017-06-05	FixupA: added softDiv for 32bit calls

	BootLinker does not assign procedure variables inside static core correctly!??

	Warning: softDiv hard coded! 
		
*)
	IMPORT S := SYSTEM, Linux0, Kernel, Files, Oberon, Texts ;

	CONST
		MIPS=1; RISCV=2; ARMv7=3; ARMv8=4; TEST=5;
(*		mipstag=0F9X; mipsttag= 0FAX; armv7tag=0FBX; armv8tag=0FCX; riscvtag=0FDX;	 not same as in ROP2 *)

		BootHeapSize = 20000H;
		targetHeapAdr = 10000H; 

		OptionChar = "\";

		NofPtrFix = 2000;	(* < 400 used for normal OLR static core *)
		
	ELF32hdrsz= 52;
	PHT32size= 32;	(* +12 byte padding *)

	ELF64hdrsz= 64;
	PHT64size= 56;	(* +8 byte padding *)

(*
	PadSize=12;
	ELFsize=ELFhdrsz+PHTsize+PadSize;	(* 96 *)
*)

	VAR
		W: Texts.Writer;
		heapAdr, bootEntryAdr, shift0, modulesVal: LONGINT;
		modTag: LONGINT;
		softDiv: LONGINT;
		showEntries : BOOLEAN;
		heap: S.PTR;
		ptrFix: ARRAY NofPtrFix OF LONGINT;
		ptrFixx: LONGINT;
		arch: LONGINT;
		archs: ARRAY TEST+1 OF ARRAY 6 OF CHAR;
		tags: ARRAY TEST+1 OF INTEGER;
		b64: BOOLEAN;

(*		Fixup: PROCEDURE(m: Module; entry, L: LONGINT; data: BOOLEAN);*)

(* ------------ Allocator (Kernel) declarations: ------------ *)

	TYPE
		Tag = POINTER TO TypeDesc;
		TypeDesc = RECORD
			size: LONGINT;
			ptroff: LONGINT
		END ;

		ADDRESS = LONGINT;
		Proc = PROCEDURE;

		FreePtr = POINTER TO FreeBlock;
		FreeBlock = RECORD
			(* off-4 *) tag: Tag;
			(* off0 *) size: LONGINT;	(* field size aligned to 8-byte boundary, size MOD B = B-4 *)
			(* off4 *) next: ADDRESS
		END ;

		InitPtr = POINTER TO RECORD tag: Tag; z0, z1, z2, z3, z4, z5, z6, z7: LONGINT END ;

	CONST
		B = 32;	(* must be a mutiple of 32 *)
		N = 9;
		nil = 0;
		mark = {0}; array = {1}; free = {2};
		
	VAR
		A: ARRAY N+1 OF (*FreePtr*) ADDRESS;

(* ------------ Loader (Modules) declarations: ------------ *)

	TYPE
		Name = ARRAY 32 OF CHAR;

		Command = PROCEDURE;

		Export = RECORD
			name: Name;
			fprint: LONGINT;
			adr: ADDRESS;
			mode: INTEGER
		END ;

		Cmd = RECORD
			name: Name;
			adr: ADDRESS
		END ;

		Bytes = POINTER TO ARRAY OF CHAR;

		Module = POINTER TO ModuleDesc;
		ModuleDesc = RECORD
			next: Module;
			name: Name;
			refcnt, sb, cb: LONGINT;	(* refcnt=-1 is not initialized; static base; code base for compatibility *)
			exports: POINTER TO ARRAY OF Export;
			tdescs: POINTER TO ARRAY OF (* Tag *) ADDRESS;
			cmds: POINTER TO ARRAY OF Cmd;
			ptrTab: POINTER TO ARRAY OF ADDRESS;
			imports: POINTER TO ARRAY OF (* Module *) ADDRESS;
			data0: POINTER TO ARRAY OF LONGINT;	(* data includes code *)
			refs: Bytes;
			term: Proc;
		END ;

		TDescDesc = POINTER TO RECORD
			tdsize, sentinel, self: LONGINT;
			ext: RECORD extlev: SHORTINT; filler: ARRAY 3 OF CHAR END ;
			name: Name;
			mdesc: Module;
			pvfprint: LONGINT
		END ;

	ELF32HDR= RECORD
		eIdent: ARRAY 16 OF CHAR;
		eType,
		eMachine: INTEGER;
		eVersion,
		eEntry,
		ePhoff,
		eShoff,
		eFlags: LONGINT;
		eEhsize,
		ePhentsize,
		ePhnum,
		eShentsize,
		eShnum,
		eShstrndx: INTEGER;
		pt: ARRAY 11 OF LONGINT;	(* program table; 12 byte padding *)
	END;

	ELF64HDR= RECORD
		eIdent: ARRAY 16 OF CHAR;
		eType,
		eMachine: INTEGER;
		eVersion,
		eEntryl, eEntryh,
		ePhoffl, ePhoffh,
		eShoffl, eShoffh,
		eFlags: LONGINT;
		eEhsize,
		ePhentsize,
		ePhnum,
		eShentsize,
		eShnum,
		eShstrndx: INTEGER;
		pt: ARRAY 16 OF LONGINT;	(* program table; 8 byte padding *)
	END;

	VAR
		modules: LONGINT;
		object: Name;
		objmode: Name;
		modeStr: ARRAY 9 OF Name;
		res, tag: INTEGER;
		KernelRoutines: ARRAY 4 OF RECORD name: Name; adr: ADDRESS END ;
		lastMod: LONGINT;
		
		eh3: ELF32HDR;		(* ELF 32 Header *)
		eh6: ELF64HDR;		(* ELF 64 Header *)

	CONST
		ModSize = SIZE(ModuleDesc);	(* on target machine!! *)
		done = 0;
		fileNotFound = 1;
		notAnObjFile = 2;
		fpMismatch = 3;
		corruptedObjFile = 4;
		cmdNotFound = 5;
		modNotFound = 6;
		notEnoughSpace = 7;
		refCntNotZero = 8;
		cyclicImport = 9;
		objNotFound = 10;

		ExtTabWordSize = 16;
		Tag0WordOffset = -2;
		Mth0WordOffset = Tag0WordOffset - ExtTabWordSize;

	
(* ------------------- Allocator procedures ------------------- *)

	PROCEDURE NewBlock(size: LONGINT): InitPtr;	(* size MOD B = 0 *)
		VAR i, rest: LONGINT; adr, AN: ADDRESS; ptr: InitPtr; restptr: FreePtr;
	BEGIN
		(*IF size < 0 (* NEW(p, MAX(LONGINT)) *) THEN HALT1 END ;*)
		i := size DIV B;
		IF i > N THEN i := N END ;
		adr := S.ADR(A[0]) + 4*i;
		AN := S.ADR(A[N]);	(* constant register *)
		LOOP
			S.GET(adr, ptr);
			IF adr = AN THEN
				LOOP
					IF ptr = NIL THEN res := notEnoughSpace;
						Texts.WriteString(W, "Pseudo-heap too small");
						Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf); RETURN NIL
					END ;
					IF ptr^.z0 + 4 >= size THEN EXIT END ;
					adr := S.ADR(ptr^.z1); S.GET(adr, ptr)
				END ;
				EXIT
			END ;
			IF ptr # NIL THEN EXIT END ;
			INC(adr, 4)
		END ;
		(* ptr # NIL *)
		S.PUT(adr, ptr^.z1);
		rest := ptr^.z0 + 4 - size;
		restptr := S.VAL(FreePtr, S.VAL(ADDRESS, ptr) + size);
		IF rest > 0 THEN	(* >= B >= 16 *)
			i := rest DIV B;
			IF i > N THEN i := N END ;
			restptr^.tag := S.VAL(Tag, S.VAL(SET, S.ADR(restptr^.size)) + free);
			restptr^.size := rest - 4;
			restptr^.next := A[i]; A[i] := S.VAL(ADDRESS, restptr)
		END ;
		RETURN ptr
	END NewBlock;
		
	PROCEDURE NewRec(tag: Tag; size: LONGINT): ADDRESS;	(* implementation of NEW(ptr) *)
		VAR ptr, init: InitPtr;
	BEGIN (* tag^.size = rectyp^.size *)
		size := S.VAL(LONGINT, S.VAL(SET, size + (4 (*tag*) + B-1))-S.VAL(SET, B-1));
		ptr := NewBlock(size);
		init := S.VAL(InitPtr, S.VAL(ADDRESS, ptr) + size - 32);
		init^.z0 := 0; init^.z1 := 0; init^.z2 := 0; init^.z3 := 0; init^.z4 := 0; init^.z5 := 0; init^.z6 := 0;
		WHILE init # ptr DO
			DEC(S.VAL(ADDRESS, init), 32);
			init^.z0 := 0; init^.z1 := 0; init^.z2 := 0; init^.z3 := 0; init^.z4 := 0; init^.z5 := 0; init^.z6 := 0; init^.z7 := 0
		END ;
		ptr^.tag := tag;
		RETURN S.VAL(ADDRESS, ptr) + 4
	END NewRec;
	
	PROCEDURE NewSys(size: LONGINT): ADDRESS;	(* implementation of S.NEW(ptr, size) *)
		VAR ptr, init: InitPtr;
	BEGIN
		size := S.VAL(LONGINT, S.VAL(SET, size + (28 + B-1))-S.VAL(SET, B-1));
		ptr := NewBlock(size);
		init := S.VAL(InitPtr, S.VAL(ADDRESS, ptr) + size - 32);
		WHILE init # ptr DO
			init^.tag := NIL; init^.z0 := 0; init^.z1 := 0; init^.z2 := 0; init^.z3 := 0; init^.z4 := 0; init^.z5 := 0; init^.z6 := 0;
			DEC(S.VAL(ADDRESS, init), 32);
		END ;
		ptr^.tag := S.VAL(Tag, S.ADR(ptr^.z0));
		ptr^.z0 := size - 4;
		ptr^.z1 := -4;
		init^.z2 := 0; init^.z3 := 0; init^.z4 := 0;
		ptr^.z5 := S.ADR(ptr^.z0);
		init^.z6 := 0;
		RETURN S.VAL(ADDRESS, ptr) + 28
	END NewSys;

(* ------------------- Loader procedures ------------------- *)

	PROCEDURE InitKernel(m: Module);
		VAR i, refs, end, lastAdr, adr, k: LONGINT; ch: CHAR; name: Name; td: TDescDesc;

		PROCEDURE RNum(VAR i: LONGINT);
			VAR n: LONGINT; shift: SHORTINT; x: CHAR;
		BEGIN
			shift := 0; n := 0; S.GET(refs, x); INC(refs);
			WHILE ORD(x) >= 128 DO
				INC(n, ASH(ORD(x) MOD 128, shift));
				INC(shift, 7); S.GET(refs, x); INC(refs);
			END ;
			i := n + ASH(ORD(x) MOD 64 - ORD(x) DIV 64*64, shift)
		END RNum;

		PROCEDURE ReadName(VAR n: ARRAY OF CHAR);
			VAR i: INTEGER; ch: CHAR;
		BEGIN i := 0;
			REPEAT S.GET(refs, ch); INC(refs); n[i] := ch; INC(i) UNTIL ch = 0X
		END ReadName;
	
	BEGIN
		bootEntryAdr := m.cb;
		i:=0;
		WHILE (i<LEN( m^.exports^)) & (m^.exports[i].name#"modules") DO INC(i) END;
		IF i=LEN( m^.exports^) THEN RETURN END;
		S.PUT( m^.exports[i].adr, modulesVal+shift0);	(* initialize Kernel.modules with correct adr and value *)
		INC(m.refcnt);	(* modules of boot file never unloaded toDo: *)

	(* find entries for KernelRoutines *)
		refs := S.ADR(m.refs[0]);
		end := refs + LEN(m.refs^);
		INC(refs);
		i := 0; lastAdr := 0;
		LOOP
			IF refs >= end THEN EXIT END ;
			RNum(adr);
			RNum(k); RNum(k); RNum(k); RNum(k);	(* saved.r, saved.f, frameSize, callArea *)
			ReadName(name);
			IF name = KernelRoutines[i].name THEN
				KernelRoutines[i].adr := m.cb+lastAdr*4; 
				IF i = 3  THEN (*INC( KernelRoutines[3].adr, shift0);*) EXIT END ;
				INC(i)
			END;			
			LOOP
				IF refs >= end THEN EXIT END ;
				S.GET(refs, ch); INC(refs);
				IF ch = 0F8X THEN EXIT END;
				INC(refs);
				RNum(k);	(* adr *)
				ReadName(name);
			END;
			lastAdr := adr;
		END;
		
(* from InitModules *)
	(* find ModuleDesc tag *)
		i := LEN(m.tdescs^);
		REPEAT
			DEC(i);
			modTag := S.VAL(LONGINT, m.tdescs[i]);
			S.GET(modTag - 4, td)
		UNTIL td.name = "ModuleDesc";
	(* patch all ModuleDesc tags *)
		m := S.VAL(Module, modules);
		WHILE m # NIL DO
			S.PUT(S.VAL(LONGINT, m) - 4, modTag);
			m := m.next
		END
	END InitKernel;

	PROCEDURE PTRFix( adr: LONGINT);
	BEGIN
		IF ptrFixx # -1 THEN
			IF ptrFixx < NofPtrFix THEN ptrFix[ptrFixx] := adr; INC(ptrFixx)
			ELSE ptrFixx := -1; res := notEnoughSpace;
				Texts.WriteString(W, "Too many ptr fixes");
				Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
			END
		END
	END PTRFix;

	PROCEDURE FixupM(m: Module; entry, L: LONGINT; data: BOOLEAN);
	CONST (* instruction format *)
		OP = 04000000H; JAL = 0C000000H; LUI = 03C000000H;
		RS = 200000H; RT = 10000H; IMM = 10000H; 
		VAR L1, c1, c2: LONGINT;
	BEGIN
		IF (entry#0) & (L # 0) THEN
			INC( entry, shift0);
			REPEAT
				L1 := L; S.GET( m.cb+L1*4, c1); (* := m.code[L1];*)
				L := L1 + ASH(S.LSH(c1, 16), -16) + 1;
				IF data THEN
					S.GET( m.cb+L1*4+4, c2); INC(c2, entry); (*c2 := m.code[L1+1] + entry;*)
					S.PUT(m.cb+L1*4, LUI + RT*((c1 DIV RS) MOD 32) + (c2 DIV IMM) MOD IMM+ASH(c2, -15) MOD 2);	(* Load/Store: IMM part is sign extended *)
					S.PUT(m.cb+L1*4+4, (c1 DIV IMM) * IMM + c2 MOD IMM);
				ELSE	(* procedure *)
					IF c1 DIV OP = LUI DIV OP THEN 	(* proc var *)
						S.PUT(m.cb+L1*4, (c1 DIV IMM) * IMM + (entry DIV IMM) MOD IMM);	(* IMM part is not sign extended *)
						S.GET(m.cb+L1*4+4, c2);
						S.PUT(m.cb+L1*4+4, (c2)+entry MOD IMM);
(*						INC(m.code[L1 + 1], entry MOD IMM);	(* wrong on overflow!*)*)
					ELSE	(* external call, (c1 DIV OP) * OP = JAL *)
						S.PUT(m.cb+L1*4, JAL + (entry DIV 4) MOD OP);
					END
				END
			UNTIL L = L1
		END
	END FixupM;

(* Linux0.Fixup, RBootLinker.FixupV and VDecoder.Obj is same *)
	PROCEDURE FixupV(m: Module; entry, L: LONGINT);
	CONST (* instruction format *)
		IMM12=1000H;  RA = 1; T0=7;
		LUI=37H; AUIPC=17H; JAL=6FH; JALR=67H; SB=23H;
	VAR L1, c1, c2: LONGINT;
	BEGIN
		IF (entry#0) & (L # 0) THEN
			INC( entry, shift0);
			REPEAT
				L1 := L; S.GET( m.cb+L1*4, c1);
				IF c1 MOD 80H= JAL THEN	(* procedure call, UJ format *)	(* to be fixed in OPL.Exit, adjustLink ? *)
					c2:= entry;
(*					IF m.code[L1+1]= 1 THEN c2:=KernelRoutines[3].adr ELSE c2:= entry END;  *)
					L := L1 + ASH(ASH( c1, -31), 18)+ASH( c1, -22) MOD 200H+ASH( ASH(c1, -20) MOD 2, 9)+ASH( ASH(c1, -12) MOD 100H, 10)+1;	(* to be fixed in OPL.Exit, adjustLink ?*)
					S.PUT( m.cb+L1*4, LUI+ASH(T0, 7)+(c2 DIV IMM12 +ASH( c2, -11) MOD 2) * IMM12); 
					S.PUT( m.cb+L1*4+4, JALR+ASH(RA, 7)+ASH(T0, 15)+ASH( c2 MOD IMM12, 20));
				ELSE
					L := L1 + ASH(c1, -15) + 1;
					S.GET( m.cb+L1*4+4, c2); INC(c2, entry);
					S.PUT( m.cb+L1*4, LUI + ASH( T0, 7)+ASH( ASH( c2, -12)+ASH(c2, -11) MOD 2, 12));	(* Store: IMM part is sign extended *);
					IF c1 MOD 80H DIV 8 = SB DIV 8 THEN	(* store, store fp *)
						S.PUT( m.cb+L1*4+4, c1 MOD 80H +ASH( c2 MOD 20H, 7)+ASH(ASH( c1, -12) MOD 8H, 12)+
							ASH( T0, 15) +ASH(ASH(c1, -7) MOD 20H, 20)+ ASH( ASH( c2, -5) MOD 80H , 25));	(* s-type *)
					ELSE														(* load, load fp, addi *)
						S.PUT( m.cb+L1*4+4,  ASH( T0, 15) + ASH( c2 MOD 1000H , 20)+c1 MOD 8000H);
					END;
				END
			UNTIL (L = L1) (*OR (L<0) OR (L>LEN(m.code^))*)
		END
	END FixupV;

(* Linux0.Fixup, RBootLinker.FixupV and ADecoder.Obj is same *)
PROCEDURE FixupA(m: Module; entry, L: LONGINT);
CONST (* instruction format *)
	BL=0EB000000H;	MOVIA2= 0E3000000H;	MOVT= 0E3400000H;
	IMM12=1000H; IMM16=10000H; IMM20= 100000H; IMM24=1000000H;  IMM28=10000000H;
VAR L1, c1, c2, c3: LONGINT;
BEGIN
	IF (entry#0) & (L # 0) THEN
		INC( entry, shift0);
		REPEAT
			L1 := L; S.GET( m.cb+L1*4, c1);
			IF c1 DIV IMM20= MOVIA2 DIV IMM20 THEN		(* load, store, adr *)
				L := L1  + S.LSH( c1, 16) DIV IMM16 +1;
				S.GET( m.cb+L1*4+4, c2);
				IF c2=MIN(LONGINT)+1 THEN
					c2:=softDiv;
(*
					S.GET( m.cb+L1*4+8, c3);
					ASSERT(c3 DIV 10H = 0E12FFF30H DIV 10H);
*)
				ELSE INC(c2, entry); (*c2 := m.data0[m.datasize+L1+1] + entry;*)
				END;
				S.PUT( m.cb+L1*4, MOVIA2+ c2 DIV IMM12 MOD 10H *IMM16+ c1 DIV IMM16 MOD 10H * IMM12+ c2 MOD IMM12);
				S.PUT( m.cb+L1*4+4, MOVT+ c2 DIV IMM28 MOD 10H *IMM16+ c1 DIV IMM16 MOD 10H * IMM12+ c2 DIV IMM16 MOD IMM12);
(*
			ELSIF c1 DIV IMM24= BL DIV IMM24 THEN	(* procedure call *)	(* to be fixed in OPL.Exit, adjustLink ? *)
				L := L1 + S.LSH( c1, 16) DIV IMM16+1;
				IF  (c1 DIV IMM16 MOD 100H=1) THEN S.PUT(m.cb+L1*4, BL+ (( softDiv-m.cb) DIV 4 -L1 -2 ) MOD IMM24);
					Texts.WriteHex( W, softDiv); Texts.WriteHex( W, L1*4); Texts.WriteHex( W, m.cb); Texts.WriteHex( W, (softDiv-m.cb) DIV 4-L1);
					Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf);
				ELSE S.PUT(m.cb+L1*4, BL+ ((entry -shift0-m.cb) DIV 4-L1-2 ) MOD IMM24);
				END;
*)
			ELSE HALT(72); (*d:=Write0(0, SYSTEM.ADR("Error in Linux0.Fixup "), 22); WriteHex( L*4); WriteHex( L1*4); WriteHex( c1); WriteHex( c2);*) RETURN
			END;
		UNTIL (L = L1) (*OR (L<0) OR (L>LEN(m.code^))*)
	END
END FixupA;

PROCEDURE Fixup(m: Module; entry, L: LONGINT; data: BOOLEAN);
BEGIN
	IF tag=36FDH THEN FixupV(m, entry, L)
	ELSIF tag=36FBH THEN FixupA(m, entry, L)
	ELSIF tag=36F9H THEN FixupM(m, entry, L, data)
	ELSE HALT(255);
	END;
END Fixup;
	
	PROCEDURE ^Load(name: ARRAY OF CHAR; VAR m: Module);

	PROCEDURE LoadModule(VAR R: Files.Rider; VAR m: Module);
		TYPE
			TDescBlock = POINTER TO RECORD word: ARRAY 32000 OF LONGINT END ;
			Type = RECORD tdb: TDescBlock; link, root, nofmeth, nofinhmeth, bmno, bpvfp: LONGINT; bname: Name END ;
			ExportPtr = POINTER TO Export;
			ArrPtr = POINTER TO RECORD a, b, c, len, data: LONGINT END ;
		VAR i, entry, link, fprint, k0, t0, curtd, limtd: LONGINT; m1, lm: Module; data: BOOLEAN; curexp, limexp: ExportPtr;
			refsize, nofimp, newreclink, newsyslink, newarrlink, datalink, datasize, consize, codesize: LONGINT;
			nofexp, nofdesc, nofcom, nofptr, linknr, expnr, descnr: INTEGER;
			name: Name; ch: CHAR; body: Command;
			links: ARRAY 256 OF RECORD entry, link: LONGINT END ;
			imps: ARRAY 32 OF Module;
			types: ARRAY 128 OF Type;
			arrPtr: ArrPtr;
			modname, impname: Name;

		PROCEDURE Block(tag: CHAR);
			VAR ch: CHAR;
		BEGIN Files.Read(R, ch);
			IF ch # tag THEN res := corruptedObjFile;
				Texts.WriteString(W, m.name); Texts.WriteString(W, " is corrupted");
				Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
			END
		END Block;
		
		PROCEDURE ReadType(VAR tdesc: ADDRESS);
			VAR tdb: TDescBlock; tdd: TDescDesc;
				i, tdsize, recsize, pvfp, bmno: LONGINT;
				nofmeth, nofnewmeth, mthno, nofptr, root, entry: LONGINT;
				name: Name;
		BEGIN
			Files.ReadString(R, name);
			IF name = "" THEN Files.ReadNum(R, pvfp) ELSE pvfp := 0 END ;
			Files.ReadNum(R, types[descnr].link); Files.ReadNum(R, recsize);
			Files.ReadNum(R, bmno); types[descnr].bmno := bmno;
			IF bmno >= 0 THEN Files.ReadString(R, types[descnr].bname);
				IF types[descnr].bname = "" THEN Files.ReadNum(R, types[descnr].bpvfp) END
			END ;
			Files.ReadNum(R, nofmeth); types[descnr].nofmeth := nofmeth; Files.ReadNum(R, types[descnr].nofinhmeth);
			Files.ReadNum(R, nofnewmeth); Files.ReadNum(R, nofptr);
			root := 14 (* tdsize..pvfp *) + nofmeth + ExtTabWordSize + 1 (* tag *);
			INC(root, (-root+2) MOD 4);	(* ADR(tdesc.a[root]) MOD 16 = 8 ! *)
			types[descnr].root := root;
			tdsize := (root + 1 (* recsize *) + nofptr + 1 (* sentinel *))*4;
			(* IF Kernel.LargestAvailable() < tdsize THEN importing := name; res := notEnoughSpace; RETURN END ; *)
			(* S.NEW(tdb, tdsize - 24 (* SysBlk header *)); *)
			tdb := S.VAL(TDescBlock, NewSys(tdsize - 24));
			IF tdb = NIL THEN RETURN END ;
			DEC(S.VAL(ADDRESS, tdb), 24);
			types[descnr].tdb := tdb; tdd := S.VAL(TDescDesc, tdb); PTRFix( S.ADR(tdd.tdsize) - 4);
			tdd.tdsize := tdsize;
			tdd.sentinel := -4;
			tdd.self := S.ADR(tdb.word[root]); PTRFix( S.ADR(tdd.self));
			tdd.name := name;
			tdd.mdesc := m; PTRFix( S.ADR(tdd.mdesc));
			tdd.pvfprint := pvfp;
			i := 0;
			WHILE i < nofnewmeth DO
				Files.ReadNum(R, mthno); Files.ReadNum(R, entry); INC(i);
				tdb.word[root + Mth0WordOffset - mthno] := m.cb+entry*4;
				PTRFix( S.ADR(tdb.word[root + Mth0WordOffset - mthno]))
			END ;
			tdb.word[root - 1] := S.ADR(tdb.word[0]); PTRFix( S.ADR(tdb.word[root - 1]));
			tdb.word[root] := recsize;
			i := 0;
			WHILE i < nofptr DO Files.ReadNum(R, tdb.word[root+1+i]); INC(i) END ;
			tdb.word[root+1+nofptr] := -(nofptr+1)*4;
			tdesc := S.ADR(tdb.word[root])
		END ReadType;

		PROCEDURE FindExp(mode: INTEGER; VAR name: Name; fprint: LONGINT; VAR adr: LONGINT);
		BEGIN
			LOOP
				IF curexp = limexp THEN res := objNotFound; object := name; objmode := modeStr[mode]; EXIT END ;
				IF (curexp.name = name) & (curexp.mode = mode) THEN
					IF curexp.fprint # fprint THEN res := fpMismatch; object := name; objmode := modeStr[mode] END ;
					adr := curexp.adr;
					INC(S.VAL(LONGINT, curexp), SIZE(Export));
					EXIT
				END ;
				INC(S.VAL(LONGINT, curexp), SIZE(Export))
			END
		END FindExp;

		PROCEDURE FindTDesc(VAR name: Name; fprint: LONGINT; VAR adr: LONGINT);
			VAR save, td: LONGINT; tdd: TDescDesc;
		BEGIN
			IF name = "" THEN save := curtd ELSE save := 0 END ;	(* anonymous tdescs are unsorted *)
			LOOP
				IF curtd = limtd THEN res := objNotFound; object := name; objmode := modeStr[8]; EXIT END ;
				S.GET(curtd, td); S.GET(td - 4, tdd);
				IF tdd.name = name THEN
					IF (tdd.pvfprint = fprint) OR (fprint = 0) THEN adr := td; INC(curtd, 4); EXIT END ;
					IF name # "" THEN res := fpMismatch; object := name; objmode := modeStr[8]; EXIT END
				END ;
				INC(curtd, 4)
			END ;
			IF save # 0 THEN curtd := save END
		END FindTDesc;

		PROCEDURE InitType(tdesc: ADDRESS; VAR type: Type);
			VAR tdb: TDescBlock; tdd: TDescDesc;
				l, r, t, k, base, tag, root, n, entry, pvfp: LONGINT; mb: Module;
		BEGIN
			tdb := type.tdb;
			IF tdb # NIL THEN	(* not done yet *)
				type.tdb := NIL;
				Fixup(m, tdesc, type.link, TRUE);
				k := 0; root := type.root; base := type.bmno;
				IF base # -1 THEN
					mb := S.VAL(Module, m.imports[base]);
					IF type.bname = "" THEN pvfp := type.bpvfp; t := -1;
						REPEAT	(* tdesc always present since local *)
							INC(t);
							S.GET(mb.tdescs[t] - 4, tdd)
						UNTIL tdd.pvfprint = pvfp
					ELSE l := 0; r := LEN(mb.tdescs^) - 1;
						LOOP
							IF l > r THEN EXIT END ;
							t := (l + r) DIV 2;
							S.GET(mb.tdescs[t] - 4, tdd);
							IF type.bname < tdd.name THEN r := t - 1
							ELSIF type.bname > tdd.name THEN l := t + 1
							ELSE EXIT
							END
						END ;
						IF l > r THEN res := objNotFound;
							Texts.WriteString(W, m.name); Texts.WriteString(W, " imports type descriptor of ");
							Texts.WriteString(W, mb.name); Texts.Write(W, "."); Texts.WriteString(W, type.bname);
							Texts.WriteString(W, ", not found"); Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf);
							RETURN
						END
					END ;
					IF base = 0 THEN InitType(mb.tdescs[t], types[t]) (* res always 0 here *) END ;
					base := mb.tdescs[t];
					S.GET(base + Tag0WordOffset*4, tag);
					WHILE tag # 0 DO
						tdb.word[root + Tag0WordOffset - k] := tag; PTRFix( S.ADR(tdb.word[root + Tag0WordOffset - k]));
						INC(k);
						S.GET(base + (Tag0WordOffset - k)*4, tag)
					END ;
					n := type.nofinhmeth;
					WHILE n > 0 DO DEC(n);
						entry := tdb.word[root + Mth0WordOffset - n];
						IF entry = 0 THEN
							S.GET(base + (Mth0WordOffset - n)*4, tdb.word[root + Mth0WordOffset - n]);
							PTRFix( S.ADR(tdb.word[root + Mth0WordOffset - n]))
						END
					END
				END ;
				S.PUT(S.ADR(tdb.word[3]), SHORT(SHORT(k)));	(* ok for little and big endian *)
				tdb.word[root + Tag0WordOffset - k] := S.ADR(tdb.word[root]);
				PTRFix( S.ADR(tdb.word[root + Tag0WordOffset - k]));
				(* INC(k);
				WHILE k < ExtTabWordSize DO tdb.word[root + Tag0WordOffset - k] := 0; INC(k) END ; *)
			END
		END InitType;

		PROCEDURE BuildModBlock;
			VAR t, gvarSize: LONGINT;
		BEGIN
			S.GET(S.VAL(ADDRESS, arrPtr) - 4, t);

			S.PUT(S.ADR(m.exports), S.VAL(ADDRESS, arrPtr) ); PTRFix( S.ADR(m.exports));
			arrPtr.len := nofexp;
			INC(S.VAL(ADDRESS, arrPtr), ((LONG(nofexp)*SIZE(Export) + 35) DIV 16)*16);
	
			S.PUT(S.VAL(ADDRESS, arrPtr) - 4, t); PTRFix( S.VAL(ADDRESS, arrPtr) - 4);
			S.PUT(S.ADR(m.tdescs), S.VAL(ADDRESS, arrPtr) ); PTRFix( S.ADR(m.tdescs));
			arrPtr.len := nofdesc;
			INC(S.VAL(ADDRESS, arrPtr), ((LONG(nofdesc)*4 + 35) DIV 16)*16);
	
			S.PUT(S.VAL(ADDRESS, arrPtr) - 4, t); PTRFix( S.VAL(ADDRESS, arrPtr) - 4);
			S.PUT(S.ADR(m.cmds), S.VAL(ADDRESS, arrPtr) ); PTRFix( S.ADR(m.cmds));
			arrPtr.len := nofcom;
			INC(S.VAL(ADDRESS, arrPtr), ((LONG(nofcom)*SIZE(Cmd) + 35) DIV 16)*16);
	
			S.PUT(S.VAL(ADDRESS, arrPtr) - 4, t); PTRFix( S.VAL(ADDRESS, arrPtr) - 4);
			S.PUT(S.ADR(m.ptrTab), S.VAL(ADDRESS, arrPtr) ); PTRFix( S.ADR(m.ptrTab));
			arrPtr.len := nofptr;
			INC(S.VAL(ADDRESS, arrPtr), ((LONG(nofptr)*4 + 35) DIV 16)*16);
	
			S.PUT(S.VAL(ADDRESS, arrPtr) - 4, t); PTRFix( S.VAL(ADDRESS, arrPtr) - 4);
			S.PUT(S.ADR(m.imports), S.VAL(ADDRESS, arrPtr) ); PTRFix( S.ADR(m.imports));
			arrPtr.len := nofimp+1;
			INC(S.VAL(ADDRESS, arrPtr), (((nofimp+1)*4 + 35) DIV 16)*16);

			gvarSize := datasize + (-datasize) MOD 8;
		
(*
			S.PUT(S.VAL(ADDRESS, arrPtr) - 4, t); PTRFix( S.VAL(ADDRESS, arrPtr) - 4);
			S.PUT(S.ADR(m.data), S.VAL(ADDRESS, arrPtr) ); PTRFix( S.ADR(m.data));
			arrPtr.len := (gvarSize + consize + 3) DIV 4;
			INC(S.VAL(ADDRESS, arrPtr), ((gvarSize + consize + 35) DIV 16)*16);
*)	
			S.PUT(S.VAL(ADDRESS, arrPtr) - 4, t); PTRFix( S.VAL(ADDRESS, arrPtr) - 4);
			S.PUT(S.ADR(m.data0), S.VAL(ADDRESS, arrPtr)); PTRFix( S.ADR(m.data0));
			m.sb := S.ADR(arrPtr.data) + (gvarSize+ consize+3) DIV 4*4; PTRFix( S.ADR(m.sb));
			m.cb:=S.ADR(arrPtr.data) + (gvarSize+ consize+3) DIV 4*4; PTRFix( S.ADR(m.cb));
			arrPtr.len := (gvarSize+ consize+3) DIV 4+codesize;
			INC(S.VAL(ADDRESS, arrPtr), ((gvarSize+ consize+3+codesize*4 + 35) DIV 16)*16);
	
			S.PUT(S.VAL(ADDRESS, arrPtr) - 4, t); PTRFix( S.VAL(ADDRESS, arrPtr) - 4);
			S.PUT(S.ADR(m.refs), S.VAL(ADDRESS, arrPtr)); PTRFix( S.ADR(m.refs));
			arrPtr.len := refsize;

		END BuildModBlock;

	BEGIN	(* m = NIL, res = done *)
	(* HeaderBlk *)
		Files.ReadLInt(R, refsize); Files.ReadInt(R, nofexp); Files.ReadInt(R, nofdesc); Files.ReadInt(R, nofcom);
		Files.ReadInt(R, nofptr); Files.ReadNum(R, nofimp); Files.ReadNum(R, newreclink); Files.ReadNum(R, newsyslink);
		Files.ReadNum(R, newarrlink); Files.ReadNum(R, datalink); Files.ReadNum(R, datasize); Files.ReadNum(R, consize);
		Files.ReadNum(R, codesize); Files.ReadString(R, modname);
	(* ImpBlk *)
		Block(81X); i := 0;
		WHILE i < nofimp DO
			Files.ReadString(R, impname);
			(*Load(impname, imps[i]); not recursive in BootLinker, all modules are listed in topological order *)
			m1 := S.VAL(Module, modules);
			WHILE (m1 # NIL) & (impname # m1.name) DO m1 := m1.next END ;
			IF m1 = NIL THEN res := modNotFound;
				Texts.WriteString(W, impname); Texts.WriteString(W, " must be loaded before ");
				Texts.WriteString(W, modname); Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf); RETURN
			END ;
			imps[i] := m1; INC(i)
		END ;
		m := S.VAL(Module, modules);
		WHILE (m # NIL) & (modname # m.name) DO m := m.next END ;
		IF m # NIL THEN res := cyclicImport;
			Texts.WriteString(W, "cyclic import of "); Texts.WriteString(W, modname);
			Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf);
			RETURN
		END ;
		(*IF Kernel.LargestAvailable() < SIZE(ModuleDesc) THEN importing := ""; res := notEnoughSpace; RETURN END ;*)
		(* NEW(m); *)
		k0 := ((LONG(nofexp)*SIZE(Export) + 35) DIV 16 + (LONG(nofdesc)*4 + 35) DIV 16 +
			(LONG(nofcom)*SIZE(Cmd) + 35) DIV 16 + (LONG(nofptr)*4 + 35) DIV 16 + ((nofimp+1)*4 + 35) DIV 16 +
			(datasize + (-datasize) MOD 8 + consize + codesize*4 + 35) DIV 16 + (refsize + 35) DIV 16)*16;
		(*IF Kernel.LargestAvailable() < k + 24 THEN importing := modname; m := NIL; res := notEnoughSpace; RETURN END ; *)
		m := S.VAL(Module, NewRec(S.VAL(Tag, modTag), ModSize)); PTRFix( S.ADR(m^) - 4);
		IF m = NIL THEN RETURN END;
		IF modulesVal=0 THEN modulesVal:=S.VAL( LONGINT, m) END; 
		lm := S.VAL(Module, lastMod);
		IF lm # NIL THEN lm.next := m; PTRFix( S.ADR(lm.next)) END ;
		lastMod := S.VAL(LONGINT, m);
		IF modules = 0 THEN modules := lastMod END ;
		m.name := modname; (*m.init := FALSE;*) m.refcnt := -1;
		(* S.NEW(arrPtr, k0); *)
		arrPtr := S.VAL(ArrPtr, NewSys(k0)); PTRFix( S.ADR(arrPtr^) - 28); PTRFix( S.ADR(arrPtr^) - 4);
		IF arrPtr = NIL THEN RETURN END ;
		BuildModBlock;
		m.imports[0] := S.ADR(m^); PTRFix( S.ADR(m.imports[0])); i := 0;
		WHILE i < nofimp DO
			m.imports[i+1] := S.ADR(imps[i]^); PTRFix( S.ADR(m.imports[i+1]));
			INC(imps[i].refcnt); INC(i)
		END ;
	(* ExpBlk *)
		Block(82X); linknr := 0; expnr := 0; descnr := 0; Files.Read(R, ch);
		WHILE ch # 0X DO
			IF ch = 8X THEN
				ReadType(m.tdescs[descnr]); PTRFix( S.ADR(m.tdescs[descnr])); INC(descnr);
				IF res # done THEN (*Delete(m);*) m := NIL; RETURN END
			ELSIF ch = 9X THEN	(* LinkProc *)
				Files.ReadNum(R, entry); links[linknr].entry := m.cb+entry*4;
				Files.ReadNum(R, links[linknr].link); INC(linknr)
			ELSE
				Files.ReadString(R, m.exports[expnr].name); Files.ReadNum(R, m.exports[expnr].fprint);
				m.exports[expnr].mode := ORD(ch);
				IF ch = 3X THEN Files.ReadNum(R, entry);
					m.exports[expnr].adr := m.sb+ entry; PTRFix( S.ADR(m.exports[expnr].adr))
				ELSIF ch = 4X THEN Files.ReadNum(R, entry);
					m.exports[expnr].adr := m.cb+entry*4; PTRFix( S.ADR(m.exports[expnr].adr))
				ELSIF ch = 6X THEN INC(expnr); m.exports[expnr].mode := 7;
					m.exports[expnr].name := m.exports[expnr-1].name; Files.ReadNum(R, m.exports[expnr].fprint)	(* pvfprint *)
				END ;
				INC(expnr)
			END ;
			Files.Read(R, ch)
		END ;
	(* CmdBlk *)
		Block(83X); i := 0; t0 := m.cb;
		WHILE i < nofcom DO
			Files.ReadString(R, m.cmds[i].name); Files.ReadNum(R, entry);
			m.cmds[i].adr := t0 + 4*entry; PTRFix( S.ADR(m.cmds[i].adr)); INC(i)
		END ;
	(* PtrBlk *)
		Block(84X); i := 0; t0 := m.sb; 
		WHILE i < nofptr DO Files.ReadNum(R, k0); m.ptrTab[i] := t0 + k0; PTRFix( S.ADR(m.ptrTab[i])); INC(i) END ;
	(* ConstBlk *)
		Block(87X); i := 0; t0:=S.ADR(m.data0^);
		WHILE i < consize DO Files.Read(R, ch); S.PUT(t0, ch); INC(t0); INC(i) END;
	(* CodeBlk *)
		Block(88X);
		i := 0; t0 := m.cb;
		WHILE i < codesize DO Files.ReadLInt(R, k0); S.PUT(t0, k0); INC(t0, 4); INC(i) END ;
		WHILE linknr > 0 DO DEC(linknr);
			Fixup(m, links[linknr].entry, links[linknr].link, FALSE);
		END;
		Fixup(m, KernelRoutines[0].adr, newreclink, FALSE);	(* Kernel already loaded *)
		Fixup(m, KernelRoutines[1].adr, newsyslink, FALSE);
		Fixup(m, KernelRoutines[2].adr, newarrlink, FALSE);
		Fixup(m, m.sb, datalink, TRUE);
	(* UseBlk *)
		Block(89X); i := 0;
		WHILE i < nofimp DO
			m1 := S.VAL(Module, m.imports[i+1]);
			curexp := S.VAL(ExportPtr, S.ADR(m1.exports^));
			limexp := S.VAL(ExportPtr, S.VAL(ADDRESS, curexp) + LEN(m1.exports^)*SIZE(Export));
			curtd := S.ADR(m1.tdescs^); limtd := curtd + LEN(m1.tdescs^)*4;
			Files.Read(R, ch);
			WHILE ch # 0X DO
				Files.ReadString(R, name); Files.ReadNum(R, fprint);
				CASE ch OF
				| 1X, 2X, 5X, 6X, 7X: FindExp(ORD(ch), name, fprint, entry); link := -1	(* no fixup*)
				| 3X, 4X: FindExp(ORD(ch), name, fprint, entry); Files.ReadNum(R, link); data := ch = 3X
				| 8X: IF name = "" THEN Files.ReadNum(R, link) ELSE link := fprint; fprint := 0 END;
						FindTDesc(name, fprint, entry); data := TRUE
				END ;
				IF res # done THEN
					IF res = fpMismatch THEN
						Texts.WriteString(W, m.name); Texts.WriteString(W, " imports ");
						Texts.WriteString(W, objmode); Texts.Write(W, " "); 
						Texts.WriteString(W, m1.name); Texts.Write(W, "."); Texts.WriteString(W, object);
						Texts.WriteString(W, " with bad fingerprint")
					ELSE
						Texts.WriteString(W, objmode); Texts.Write(W, " ");
						Texts.WriteString(W, m1.name); Texts.Write(W, ".");
						IF object = "" THEN Texts.WriteString(W, "'anonymous'") ELSE Texts.WriteString(W, object) END ;
						Texts.WriteString(W, " not found")
					END ;
					Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf); m := NIL; RETURN
				END ;
				IF link # -1 THEN Fixup(m, entry, link, data) END ;
				Files.Read(R, ch)
			END ;
			INC(i)
		END ;
	(* RefBlk *)
		Block(8AX); i := 0; t0:= S.ADR(m.refs[0]);
		WHILE i < refsize DO Files.Read(R, ch); S.PUT(t0, ch); INC(t0); INC(i) END ;
	(* init types *)
		i := 0;
		WHILE i < LEN(m.tdescs^) DO
			InitType(m.tdescs[i], types[i]);
			IF res # done THEN (*Delete(m);*) m := NIL; RETURN END ;
			INC(i)
		END ;
	(* execute body *)
		IF m.name = "Kernel" THEN InitKernel(m); 
			Fixup(m, KernelRoutines[0].adr, newreclink, FALSE); (* can be removed? No *) 
		ELSIF m.name="Linux0" THEN
			softDiv:=m.cb+shift0+20H; (* ugly, distance to Div hard coded *)
			
		END;
		(* body := S.VAL(Command, S.ADR(m.code[0])); *) m.refcnt:=0;
		(* Unix.Cacheflush(S.ADR(m.code[0]), codesize*4, 1); *)
		(* body; *)
	END LoadModule;

	PROCEDURE Load(name: ARRAY OF CHAR; VAR m: Module);
		VAR f: Files.File; R: Files.Rider; i, j: INTEGER; fname: ARRAY 64 OF CHAR; ch: CHAR;
	BEGIN
		m := S.VAL(Module, modules); res := done;
		WHILE (m # NIL) & (name # m.name) DO m := m.next END;
		IF m = NIL THEN
			COPY(archs[arch], fname);
			j:=0;
			REPEAT INC(j) UNTIL fname[j]=0X;
			fname [j]:="/"; INC(j);
			i:=0;
			WHILE name[i] # 0X DO fname[j]:= name[i]; INC(i); INC(j) END ;
			fname[j] := "."; fname[j+1] := "O"; fname[j+2] := "b"; fname[j+3] := "j";fname[j+4] := 0X;

			f := Files.Old(fname);
			IF f = NIL THEN res := fileNotFound;
				Texts.WriteString(W, fname); Texts.WriteString(W, " not found");
				Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf); RETURN
			END ;
			Files.Set(R, f, 0);
			Files.ReadInt(R, tag);
			IF tag=tags[arch] THEN LoadModule(R, m)
			ELSE res := notAnObjFile;
				Texts.WriteString(W, fname); Texts.WriteString(W, " not an object file");
				Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
			END
		END
	END Load;

	PROCEDURE Init;
		VAR a: ADDRESS; i, size: LONGINT; rest: FreePtr;
	BEGIN
		KernelRoutines[0].name := "NewRec"; KernelRoutines[0].adr := 0;
		KernelRoutines[1].name := "NewSys"; KernelRoutines[1].adr := 0;
		KernelRoutines[2].name := "NewArr"; KernelRoutines[2].adr := 0;
		KernelRoutines[3].name := "SysHalt"; KernelRoutines[3].adr := 0;

		modules := 0;	lastMod := 0;	modTag := 0;
		modulesVal:=0;
		ptrFixx := 0;
		i := 0;
		WHILE i < N DO A[i] := nil; INC(i) END;
		heapAdr := S.VAL(LONGINT, heap);

(*
		i:=heapAdr;
		WHILE i< heapAdr+BootHeapSize DO
			S.PUT( heapAdr, LONG(LONG(0))); INC(i, 4)
		END;
*)
		INC( heapAdr, (-heapAdr) MOD B);
		a := heapAdr + B - 4;
		size := S.VAL(LONGINT, heap) + BootHeapSize - a;
		DEC( size, size MOD B);
		rest := S.VAL(FreePtr, a);
		rest^.tag := S.VAL(Tag, S.ADR(rest^.size));
		rest^.size := size - 4;
		rest^.next := nil;
		A[N] := a;
		shift0:= targetHeapAdr - heapAdr;
		IF b64 THEN INC(shift0, +SIZE(ELF64HDR)) ELSE INC(shift0, +SIZE(ELF32HDR)) END;
	END Init;

	PROCEDURE RelocatePtr;
		VAR i, val, adr: LONGINT;
	BEGIN
		i := 0;
		WHILE i < ptrFixx DO adr := ptrFix[i]; S.GET(adr, val); S.PUT(adr, val+shift0); INC(i) END ;
	END RelocatePtr;
	
PROCEDURE MkELF32hdr( base, len, eflags: LONGINT; eMachine : INTEGER);
VAR i: LONGINT;
BEGIN
	eh3.eIdent[ 0]:= 7FX;
	eh3.eIdent[ 1]:= "E";
	eh3.eIdent[ 2]:= "L";
	eh3.eIdent[ 3]:= "F";
	eh3.eIdent[ 4]:= 1X;	(* EI_Class= ELFCLASS32 *)
	eh3.eIdent[ 5]:= 1X;	(* EI_DATA= ELFDASA2LSB *)
	eh3.eIdent[ 6]:= 1X;	(* EI_VERSION= EV_CURRENT *)
	eh3.eIdent[ 7]:= 0X;	(* EI_OSABI= UNIX-System V *)
	FOR i:= 8 TO 15 DO eh3.eIdent[ i]:= 0X END;	(* EI_PAD=0 *)
		(* ELF header *)
	eh3.eType:= 2;		(* e-type= ET_EXEC *)
	eh3.eMachine:= eMachine;
	eh3.eVersion:= 1;	(* e_version = EV_CURRENT *)
	eh3.eEntry:= base;	(* e_entry = virtual adr to first start control *)
	eh3.ePhoff:= ELF32hdrsz;	(* e_phoff = program header's table file offset *)
	eh3.eShoff:= 0; (*len+ELFhdrsz+PHTsize+PadSize +2*LEN(attr)+4*LEN(str)*);			(* e_shoff = section header table's file offset *)
	eh3.eFlags:= eflags;
	eh3.eEhsize:= ELF32hdrsz;	(* e_ehsize = ELF header's size in bytes *)
	eh3.ePhentsize:= PHT32size;	(* e_phentsize = size of one entry in file's program header table *)
	eh3.ePhnum:= 1;			(* e_phnum = number of entries in program header's table *)
	eh3.eShentsize:= 40;	(* e_shentsize = section header entry size, was 40*)
	eh3.eShnum:= 0;			(* e_shnum = 4 section headers *)
	eh3.eShstrndx:= 0;		(* e_shstrndx = SHN_UNDEF was: 3*)
	
	(* Program Header Table *)
	eh3.pt[ 0]:= 1;	(* p_type = PT_LOAD *)
	eh3.pt[ 1]:= 0; (* was ELFhdrsz+PHTsize+PadSize;*)	(* p_offset = offset from the beginning of the file to first byte of segment *)
	eh3.pt[ 2]:= targetHeapAdr;	(* p_vadr = virtual adr of the first byte in memory *)
	eh3.pt[ 3]:= 0;	(* p_padr = physical adr ignored *)
	eh3.pt[ 4]:= len;	(* p_filesz = number of bytes in the file image of the segment *)
	eh3.pt[ 5]:= BootHeapSize;	(* p_memsz = number of bytes in memory of the segment *)
	eh3.pt[ 6]:= 7;	(* p_flags = PF_R+ PF_W+ PF_X, allow read, write, execution *)
	eh3.pt[ 7]:= 10000H;	(* p_align = page size; MIPS Creator Ci20 might need 10000H*)
	IF arch=ARMv7 THEN eh3.pt[ 7]:= 8000H END;
	eh3.pt[ 8]:= 0;		(* pad *)
	eh3.pt[ 9]:= 0;
	eh3.pt[ 10]:= 0;
END MkELF32hdr;

PROCEDURE MkELF64hdr( base, len, eflags : LONGINT; eMachine: INTEGER);
VAR i: LONGINT;
BEGIN
	eh6.eIdent[ 0]:= 7FX;
	eh6.eIdent[ 1]:= "E";
	eh6.eIdent[ 2]:= "L";
	eh6.eIdent[ 3]:= "F";
	eh6.eIdent[ 4]:= 2X;	(* EI_Class= ELFCLASS64 *)
	eh6.eIdent[ 5]:= 1X;	(* EI_DATA= ELFDASA2LSB *)
	eh6.eIdent[ 6]:= 1X;	(* EI_VERSION= EV_CURRENT *)
	eh6.eIdent[ 7]:= 0X;	(* EI_OSABI= UNIX-System V *)
	FOR i:= 8 TO 15 DO eh6.eIdent[ i]:= 0X END;	(* EI_PAD=0 *)
		(* ELF header *)
	eh6.eType:= 2;		(* e-type= ET_EXEC *)
	eh6.eMachine:= eMachine;
	eh6.eVersion:= 1;	(* e_version = EV_CURRENT *)
	eh6.eEntryl:= base; eh6.eEntryh:= 0;	(* e_entry = virtual adr to first start control *)
	eh6.ePhoffl:= ELF64hdrsz; eh6.ePhoffh:= 0;	(* e_phoff = program header's table file offset *)
	eh6.eShoffl:= 0; eh6.eShoffh:= 0; (*len+ELFhdrsz+PHTsize+PadSize +2*LEN(attr)+4*LEN(str)*);			(* e_shoff = section header table's file offset *)
	eh6.eFlags:= eflags;	
	eh6.eEhsize:= ELF64hdrsz;	(* e_ehsize = ELF header's size in bytes *)
	eh6.ePhentsize:= PHT64size;	(* e_phentsize = size of one entry in file's program header table *)
	eh6.ePhnum:= 1;			(* e_phnum = number of entries in program header's table *)
	eh6.eShentsize:= 64;	(* e_shentsize = section header entry size, was 40*)
	eh6.eShnum:= 0;			(* e_shnum = 4 section headers *)
	eh6.eShstrndx:= 0;		(* e_shstrndx = SHN_UNDEF was: 3*)
	
	(* Program Header Table *)
	eh6.pt[ 0]:= 1;	(* p_type: PT_LOAD=1, PT_PHDR=6 *)
	eh6.pt[ 1]:= 7; 	(* p_flags ?? *)
	eh6.pt[ 2]:= 0;	(*p_offset_l *)
	eh6.pt[ 3]:= 0;	(* p_offset_h *)
	eh6.pt[ 4]:= targetHeapAdr; (* p_vadr_l *)	(* p_offset = offset from the beginning of the file to first byte of segment *)
	eh6.pt[ 5]:= 0;	(* p_vadr_h *)
	eh6.pt[ 6]:= targetHeapAdr;	(* p_padr_l = physical adr ignored *)
	eh6.pt[ 7]:= 0;	(*  p_padr_h *)
	eh6.pt[ 8]:= len;	(* p_filesz_l *)
	eh6.pt[ 9]:= 0;	(* p_filesz_h *)
	eh6.pt[ 10]:= BootHeapSize;	(* p_memsz_l *)
	eh6.pt[ 11]:= 0;		(* p_memsz_h *)
	eh6.pt[ 12]:= 10000H;	(* p-align_l *)
	eh6.pt[ 13]:= 0;	(* p-align_h *)
	eh6.pt[ 14]:= 0;
	eh6.pt[ 15]:= 0;
END MkELF64hdr;

	PROCEDURE Out(VAR bootName: ARRAY OF CHAR);
		VAR end, of, r0: LONGINT;
			m: Module;  
	BEGIN
		IF modTag = 0 THEN res := modNotFound;
			Texts.WriteString(W, "Modules (Kernel)not loaded");
			Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf); RETURN
		END ;
	(* cut heap *)
		end := S.VAL(LONGINT, NewBlock(B*N));
	(* find data blocks to be skipped p.m.: not skipped any more *)
		m := S.VAL(Module, modules);
		WHILE m # NIL DO
			IF showEntries THEN Texts.WriteLn(W);
				Texts.WriteString(W, "  "); Texts.WriteString(W, m.name);
				Texts.WriteString(W, " body at "); Texts.WriteHex(W, m.cb + shift0); Texts.Write(W, "H")
			END;
			m := m.next
		END;
		Texts.WriteLn(W);
	(* output heap *)
		RelocatePtr;

	(* create bootfile with correct permissions and copy data *)
		of:= Linux0.Openat0( Linux0.ATFDCWD, S.ADR(bootName[0]), Linux0.ORDWR+Linux0.OCREAT+Linux0.OTRUNC, 1EDH);	(* mode = octal 755 *)
		Texts.WriteString(W, " little endian heap: "); Texts.WriteInt(W, end - heapAdr, 0); Texts.WriteString(W, "  file: ");
		IF b64 THEN
			(* MIPS: see https://dmz-portal.mips.com/wiki/MIPS_ELF_header_definitions ; 200H= 64 bit FP *)
			IF arch=MIPS THEN MkELF64hdr( bootEntryAdr+shift0,  end - heapAdr+SIZE(ELF64HDR), 80000000H, 8);
			ELSIF arch=RISCV THEN MkELF64hdr( bootEntryAdr+shift0,  end - heapAdr+SIZE(ELF64HDR), 0, 243);
			ELSIF arch=ARMv8 THEN MkELF64hdr( bootEntryAdr+shift0,  end - heapAdr+SIZE(ELF64HDR), 0, 183);
			ELSE Texts.WriteString(W, "64 bit target not supported ");
			END;
(*S.PUT( bootEntryAdr+4, LONG(LONG(0)));*)
			r0:=Linux0.Write0( of, S.ADR(eh6), SIZE(ELF64HDR));
			Texts.WriteInt(W, end - heapAdr+SIZE(ELF64HDR), 0);
		ELSE
			(* ARMv7: eMachine:= 40 *)
			IF arch=MIPS THEN MkELF32hdr( bootEntryAdr+shift0,  end - heapAdr+SIZE(ELF32HDR), 70000000H, 8);
			ELSIF arch=RISCV THEN MkELF32hdr( bootEntryAdr+shift0,  end - heapAdr+SIZE(ELF32HDR), 0, 243);
			ELSIF arch=ARMv7 THEN MkELF32hdr( bootEntryAdr+shift0,  end - heapAdr+SIZE(ELF32HDR), 5000402H, 40);
			ELSE Texts.WriteString(W, "32 bit target not supported ");
			END;
			r0:=Linux0.Write0( of, S.ADR(eh3), SIZE(ELF32HDR));
			Texts.WriteInt(W, end - heapAdr+SIZE(ELF32HDR), 0);
		END;
		r0:=Linux0.Write0( of, heapAdr, end - heapAdr);
		r0:=Linux0.Close0( of);
	END Out;

	PROCEDURE GetArgs(VAR S: Texts.Scanner);
		VAR text: Texts.Text; beg, end, time: LONGINT;
	BEGIN
		Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos); Texts.Scan(S);
		IF (S.line # 0) OR (S.class # Texts.Name) & (S.class # Texts.Int) THEN
			Oberon.GetSelection(text, beg, end, time);
			IF time>=0 THEN Texts.OpenScanner(S, text, beg); Texts.Scan(S) END
		END
	END GetArgs;
	
	PROCEDURE Link*;
		VAR bootName: Name; s: Texts.Scanner; VAR m: Module; ch: CHAR;
	BEGIN softDiv:=0;
		GetArgs(s);
		IF s.class = Texts.Int THEN
			Texts.WriteString(W, "  targetHeapAdr now fixed in BootLinker/Kernel"); Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf);
			RETURN
		END;

		IF s.class = Texts.Name THEN COPY(s.s, bootName); Texts.Scan(s) ELSE RETURN END ;
		showEntries := FALSE;
		IF (s.class = Texts.Char) & (s.c = OptionChar) THEN
			ch := s.nextCh;
			LOOP
				IF ch = " " THEN EXIT
				ELSIF ch = "e" THEN showEntries := TRUE
				ELSE
					IF (ch)="A" THEN arch:= ARMv8;
					ELSIF ch="a" THEN arch:= ARMv7;
					ELSIF CAP(ch)="M" THEN arch:= MIPS;
					ELSIF CAP(ch)="V" THEN arch:= RISCV;
					ELSIF CAP(ch)="T" THEN arch:= TEST
					ELSE Texts.WriteString(W, "  unknown option"); Texts.WriteLn(W);
						Texts.Append(Oberon.Log, W.buf); RETURN
					END;
					b64:=ch=CAP(ch);
				END;
				Texts.Read(s, ch)
			END ;
			s.nextCh := ch; Texts.Scan(s)
		END ;
		IF (s.class = Texts.Char) & (s.c = ":") THEN Texts.Scan(s) ELSE RETURN END;
		IF (s.class = Texts.Char) & (s.c = "=") THEN Texts.Scan(s) ELSE RETURN END;
		IF s.class = Texts.Name THEN
			Init;
			Texts.WriteString(W, "linking ");
			Texts.WriteString(W, bootName);
			Texts.WriteString(W, " ("); Texts.WriteString(W, archs[arch]); 
			IF b64 THEN Texts.WriteString(W, ", 64Bit)");
			ELSE Texts.WriteString(W, ", 32Bit)");
			END;
			Texts.Append(Oberon.Log, W.buf);
			res := done;
			REPEAT Load(s.s, m); Texts.Scan(s) UNTIL (s.class # Texts.Name) OR (res # done);
			IF res = done THEN Out(bootName) ELSE Texts.WriteString(W, "failed") END;
			Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
		END;
		Oberon.Collect;
	END Link;

BEGIN
	Texts.OpenWriter(W); S.NEW(heap, BootHeapSize);
	modeStr[1] := "constant";
	modeStr[2] := "type";
	modeStr[3] := "variable";
	modeStr[4] := "procedure";
	modeStr[5] := "code procedure";
	modeStr[6] := "public structure of";
	modeStr[7] := "private structure of";
	modeStr[8] := "type descriptor of";
	archs[ MIPS]:= "mips"; tags[MIPS]:= 36F9H;
	archs[ RISCV]:= "riscv"; tags[RISCV]:= 36FDH;
	archs[ ARMv7]:="armv7"; tags[ARMv7]:= 36FBH;
	archs[ ARMv8]:="armv8"; tags[ ARMv8]:= 36FCH (*36FBH *);
	archs[ TEST]:= "mipst"; tags[TEST]:= 36FAH;
END RBootLinker.

MIPSBootLinker.Link [heapAdr] bootFileName := modName0 modName1 ... ~

	All module names must be listed and topologically sorted.
	If the optional heap address is present, no relocation information is generated.

Boot File Format:

	heapAdr4
	heapSize4
	{adr4 len4 {int4}}		(* len4/4 times int4 *)
	entryAdr4 0X 0X 0X 0X
[
	nofPtr {adr}				(* nofPtr times adr, etc... *)
	nofWord {adr}
	nofDouble {adr}
	nofProc {adr}
	nofJal {adr}
	dlsymAdr	-- removed by p.m.
]

	All numbers in the relocate information part are in compact format.
	adr*4 is an offset from heapAdr4.
