MODULE Modules;	(* RC 14.2.94 *)	(* object model *)

(*
	common for RISC-V, MIPS  and ARMv7

	tag: mips: 36F9H; mipst: 36FAH; arm: 36FBH;

	p.m.:
	2015-03-30	removed S.GETREG(7, r) after Kernel.Open0( S.ADR(fname), 0, 0);	(check now in Kernel.Open0)	not tested!
	2015-04-17	removed Kernel.GC in ThisMod
	2015-06-10	added crude error messages similar like ARM, X86, changed initialization 
	2015-07-05	MBootLinker, Kernel, Modules: static core initialization done in Kernel
	2015-12-09	imported Linux0
	2016-06-06	removed 8byte access in Fixup
	2016-10-03	removed ModNameLen, changed imps in Load from ARRAY 32 TO ARRAY 64 OF Module because of hidden imports
	2017-03-24	WIP changing data layout
*)

	IMPORT Linux0, Kernel, S := SYSTEM;

	TYPE
		ModuleName* = Kernel.Name;
		Command* = PROCEDURE;

		ADDRESS = LONGINT;

		Export* = Kernel.Export;

		Cmd* = Kernel.Cmd;

		Module* = Kernel.Module;
		ModuleDesc* = Kernel.ModuleDesc;
		
		File = RECORD
			fd, adr, adrpos, length: LONGINT;
		END;
					
	VAR
		res*: INTEGER;
		resMsg*: ARRAY 256 OF CHAR;
		resMsgLen: LONGINT;
		imported, importing, objname: ModuleName;

	CONST
		done = 0;
		fileNotFound = 1;
		invalidObjFile = 2;
		fpMismatch = 3;
		corruptedObjFile = 4;
		cmdNotFound = 5;
		moduleNotFound = 6;
		notEnoughSpace = 7;
		refCntNotZero = 8;
		cyclicImport = 9;	(* not detected any more *)
		objNotFound = 10;
		tooManyFiles = 11;
		incompImport = 16;

		ExtTabWordSize = 16;
		Tag0WordOffset = -2;
		Mth0WordOffset = Tag0WordOffset - ExtTabWordSize;
	
	VAR
		loop: Command;
		modeStr: ARRAY 9 OF ModuleName;

PROCEDURE FSize( fd: LONGINT): LONGINT;
VAR res: LONGINT; status: Linux0.Status;
BEGIN
	res:=Linux0.FStat0(  fd, S.ADR(status));
	RETURN status.size;
END FSize;
	
PROCEDURE ReadString(VAR r: File; VAR x: ARRAY OF CHAR);
VAR i: INTEGER; ch: CHAR;
BEGIN i := 0;
	LOOP
		S.GET( r.adrpos, ch); INC( r.adrpos); x[i] := ch; INC(i);
		IF ch = 0X THEN EXIT END;
		IF i = LEN(x) THEN x[i-1] := 0X;
			REPEAT S.GET( r.adrpos, ch); INC( r.adrpos) UNTIL ch = 0X;
			EXIT
		END
	END
END ReadString;

(* From Files.  Reads a number in compressed variable length notation using the minimum amount of bytes. *)
PROCEDURE ReadNum(VAR r: File; VAR x: LONGINT);
VAR ch: CHAR; n: INTEGER; y: LONGINT;
BEGIN
	n := 0; y := 0; S.GET( r.adrpos, ch); INC( r.adrpos);
	WHILE ch >= 80X DO 
		INC(y, S.LSH(LONG(ch) - 128, n)); INC(n, 7); S.GET( r.adrpos, ch); INC( r.adrpos);
	END;
	x := ASH(S.LSH(LONG(ch), (Linux0.RegSize - 7) (*-25+32*) ), n-(Linux0.RegSize - 7) (*+25-32*) ) + y;
END ReadNum;

(* Error Messages *)

PROCEDURE Ch(ch: CHAR);
BEGIN
	IF resMsgLen # LEN(resMsg)-1 THEN
		resMsg[resMsgLen] := ch; INC(resMsgLen); resMsg[resMsgLen] := 0X
	END
END Ch;

PROCEDURE Str(s: ARRAY OF CHAR);
VAR i: LONGINT;
BEGIN
	i := 0; WHILE s[i] # 0X DO Ch(s[i]); INC(i) END
END Str;

PROCEDURE Ln;
BEGIN	Ch(0DX)
END Ln;

