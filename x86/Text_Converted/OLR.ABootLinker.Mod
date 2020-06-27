MODULE ABootLinker;   (* as 5.12.98 *)

(*
	2012-12-30	p.m.:	changed eh.eShentsize to 0
	2013-01-05	p.m.:	code alignemt to 8000H
	2013-01-14	p.m.:	added PHDR entry
	2013-01-19	p.m.:	changed eh.eShentsize to 40
	2013-04-13	p.m.:		shdr[13]:= 80060H;		was: shdr[13]:= 8060H;	(* sh_addr *)
	2014-04-16	p.m.: 	Fixed ExtCallFixup to match ALO.OCE.Mod
	2014-04-22	p.m.: 	Fixed ExtCallFixup to match ALO.OCE.Mod, Teaps >12
	2014-05-27	p.m.:	ImageName using Prefix
	2014-06-27			:	removed ELF sections
	2014-07-29			: made e_shentsize 40 again
	2015-07-20	output file created with correct permissions (octal 755)
		
*)

	IMPORT Linux0, Kernel, Files, Texts, Out, Oberon, SYSTEM, OBM;

	CONST
	RDonly= 0;	WRonly= 1;	RDWR=2;	OCREAT=40H;	OEXCL=80H;	OTRUNC= 200H;	OAPPEND=400H;	(* from X86 & ARM*)
	ELFhdrsz= 52;
	PHTsize= 32;
	PadSize=12;
	LoadBase4 = 080000H+ELFhdrsz+PHTsize+PadSize; (* this is where the code is put*)
	(*	CodeSize= 2000000H;	(* ignored 32MB size reserved by ELF header for code *)*)

		MaxExts = 15;
		MaxModules = 25; (* Max. No. of statically linked modules *)

TYPE
	ELF32EHDR= RECORD
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
	END;
	