PROCEDURE Clear;
BEGIN
	resMsg[0] := 0X; resMsgLen := 0
END Clear;

PROCEDURE ErrMsg(res: INTEGER);
BEGIN
	IF res # 0 THEN
		Clear;  Str(importing);
		IF (res = fileNotFound) OR (res = moduleNotFound) THEN Str(" not found")
		ELSIF res = invalidObjFile THEN Str(" not an obj-file")
		ELSIF res = corruptedObjFile THEN Str(" corrupted obj file")
		ELSIF res = notEnoughSpace THEN Str(" not enough space")
		ELSIF res = refCntNotZero THEN Str(" reference count not zero")
		ELSIF res = cyclicImport THEN Str(" cyclic import")
		ELSIF res = incompImport THEN
			Str(" imports incompatible version of ");  Str(imported);
		ELSIF res = cmdNotFound THEN
			Clear;  Str(imported);  Ch(".");  Str(importing);
			Str(" command not found");  (* assumes importing = procedure name and imported = module name *)
		ELSIF res = objNotFound THEN
			Clear;  Str(imported);  Ch(".");  Str(objname);
			Str(" object not found");
		ELSIF res =  fpMismatch THEN Str(" fp mismatch");
		ELSE Str(" unknown error code")
		END;
		Kernel.WriteString("Modules: ");  Kernel.WriteString(resMsg);  Kernel.WriteLn
	END
END ErrMsg;