VAR
	eh: ELF32EHDR;		(* ELF Header *)
	shdr: ARRAY 40 OF LONGINT;	(* Sector Header *)
	attr: ARRAY 11 OF INTEGER;	(* attributes *)
	str: ARRAY 9 OF LONGINT;	(* string sector *)
	pt: ARRAY 11 OF LONGINT;	(* programm table *)
	ImageName: ARRAY 256 OF CHAR;
		
	TYPE
		Cmd = RECORD (* Must be the same definition as Kernel.Cmd!!! *)
				name : ARRAY 32 OF CHAR;
				adr : LONGINT
			END;
					
		Type = RECORD
				tdaddr : LONGINT; (* Address of type desc *)
				tagaddr : LONGINT; (* Address of Pointer to Type desc (==tag) *)
				nofPtrs : INTEGER;
				extlev : INTEGER;
				ptrs : POINTER TO ARRAY OF LONGINT; (* ptr offsets *)
				tags : ARRAY MaxExts OF LONGINT;
				recsize : LONGINT;
				name : ARRAY 32 OF CHAR;
			END;
								
		Object = POINTER TO ObjectDesc;
		ObjectDesc = RECORD
				next : Object;
				name : ARRAY 32 OF CHAR;
				key : LONGINT;
				refcnt : LONGINT;
				refpos : LONGINT; 
				entryPoint : LONGINT; (* Relative to base, byte address *)
				nofImports, nofEntries, nofPtrs, nofCmds, nofRecs : INTEGER;
				codeSize, strConstSize, dataSize : LONGINT;
				imports : POINTER TO ARRAY OF Object;
				entries : POINTER TO ARRAY OF LONGINT; (* byte addresses *)
				ptrs : POINTER TO ARRAY OF LONGINT; (* byte addresses *)
				types : POINTER TO ARRAY OF Type;
				cmds : POINTER TO ARRAY OF Cmd;
				base : LONGINT; (* Address of module code, byte address *)
				mdesc : LONGINT; (* Address of Module Desc, byte address *)
				refs : POINTER TO ARRAY OF CHAR;
				init : BOOLEAN;
			END;

		Init = POINTER TO RECORD word : ARRAY 512 OF LONGINT END;
				
	VAR
		code : POINTER TO ARRAY OF LONGINT; (* 192K for Kernel code, string consts, data, module descs and type descs *)
		objs : Object;
		modules : LONGINT; (* "Address" of first ModuleDesc *)
		modulesAddr : LONGINT; (* Offset into code of Kernel.modules (in words!) *)
		modLoadAddrAddr : LONGINT; (* Offset into code of Modules.modLoadAddr (in words!) *)
		pc : LONGINT; (* word address *)
		fixup: ARRAY 16 OF LONGINT;
		initCalls : ARRAY MaxModules OF Object;
		initCnt : INTEGER;
		quiet: BOOLEAN;


	PROCEDURE Hex(x : LONGINT);
	VAR
		buf: ARRAY 9OF CHAR;
		i, j: LONGINT;
	BEGIN
		FOR i := 7 TO 0 BY -1 DO
			buf[i] := CHR(x MOD 10H + 48); IF buf[i] > "9" THEN buf[i] := CHR(ORD(buf[i]) - 48 + 65 - 10) END;
			x := x DIV 10H
		END;
		buf[8] := 0X;
		Out.String(buf) 
	END Hex;
	
	PROCEDURE GetObj(name : ARRAY OF CHAR) : Object;
	VAR o : Object;
	BEGIN
		o:=objs;
		WHILE o#NIL DO
			IF o.name=name THEN RETURN o END;
			o:=o.next;
		END;
		RETURN NIL
	END GetObj;
	
	PROCEDURE GetTag(m,t : ARRAY OF CHAR) : LONGINT; (* Module & Type name *)
	VAR o : Object; i : INTEGER;
	BEGIN
		o:=GetObj(m); IF o=NIL THEN RETURN 0 END;
		FOR i:=0 TO o.nofRecs-1 DO
			IF o.types[i].name=t THEN RETURN o.types[i].tdaddr END;
		END;
		RETURN 0;
	END GetTag;

	PROCEDURE Loaded(name : ARRAY OF CHAR; VAR o : Object) : BOOLEAN;
	BEGIN
		o:=GetObj(name);
		RETURN o#NIL
	END Loaded;			
	
	PROCEDURE NewSys(VAR a : SYSTEM.PTR; size : LONGINT);
	BEGIN
		(* adjust PC so that PC MOD 32 = 28, remember that pc is "word-counting"!!! *)
		INC(pc,7-(pc MOD 8));
		
		(* "Allocate" Memory and init SysBlk *)
		code[pc]:=LoadBase4+(pc+1)*4;
		code[pc+1]:=size+24;
		code[pc+2]:=-4; code[pc+3]:=0; code[pc+4]:=0; code[pc+5]:=0;
		code[pc+6]:=LoadBase4+(pc+1)*4;
		a:=SYSTEM.VAL(SYSTEM.PTR,SYSTEM.ADR(code[pc+7]));
		INC(pc, (size+28+3) DIV 4);
	END NewSys;

	PROCEDURE NewSysArr(VAR a : SYSTEM.PTR; elems, esize : LONGINT);
	VAR init : Init;
	BEGIN
		NewSys(a,elems*esize+8);
		init:=SYSTEM.VAL(Init,a); 

		init.word[0]:=LoadBase4+SYSTEM.ADR(init.word[0])-SYSTEM.ADR(code[0])+8;
		init.word[1]:=elems;
	END NewSysArr;
	
	PROCEDURE NewDynArr(VAR a : SYSTEM.PTR; elems, esize, tag : LONGINT);
	VAR init : Init;
	BEGIN
		(* adjust PC so that PC MOD 32 = 28, remember that pc is "word-counting"!!! *)
		INC(pc,7-(pc MOD 8));
		
		(* "Allocate" Memory and init ArrBlk *)
		code[pc]:=tag+2; (* 2 = 010B *)
		code[pc+1]:=LoadBase4+(pc+5)*4+(elems-1)*esize; (* last elem *)
		code[pc+2]:=0; (* reserved *)
		code[pc+3]:=LoadBase4+(pc+5)*4; (* first elem *)
		code[pc+4]:=elems;
		a:=SYSTEM.VAL(SYSTEM.PTR,SYSTEM.ADR(code[pc+1]));
		INC(pc, (20+elems*esize+3) DIV 4);
	END NewDynArr;

	PROCEDURE NewRec(VAR a : SYSTEM.PTR; tag : LONGINT);
	VAR size : LONGINT;
	BEGIN
		ASSERT(tag>LoadBase4,100); ASSERT(tag MOD 16 = 8,101);
		
		size:=code[(tag-LoadBase4) DIV 4];
		
		(* adjust PC so that PC MOD 32 = 28, remember that pc is "word-counting"!!! *)
		INC(pc,7-(pc MOD 8));
		
		(* "Allocate" Memory and init RecBlk *)
		code[pc]:=tag; 
		a:=SYSTEM.VAL(SYSTEM.PTR,SYSTEM.ADR(code[pc+1]));
		INC(pc, (size+4+3) DIV 4);
	END NewRec;
	
	PROCEDURE ReadHeader(VAR r : Files.Rider; VAR o : Object);
	VAR tag : CHAR; comsize : INTEGER;
	BEGIN
		Files.Read(r, tag); Files.Read(r,tag); 
		Files.ReadLInt(r,o.refpos); 
		Files.ReadLInt(r,o.entryPoint); (* module body entry point *)
		Files.ReadInt(r,o.nofImports);
		Files.ReadInt(r,o.nofEntries);
		Files.ReadInt(r,o.nofPtrs);
		Files.ReadInt(r,o.nofCmds);
		Files.ReadLInt(r,o.strConstSize);
		Files.ReadLInt(r,o.dataSize);
		Files.ReadLInt(r,o.codeSize);
		Files.ReadInt(r,o.nofRecs);
		Files.ReadLInt(r,o.key);
		Files.ReadString(r,o.name);
		
		NEW(o^.imports,o.nofImports+1); (* imports are index 1..nofImports! *)
		NEW(o^.entries,o.nofEntries+1); (* +1 because we can't allocate a array of size 0 *)
		NEW(o^.ptrs,o.nofPtrs+1); (* ditto *)
		NEW(o^.types,o.nofRecs+1); (* ditto *)
		NEW(o^.cmds,o.nofCmds+1); (* ditto *)

		o.init:=FALSE;
	END ReadHeader;
		 
	PROCEDURE ReadTypes(VAR r : Files.Rider; VAR o : Object);
	VAR nofTypes : LONGINT; i, j : INTEGER; extlev : SHORTINT;
	BEGIN
		FOR i:=0 TO o.nofRecs-1 DO
			Files.ReadLInt(r,o.types[i].tagaddr); 
			Files.ReadInt(r,o.types[i].nofPtrs); NEW(o.types[i].ptrs,o.types[i].nofPtrs+1); (* don't trap if np=0 *)
			Files.ReadLInt(r,o.types[i].recsize);
			Files.ReadString(r,o.types[i].name);
			Files.Read(r,extlev); o.types[i].extlev:=extlev;
			FOR j:=0 TO extlev-1 DO Files.ReadLInt(r,o.types[i].tags[j]) END;
			FOR j:=0 TO o.types[i].nofPtrs-1 DO Files.ReadLInt(r,o.types[i].ptrs[j]) END;
		END
	END ReadTypes;
			
	PROCEDURE BuildTypeDescs(o : Object);
	VAR i,j, start, t,mno, eno : LONGINT;
			init : Init;
	BEGIN
		FOR i:=0 TO o.nofRecs-1 DO
			(* adjust PC so that PC MOD 32 = 28, remember that pc is "word-counting"!!! *)
			INC(pc,7-(pc MOD 8));
		
			o.types[i].tdaddr:=LoadBase4+pc*4+124;
			(*
			(* DEBUG only *)	
			Out.String("patch at: "); Hex(o.types[i].tagaddr); Out.String(" with "); Hex(o.types[i].tdaddr); 
			Out.String("  TD for "); Out.String(o.types[i].name); Out.Ln;
			(* end of DEBUG *)
			*)
			
			code[(o.base-LoadBase4+o.types[i].tagaddr) DIV 4]:=o.types[i].tdaddr; (*patch the type tag for this type *)

			(* Now, generate the Type Desc *)
			code[pc]:=LoadBase4+(pc+1)*4;  INC(pc); 
			start:=pc;
			code[pc]:=o.types[i].nofPtrs*4+8+56+(MaxExts+1)*4; INC(pc);       (* tdsize *)
			code[pc]:=-4; INC(pc);  (* sentinel *)
			code[pc]:=LoadBase4+pc*4+72; INC(pc); (* self *)
			code[pc]:=0; INC(pc); (* filler *)
			FOR j:=0 TO 7 DO SYSTEM.GET( SYSTEM.ADR(o.types[i].name[j*4]), code[pc]); INC(pc) END;
			code[pc]:=0; INC(pc);  (* mdesc. will be fixed later *)
			FOR j:=0 TO o.types[i].extlev-1 DO 
				t:=o.types[i].tags[j];
				IF t<0 THEN (* non exported tag *)
					code[pc+MaxExts-j]:=code[(o.base+t-LoadBase4) DIV 4]; 
				ELSE (* exported or imported *)
					mno:=t DIV 100H; eno:=t MOD 100H;
					IF mno=0 THEN code[pc+MaxExts-j]:=code[(o.entries[eno]-LoadBase4) DIV 4];
					ELSE code[pc+MaxExts-j]:=code[(o.imports[mno].entries[eno]-LoadBase4) DIV 4];
					END
				END
			END;
			FOR j:=o.types[i].extlev TO MaxExts DO code[pc+MaxExts-j]:=0 END;
			INC(pc,MaxExts+1);
			code[pc]:=LoadBase4+start*4; INC(pc);
		
			code[pc-1-o.types[i].extlev-1]:=o.types[i].tdaddr; (* patch the tag table (insert pointer to self) *)
			(*
			(* DEBUG only *)
			Out.String("---Dump of tag-table for "); Out.String(o.types[i].name); Out.String("---"); Out.Ln;
			FOR j:=0 TO MaxExts DO
				Out.String("extlev="); Out.Int(MaxExts-j,1); Out.String("   "); Hex(code[(o.types[i].tdaddr-LoadBase-68) DIV 4+j]); Out.Ln;
			END;
			Out.String("---End of Dump---"); Out.Ln;
			(* end of DEBUG *)
			*)
			code[pc]:=o.types[i].recsize; INC(pc);
			FOR j:=0 TO o.types[i].nofPtrs-1 DO 
				code[pc]:=o.types[i].ptrs[j]; INC(pc)
			END;
			code[pc]:= -4*(o.types[i].nofPtrs+1); INC(pc);			
		END	
	END BuildTypeDescs;
	
	PROCEDURE BuildModuleBlocks;
	VAR i, tag : LONGINT; o : Object; init : Init; entries, ptrTab, tdescs, refs, cmds, imports : Init;
	BEGIN
		o:=objs;
		WHILE o#NIL DO
			tag:=GetTag("Kernel","ModuleDesc"); 
			NewRec(SYSTEM.VAL(SYSTEM.PTR, init),tag); o.mdesc:=SYSTEM.ADR(init.word[0])-SYSTEM.ADR(code[0])+LoadBase4;
			init.word[0]:=modules; modules:=o.mdesc;
			SYSTEM.MOVE(SYSTEM.ADR(o.name),SYSTEM.ADR(init.word[1]),32);
			
			NewSysArr(SYSTEM.VAL(SYSTEM.PTR, entries),o.nofEntries,4); SYSTEM.MOVE(SYSTEM.ADR(o.entries^[0]),SYSTEM.ADR(entries.word[2]),o.nofEntries*4);
			NewSysArr(SYSTEM.VAL(SYSTEM.PTR, ptrTab),o.nofPtrs,4); SYSTEM.MOVE(SYSTEM.ADR(o.ptrs^[0]),SYSTEM.ADR(ptrTab.word[2]),o.nofPtrs*4);
			NewSysArr(SYSTEM.VAL(SYSTEM.PTR, tdescs),o.nofRecs,4); FOR i:=0 TO o.nofRecs-1 DO tdescs.word[2+i]:=o.types[i].tdaddr; END;
			NewSysArr(SYSTEM.VAL(SYSTEM.PTR, refs),LEN(o.refs^),1); SYSTEM.MOVE(SYSTEM.ADR(o.refs^[0]),SYSTEM.ADR(refs.word[2]),LEN(o.refs^));
			NewSysArr(SYSTEM.VAL(SYSTEM.PTR, cmds),o.nofCmds,SIZE(Cmd)); SYSTEM.MOVE(SYSTEM.ADR(o.cmds^[0]),SYSTEM.ADR(cmds.word[2]),o.nofCmds*SIZE(Cmd));
			NewDynArr(SYSTEM.VAL(SYSTEM.PTR, imports),o.nofImports+1,4,GetTag("Kernel","PtrElemDesc")); 
			imports.word[4]:=o.mdesc; FOR i:=1 TO o.nofImports DO imports.word[4+i]:=o.imports[i].mdesc END;
			
			init.word[9]:=00000001H; (* initialised, not trapped *)
			init.word[10]:=o.key;
			init.word[11]:=o.refcnt;
			init.word[12]:=o.base;
			init.word[13]:=SYSTEM.VAL(LONGINT,entries)-SYSTEM.ADR(code[0])+LoadBase4;
			init.word[14]:=SYSTEM.VAL(LONGINT,cmds)-SYSTEM.ADR(code[0])+LoadBase4;
			init.word[15]:=SYSTEM.VAL(LONGINT,ptrTab)-SYSTEM.ADR(code[0])+LoadBase4;
			init.word[16]:=SYSTEM.VAL(LONGINT,tdescs)-SYSTEM.ADR(code[0])+LoadBase4;
			init.word[17]:=SYSTEM.VAL(LONGINT,imports)-SYSTEM.ADR(code[0])+LoadBase4;
			init.word[18]:=o.strConstSize+o.dataSize+o.codeSize;
			init.word[19]:=o.base-o.dataSize; 
			init.word[20]:=SYSTEM.VAL(LONGINT,refs)-SYSTEM.ADR(code[0])+LoadBase4;
			init.word[21]:=0; (* No Term-Handler *)
			
			o:=o.next;
		END
	END BuildModuleBlocks;
	
	PROCEDURE ExtCallFixup(fixlist : LONGINT; o : Object);
	VAR pos, mno, eno, cw, addr, cc : LONGINT; 
	BEGIN
		WHILE fixlist#0 DO
			pos:=(fixlist+o.base-LoadBase4) DIV 4; 
			cw:=code[pos]; 
			mno:=cw DIV 100H MOD 100H(*32*); eno:=cw MOD 100H;
			cc:=0EH;	(* cc= AL *)
			IF mno=0 THEN
				addr:= fixup[ eno];
				IF eno=4 THEN cc:= code[pos-1] DIV 10000000H MOD 10H END;
				IF addr=-1 THEN Out.String("fixup "); Out.Int( eno, 6); Out.String(" could not be patched!"); Out.Ln END;
			ELSE 
				addr:=o.imports[mno].entries[eno ];
			END;
			code[pos]:=SYSTEM.LSH( cc, 28)+0B000000H+((addr DIV 4 - (pos+(LoadBase4 DIV 4) +2)) MOD 1000000H); (* ExtCall is always BL not if SWI replacement p.m.*)
(*			code[pos]:=0EB000000H+((addr - LoadBase) DIV 4 - pos -2) MOD 1000000H;*)

			fixlist:=SYSTEM.LSH(cw,-17) MOD 8000H*4;	(* 0 .. 128 KB *)
			(*fixlist:=SYSTEM.LSH(cw,-13) MOD 8000H*4;*)
		END
	END ExtCallFixup;
	
	PROCEDURE ExtAddrFixup(fixlist: LONGINT; o : Object);
	VAR pos, mno, eno, cw : LONGINT;
	BEGIN 
		WHILE fixlist#0 DO
			pos:=(fixlist+o.base-LoadBase4) DIV 4;
			cw:=code[pos];
			mno:=cw DIV 100H MOD 100H(*32*); eno:=cw MOD 100H;
			code[pos]:=o.imports[mno].entries[eno];
			fixlist:=SYSTEM.LSH(cw,-17) MOD 8000H*4;	(* 0 .. 128 KB *)
			(*fixlist:=SYSTEM.LSH(cw,-17)*4;*)
		END;
	END ExtAddrFixup;
	
	PROCEDURE Fixup(fixlist:LONGINT; o : Object);
	VAR pos, cw(*, tmp*) : LONGINT;		 
	BEGIN
		WHILE fixlist#0 DO
			pos:=(o.base+fixlist-LoadBase4) DIV 4;
			cw := code[pos];
			code[pos] := cw MOD 20000H + o.base;
			fixlist:=SYSTEM.LSH(cw,-17) MOD 8000H*4;	(* 0 .. 128 KB *)
			(*tmp:=SYSTEM.LSH(code[pos],-17); 
			code[pos]:=code[pos] MOD 20000H + o.base; fixlist:=tmp*4;*)
		END
	END Fixup;	

	PROCEDURE LoadObject(modname : ARRAY OF CHAR; VAR o : Object);
	VAR
		f : Files.File; r : Files.Rider; tag, tag2 : SHORTINT;
		name : ARRAY 40 OF CHAR;
		str : ARRAY 32 OF CHAR;
		i, key : LONGINT;
		p : Object;
		
		PROCEDURE Expect(tag : CHAR) : BOOLEAN;
		VAR ch : CHAR;
		BEGIN
			Files.Read(r,ch); IF ch#tag THEN Out.String("corrupt object file"); Out.Ln END;
			RETURN tag=ch;
		END Expect;

		PROCEDURE InitSpecial(o : Object);
		VAR r : Files.Rider; ch : CHAR; name : ARRAY 64 OF CHAR; addr : LONGINT; 
		
			PROCEDURE AddrOut(n : ARRAY OF CHAR; adr : LONGINT);
			BEGIN Out.String("  "); Out.String(n); Out.String(": "); Hex(adr); Out.Ln;
			END AddrOut;
			
		BEGIN
			Files.Set(r,f,o.refpos);
			Files.Read(r,ch);
			IF ch#08BX THEN Out.String("corrupt object file"); Out.Ln; RETURN END;
			WHILE ~r.eof DO
				Files.Read(r,ch);
				IF ch=0F8X THEN (* procedure *)
					Files.ReadNum(r,addr); Files.ReadString(r,name);
					IF o.name="Kernel" THEN
						IF name="DivMod" THEN fixup[3]:=addr+o.base; AddrOut("DivMod",fixup[3])
						ELSIF name="NewArr" THEN fixup[2]:=addr+o.base; AddrOut("NewArr",fixup[2])
						ELSIF name="NewSys" THEN fixup[1]:=addr+o.base; AddrOut("NewSys",fixup[1])
						ELSIF name="NewRec" THEN fixup[0]:=addr+o.base; AddrOut("NewRec",fixup[0])
						ELSIF name="SysHalt" THEN fixup[4]:=addr+o.base; AddrOut("SysHalt", fixup[4])
						END
					END;
				ELSE
					Files.Read(r,ch); 
					IF ch>80X THEN Files.ReadNum(r,addr) (* dim *) END; 
					Files.ReadNum(r,addr); Files.ReadString(r,name);
					IF (o.name="Kernel") & (name="modules") THEN modulesAddr:=(o.base+addr-LoadBase4) DIV 4 ; 
					ELSIF (o.name="Modules") & (name="modLoadAddr") THEN modLoadAddrAddr:=(o.base+addr-LoadBase4) DIV 4 
					END
				END
			END
		END InitSpecial;

		PROCEDURE DumpProcAddrs(o : Object);
		VAR r : Files.Rider; ch : CHAR; name : ARRAY 64 OF CHAR; addr : LONGINT; 
		BEGIN
			Files.Set(r,f,o.refpos); Files.Read(r,ch); 
			IF ch#08BX THEN Out.String("corrupt object file"); Out.Ln; RETURN END; 
			WHILE ~r.eof DO
				Files.Read(r,ch);
				IF ch=0F8X THEN (* procedure *)
					Files.ReadNum(r,addr); Files.ReadString(r,name);
					IF ~quiet THEN
						Out.String(o.name); Out.String("."); Out.String(name); Out.String(" @ "); Hex(addr+o.base); Out.Ln;
					END;
				ELSE (* ignore *)
					Files.Read(r,ch); IF ch>80X THEN Files.ReadNum(r,addr) (* dim *) END;
					Files.ReadNum(r,addr); Files.ReadString(r,name)
				END
			END
		END DumpProcAddrs;
		
		PROCEDURE DumpTDescs(o : Object);
		VAR i : LONGINT;
		BEGIN
			IF ~quiet THEN
				FOR i:=0 TO o.nofRecs-1 DO
					Out.String(o.name); Out.String("."); Out.String(o.types[i].name); Out.String("  "); Hex(o.types[i].tdaddr); Out.Ln 
				END
			END
		END DumpTDescs;
		
	BEGIN
		IF Loaded(modname,o) THEN
			IF ~o.init THEN Out.String("cyclic import of "); Out.String(modname); Out.Ln; HALT(99) END;
			INC(o.refcnt);
		ELSE
			Out.String("linking "); Out.String(modname); Out.Ln;
			OBM.MakeFileName(modname,name, OBM.OFext);
			f := Files.Old(name);
			IF f # NIL THEN 
				NEW(o); o.refcnt:=1;
				Files.Set(r, f, 0); 
				ReadHeader(r,o);
			
				(* Import block *)
				IF ~Expect(085X) THEN RETURN END;
				FOR i:=1 TO o.nofImports DO
					Files.ReadLInt(r,key); Files.ReadString(r,str);
					LoadObject(str,o.imports[i]); 
					IF key#o.imports[i].key THEN
						Out.String(name); Out.String(" imports "); Out.String(str); Out.String(" with wrong key"); 
						HALT(99);
					END;
				END;
				IF objs = NIL THEN
					objs := o
				ELSE
					p := objs;
					WHILE p.next # NIL DO p := p.next END;
					p.next := o
				END;

				IF initCnt=MaxModules THEN Out.String("too many modules"); Out.Ln
				ELSE initCalls[initCnt]:=o; INC(initCnt)
				END;
				
				o.base:=pc*4+o.dataSize+LoadBase4;
				IF (o.name="Kernel") OR (o.name="Modules") THEN InitSpecial(o) END;
				
				(* entry block *)
				IF ~Expect(082X) THEN RETURN END;
				FOR i:=0 TO o.nofEntries-1 DO Files.ReadLInt(r, o.entries[i]); INC(o.entries[i],o.base) END; 
			
				(* pointer block *)
				IF ~Expect(084X) THEN RETURN END;
				FOR i:=0 TO o.nofPtrs-1 DO Files.ReadLInt(r,o.ptrs[i]); INC(o.ptrs[i],o.base) END;
			
				(* command block *)
				IF ~Expect(083X) THEN RETURN END;
				FOR i:=0 TO o.nofCmds-1 DO Files.ReadString(r,o.cmds[i].name); Files.ReadLInt(r,o.cmds[i].adr); INC(o.cmds[i].adr,o.base) END; 
			
				(* code & string consts block *)
				INC(pc,o.dataSize DIV 4);
				IF ~Expect(088X) THEN RETURN END;
				FOR i:=0 TO (o.codeSize DIV 4)-1 DO Files.ReadLInt(r,code[pc]); INC(pc) END;
				IF ~Expect(087X) THEN RETURN END;
				FOR i:=0 TO (o.strConstSize DIV 4)-1 DO Files.ReadLInt(r,code[pc]); INC(pc) END;

				(* fixups *)
				IF ~Expect(086X) THEN RETURN END;
				Files.ReadLInt(r,i); ExtCallFixup(i,o);
				Files.ReadLInt(r,i); ExtAddrFixup(i,o);
				Files.ReadLInt(r,i); Fixup(i,o);

				(*tdescs *)
				IF ~Expect(089X) THEN RETURN END;
				ReadTypes(r,o);

				(* refs *)
				IF ~Expect(08BX) THEN RETURN END;
				NEW(o.refs,Files.Length(f)-Files.Pos(r));
				Files.ReadBytes(r,o.refs^,Files.Length(f)-Files.Pos(r));
				
				(* Build type descs *)
				BuildTypeDescs(o); 
						
				DumpProcAddrs(o);
				DumpTDescs(o);
				
				o.init := TRUE;
			ELSE Out.String(name); Out.String(" not found"); Out.Ln
			END
		END
	END LoadObject;

	PROCEDURE FixTypeDescs; (* fixes mdesc entries in all type-descs *)
	VAR o : Object; i : INTEGER; p : LONGINT;
	BEGIN
		o:=objs;
		WHILE o#NIL DO 
			FOR i:=0 TO o.nofRecs-1 DO
				p:=(o.types[i].tdaddr-LoadBase4) DIV 4;
				code[p-2-(MaxExts+1)]:=o.mdesc;  
			END;
			o:=o.next
		END
	END FixTypeDescs;

PROCEDURE MkELFhdr( heapsize, base, len : LONGINT);
VAR i: LONGINT;
BEGIN
	eh.eIdent[ 0]:= 7FX;
	eh.eIdent[ 1]:= "E";
	eh.eIdent[ 2]:= "L";
	eh.eIdent[ 3]:= "F";
	eh.eIdent[ 4]:= 1X;	(* EI_Class= ELFCLASS32 *)
	eh.eIdent[ 5]:= 1X;	(* EI_DATA= ELFDASA2LSB *)
	eh.eIdent[ 6]:= 1X;	(* EI_VERSION= EV_CURRENT *)
	eh.eIdent[ 7]:= 0X;	(* EI_PAD start *)
	FOR i:= 8 TO 15 DO eh.eIdent[ i]:= 0X END;
		(* ELF header *)
	eh.eType:= 2;		(* e-type= ET_EXEC *)
	eh.eMachine:= 40;	(* e_machine 3 = EM_386 40=ARM*)
	eh.eVersion:= 1;	(* e_version = EV_CURRENT *)
	eh.eEntry:= base;	(* e_entry = virtual adr to first start control *)
	eh.ePhoff:= ELFhdrsz;	(* e_phoff = program header's table file offset *)
	eh.eShoff:= 0; (*len+ELFhdrsz+PHTsize+PadSize +2*LEN(attr)+4*LEN(str)*);			(* e_shoff = section header table's file offset *)
	eh.eFlags:= 05000402H;			(* e_flags = no flags on 32 bit intel architecture was: 05000002H *)
	eh.eEhsize:= ELFhdrsz;	(* e_ehsize = ELF header's size in bytes *)
	eh.ePhentsize:= PHTsize;	(* e_phentsize = size of one entry in file's program header table *)
	eh.ePhnum:= 1;			(* e_phnum = number of entries in program header's table *)
	eh.eShentsize:= 40;	(* e_shentsize = section header entry size, was 40*)
	eh.eShnum:= 0;			(* e_shnum = 4 section headers *)
	eh.eShstrndx:= 0;		(* e_shstrndx = SHN_UNDEF was: 3*)
	
	(* Program Header Table *)
	pt[ 0]:= 1;	(* p_type = PT_LOAD *)
	pt[ 1]:= 0; (* was ELFhdrsz+PHTsize+PadSize;*)	(* p_offset = offset from the beginning of the file to first byte of segment *)
	pt[ 2]:= LoadBase4- ELFhdrsz-PHTsize-PadSize;	(* p_vadr = virtual adr of the first byte in memory *)
	pt[ 3]:= LoadBase4- ELFhdrsz-PHTsize-PadSize;	(* p_padr = physical adr ignored *)
	pt[ 4]:= len+ELFhdrsz+PHTsize+PadSize;	(* p_filesz = number of bytes in the file image of the segment *)
	pt[ 5]:= heapsize+ELFhdrsz+PHTsize+PadSize;	(* p_memsz = number of bytes in memory of the segment *)
	pt[ 6]:= 7;	(* p_flags = PF_R+ PF_W+ PF_X, allow read, write, execution *)
	pt[ 7]:= 8000H;	(* p_align = page size *)
	pt[ 8]:= 0;		(* pad *)
	pt[ 9]:= 0;
	pt[ 10]:= 0;
	
	FOR i:=0 TO 9 DO
		shdr[i]:=0;
	END;
(*	
	(* section header .text *)
	shdr[10]:= 1;		(* sh_name *)
	shdr[11]:= 1;		(* sh_type 1=PROGBITS*)
	shdr[12]:= 7;			(* sh_flags 7=XAW*)
	shdr[13]:= 80060H;			(* sh_addr *)
	shdr[14]:= 60H;			(* sh_offset *)
	shdr[15]:= len;			(* sh_size *)
	shdr[16]:= 0;			(* sh_link *)
	shdr[17]:= 0;			(* sh_info *)
	shdr[18]:= 8;			(* sh_addralign *)
	shdr[19]:= 0;			(* sh_entsize *)
	
	(* section header .ARM.attributes *)
	shdr[20]:= 17;
	shdr[21]:= 70000003H;		(* sh_type ARM_ATTRIBUTR *)
	shdr[22]:= 0;
	shdr[23]:= 0;
	shdr[24]:= pc+60H;		(* sh_offset *)
	shdr[25]:= 16H;
	shdr[26]:= 0;
	shdr[27]:= 0;
	shdr[28]:= 1;
	shdr[29]:= 0;

	(* section header .shstrtab *)
	shdr[30]:= 7;
	shdr[31]:= 3;		(* sh_type STRTAB *)
	shdr[32]:= 0;
	shdr[33]:= 0;
	shdr[34]:= pc+76H;		(* sh_offset *)
	shdr[35]:= 36;
	shdr[36]:= 0;
	shdr[37]:= 0;
	shdr[38]:= 1;
	shdr[39]:= 0;
	
	attr[0]:= 1541H;
	attr[1]:=0000H;
	attr[2]:= 6100H;
	attr[3]:= 6165H;
	attr[4]:= 6962H;
	attr[5]:= 0100H;
	attr[6]:= 000BH;
	attr[7]:= 0000H;
	attr[8]:= 0106H;
	attr[9]:= 0108H;
	attr[10]:= 012CH;
	
	str[0]:= ((ORD("e")*256+ORD("t"))*256+ORD("."))*256+0;
	str[1]:= ((ORD(".")*256+0)*256+ORD("t"))*256+ORD("x");
	str[2]:= ((ORD("t")*256+ORD("s"))*256+ORD("h"))*256+ORD("s");
	str[3]:= ((ORD("b")*256+ORD("a"))*256+ORD("t"))*256+ORD("r");
	str[4]:= ((ORD("R")*256+ORD("A"))*256+ORD("."))*256+0;
	str[5]:= ((ORD("t")*256+ORD("a"))*256+ORD("."))*256+ORD("M");
	str[6]:= ((ORD("b")*256+ORD("i"))*256+ORD("r"))*256+ORD("t");
	str[7]:= ((ORD("s")*256+ORD("e"))*256+ORD("t"))*256+ORD("u");
	str[8]:= 0;
*)		
(*	shdr[25]:=
	shdr[26]:=
	shdr[27]:=
	shdr[28]:=
	shdr[29]:=
*)
END MkELFhdr;

PROCEDURE BuildImage( s: ARRAY OF CHAR);
VAR i: LONGINT;
		f : Files.File; r : Files.Rider;
		o : Object;
		entry, res, of : LONGINT;
		buf: ARRAY 64 OF LONGINT;
BEGIN
	LoadObject(s,o); BuildModuleBlocks; FixTypeDescs;

	(* patch linked list of modules *)
	IF ~quiet THEN
		Out.String("Kernel.modules @ "); Hex(modulesAddr*4+LoadBase4); Out.String("   init val="); Hex(modules); Out.Ln;
	END;
	code[modulesAddr]:=modules;
											
	(* Generate calls to module bodies *)
	entry:=LoadBase4+pc*4; Out.String("Entry="); Hex(entry); Out.Ln;
	code[pc]:=0E3A0C000H; INC(pc); (* MOV FP,0 *)
	FOR i:=0 TO initCnt-1 DO
		code[pc]:=0EB000000H+(((initCalls[i].entryPoint+initCalls[i].base-LoadBase4) DIV 4-(pc+2)) MOD 1000000H);
		INC(pc);
	END;
	code[pc]:=0EA000000H+((-2) MOD 1000000H); (* "loop: B loop" We should not get here, but who knows... *)
	
	(* Patch "modLoadAddr" *)
	code[modLoadAddrAddr]:=LoadBase4+(pc+1023) DIV 1024 * 1*4096;
	
	(* Now the funny part. Generate the a.out file! *)

	i:=0;
(*
	WHILE OBM.prefix[ i]#0X DO
		ImageName[i]:=OBM.prefix[ i];
		INC( i);
	END;
	IF i>0 THEN ImageName[i-1]:= "/" END;
*)
	ImageName[i]:= "o";
	ImageName[i+1]:= "l";
	ImageName[i+2]:= "a";
	ImageName[i+3]:= 0X;

	f:=Files.New("");
	Files.Set(r,f,0); 
	pc:=pc*4;			
	MkELFhdr( pc, entry, pc );

(*	(* generate a.out header *)
			code[0]:=ElfMagic; (* midmag *)
			code[1]:=pc; (* text *)
			code[1]:=CodeSize; (* text *)

			code[2]:=0; (* data *)
			code[3]:=0; (* bss *)
			code[4]:=0; (* sym *)
			code[5]:=entry; (* entry *)
			code[6]:=0; (* trsize *)
			code[7]:=0; (* drsize *)
*)								
			(* write file *)
	Out.String("writing "); Out.String(ImageName); Out.Ln;
	Files.WriteBytes(r, eh, SIZE(ELF32EHDR));
	Files.WriteBytes(r, pt, 4*LEN(pt));
	Files.WriteBytes(r, code^, pc);
(*
	Files.WriteBytes(r, attr, 2*LEN(attr));
	Files.WriteBytes(r, str, 4*LEN(str));
	Files.WriteBytes(r, shdr, 4*LEN(shdr));
*)
	(* create bootfile with correct permissions and copy data *)
	Files.Set( r, f, 0);
	of:= Linux0.Openat0( Linux0.ATFDCWD, SYSTEM.ADR(ImageName[0]), RDWR+OCREAT+OTRUNC, 1EDH);	(* mode = 755 octal *)
	REPEAT
		Files.ReadBytes( r, buf, 256);
		res:=Linux0.Write0( of, SYSTEM.ADR(buf[0]), 256-r.res);
	UNTIL r.eof;
	res:=Linux0.Close0(of);
	Files.Close(f); f:=NIL;
	Out.String("done."); Out.Ln;
END BuildImage;
	
	PROCEDURE  Link*;
		VAR 
			s: Texts.Scanner;  text : Texts.Text;
			beg, end, time, i : LONGINT;
											
	BEGIN
		Out.String("OLR Oberon BootLinker 2015-02-12"); Out.Ln;
		objs:=NIL; pc:=0;
		FOR i:=0 TO 15 DO fixup[ i]:= -1 END;
		modules:=0; initCnt:=0;
		modulesAddr := -1; modLoadAddrAddr := -1;
		FOR i := 0 TO MaxModules-1 DO initCalls[i] := NIL END;
		IF code = NIL THEN NEW(code, 30000H) END;
		FOR i := 0 TO LEN(code^)-1 DO code[i] := 0 END;
		Texts.OpenScanner(s, Oberon.Par.text, Oberon.Par.pos); Texts.Scan(s);
		quiet := FALSE;
		WHILE (s.class = Texts.Char) & (s.c = Oberon.OptionChar) DO
			Texts.Scan(s);
			IF s.class = Texts.Name THEN
				IF s.s = "q" THEN quiet := TRUE
				ELSIF s.s[0] = "P" THEN
					i := 1; WHILE s.s[i] # 0X DO OBM.prefix[i-1] := s.s[i]; INC(i) END;
					OBM.prefix[i-1] := 0X
				ELSE (* skip *)
				END;
				Texts.Scan(s)
			END
		END;
		IF (s.class = Texts.Char) & (s.c = "^") THEN
			Oberon.GetSelection(text, beg, end, time);
			IF time>=0 THEN Texts.OpenScanner(s, text, beg); Texts.Scan(s) ELSE s.class := Texts.Inval END
		ELSIF ~(s.class IN {Texts.Name, Texts.String}) OR (s.line # 0) THEN s.class := Texts.Inval;
		END ;
		IF s.class = Texts.Name THEN
			BuildImage(s.s);
			Oberon.Collect;
		ELSE Out.String("no module name"); Out.Ln;  
		END;
	END Link;

BEGIN
	code := NIL
END ABootLinker.