PROCEDURE FindMod*(name: ARRAY OF CHAR): Module;
VAR m: Module;
BEGIN
	m := Kernel.modules;
	WHILE (m # NIL) & (m.name # name) DO m := m.next END;
	RETURN m
END FindMod;

(*
	PROCEDURE FindRoots;
		VAR m: Module; i, p, ptradr: LONGINT; ptr: Kernel.BlockPtr;
	BEGIN
		m := modules;	(* ModuleDesc and ModuleBlock are marked via modules *)
		WHILE m # NIL DO
			i := LEN(m.ptrTab^); ptradr := S.ADR(m.ptrTab[0]);
			WHILE i > 0 DO
				S.GET(ptradr, p); S.GET(p, ptr);
				IF ptr # NIL THEN Kernel.Mark( ptr) END ;
				DEC(i); INC(ptradr, 4)
			END ;
			i := LEN(m.tdescs^); ptradr := S.ADR(m.tdescs[0]);
			WHILE i > 0 DO
				S.GET(ptradr, ptr); Kernel.Mark(ptr);
				DEC(i); INC(ptradr, 4)
			END ;
			m := m^.next
		END
	END FindRoots;

	PROCEDURE FindAmbRoots;
		VAR i, p, sp: LONGINT;
			(* Chameleon: ctxt: Mips.ExcContextPtr; usp, ssp: LONGINT *)
			(* DECoberon: *) ctxt: Kernel.SigCPTR;
	BEGIN
		S.GETREG(29, sp);
(* Chameleon:
		S.GETREG(28, ctxt);			
		IF sp <= Kernel.UserStackAdr THEN usp := sp; ssp := S.ADR(ctxt^)
		ELSE usp := ctxt.r[29]; ssp := sp
		END ;
		(* user stack *)
		WHILE usp < Kernel.UserStackAdr DO
			S.GET(usp, p); Kernel.Candidate(p);
			INC(usp, 4)
		END ;
		(* system stack *)
		WHILE ssp < Kernel.SysStackAdr DO
			S.GET(ssp, p); Kernel.Candidate(p);
			INC(ssp, 4)
		END ;
*)
(* DECoberon: *)
		IF Kernel.handlingtrap THEN	(* running on system stack *)
			WHILE sp < Kernel.sysStackBot DO	(* system stack *)
				S.GET(sp, p); Kernel.Candidate(p);
				INC(sp, 4)
			END ;
			ctxt := S.VAL(Kernel.SigCPTR, Kernel.curSigCtxt);
			i := 1;
			WHILE i < 26 DO p := ctxt.regs[Unix.RegW*i+Unix.RegW DIV 2]; Kernel.Candidate(p); INC(i) END ;
			sp := ctxt.regs[Unix.RegW*29+Unix.RegW DIV 2];
			IF (sp >= Kernel.sysStackTop) & (sp < Kernel.sysStackBot) THEN
				(* interrupted on system stack, cannot GC user stack *)
				sp := Kernel.jmpBuf.sp
			END
		END ;
		WHILE sp < Kernel.jmpBuf.sp DO	(* user stack *)
			S.GET(sp, p); Kernel.Candidate(p);
			INC(sp, 4)
		END ;
		(* callee-saved general registers *)
		S.GETREG(16, p); Kernel.Candidate(p);
		S.GETREG(17, p); Kernel.Candidate(p);
		S.GETREG(18, p); Kernel.Candidate(p);
		S.GETREG(19, p); Kernel.Candidate(p);
		S.GETREG(20, p); Kernel.Candidate(p);
		S.GETREG(21, p); Kernel.Candidate(p);
		S.GETREG(22, p); Kernel.Candidate(p);
		S.GETREG(23, p); Kernel.Candidate(p)
	END FindAmbRoots;
*)
	
	PROCEDURE Delete(m: Module);
		VAR m1: Module; i: LONGINT;
	BEGIN
		m1 := Kernel.modules;
		IF m1 = m THEN Kernel.modules := m.next
		ELSE
			WHILE m1.next # m DO m1 := m1.next END ;
			m1.next := m.next
		END ;
		i := LEN(m.imports^);
		WHILE i > 1 DO DEC(i); m1 := S.VAL(Module, m.imports[i]); DEC(m1.refcnt) END
	END Delete;

	PROCEDURE ^Load( name: ARRAY OF CHAR; VAR m: Module);

	PROCEDURE LoadModule(VAR f: File; VAR m: Module);
		TYPE
			TDescBlock = POINTER TO RECORD word: ARRAY 32000 OF LONGINT END ;
			TDescDesc = POINTER TO RECORD
				tdsize, sentinel, self: LONGINT;
				ext: RECORD extlev: SHORTINT; filler: ARRAY 3 OF CHAR END ;
				name: ModuleName;
				mdesc: Module;
				pvfprint: LONGINT
			END ;
			Type = RECORD tdb: TDescBlock; link, root, nofmeth, nofinhmeth, bmno, bpvfp: LONGINT; bname: ModuleName END ;
			ExportPtr = POINTER TO Export;
			ArrPtr = POINTER TO RECORD a, b, c, len, data: LONGINT END;

		VAR i, entry, link, fprint, k, t, curtd, limtd: LONGINT; m1: Module; data: BOOLEAN; curexp, limexp: ExportPtr;
			refsize, nofimp, newreclink, newsyslink, newarrlink, datalink, datasize, consize, codesize: LONGINT;
			nofexp, nofdesc, nofcom, nofptr, linknr, expnr, descnr: INTEGER;
			name: ModuleName; ch: CHAR; body: Command;
			links: ARRAY 256 OF RECORD entry, link: LONGINT END ;
			imps: ARRAY 64 OF Module;
			types: ARRAY 128 OF Type;
			arrPtr: ArrPtr;
			modname, impname: ModuleName;

		PROCEDURE Block(tag: CHAR);
			VAR ch: CHAR;
		BEGIN S.GET(f.adrpos, ch); INC(f.adrpos); IF ch # tag THEN importing := m.name; res := corruptedObjFile; ErrMsg(res) END
		END Block;
		
		PROCEDURE ReadType(VAR tdesc: ADDRESS);
			VAR tdb: TDescBlock; tdd: TDescDesc;
				i, tdsize, recsize, pvfp, bmno: LONGINT;
				nofmeth, nofnewmeth, mthno, nofptr, root, entry: LONGINT;
				name: ModuleName;
		BEGIN
			ReadString(f, name);
			IF name = "" THEN ReadNum(f, pvfp) ELSE pvfp := 0 END ;
			ReadNum(f, types[descnr].link); ReadNum(f, recsize);
			ReadNum(f, bmno); types[descnr].bmno := bmno;
			IF bmno >= 0 THEN ReadString(f, types[descnr].bname);
				IF types[descnr].bname = "" THEN ReadNum(f, types[descnr].bpvfp) END
			END ;
			ReadNum(f, nofmeth); types[descnr].nofmeth := nofmeth; ReadNum(f, types[descnr].nofinhmeth);
			ReadNum(f, nofnewmeth); ReadNum(f, nofptr);
			root := 14 (* tdsize..pvfp *) + nofmeth + ExtTabWordSize + 1 (* tag *);
			INC(root, (-root+2) MOD 4);	(* ADR(tdesc.a[root]) MOD 16 = 8 ! *)
			types[descnr].root := root;
			tdsize := (root + 1 (* recsize *) + nofptr + 1 (* sentinel *))*4;
			IF Kernel.LargestAvailable() < tdsize THEN importing := name; res := notEnoughSpace; ErrMsg( res); RETURN END;
			S.NEW(tdb, tdsize - 24 (* SysBlk header *));
			DEC(S.VAL(ADDRESS, tdb), 24);
			types[descnr].tdb := tdb; tdd := S.VAL(TDescDesc, tdb);
			tdd.tdsize := tdsize;
			tdd.sentinel := -4;
			tdd.self := S.ADR(tdb.word[root]);
			tdd.name := name;
			tdd.mdesc := m;
			tdd.pvfprint := pvfp;
			i := 0;
			WHILE i < nofnewmeth DO
				ReadNum(f, mthno); ReadNum(f, entry); INC(i);
				tdb.word[root + Mth0WordOffset - mthno] := m.sb+entry*4;
			END ;
			tdb.word[root - 1] := S.ADR(tdb.word[0]);
			tdb.word[root] := recsize;
			i := 0;
			WHILE i < nofptr DO ReadNum(f, tdb.word[root+1+i]); INC(i) END ;
			tdb.word[root+1+nofptr] := -(nofptr+1)*4;
			tdesc := S.ADR(tdb.word[root])
		END ReadType;

		PROCEDURE FindExp(mode: INTEGER; VAR name: ModuleName; fprint: LONGINT; VAR adr: LONGINT);
		BEGIN
			LOOP
				IF curexp = limexp THEN res := objNotFound; imported := modeStr[mode]; objname:=name; ErrMsg(res); EXIT END ;
				IF (curexp.name = name) & (curexp.mode = mode) THEN
					IF curexp.fprint # fprint THEN res := fpMismatch; importing := name; imported := modeStr[mode]; ErrMsg(res) END ;
					adr := curexp.adr;
					INC(S.VAL(LONGINT, curexp), SIZE(Export));
					EXIT
				END ;
				INC(S.VAL(LONGINT, curexp), SIZE(Export))
			END
		END FindExp;

		PROCEDURE FindTDesc(VAR name: ModuleName; fprint: LONGINT; VAR adr: LONGINT);
			VAR save, td: LONGINT; tdd: TDescDesc;
		BEGIN save := curtd;	(* anonymous tdescs are unsorted *)
			LOOP
				IF curtd = limtd THEN res := objNotFound; imported := modeStr[8]; importing:=name; importing:="fixme"; ErrMsg( res); EXIT END ;
				S.GET(curtd, td); S.GET(td - 4, tdd);
				IF tdd.name = name THEN
					IF (tdd.pvfprint = fprint) OR (fprint = 0) THEN adr := td; INC(curtd, 4); EXIT END ;
					IF name # "" THEN res := fpMismatch; importing := name; imported := modeStr[8]; ErrMsg( res); EXIT END
				END ;
				INC(curtd, 4)
			END ;
			IF name = "" THEN curtd := save END
		END FindTDesc;

		PROCEDURE InitType(tdesc: ADDRESS; VAR type: Type);
			VAR tdb: TDescBlock; tdd: TDescDesc;
				l, r, t, k, base, tag, root, n, entry, pvfp: LONGINT; mb: Module;
		BEGIN
			tdb := type.tdb;
			IF tdb # NIL THEN	(* not done yet *)
				type.tdb := NIL;
				Linux0.Fixup(m.sb, tdesc, type.link, TRUE);
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
						IF l > r THEN importing := m.name; imported := mb.name;
							imported := modeStr[8]; importing:="fixme 2"; res := objNotFound; ErrMsg( res); RETURN
						END
					END ;
					IF base = 0 THEN InitType(mb.tdescs[t], types[t]) (* res always 0 here *) END ;
					base := mb.tdescs[t];
					S.GET(base + Tag0WordOffset*4, tag);
					WHILE tag # 0 DO
						tdb.word[root + Tag0WordOffset - k] := tag;
						INC(k);
						S.GET(base + (Tag0WordOffset - k)*4, tag)
					END ;
					n := type.nofinhmeth;
					WHILE n > 0 DO DEC(n);
						entry := tdb.word[root + Mth0WordOffset - n];
						IF entry = 0 THEN S.GET(base + (Mth0WordOffset - n)*4, tdb.word[root + Mth0WordOffset - n]) END
					END
				END ;
				S.PUT(S.ADR(tdb.word[3]), SHORT(SHORT(k)));	(* ok for little and big endian *)
				tdb.word[root + Tag0WordOffset - k] := S.ADR(tdb.word[root]);
				(* INC(k);
				WHILE k < ExtTabWordSize DO tdb.word[root + Tag0WordOffset - k] := 0; INC(k) END ; *)
			END
		END InitType;

		PROCEDURE BuildModBlock;
			VAR t, gvarSize: LONGINT;
		BEGIN
			S.GET(S.VAL(ADDRESS, arrPtr) - 4, t);

			S.PUT(S.ADR(m.exports), arrPtr);
			arrPtr.len := nofexp;
			INC(S.VAL(ADDRESS, arrPtr), ((LONG(nofexp)*SIZE(Export) + 35) DIV 16)*16);
	
			S.PUT(S.VAL(ADDRESS, arrPtr) - 4, t);
			S.PUT(S.ADR(m.tdescs), arrPtr);
			arrPtr.len := nofdesc;
			INC(S.VAL(ADDRESS, arrPtr), ((LONG(nofdesc)*4 + 35) DIV 16)*16);
	
			S.PUT(S.VAL(ADDRESS, arrPtr) - 4, t);
			S.PUT(S.ADR(m.cmds), arrPtr);
			arrPtr.len := nofcom;
			INC(S.VAL(ADDRESS, arrPtr), ((LONG(nofcom)*SIZE(Cmd) + 35) DIV 16)*16);
	
			S.PUT(S.VAL(ADDRESS, arrPtr) - 4, t);
			S.PUT(S.ADR(m.ptrTab), arrPtr);
			arrPtr.len := nofptr;
			INC(S.VAL(ADDRESS, arrPtr), ((LONG(nofptr)*4 + 35) DIV 16)*16);
	
			S.PUT(S.VAL(ADDRESS, arrPtr) - 4, t);
			S.PUT(S.ADR(m.imports), arrPtr);
			arrPtr.len := nofimp+1;
			INC(S.VAL(ADDRESS, arrPtr), (((nofimp+1)*4 + 35) DIV 16)*16);
	
			gvarSize := datasize + (-datasize) MOD 8;
(*
			S.PUT(S.VAL(ADDRESS, arrPtr) - 4, t);
			S.PUT(S.ADR(m.data), arrPtr);
			arrPtr.len := (gvarSize + consize + 3) DIV 4;
			INC(S.VAL(ADDRESS, arrPtr), ((gvarSize + consize + 35) DIV 16)*16);
*)	
			S.PUT(S.VAL(ADDRESS, arrPtr) - 4, t);
			S.PUT(S.ADR(m.data0), arrPtr);
			m.sb := S.ADR(arrPtr.data) + (gvarSize+ consize+3) DIV 4*4;
			m.cb:=m.sb;	(* only used for compatibility with legacy x86 *)
			arrPtr.len := (gvarSize+ consize+3) DIV 4+codesize;
			INC(S.VAL(ADDRESS, arrPtr), ((gvarSize+ consize+3+codesize*4 + 35) DIV 16)*16);
	
			S.PUT(S.VAL(ADDRESS, arrPtr) - 4, t);
			S.PUT(S.ADR(m.refs), arrPtr);
			arrPtr.len := refsize;

		END BuildModBlock;

	BEGIN	(* m = NIL, res = done *)
	(* HeaderBlk *)
		S.GET(f.adrpos, refsize); INC(f.adrpos, 4); S.GET(f.adrpos, nofexp); INC(f.adrpos, 2); S.GET(f.adrpos, nofdesc); INC(f.adrpos, 2);
		S.GET(f.adrpos, nofcom); INC(f.adrpos, 2); S.GET(f.adrpos, nofptr); INC(f.adrpos, 2);
		ReadNum(f, nofimp); ReadNum(f, newreclink); ReadNum(f, newsyslink);
		ReadNum(f, newarrlink); ReadNum(f, datalink); ReadNum(f, datasize); ReadNum(f, consize);
		ReadNum(f, codesize); ReadString(f, modname);
	(* ImpBlk *)
		Block(81X); i := 0;
		WHILE i < nofimp DO
			ReadString(f, impname);
			IF Kernel.trace="Modules" THEN Kernel.WriteHex( i, 4); Kernel.WriteChar(" "); Kernel.WriteString(impname); Kernel.WriteLn END;
			Load(impname, imps[i]);
			IF res # done THEN
				Kernel.WriteString(impname);Kernel.WriteString(" Loading failed"); Kernel.WriteLn;
				RETURN
			END ;
			INC(i)
		END;

		m := Kernel.modules;
		WHILE (m # NIL) & (modname # m.name) DO m := m.next END ;
		IF m # NIL THEN (* cyclic load, done *) RETURN END ;
		IF Kernel.LargestAvailable() < SIZE(ModuleDesc) THEN 
			importing := ""; res := notEnoughSpace; ErrMsg( res);
			RETURN
		END ;
		NEW(m);
		k := ((LONG(nofexp)*SIZE(Export) + 35) DIV 16 + (LONG(nofdesc)*4 + 35) DIV 16 +
			(LONG(nofcom)*SIZE(Cmd) + 35) DIV 16 + (LONG(nofptr)*4 + 35) DIV 16 + ((nofimp+1)*4 + 35) DIV 16 +
			(datasize + (-datasize) MOD 8 + consize + codesize*4 + 35) DIV 16 + (refsize + 35) DIV 16)*16;
		IF Kernel.LargestAvailable() < k + 24 THEN importing := modname; m := NIL; res := notEnoughSpace; ErrMsg( res);	RETURN END ;
		m.next := Kernel.modules; Kernel.modules := m;
		m.name := modname; (*m.init := FALSE;*) m.refcnt := -1;
		S.NEW(arrPtr, k); BuildModBlock;
		m.imports[0] := S.ADR(m^); i := 0;

		WHILE i < nofimp DO m.imports[i+1] := S.ADR(imps[i]^); INC(imps[i].refcnt); INC(i) END ;
	(* ExpBlk *)
		Block(82X); linknr := 0; expnr := 0; descnr := 0; S.GET(f.adrpos, ch); INC(f.adrpos);
		WHILE ch # 0X DO
			IF ch = 8X THEN
				ReadType(m.tdescs[descnr]); INC(descnr);
				IF res # done THEN Delete(m); m := NIL; RETURN END;
			ELSIF ch = 9X THEN
				ReadNum(f, entry); links[linknr].entry := m.sb+entry*4;
				ReadNum(f, links[linknr].link); INC(linknr)
			ELSE
				ReadString(f, m.exports[expnr].name); ReadNum(f, m.exports[expnr].fprint);
				m.exports[expnr].mode := ORD(ch);
				IF ch = 3X THEN ReadNum(f, entry); m.exports[expnr].adr := m.sb + entry;
				ELSIF ch = 4X THEN ReadNum(f, entry); m.exports[expnr].adr := m.sb+entry*4;
				ELSIF ch = 6X THEN INC(expnr); m.exports[expnr].mode := 7;
					m.exports[expnr].name := m.exports[expnr-1].name; ReadNum(f, m.exports[expnr].fprint)	(* pvfprint *)
				END ;
				INC(expnr)
			END ;
			S.GET(f.adrpos, ch); INC(f.adrpos);
		END ;

	(* CmdBlk *)
		Block(83X); i := 0; t := m.sb;
		WHILE i < nofcom DO
			ReadString(f, m.cmds[i].name); ReadNum(f, entry);
			m.cmds[i].adr := t + 4*entry; INC(i)
		END ;
	(* PtrBlk *)
		Block(84X); i := 0; t := m.sb;
		WHILE i < nofptr DO ReadNum(f, k); m.ptrTab[i] := t + k; INC(i) END;
	(* ConstBlk *)
		Block(87X); i := 0; t:=S.ADR(m.data0^);
		WHILE i < consize DO S.GET(f.adrpos, ch); INC(f.adrpos); S.PUT(t, ch); INC(t); INC(i) END ;
	(* CodeBlk *)
		Block(88X);
		i := 0; t := m.sb;
		WHILE i < codesize DO S.GET(f.adrpos, k); INC(f.adrpos, 4); S.PUT(t, k); INC(t, 4); INC(i) END ;
		WHILE linknr > 0 DO DEC(linknr); Linux0.Fixup(m.sb, links[linknr].entry, links[linknr].link, FALSE) END ;
		Linux0.Fixup(m.sb, Kernel.runtime[0], newreclink, FALSE);	(* Kernel already loaded *)
		Linux0.Fixup(m.sb, Kernel.runtime[1], newsyslink, FALSE);
		Linux0.Fixup(m.sb, Kernel.runtime[2], newarrlink, FALSE);
		Linux0.Fixup(m.sb, m.sb, datalink, TRUE);
	(* UseBlk *)
		Block(89X); i := 0;
		WHILE i < nofimp DO
			m1 := S.VAL(Module, m.imports[i+1]);
			curexp := S.VAL(ExportPtr, S.ADR(m1.exports^));
			limexp := S.VAL(ExportPtr, S.VAL(ADDRESS, curexp) + LEN(m1.exports^)*SIZE(Export));
			curtd := S.ADR(m1.tdescs^); limtd := curtd + LEN(m1.tdescs^)*4;
			S.GET(f.adrpos, ch); INC(f.adrpos);
			WHILE ch # 0X DO
				ReadString(f, name); ReadNum(f, fprint);
				CASE ch OF
				| 1X, 2X, 5X, 6X, 7X: FindExp(ORD(ch), name, fprint, entry); link := -1	(* no fixup*)
				| 3X, 4X: FindExp(ORD(ch), name, fprint, entry); ReadNum(f, link); data := ch = 3X
				| 8X: IF name = "" THEN ReadNum(f, link) ELSE link := fprint; fprint := 0 END ;
						FindTDesc(name, fprint, entry); data := TRUE
				END ;
				IF res # done THEN importing := m.name; imported := m1.name;
					ErrMsg( res);
					Delete(m); m := NIL; RETURN
				END ;
				IF link # -1 THEN Linux0.Fixup(m.sb, entry, link, data) END ;
				S.GET(f.adrpos, ch); INC(f.adrpos);
			END ;
			INC(i)
		END ;
	(* RefBlk *)
		Block(8AX); 
		S.MOVE( f.adrpos, S.ADR(m.refs^), refsize); INC( f.adrpos, refsize);
	(* init types *)
		i := 0;
		WHILE i < LEN(m.tdescs^) DO
			InitType(m.tdescs[i], types[i]);
			IF res # done THEN Delete(m); m := NIL; RETURN END ;
			INC(i)
		END ;
	(* execute body *)
		body := S.VAL(Command, m.sb); (*m.init := TRUE;*)m.refcnt:=0;
		Kernel.WriteHex( m.sb, 8); Kernel.WriteHex( codesize*4, 9); Kernel.WriteChar( " ");  Kernel.WriteString(m.name); Kernel.WriteLn;
		i:=Linux0.CacheFlush0( m.sb, codesize*4);
		body;
		res := done;
	END LoadModule;

	PROCEDURE Load( name: ARRAY OF CHAR; VAR m: Module);
		VAR f: File; i, j, sp: LONGINT; fname: ARRAY 64 OF CHAR; tag: INTEGER; 
	BEGIN
		m := Kernel.modules; res := done;
		WHILE (m # NIL) & (name # m.name) DO m := m.next END ;
		IF m = NIL THEN	
			fname:=Linux0.ObjPrefix;
			j:=0;
			WHILE fname[j] # 0X DO INC(j) END ;
			i:=0;
			WHILE name[i] # 0X DO fname[j]:= name[i]; INC(i); INC(j) END ;
			fname[j] := "."; fname[j+1] := "O"; fname[j+2] := "b"; fname[j+3] := "j";fname[j+4] := 0X;

(* p.m.
			IF Kernel.nofiles >= Unix.OpenMax - 4 THEN
				state := Kernel.GCenabled; Kernel.GCenabled := TRUE; Kernel.GC(TRUE); Kernel.GCenabled := state
			END ;
			IF Kernel.nofiles >= Unix.OpenMax - 4 THEN importing := ""; res := tooManyFiles; ErrMsg( res) RETURN END ;
*)
			f.fd:= Linux0.Openat0( Linux0.ATFDCWD, S.ADR(fname), 0, 0);
			IF f.fd<3 THEN
				COPY(fname, importing);  res := fileNotFound; ErrMsg(res); 
				RETURN;
			END;
			f.length:= FSize(f.fd);
			f.adr:=Linux0.Mmap20( 0, f.length, 1, Linux0.MAPPRIVATE, f.fd,  0);	(* PROT_READ=1 PROT_WRITE=2; MAP_SHARED=1, MAP_PRIVATE=2 *)
			IF f.adr MOD 1000H#0 THEN	Kernel.WriteString("Modules.Load f.adr= "); Kernel.WriteHex( f.adr, 8); Kernel.WriteLn END;
			f.adrpos:=f.adr;
			S.GET(f.adrpos, tag); INC(f.adrpos, 2);
			IF tag = Linux0.ObjTag THEN LoadModule(f, m);
			ELSE COPY(fname, importing); res := invalidObjFile; ErrMsg(res);
			END;
			IF f.adr#0 THEN f.adr:=Linux0.Munmap0( f.adr, f.length); END;
			f.fd:=Linux0.Close0( f.fd);
		END;	
	END Load;

	PROCEDURE ThisMod* (name: ARRAY OF CHAR): Module;
		VAR mod: Module;
	BEGIN
(*		Kernel.GC; (* Kernel.GCenabled = FALSE at boot time or when ThisMod called in bodies *)*)
		Kernel.DisableGC;
		Load(name, mod);
		Kernel.EnableGC;
		RETURN mod
	END ThisMod;

	PROCEDURE ThisCommand* (mod: Module; name: ARRAY OF CHAR): Command;
		VAR i: LONGINT;
	BEGIN
		IF mod=NIL THEN 
			COPY(name, importing); res := moduleNotFound; ErrMsg(res); RETURN NIL
		END;
		i := LEN(mod.cmds^);
		WHILE i > 0 DO DEC(i);
			IF mod.cmds[i].name = name THEN
				res := done;
				RETURN S.VAL(Command, mod.cmds[i].adr)
			END
		END ;
		COPY(mod.name, imported);  COPY(name, importing); res := cmdNotFound; ErrMsg( res); RETURN NIL
	END ThisCommand;

	PROCEDURE Free* (name: ARRAY OF CHAR; all: BOOLEAN);
		VAR m, m1: Module; i: LONGINT;
	BEGIN res := done;
		m := Kernel.modules;
		WHILE (m # NIL) & (name # m.name) DO m := m.next END ;
		IF m = NIL THEN COPY(name, importing); res := moduleNotFound; ErrMsg( res)
		ELSIF m.refcnt # 0 THEN importing := m.name; res := refCntNotZero; ErrMsg( res)
		ELSE i := LEN(m.imports^);
			WHILE i > 1 DO DEC(i); m1 := S.VAL(Module, m.imports[i]); DEC(m1.refcnt) END ;
			IF all THEN i := LEN(m.imports^);
				WHILE i > 1 DO DEC(i); m1 := S.VAL(Module, m.imports[i]); Free(m1.name, TRUE) END ;
				res := done
			END ;
			m1 := Kernel.modules;	(* recursive call may change list structure *) 
			IF m1 = m THEN Kernel.modules := m.next
			ELSE
				WHILE m1.next # m DO m1 := m1.next END ;
				m1.next := m.next
			END;
		END
	END Free;

	PROCEDURE InstallTermHandler*( handler: Kernel.Proc);
	BEGIN
		Kernel.InstallTermHandler( handler);
	END InstallTermHandler; 
(*
PROCEDURE Test;
VAR a: ARRAY 32 OF LONGINT; i, res: LONGINT;
BEGIN
	res:=Linux0.Openat0( Linux0.ATFDCWD, S.ADR("OLR.Tool"), Linux0.ORDonly, 0);
	res:=Linux0.FStat0( res, S.ADR(a));
	FOR i:=0 TO 31 DO Kernel.WriteInt(a[i], 9); Kernel.WriteLn END;
END Test;
*)
BEGIN	(* entry of boot file, must not return *)
	modeStr[0] := "";
	modeStr[1] := "constant";
	modeStr[2] := "type";
	modeStr[3] := "variable";
	modeStr[4] := "procedure";
	modeStr[5] := "code procedure";
	modeStr[6] := "public structure of";
	modeStr[7] := "private structure of";
	modeStr[8] := "type descriptor of";
(* p.m.
		Kernel.FindRoots := FindRoots;
		Kernel.FindAmbRoots := FindAmbRoots;
*)
(*	Test;*)
	Kernel.Static:=FALSE;
(* init loop only if Modules is last module in boot file: *)

	loop := ThisCommand(ThisMod("System"), "Init");
	IF loop #NIL THEN loop END; (* call loop only if Modules is last module in boot file *)
	Kernel.WriteString("Error: End of Modules reached. Shutting down!"); Kernel.WriteLn;
	Kernel.Shutdown( 1);

END Modules.
