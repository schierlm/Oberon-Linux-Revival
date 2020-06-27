MODULE MPeephole;
(*peephole optimizer for R2000/R3000, Ambros Marzetta, 10.4.1991, RC 29.8.91, AM 7.11.91, RC 23.7.92/3.8.93 *)
	(*commands:
		POR.Do {objfile} (*optimize objfiles*)
		POR.DoPartial objfile 1 1 1 1 (*FindBlocks RedundantBranches FillLoadDelaySlots FillBranchDelaySlots*)
		POR.Describe Instr
		POR.Dependent Instr1 Instr2
		
		important procedures:
		MakeInstrRec dependent ReadFile FindBlocks RedundantBranches FillLoadDelaySlots InitSort
		Choose Emit RemoveFromGraph LastInstrOfBlock SortBlock FillBranchDelaySlots FindRealAddresses WriteFile

		Peter Matthias
		2015-05-24		changed MaxCode from 10000 to 20000
		2015-06-14	changed MaxCode, MaxBlock and MaxBlockSize; added OptimizeAll
		2015-06-16	fixed uninitialized name in OptimizeMod
		2015-08-21	not optimizing LoadDelaySlot	(MOP2 does not use LDS)
	*)
	
	IMPORT Files, Texts, Oberon, SYSTEM, Kernel;
	
	CONST
		prefix="./mips";
		MaxFilename = 64; (*characters in file name*)
		MaxName = 32; (*characters in module or procedure name*)
		MaxCode = 30000; (*words in code block of object file, was 10000*)
		MaxBlock = 5000; (*basic blocks in code, was 3000*)
		MaxBlockSize = 600; (*words in a basic block, was 300*)
		MaxEntry = 500; (*entries in entry table*)
		MaxLink = 1000; (*link chains in object file*)
		MaxRef = 250; (*procedures in RefBlk*)
		
		T5 = 32; T6 = 64; T8 = 256; T10 = 1024; T11 = 2048; T16 = 10000H; (*powers of two*)
		T21 = 32 * T16; T24 = 8 * T21; T25 = 2 * T24; T26 = 32 * T21;
		
		SPECIAL = 0; BCOND = 1; J = 2; JAL = 3; BEQ = 4; BNE = 5; BLEZ = 6; BGTZ = 7;
		ADDI = 8; ADDIU = 9; SLTI = 10; SLTIU = 11; LUI = 15; COP1 = 17; COP2 = 18; LWC1 = 49; SWC1 = 57; (*opcode*)
		
		BLTZ = 0; BGEZ = 1; BLTZAL = 16; BGEZAL = 17; (*BCOND*)
		
		JR = 8; JALR = 9; SYSCALL = 12; BREAK = 13; MFHI = 16; MFLO = 18;(*special*)
		
		linkflag = 0; followlinkflag = 1; labelflag = 2; branchflag = 3; (*flags*)
		Pnone = 0; Pdelayed = 1; (*priorities for sorting*)
		Shi = 0; Slo = 1; Smem = 2; Scop1cond = 3; Somega = 4; (*"special registers"*)
		BlockA = 0; BlockB = 1; BlockC = 2; BlockD = 3; BlockE = 4; BlockF = 5; (*block types*)
		
		OFtag = 36F9H; (*object file tag*) Nil = -5; NOP = 0; BC1 = 69;
		Extension = ".Obj";
		
	TYPE
(*		Filename = ARRAY MaxFilename OF CHAR;*)
		Name = ARRAY MaxName OF CHAR;
		Instr = LONGINT; (*R2000 instruction*)
		CodeArray = ARRAY MaxCode OF Instr;
		Flag = SET;
		FlagArray = ARRAY MaxCode OF Flag;
		RegSet = RECORD g, f, s: SET END;
		State = RECORD delayedset: RegSet; hiwait, lowait: INTEGER END;
		BlockRec = RECORD begin, type: INTEGER; beginstate: State; END;
		BlockArray = ARRAY MaxBlock OF BlockRec;
		EntryArray = ARRAY MaxEntry OF INTEGER;
		LinkArray = ARRAY MaxLink OF INTEGER;
		RefArray = ARRAY MaxRef OF INTEGER;
		InstrRec = RECORD i: Instr; r1, r, w: RegSet; delayed, nop: BOOLEAN; priority: SHORTINT END;

	DirEntP= POINTER TO RECORD
					dino: LONGINT;
					doff: LONGINT;
					dreclen: INTEGER;
					dname: Files.FileName;
(*					pad, type: CHAR;  pad, type do it manually  *)
				END;

	
	VAR
		WR: Texts.Writer; Par: Texts.Scanner;
		code: CodeArray; flags: FlagArray; codesize, nofptr, nofdesc, nofcom: INTEGER;
		nofimp, datasize, consize, oldcodesize: LONGINT;
		block: BlockArray; nofblock: INTEGER;
		entry: EntryArray; nofentr: INTEGER;
		link: LinkArray; noflink: INTEGER;
		ref: RefArray; nofref: INTEGER;
		blocknr: ARRAY MaxCode OF INTEGER; (*local to FindBlocks*)
	
	PROCEDURE SetFlag(index, i: INTEGER);
	BEGIN
		INCL(flags[index], i)
	END SetFlag;
	
	PROCEDURE GetFlag(index, i: INTEGER): BOOLEAN;
	BEGIN
		RETURN i IN flags[index]
	END GetFlag;
	
	PROCEDURE min(a, b: INTEGER): INTEGER;
	BEGIN
		IF a < b THEN RETURN a ELSE RETURN b END
	END min;
	
	PROCEDURE ClearRegSet(VAR x: RegSet);
	BEGIN
		x.g := {}; x.f := {}; x.s := {}
	END ClearRegSet;
	
	PROCEDURE RegSetUnion(VAR x, y: RegSet);
	BEGIN
		x.g := x.g+y.g; x.f := x.f+y.f; x.s := x.s+y.s
	END RegSetUnion;

	PROCEDURE StateUnion(VAR x, y: State);
	BEGIN
		RegSetUnion(x.delayedset, y.delayedset);
		IF x.hiwait < y.hiwait THEN x.hiwait := y.hiwait END;
		IF x.lowait < y.lowait THEN x.lowait := y.lowait END
	END StateUnion;
	
	PROCEDURE sImm(i: Instr): INTEGER; (*15..0*)
	BEGIN
		RETURN SHORT(i * T16 DIV T16)
	END sImm;
	
	PROCEDURE uOp(i: Instr): INTEGER; (*31..26*)
	BEGIN
		RETURN SHORT(i DIV T26 MOD T6)
	END uOp;
	
	PROCEDURE uRs(i: Instr): INTEGER;(*25..21*)
	BEGIN
		RETURN SHORT(i DIV T21 MOD T5)
	END uRs;
	
	PROCEDURE uRt(i: Instr): INTEGER; (*20..16*)
	BEGIN
		RETURN SHORT(i DIV T16 MOD T5)
	END uRt;
	
	PROCEDURE uRd(i: Instr): INTEGER; (*15..11*)
	BEGIN
		RETURN SHORT(i DIV T11 MOD T5)
	END uRd;
	
	PROCEDURE uShamt(i: Instr): INTEGER; (*10..6*)
	BEGIN
		RETURN SHORT(i DIV T6 MOD T5)
	END uShamt;
	
	PROCEDURE uFunct(i: Instr): INTEGER; (*5..0*)
	BEGIN
		RETURN SHORT(i MOD T6)
	END uFunct;
	
	PROCEDURE SetImm(VAR i: Instr; j: LONGINT);
	BEGIN
		i := i DIV T16 * T16 + j MOD T16
	END SetImm;
	
	PROCEDURE isAbsBranch(i: Instr): BOOLEAN;
	BEGIN
		RETURN uOp(i) DIV 2 = 1 (*J, JAL*)
	END isAbsBranch;
	
	PROCEDURE isRegBranch(i: Instr): BOOLEAN;
	BEGIN
		RETURN (uOp(i) = SPECIAL) & (uFunct(i) DIV 2 = 4 (*JR, JALR*))
	END isRegBranch;
	
	PROCEDURE isSureRelBranch(i: Instr): BOOLEAN; (*BEQ 0, 0, ...*)
	BEGIN
		RETURN i DIV T16 = BEQ*T10
	END isSureRelBranch;
	
	PROCEDURE isSureBranch(i: Instr): BOOLEAN; (*unconditional branch without link*)
	BEGIN
		RETURN (i DIV T16 = BEQ*T10) OR
						(uOp(i) = J) OR
						((uOp(i) = SPECIAL) & (uFunct(i) = JR))
	END isSureBranch;
	
	PROCEDURE isCondBranch(i: Instr): BOOLEAN;
	BEGIN
		RETURN (uOp(i) DIV 4 = 1 (*BEQ, BGTZ, BLEZ, BNE*)) & (i DIV T16 # BEQ*T10) OR
						(uOp(i) = BCOND) & (i DIV T16 # BCOND*T10+BGEZAL) OR
						(i DIV T24 = BC1)
	END isCondBranch;
	
	PROCEDURE isRelBranch(i: Instr): BOOLEAN;
	BEGIN
		RETURN (uOp(i) DIV 4 = 1 (*BEQ, BGTZ, BLEZ, BNE*)) OR (uOp(i) = BCOND) OR (i DIV T24 = BC1)
	END isRelBranch;
	
	PROCEDURE isAnyBranch(i: Instr): BOOLEAN;
	BEGIN
		RETURN isRelBranch(i) OR isAbsBranch(i) OR isRegBranch(i)
	END isAnyBranch;
	
	PROCEDURE isMFHI(i: Instr): BOOLEAN;
	BEGIN
		RETURN (uOp(i) = SPECIAL) & (uFunct(i) = MFHI)
	END isMFHI;
	
	PROCEDURE isMFLO(i: Instr): BOOLEAN;
	BEGIN
		RETURN (uOp(i) = SPECIAL) & (uFunct(i) = MFLO)
	END isMFLO;
	
	PROCEDURE MakeInstrRec2(i: Instr; VAR rec: InstrRec);
		VAR op, funct, rs, rt, rd, ft, fs, fd: INTEGER; r2g: SET;
	BEGIN
		op := uOp(i); funct := uFunct(i); rs := uRs(i); rt := uRt(i); rd := uRd(i); ft := rt; fs := rd; fd := uShamt(i);
		rec.i := i; rec.priority := Pnone; rec.delayed := FALSE; rec.nop := FALSE;
		ClearRegSet(rec.r); ClearRegSet(rec.w); INCL(rec.r.s, Somega); r2g := {};
		IF op = SPECIAL THEN
			IF (funct # SYSCALL) & (funct # BREAK) THEN
				INCL(rec.r.g, rs); INCL(rec.r.g, rt); INCL(rec.w.g, rd)
			END;
			IF funct DIV 8 = 1 THEN (*JR, JALR, SYSCALL, BREAK*)
				INCL(rec.w.s, Somega)
			ELSIF funct DIV 16 = 1 THEN (*MFHI, MFLO, MTHI, MTLO, MULT, MULTU, DIV, DIVU*)
				IF funct = MFHI THEN
					INCL(rec.r.s, Shi)
				ELSIF funct = MFLO THEN
					INCL(rec.r.s, Slo)
				ELSE
					INCL(rec.w.s, Shi); INCL(rec.w.s, Slo); INCL(rec.r.s, Shi); INCL(rec.r.s, Slo)
				END
			END
		ELSIF op DIV 8 = 4 THEN (*load*)
			INCL(rec.r.g, rs); INCL(rec.w.g, rt); INCL(rec.r.s, Smem); rec.delayed := TRUE;
			IF op MOD 4 = 2 THEN INCL(rec.r.g, rt); INCL(r2g, rt) END (*LWL, LWR*)
		ELSIF op DIV 8 = 5 THEN (*store*)
			INCL(rec.r.g, rs); INCL(rec.r.g, rt); INCL(rec.w.s, Smem);
		ELSIF op DIV 4 = 1 THEN (*BEQ, BNE, BLEZ, BGTZ*)
			INCL(rec.r.g, rs); INCL(rec.r.g, rt); INCL(rec.w.s, Somega)
		ELSIF (8<=op) & (op<=14) THEN (*ADDI...*)
			INCL(rec.r.g, rs); INCL(rec.w.g, rt)
		ELSIF op = LUI THEN
			INCL(rec.w.g, rt)
		ELSIF op = BCOND THEN
			INCL(rec.r.g, rs); INCL(rec.w.s, Somega); IF rt >= 16 THEN (*BLTZAL, BGEZAL*) INCL(rec.w.g, 31) END
		ELSIF op DIV 2 = 1 THEN (*J, JAL*)
			INCL(rec.w.s, Somega); IF op = JAL THEN INCL(rec.w.g, 31) END
		ELSIF op = LWC1 THEN
			INCL(rec.r.g, rs); INCL(rec.w.f, ft); INCL(rec.r.s, Smem); rec.delayed := TRUE
		ELSIF op = SWC1 THEN
			INCL(rec.r.g, rs); INCL(rec.r.f, ft); INCL(rec.w.s, Smem)
		ELSIF op = COP1 THEN
			IF rs = 0 THEN (*MFC1*)
				INCL(rec.w.g, rt); INCL(rec.r.f, fs); rec.delayed := TRUE
			ELSIF rs = 4 THEN (*MTC1*)
				INCL(rec.r.g, rt); INCL(rec.w.f, fs); rec.delayed := TRUE
			ELSIF rs DIV 8 = 1 THEN (*BC1F, BC1T*)
				INCL(rec.w.s, Somega); INCL(rec.r.s, Scop1cond)
			ELSIF rs < 16 THEN (*CFC1, CTC1*)
				INCL(rec.w.s, Somega); rec.delayed := TRUE
			ELSE (*rs >= 16*)
				IF funct >= 48 THEN (*compare*)
					INCL(rec.w.s, Scop1cond); rec.delayed := TRUE;
					INCL(rec.r.f, ft); INCL(rec.r.f, fs);
					IF ODD(rs) THEN (*double*) INCL(rec.r.f, ft+1); INCL(rec.r.f, fs+1) END
				ELSIF funct <= 3 THEN (*ADD, SUB, MUL, DIV*)
					INCL(rec.r.f, ft); INCL(rec.r.f, fs); INCL(rec.w.f, fd); INCL(rec.w.f, fd+1);
					IF ODD(rs) THEN (*double*) INCL(rec.r.f, ft+1); INCL(rec.r.f, fs+1) END
				ELSIF funct <= 7 THEN (*ABS, MOV, NEG*)
					INCL(rec.r.f, fs); INCL(rec.w.f, fd); INCL(rec.w.f, fd+1);
					IF ODD(rs) THEN (*double*) INCL(rec.r.f, fs+1) END
				ELSE (*CVT*)
					INCL(rec.r.f, fs); INCL(rec.r.f, fs+1); INCL(rec.w.f, fd); INCL(rec.w.f, fd+1)
				END
			END
		ELSIF op MOD 32 >= 16 THEN (*COP0, COP2, COP3, LWC0, LWC2, LWC3, SWC0, SWC2, SWC3*)
			INCL(rec.w.s, Somega); rec.delayed := TRUE
		END;
		EXCL(rec.r.g, 0); EXCL(rec.w.g, 0); (*register 0 is always zero*)
		IF (rec.w.g = {}) & (rec.w.f = {}) & (rec.w.s = {}) THEN
			rec.nop := TRUE;
			ClearRegSet(rec.r)
		END;
		IF rec.delayed THEN rec.priority := Pdelayed END;
		rec.r1 := rec.r;
		rec.r1.g := rec.r1.g - r2g
	END MakeInstrRec2;
	
	PROCEDURE MakeInstrRec(index: INTEGER; VAR rec: InstrRec);
		VAR i: Instr; op: INTEGER;
	BEGIN
		i := code[index]; op := uOp(i);
		IF GetFlag(index, followlinkflag) THEN (*treat longword after a link as a NOP*)
			rec.i := i; rec.priority := Pnone; rec.delayed := FALSE; rec.nop := TRUE;
			ClearRegSet(rec.r); ClearRegSet(rec.w); rec.r1 := rec.r;
		ELSIF GetFlag(index, linkflag) & (op # JAL) THEN
			rec.i := i; ClearRegSet(rec.r); ClearRegSet(rec.w); rec.r1 := rec.r; INCL(rec.r.s, Somega);
			rec.nop := FALSE; rec.priority := Pnone;
			IF op = LUI THEN (*load address (case table / procedure)*)
				INCL(rec.w.g, 1); INCL(rec.w.g, uRt(code[index+1])); rec.delayed := FALSE
			ELSIF op = ADDIU THEN (*load address (variable)*)
				INCL(rec.w.g, uRt(i)); rec.delayed := FALSE
			ELSIF op >= 48 THEN (*load/store global data (8 byte)*)
				INCL(rec.w.g, 1);
				IF op >= 56 THEN (*store*)
					INCL(rec.r.f, uRt(i)); INCL(rec.r.f, uRt(i)+1);INCL(rec.w.s, Smem); rec.delayed := FALSE
				ELSE (*load*)
					INCL(rec.w.f, uRt(i)); INCL(rec.w.f, uRt(i)+1); INCL(rec.r.s, Smem); rec.delayed := TRUE
				END
			ELSE (*load/store global data (1, 2, 4 byte)*)
				INCL(rec.w.g, uRs(i));
				IF op >= 40 THEN (*store*)
					INCL(rec.r.g, uRt(i)); INCL(rec.w.s, Smem); rec.delayed := FALSE
				ELSE (*load*)
					INCL(rec.w.g, uRt(i)); INCL(rec.r.s, Smem); rec.delayed := TRUE
				END
			END;
			IF rec.delayed THEN rec.priority := Pdelayed END
		ELSE (*ordinary instruction*)
			MakeInstrRec2(i, rec)
		END
	END MakeInstrRec;
	
	PROCEDURE dependent(VAR a, b: InstrRec): BOOLEAN; (*TRUE if a and b can not be exchanged*)
	BEGIN
		IF a.r.g*b.w.g + a.w.g*b.r.g + a.w.g*b.w.g # {} THEN RETURN TRUE END;
		IF a.r.f*b.w.f + a.w.f*b.r.f + a.w.f*b.w.f # {} THEN RETURN TRUE END;
		RETURN a.r.s*b.w.s + a.w.s*b.r.s + a.w.s*b.w.s # {}
	END dependent;
	
	PROCEDURE WriteRegSet(x: RegSet);
		VAR i: INTEGER;
	BEGIN
		i := 0; WHILE i < 32 DO IF i IN x.g THEN Texts.WriteString(WR, " r"); Texts.WriteInt(WR, i, 0) END; INC(i) END;
		i := 0; WHILE i < 32 DO IF i IN x.f THEN Texts.WriteString(WR, " f"); Texts.WriteInt(WR, i, 0) END; INC(i) END;
		i := 0; WHILE i < 32 DO IF i IN x.s THEN Texts.WriteString(WR, " s"); Texts.WriteInt(WR, i, 0) END; INC(i) END
	END WriteRegSet;
	
(*	PROCEDURE Describe*; (*POR2000.Describe Instr*)
		VAR S: Texts.Scanner;
			a: InstrRec;
	BEGIN
		Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos);
		Texts.Scan(S);
		IF S.class = Texts.Int THEN
			MakeInstrRec2(S.i, a);
			Texts.WriteString(WR, "R:"); WriteRegSet(a.r); Texts.WriteLn(WR);
			Texts.WriteString(WR, "R1:"); WriteRegSet(a.r1); Texts.WriteLn(WR);
			Texts.WriteString(WR, "W:"); WriteRegSet(a.w); Texts.WriteLn(WR);
			IF a.delayed THEN Texts.WriteString(WR, "delayed ") END;
			IF a.nop THEN Texts.WriteString(WR, "nop ") END
		ELSE Texts.WriteString(WR, "argument is not an integer")
		END;
		Texts.WriteLn(WR); Texts.Append(Oberon.Log, WR.buf)
	END Describe;*)
	
(*	PROCEDURE Dependent*; (*POR2000.Dependent Instr Instr*)
		VAR S: Texts.Scanner;
			a, b: InstrRec;
	BEGIN (*Dependent*)
		Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos);
		Texts.Scan(S);
		IF S.class = Texts.Int THEN
			MakeInstrRec2(S.i, a);
			Texts.Scan(S);
			IF S.class = Texts.Int THEN
				MakeInstrRec2(S.i, b);
				IF dependent(a, b) THEN
					Texts.WriteString(WR, "dependent")
				ELSE
					Texts.WriteString(WR, "not dependent")
				END
			ELSE Texts.WriteString(WR, "second argument is not an integer")
			END
		ELSE Texts.WriteString(WR, "first argument is not an integer")
		END;
		Texts.WriteLn(WR); Texts.Append(Oberon.Log, WR.buf)
	END Dependent;*)
	
	PROCEDURE ChangeBlockSize(blocknr, diff: INTEGER);
		VAR from, to, e: INTEGER;
	BEGIN
		IF diff # 0 THEN
			INC(codesize, diff);
			e := blocknr + 1; WHILE e <= nofblock DO INC(block[e].begin, diff); INC(e) END;
			IF diff > 0 THEN
				e := block[blocknr+1].begin;
				to := codesize; from := to - diff;
				WHILE to > e DO DEC(from); DEC(to); code[to] := code[from]; flags[to] := flags[from] END
			ELSE
				to := block[blocknr+1].begin;
				from := to - diff;
				WHILE to < codesize DO code[to] := code[from]; flags[to] := flags[from]; INC(from); INC(to) END
			END
		END
	END ChangeBlockSize;
	
	PROCEDURE Append(VAR a: ARRAY OF CHAR; b: ARRAY OF CHAR);
		(*a := a + b*)
		VAR ia, ib: INTEGER;
	BEGIN
		ia := 0; WHILE a[ia] # 0X DO INC(ia) END;
		ib := 0; WHILE b[ib] # 0X DO a[ia] := b[ib]; INC(ia); INC(ib) END;
		a[ia] := 0X
	END Append;
	
	PROCEDURE GetFilename(VAR filename: Files.FileName);
		VAR i: INTEGER;
	BEGIN
		Texts.Scan(Par);
		IF Par.class = Texts.Name THEN
			i := 0;
			WHILE Par.s[i] # 0X DO filename[i] := Par.s[i]; INC(i) END;
			filename[i] := 0X;
			Append(filename, Extension)
		ELSE filename := "" END
	END GetFilename;

	PROCEDURE BooleanPar(): BOOLEAN;
	BEGIN
		Texts.Scan(Par);
		RETURN (Par.class = Texts.Int) & (Par.i # 0)
	END BooleanPar;
	
	PROCEDURE ReadFile(filename: Files.FileName; VAR ok: BOOLEAN; VAR R: Files.Rider);
		VAR
			f: Files.File;
			refsize, k, nofnm, nofp: LONGINT;
			tag, i: INTEGER;
			name: Name;
			ch: CHAR;
	
		PROCEDURE Block(tag: CHAR);
			VAR ch: CHAR;
		BEGIN
			Files.Read(R, ch); IF ch # tag THEN HALT(99) END ;
		END Block;
		
		PROCEDURE Skip(n: LONGINT);
		BEGIN
			Files.Set(R, Files.Base(R), Files.Pos(R)+n)
		END Skip;
		
		PROCEDURE MakeLinks(ent, link: INTEGER);
			VAR this, next: INTEGER;
		BEGIN
			next := link;
			REPEAT
				this := next;
				next := this + 1 + sImm(code[this]);
				IF next = this - 1 THEN (*8 bytes access*)
					this := next;
					next := this + 1 + sImm(code[this]);
					SetFlag(this+2, followlinkflag);
					SetImm(code[this+1], ent)
				END;
				IF ~ isAbsBranch(code[this]) THEN SetFlag(this+1, followlinkflag) END;
				SetFlag(this, linkflag);
				SetImm(code[this], ent)
			UNTIL next = this
		END MakeLinks;
		
	BEGIN (*ReadFile*)
		ok := TRUE;
		f := Files.Old(filename);
		IF f = NIL THEN
			Texts.WriteString(WR, filename); Texts.WriteString(WR, ": file not found"); Texts.WriteLn(WR);
			Texts.Append(Oberon.Log, WR.buf);
			ok := FALSE; RETURN
		END ;
		Files.Set(R, f, 0);
		Files.ReadInt(R, tag);
		IF tag # OFtag THEN
			Texts.WriteString(WR, "not an object file"); Texts.WriteLn(WR);
			Texts.Append(Oberon.Log, WR.buf);
			ok := FALSE; RETURN
		END ;
	(* HeaderBlk *)
		Files.ReadLInt(R, refsize); Files.ReadInt(R, i); Files.ReadInt(R, nofdesc); Files.ReadInt(R, nofcom);
		Files.ReadInt(R, nofptr); Files.ReadNum(R, nofimp); Files.ReadNum(R, k); link[0] := SHORT(k);
		Files.ReadNum(R, k); link[1] := SHORT(k); Files.ReadNum(R, k); link[2] := SHORT(k);
		Files.ReadNum(R, k); link[3] := SHORT(k); noflink := 4; nofentr := 0;
		Files.ReadNum(R, datasize); Files.ReadNum(R, consize);
		Files.ReadNum(R, k); codesize := SHORT(k); Files.ReadString(R, name);
	(* ImpBlk *)
		Block(81X); i := 0;
		WHILE i < nofimp DO Files.ReadString(R, name); INC(i) END ;
	(* ExpBlk *)
		Block(82X); Files.Read(R, ch);
		WHILE ch # 0X DO
			IF ch = 8X THEN
				Files.ReadString(R, name);
				IF name = "" THEN Files.ReadNum(R, k) END ;
				Files.ReadNum(R, k); link[noflink] := SHORT(k); INC(noflink); Files.ReadNum(R, k); Files.ReadNum(R, k);
				IF k >= 0 THEN Files.ReadString(R, name);
					IF name = "" THEN Files.ReadNum(R, k) END
				END ;
				Files.ReadNum(R, k); Files.ReadNum(R, k);
				Files.ReadNum(R, nofnm); Files.ReadNum(R, nofp);
				i := 0;
				WHILE i < nofnm DO Files.ReadNum(R, k);
					Files.ReadNum(R, k); entry[nofentr] := SHORT(k); INC(nofentr); INC(i)
				END ;
				i := 0;
				WHILE i < nofp DO Files.ReadNum(R, k); INC(i) END
			ELSIF ch = 9X THEN
				Files.ReadNum(R, k); entry[nofentr] := SHORT(k); INC(nofentr);
				Files.ReadNum(R, k); link[noflink] := SHORT(k); INC(noflink)
			ELSE
				Files.ReadString(R, name); Files.ReadNum(R, k);
				IF ch = 3X THEN Files.ReadNum(R, k)
				ELSIF ch = 4X THEN Files.ReadNum(R, k); entry[nofentr] := SHORT(k); INC(nofentr)
				ELSIF ch = 6X THEN Files.ReadNum(R, k)
				END
			END ;
			Files.Read(R, ch)
		END ;
	(* CmdBlk *)
		Block(83X); i := 0;
		WHILE i < nofcom DO
			Files.ReadString(R, name); Files.ReadNum(R, k); entry[nofentr] := SHORT(k); INC(nofentr); INC(i)
		END ;
	(* PtrBlk *)
		Block(84X); i := 0;
		WHILE i < nofptr DO Files.ReadNum(R, k); INC(i) END ;
	(* ConstBlk *)
		Block(87X); Skip(consize);
	(* CodeBlk *)
		Block(88X);
		IF codesize > MaxCode THEN HALT(93) (*code too long*) END;
		i := 0;
		WHILE i < codesize DO Files.ReadLInt(R, code[i]); INC(i) END;
	(* UseBlk *)
		Block(89X); i := 0;
		WHILE i < nofimp DO
			Files.Read(R, ch);
			WHILE ch # 0X DO
				Files.ReadString(R, name); Files.ReadNum(R, k);
				CASE ch OF
				| 1X, 2X, 5X, 6X, 7X:
				| 3X, 4X: Files.ReadNum(R, k); link[noflink] := SHORT(k); INC(noflink)
				| 8X: IF name = "" THEN Files.ReadNum(R, k) END ;
						link[noflink] := SHORT(k); INC(noflink)
				END ;
				Files.Read(R, ch)
			END ;
			INC(i)
		END ;
	(* RefBlk *)
		Block(8AX); nofref := 0;
		Files.Read(R, ch);
		WHILE ~ R.eof DO
			IF ch # 0F8X THEN HALT(99) END;
			Files.ReadNum(R, k); ref[nofref] := SHORT(k);
			Files.ReadNum(R, k); Files.ReadNum(R, k); Files.ReadNum(R, k); Files.ReadNum(R, k); INC(nofref);
			Files.ReadString(R, name);
			Files.Read(R, ch);
			WHILE (ch # 0F8X) & ~R.eof DO Files.Read(R, ch); Files.ReadNum(R, k); Files.ReadString(R, name); Files.Read(R, ch) END
		END;
		i := 0; WHILE i < codesize DO flags[i] := {}; INC(i) END;
		i := 0;
		WHILE i < noflink DO
			IF link[i] # 0 THEN MakeLinks(i, link[i]); link[i] := Nil END ;
			INC(i)
		END;
		Files.Set(R, f, 0)
	END ReadFile;
	
	PROCEDURE FindBlocks;
		VAR i, last, dest, destblock: INTEGER; instr: InstrRec; br: Instr;
	BEGIN
		(*mark all labels and branches*)
		i := 0; WHILE i < nofentr DO SetFlag(entry[i], labelflag); INC(i) END;
		i := 0; WHILE i < nofref DO SetFlag(ref[i], labelflag); INC(i) END;
		i := 0;
		WHILE i < codesize DO
			IF ~ GetFlag(i, followlinkflag) & isAnyBranch(code[i]) THEN
				SetFlag(i, branchflag);
				SetFlag(i+2, labelflag);
				IF isRelBranch(code[i]) THEN
					dest := i+1+sImm(code[i]);
					SetFlag(dest, labelflag)
				END
			END;
			INC(i)
		END;
		(*all branches and labels are flagged; now initialize block array*)
		nofblock := 0;
		i := 0;
		WHILE i < codesize DO
			IF GetFlag(i, labelflag) THEN (*this instruction begins a basic block*)
				ClearRegSet(block[nofblock].beginstate.delayedset);
				block[nofblock].beginstate.hiwait := 0; block[nofblock].beginstate.lowait := 0;
				IF nofblock > 0 THEN (*determine type of preceding block*)
					IF GetFlag(i-1, branchflag) THEN
						IF isCondBranch(code[i-1]) THEN block[nofblock-1].type := BlockD ELSE block[nofblock-1].type := BlockE END
					ELSIF GetFlag(i-2, branchflag) THEN
						IF i = last + 1 THEN
							block[nofblock-1].type := BlockF
						ELSIF isCondBranch(code[i-2]) THEN
							block[nofblock-1].type := BlockB
						ELSE
							block[nofblock-1].type := BlockC
						END
					ELSE
						block[nofblock-1].type := BlockA
					END
				END;
				blocknr[i] := nofblock;
				block[nofblock].begin := i; last := i;
				INC(nofblock)
			END;
			INC(i); 
			IF (i-last>=MaxBlockSize-3) & (~GetFlag(i,followlinkflag)) THEN SetFlag(i,labelflag) END (*split blocks that are too long*)
		END;
		block[nofblock].begin := codesize;
		block[nofblock-1].type := BlockB; (*the last block must end with an unconditional branch*)
		(*change all addresses into block numbers*)
		i := 0; WHILE i < nofentr DO entry[i] := blocknr[entry[i]]; INC(i) END;
		i := 0; WHILE i < nofref DO ref[i] := blocknr[ref[i]]; INC(i) END;
		i := 0;
		WHILE i < codesize DO (*change destinations of relative branches*)
			IF GetFlag(i, branchflag) & isRelBranch(code[i]) THEN
				destblock := blocknr[i+1+sImm(code[i])];
				SetImm(code[i], 2*destblock);
			END;
			INC(i)
		END;
		i := 0;
		WHILE i < nofblock DO
			IF block[i].type = BlockF THEN
				br := code[block[i].begin-1];
				IF isRelBranch(br) THEN
					destblock := sImm(br) DIV 2;
					MakeInstrRec(block[i].begin, instr);
					IF instr.delayed THEN
						RegSetUnion(block[destblock].beginstate.delayedset, instr.w)
					ELSIF isMFHI(instr.i) THEN
						block[destblock].beginstate.hiwait := 2
					ELSIF isMFLO(instr.i) THEN
						block[destblock].beginstate.lowait := 2
					END
				END
			END;
			INC(i)
		END
	END FindBlocks;
	
	PROCEDURE RedundantBranches;
		VAR i, index, dest, destindex, count: INTEGER; slot: LONGINT;
	BEGIN
		i := 0;
		WHILE i < nofblock DO
			index := block[i+1].begin - 2;
			IF (block[i].type IN {BlockB, BlockC}) & isRelBranch(code[index]) THEN
				count := 5; (*this count is to prevent infinite loops if the code contains a branch to itself*)
				dest := sImm(code[index]) DIV 2;
				destindex := block[dest].begin;
				IF isCondBranch(code[index]) THEN (*CondBranch -> SureRelBranch+ is redundant*)
					WHILE isSureRelBranch(code[destindex]) & (code[destindex+1] = NOP) & (count >= 0) DO
						dest := sImm(code[destindex]) DIV 2;
						destindex := block[dest].begin;
						DEC(count)
					END;
					SetImm(code[index], dest*2)
				ELSIF isSureRelBranch(code[index]) THEN (*SureRelBranch+ -> SureBranch is redundant*)
					slot := code[index+1];
					WHILE isSureRelBranch(code[destindex]) & (slot=NOP) & (count>=0) DO
						slot := code[destindex+1];
						dest := sImm(code[destindex]) DIV 2;
						destindex := block[dest].begin;
						DEC(count)
					END;
					WHILE isSureRelBranch(code[destindex]) & (code[destindex+1]=NOP) & (count>=0) DO
						dest := sImm(code[destindex]) DIV 2;
						destindex := block[dest].begin;
						DEC(count)
					END;
					IF isSureBranch(code[destindex]) & ((code[destindex+1]=NOP) OR (slot=NOP)) THEN
						code[index] := code[destindex];
						IF slot = NOP THEN code[index+1] := code[destindex+1] ELSE code[index+1] := slot END
					ELSE
						SetImm(code[index], dest*2);
						code[index+1] := slot
					END
				END
			END;
			INC(i)
		END
	END RedundantBranches;
	
	PROCEDURE FillLoadDelaySlots;
		VAR i: INTEGER;
		
		PROCEDURE SortBlock(blocknr: INTEGER);
			(*sort block blocknr*)
			(*respect block[blocknr].beginstate; respect or modify beginstate of succeeding blocks*)
			CONST W = 32; (*window size*)
				W2 = 2*W;
			TYPE
				Wset = SET;
				Warray = ARRAY W OF Wset;
				Parray = ARRAY W2 OF INTEGER;
				Iarray = ARRAY W2 OF InstrRec;
			VAR
				begin, end, b, b1, b2, newcodeaddr, i: INTEGER;
				cand: Wset; (*candidates from b+1..b+W (mod W) to become the next instruction*)
				bsucc: Wset; (*successors of b (mod W)*)
				succ: Warray; (*successors of b+1..b+W (twice mod W)*)
				preds: Parray; (*number of predecessors of b+1..b+W2 (mod W2)*)
				binstr: InstrRec;
				instr: Iarray; (*instructions b+1..b+64 (mod W2)*)
				newcode: ARRAY MaxBlockSize OF Instr;
				newflags: ARRAY MaxBlockSize OF Flag;
				state, statem1, statem2: State;
				
			PROCEDURE InclCand(i: INTEGER);
			BEGIN
				IF (i <= b) OR (i > b+W) THEN HALT(99) END;
				INCL(cand, i MOD W);
				(*IF  THEN
					Texts.WriteString(WR, "                    +");
					Texts.WriteInt(WR, i, 5); Texts.WriteLn(WR); Texts.Append(Oberon.Log, WR.buf)
				END*)
			END InclCand;
			
			PROCEDURE ExclCand(i: INTEGER);
			BEGIN
				IF (i <= b) OR (i > b+W) THEN HALT(99) END;
				EXCL(cand, i MOD W);
				(*IF  THEN
					Texts.WriteString(WR, "                    -");
					Texts.WriteInt(WR, i, 5); Texts.WriteLn(WR); Texts.Append(Oberon.Log, WR.buf)
				END*)
			END ExclCand;
			
			PROCEDURE WriteEdge(ch: CHAR; i, j: INTEGER);
			BEGIN
				IF (i < b) OR (i > b+W) OR (j <= i) OR (j > i+W) OR (j > b+W2) THEN HALT(99) END;
				(*IF  THEN
					Texts.Write(WR, ch);
					Texts.WriteInt(WR, i, 5); Texts.WriteInt(WR, j, 5); Texts.WriteLn(WR); Texts.Append(Oberon.Log, WR.buf)
				END*)
			END WriteEdge;
	
			PROCEDURE InitSort;
				VAR i, j, i1: INTEGER;
			BEGIN
				begin := block[blocknr].begin; end := block[blocknr+1].begin;
				b := begin; WHILE GetFlag(b, followlinkflag) DO INC(b) END (*case statement*);
				b1 := min(b+W+1, end); b2 := min(b1+W, end);
				i := 0; WHILE i < W2 DO preds[i] := 0; INC(i) END;
				i := 0; WHILE i < W DO succ[i] := {}; INC(i) END;
				i := b+1; WHILE i < b2 DO MakeInstrRec(i, instr[i MOD W2]); INC(i) END;
				MakeInstrRec(b, binstr); cand := {}; bsucc := {};
				
				i := b+1;
				WHILE i < b1 DO
					IF dependent(binstr, instr[i MOD W2]) THEN WriteEdge("+", b, i); INCL(bsucc, i MOD W); INC(preds[i MOD W2]) END;
					INC(i)
				END;
				
				i := b+1;
				WHILE i < b1 DO
					IF ~ instr[i MOD W2].nop THEN
						j := i+1; i1 := min(i+W+1, end);
						WHILE j < i1 DO
							IF dependent(instr[i MOD W2], instr[j MOD W2]) THEN
								WriteEdge("+", i, j); INCL(succ[i MOD W], j MOD W); INC(preds[j MOD W2])
							END;
							INC(j)
						END
					END;
					INC(i)
				END;
				
				i := b+1;
				WHILE i < b1 DO
					IF  (preds[i MOD W2] = 0) & ~ instr[i MOD W2].nop THEN InclCand(i) END;
					INC(i)
				END
			END InitSort;
			
			PROCEDURE EmitNop;
			BEGIN
				newcode[newcodeaddr] := NOP; newflags[newcodeaddr] := {}; INC(newcodeaddr);
				statem2 := statem1; statem1 := state;
				ClearRegSet(state.delayedset);
				IF state.hiwait > 0 THEN DEC(state.hiwait) END;
				IF state.lowait > 0 THEN DEC(state.lowait) END
			END EmitNop;
			
			PROCEDURE needsNop(VAR einstr: InstrRec; VAR state: State): BOOLEAN;
				(*must we emit a NOP before the instruction einstr?*)
			BEGIN
				RETURN (einstr.r1.g * state.delayedset.g + einstr.r1.f * state.delayedset.f + einstr.r1.s * state.delayedset.s # {}) OR
					(state.hiwait # 0) & (Shi IN einstr.w.s) OR (state.lowait # 0) & (Slo IN einstr.w.s)
			END needsNop;
				
			PROCEDURE EmitOne;
				VAR e: INTEGER;
				
				PROCEDURE Choose(VAR e: INTEGER); (*choose an instruction e from cand*)
					VAR
						curprio, maxprio, numsucc, maxsucc, mini, i, j, k, c, c1: INTEGER;
						csucc, rcand: Wset;
						candidate: ARRAY W+1 OF INTEGER;
				BEGIN
					(*selection criteria:
						1. an instruction which doesn't need a NOP before itself
						2. maximum priority (load > others)
						3. maximum number of successors
					*)
					rcand := {};
					i := b+1; WHILE i < b1 DO
						IF (i MOD W IN cand) & ~ needsNop(instr[i MOD W2], state) THEN INCL(rcand, i MOD W) END;
						INC(i)
					END;
					
					IF needsNop(binstr, state) & (rcand = {}) THEN (*all instructions need a NOP before themselves*)
						rcand := cand; candidate[0] := b; j := 1; maxprio := binstr.priority
					ELSE
						IF needsNop(binstr, state) THEN (*consider only the instructions from rcand, which is not empty*)
							j := 0; maxprio := -1
						ELSE (*consider b and rcand*)
							candidate[0] := b; j := 1; maxprio := binstr.priority
						END
					END;
					i := b+1;
					WHILE i < b1 DO
						IF i MOD W IN rcand THEN
							curprio := instr[i MOD W2].priority;
							IF curprio = maxprio THEN
								candidate[j] := i; INC(j)
							ELSIF curprio > maxprio THEN
								candidate[0] := i; j := 1; maxprio := curprio
							END
						END;
						INC(i)
					END;
					mini := 0;
					(*candidate[mini..j-1] contains all instructions with maximum priority*)
					IF j > 1 THEN
						(*count the successors of all candidates*)
							i := 0; maxsucc := -1;
							WHILE i < j DO
								(*count the successors of candidate[i]*)
									c := candidate[i]; csucc := succ[c MOD W]; numsucc := 0;
									k := c+1; c1 := min(c+W+1, b2);
									WHILE k < c1 DO
										IF (k MOD W IN csucc) & (preds[k MOD W2] = 1) THEN INC(numsucc) END;
										INC(k)
									END;
									IF numsucc < maxsucc THEN
										candidate[i] := Nil
									ELSIF numsucc > maxsucc THEN
										mini := i; maxsucc := numsucc
									END;
								INC(i)
							END
					END;
					(*candidate[mini..j-1] contains all instructions with maximum number of successors*)
					e := candidate[mini]
				END Choose;
				
				PROCEDURE Emit(e: INTEGER);
					(*emit as many NOPs as necessary, then emit code[e] and adjust the state*)
					(*if code[e] is a link, emit also the following words*)
					VAR einstr: InstrRec; i: INTEGER;
				BEGIN
					IF e = b THEN einstr := binstr ELSE einstr := instr[e MOD W2] END;
					WHILE needsNop(einstr, state) DO EmitNop END; (*insert one or two NOPs if necessary*)
					newcode[newcodeaddr] := code[e]; newflags[newcodeaddr] := flags[e]; INC(newcodeaddr);
					IF GetFlag(e, linkflag) THEN
						i := e+1;
						WHILE GetFlag(i, followlinkflag) DO
							newcode[newcodeaddr] := code[i]; newflags[newcodeaddr] := flags[i]; INC(newcodeaddr); INC(i)
						END
					END;
					statem2 := statem1; statem1 := state;
					IF einstr.delayed THEN state.delayedset := einstr.w ELSE ClearRegSet(state.delayedset) END;
					IF isMFHI(einstr.i) THEN state.hiwait := 2 ELSIF state.hiwait > 0 THEN DEC(state.hiwait) END;
					IF isMFLO(einstr.i) THEN state.lowait := 2 ELSIF state.lowait > 0 THEN DEC(state.lowait) END
				END Emit;
				
				PROCEDURE RemoveFromGraph(e: INTEGER);
				VAR j, e1: INTEGER;
					esucc, b1succ: Wset;
					incb: BOOLEAN;
					b1instr: InstrRec;
				
				BEGIN
					incb := e=b;
					IF incb THEN esucc := bsucc ELSE ExclCand(e); esucc := succ[e MOD W] END;
					(*remove all edges incident to e*)
						j := e+1; e1 := min(e+W+1, b2);
						WHILE j < e1 DO
							IF j MOD W IN esucc THEN
								WriteEdge("-", e, j);
								DEC(preds[j MOD W2]);
								IF (j < b1) & (preds[j MOD W2] = 0) & ~ instr[j MOD W2].nop THEN InclCand(j) END
							END;
							INC(j)
						END;
					(*set b to the next instruction not yet processed*)
						WHILE incb & (b < end) DO
							INC(b); bsucc := succ[b MOD W]; binstr := instr[b MOD W2];
							incb := ~ (b MOD W IN cand); (*code[b] is already emitted or is a nop*)
							IF b2 < end THEN (*increment b2*)
								MakeInstrRec(b2, instr[b2 MOD W2]);
								IF preds[b2 MOD W2] # 0 THEN HALT(99) END;
								INC(b2)
							END;
							IF b1 < end THEN (*increment b1*)
								(*find edges beginning at b1*)
									j := b1+1; b1succ := {}; b1instr := instr[b1 MOD W2];
									WHILE j < b2 DO
										IF dependent(b1instr, instr[j MOD W2]) THEN
											WriteEdge("+", b1, j); INCL(b1succ, j MOD W); INC(preds[j MOD W2]);
										END;
										INC(j)
									END;
									succ[b1 MOD W] := b1succ;
								(*add b1 to candidate set*)
									IF (preds[b1 MOD W2] = 0) & ~ instr[b1 MOD W2].nop THEN
										InclCand(b1)
									ELSE
										ExclCand(b1)
									END;
								INC(b1)
							END
						END
				END RemoveFromGraph;
				
			BEGIN (*EmitOne*)
				Choose(e);
				Emit(e);
				RemoveFromGraph(e)
			END EmitOne;
			
			PROCEDURE LastInstrOfBlock;
				VAR
					br, hi: Instr;
					hf: Flag;
					rec0, rec1, slotinstr, branchinstr: InstrRec;
					destblock: INTEGER;
					makenop: BOOLEAN;
			BEGIN
				(*all instructions (except possibly the final NOP) are in newcode[0..newcodeaddr-1]*)
				CASE block[blocknr].type OF
					BlockA: (*no branch at end; succeeding block may not yet be sorted*)
					StateUnion(block[blocknr+1].beginstate, state)
				| BlockD, BlockE: (*branch is last instruction; insert NOP before branch if necessary*)
					MakeInstrRec(end, rec0); (*instruction after branch*)
					IF (state.hiwait > 0) & (Shi IN rec0.w.s) OR (state.lowait > 0) & (Slo IN rec0.w.s) THEN
						(*insert NOP before branch*)
							newcode[newcodeaddr] := newcode[newcodeaddr-1];
							newflags[newcodeaddr] := newflags[newcodeaddr-1];
							newcode[newcodeaddr-1] := NOP; newflags[newcodeaddr-1] := {};
							INC(newcodeaddr); state.hiwait := 0; state.lowait := 0
					END
				| BlockF: (*one-instruction-block in delay slot of a branch*)
					IF newcodeaddr # 1 THEN HALT(92) END;
					IF block[blocknr-1].type = BlockD THEN (*conditional branch*)
						StateUnion(block[blocknr+1].beginstate, state)
					END;
					(*beginstate of branch destination has already been set in FindBlocks*)
				| BlockB, BlockC: (*the block ends with a branch and an instruction in its delay slot*)
					(* There are three possibilities:
							a: the branch is at newcodeaddr-1 -> Fill the delay slot.
							b: the branch is at newcodeaddr-2 -> There is something in the delay slot. Make the transition to the next block.
							c: the branch is at newcodeaddr-3 ->
								c1: There is a load global from a case statement after the branch
								c2: There is a MFLO... before the branch and a NOP between the branch and a DIV... - Exchange branch and NOP.
					*)
					IF (newcodeaddr >= 2) & ~ (branchflag IN newflags[newcodeaddr-1]) THEN
						(*there is already an instruction in the delay slot of the branch*)
						IF branchflag IN newflags[newcodeaddr-2] THEN (*one word instruction in delay slot*) (*b*)
							br := newcode[newcodeaddr-2];
							IF isRelBranch(br) THEN
								destblock := sImm(br) DIV 2;
								MakeInstrRec2(newcode[newcodeaddr-1], slotinstr);
								MakeInstrRec(block[destblock].begin, rec0);
								MakeInstrRec(block[destblock].begin+1, rec1);
								IF needsNop(rec0, state) OR
									(state.hiwait=2) & (Shi IN rec1.w.s) OR (state.lowait=2) & (Slo IN rec1.w.s) THEN
									(*move slot instruction before branch; put NOP into delay slot and maybe before the slot instruction*)
										IF needsNop(slotinstr, statem2) THEN
											newcode[newcodeaddr] := newcode[newcodeaddr-2]; (*branch*)
											newflags[newcodeaddr] := newflags[newcodeaddr-2];
											newcode[newcodeaddr+1] := NOP; newflags[newcodeaddr+1] := {};
											newcode[newcodeaddr-2] := NOP; newflags[newcodeaddr-2] := {}; INC(newcodeaddr, 2)
										ELSE
											hi := newcode[newcodeaddr-1]; hf := newflags[newcodeaddr-1]; (*slot instruction*)
											newcode[newcodeaddr-1] := newcode[newcodeaddr-2]; (*branch*)
											newflags[newcodeaddr-1] := newflags[newcodeaddr-2];
											newcode[newcodeaddr-2] := hi; newflags[newcodeaddr-2] := hf; (*slot instruction*)
											newcode[newcodeaddr] := NOP; newflags[newcodeaddr] := {}; INC(newcodeaddr)
										END; 
										ClearRegSet(state.delayedset); state.hiwait := 0; state.lowait := 0;
								ELSE
									StateUnion(block[destblock].beginstate, state)
								END
							END
						ELSIF branchflag IN newflags[newcodeaddr-3] THEN (*c*)
							IF linkflag IN newflags[newcodeaddr-2] THEN (*c1*)
								 (*load/store global, more than one word in delay slot (case statement)*)
							ELSIF newcode[newcodeaddr-2] = NOP THEN (*c2*)
								(*exchange branch and NOP*)
								hi := newcode[newcodeaddr-2]; hf := newflags[newcodeaddr-2];
								newcode[newcodeaddr-2] := newcode[newcodeaddr-3]; (*branch*)
								newflags[newcodeaddr-2] := newflags[newcodeaddr-3];
								newcode[newcodeaddr-3] := hi; newflags[newcodeaddr-3] := hf; (*nop*)
							ELSE HALT(98)
							END
						ELSE HALT(99)
						END
					ELSE (*there is not yet an instruction in the delay slot of the branch*) (*a*)
						IF (newcodeaddr < 2) OR (followlinkflag IN newflags[newcodeaddr-2]) THEN makenop := TRUE
						ELSE
							MakeInstrRec2(newcode[newcodeaddr-2], slotinstr);
							MakeInstrRec2(newcode[newcodeaddr-1], branchinstr);
							EXCL(branchinstr.w.s, Somega);
							makenop := dependent(slotinstr, branchinstr) OR slotinstr.delayed OR
								isMFHI(slotinstr.i) OR isMFLO(slotinstr.i) OR needsNop(branchinstr, statem2)
						END;
						IF makenop THEN
							EmitNop
						ELSE (*exchange branch and instruction before it*)
							hi := newcode[newcodeaddr-1]; hf := newflags[newcodeaddr-1];
							newcode[newcodeaddr-1] := newcode[newcodeaddr-2];
							newflags[newcodeaddr-1] := newflags[newcodeaddr-2];
							newcode[newcodeaddr-2] := hi; newflags[newcodeaddr-2] := hf
						END;
						br := newcode[newcodeaddr-2];
						IF isRelBranch(br) THEN
							destblock := sImm(br) DIV 2;
							StateUnion(block[destblock].beginstate, state)
						END
					END;
					IF block[blocknr].type = BlockB THEN StateUnion(block[blocknr+1].beginstate, state) END
				END(*CASE*)
			END LastInstrOfBlock;
			
		BEGIN (*SortBlock*)
			state := block[blocknr].beginstate;
			InitSort;
			newcodeaddr := 0;
			WHILE b < end DO EmitOne END;
			LastInstrOfBlock;
			ChangeBlockSize(blocknr, newcodeaddr - (end - begin));
			i := newcodeaddr; WHILE i > 0 DO DEC(i); code[begin+i] := newcode[i]; flags[begin+i] := newflags[i] END
		END SortBlock;
			
	BEGIN (*FillLoadDelaySlots*)
		i := 0;
		WHILE i < nofblock DO
			SortBlock(i);
			INC(i)
		END
	END FillLoadDelaySlots;
	
	PROCEDURE FillBranchDelaySlots;
		VAR i, index, destindex: INTEGER;
			br: Instr;
			instr: InstrRec;
			
		PROCEDURE possible(candindex, otherindex: INTEGER): BOOLEAN;
			(*is it possible to execute the instruction cand before those at otherindex without side effects?*)
			VAR candrec, otherrec: InstrRec;
		BEGIN
			IF GetFlag(candindex, linkflag) THEN RETURN FALSE END;
			MakeInstrRec(candindex, candrec);
			IF Smem IN candrec.r.s THEN RETURN FALSE END; (* We may not execute a read from memory instruction because it could
				be a nil reference. *)
			IF candrec.w.s * {Smem, Somega} # {} THEN RETURN FALSE END;
			IF (uOp(candrec.i) = SPECIAL) & (uFunct(candrec.i) DIV 8 = 3) THEN RETURN FALSE END; (*MULT, DIV*)
			IF (candrec.i DIV T25 = COP2*2 + 1) & (candrec.i MOD 32 <= 4) THEN RETURN FALSE END; (*some COP2 instructions*)
			IF isMFLO(candrec.i) OR isMFHI(candrec.i) THEN RETURN FALSE END;
			LOOP
				MakeInstrRec(otherindex, otherrec);
				IF otherrec.r.g * candrec.w.g + otherrec.r.f * candrec.w.f + otherrec.r.s * candrec.w.s # {} THEN
					RETURN FALSE (*other instruction reads from the registers that cand writes*)
				END;
				IF (candrec.w.g - otherrec.w.g) + (candrec.w.f - otherrec.w.f) + (candrec.w.s - otherrec.w.s) = {} THEN
					RETURN TRUE (*other instruction writes to the registers that cand writes*)
				END;
				IF Somega IN otherrec.w.s THEN RETURN FALSE (*end of the block*) END;
				INC(otherindex)
			END
		END possible;
		
	BEGIN (*FillBranchDelaySlots*)
		(* three cases:
			1. branch to a NOP
			2. unconditional branch with a NOP in the delay slot
			3. conditional branch with a NOP in the delay slot
		*)
		i := 0;
		WHILE i < nofblock DO (*check branch at end of every block*)
			index := block[i+1].begin - 2;
			IF (block[i].type IN {BlockB, BlockC}) & isRelBranch(code[index]) THEN
				(*delay slot is in the same block and it is neither a J nor a JR*)
				br := code[index];
				destindex := block[sImm(br) DIV 2].begin;
				IF (code[destindex] = NOP) THEN (*case 1: branch to a NOP*)
					MakeInstrRec(index+1, instr); (*instruction in the delay slot of the branch*)
					IF ~ instr.delayed & ~ isMFHI(instr.i) & ~ isMFLO(instr.i) THEN
						INC(destindex); INC(code[index])
					END
				ELSIF code[index+1] = NOP THEN (*there is a NOP in the delay slot*)
					IF ~ isCondBranch(br) THEN (*case 2: unconditional branch*)
						IF ~ GetFlag(destindex, branchflag) & ~ GetFlag(destindex, linkflag) THEN
							code[index+1] := code[destindex];
							INC(code[index])
						END
					ELSE (*case 3: conditional branch, this is the interesting case*)
						IF destindex < index THEN (*backward branch; try first to optimize the loop*)
							IF ~ ODD(sImm(br)) & possible(destindex, index+2) THEN (*branch destination*)
								code[index+1] := code[destindex]; INC(code[index])
							ELSIF possible(index+2, destindex) THEN (*following instruction*)
								ChangeBlockSize(i, -1)
							END
						ELSE (*forward branch*)
							IF possible(index+2, destindex) THEN (*following instruction*)
								ChangeBlockSize(i, -1)
							ELSIF ~ ODD(sImm(br)) & possible(destindex, index+2) THEN (*branch destination*)
								code[index+1] := code[destindex]; INC(code[index])
							END
						END (*forward branch*)
					END (*conditional branch*)
				END (*NOP in delay slot*)
			END (*BlockB, BlockC*);
			INC(i)
		END (*WHILE*)
	END FillBranchDelaySlots;

	PROCEDURE FindRealAddresses;
		VAR i, h: INTEGER;
	BEGIN
		i := 0; WHILE i < nofentr DO entry[i] := block[entry[i]].begin; INC(i) END;
		i := 0; WHILE i < nofref DO ref[i] := block[ref[i]].begin; INC(i) END;
		i := 0;
		WHILE i < codesize DO
			IF GetFlag(i, branchflag) & isRelBranch(code[i]) THEN
				h := block[sImm(code[i]) DIV 2].begin + sImm(code[i]) MOD 2 - (i+1);
				SetImm(code[i], h)
			END;
			INC(i)
		END
	END FindRealAddresses;

	PROCEDURE WriteFile(filename: Files.FileName; VAR R: Files.Rider);
		VAR
			f: Files.File;
			WF: Files.Rider;
			i: INTEGER;
			nofnm, nofp, k, pos: LONGINT;
			name: ARRAY 32 OF CHAR;
			ch: CHAR;
			
		PROCEDURE CNum;
			VAR x: CHAR;
		BEGIN
			REPEAT
				Files.Read(R, x);
				Files.Write(WF, x)
			UNTIL ORD(x) < 128
		END CNum;
		
		PROCEDURE SNum;
			VAR k: LONGINT;
		BEGIN Files.ReadNum(R, k)
		END SNum;

		PROCEDURE Skip(n: LONGINT);
		BEGIN
			Files.Set(R, Files.Base(R), Files.Pos(R)+n)
		END Skip;
		
		PROCEDURE Copy(n: LONGINT);
			CONST bufsize = 2048;
			VAR buffer: ARRAY bufsize OF CHAR; i: LONGINT;
		BEGIN
			WHILE n > 0 DO
				IF n > bufsize THEN i := bufsize ELSE i := n END ;
				Files.ReadBytes(R, buffer, i);
				Files.WriteBytes(WF, buffer, i);
				DEC(n, i)
			END
		END Copy;
		
		PROCEDURE CopyName;
			VAR ch: CHAR;
		BEGIN
			REPEAT Files.Read(R, ch); Files.Write(WF, ch) UNTIL ch = 0X
		END CopyName;
		
		PROCEDURE Link(i: INTEGER);
			(*put code[i] at head of link chain*)
			VAR index: INTEGER;
		BEGIN
			index := sImm(code[i]);
			IF link[index] = Nil THEN
				SetImm(code[i], -1)
			ELSE
				SetImm(code[i], link[index] - (i+1))
			END;
			link[index] := i
		END Link;
		
	BEGIN (*WriteFile*)
		i := codesize - 1;
		WHILE i >= 0 DO
			IF GetFlag(i, linkflag) THEN
				Link(i);
				IF GetFlag(i+1, followlinkflag) & GetFlag(i+2, followlinkflag) THEN (*8 bytes access*)
					Link(i+1)
				END
			END;
			DEC(i)
		END;
		f := Files.New(filename);
		Files.Set(WF, f, 0);
		Copy(14); (*OFtag2, refsize4 to be patched later, nofexp2, noftdesc2,  nofcom2,  nofptr2*)
		CNum; noflink := 4; nofentr := 0;
		SNum; SNum; SNum; SNum;
		Files.WriteNum(WF, link[0]); Files.WriteNum(WF, link[1]);
		Files.WriteNum(WF, link[2]); Files.WriteNum(WF, link[3]);
		SNum; SNum; Files.ReadNum(R, oldcodesize);
		Files.WriteNum(WF, datasize); Files.WriteNum(WF, consize); Files.WriteNum(WF, codesize);
		CopyName;
	(* ImpBlk *)
		Copy(1); i := 0;
		WHILE i < nofimp DO CopyName; INC(i) END ;
	(* ExpBlk *)
		Copy(1); Files.Read(R, ch); Files.Write(WF, ch);
		WHILE ch # 0X DO
			IF ch = 8X THEN
				Files.ReadString(R, name); Files.WriteString(WF, name);
				IF name = "" THEN CNum END ;
				SNum; Files.WriteNum(WF, link[noflink]); INC(noflink); CNum; Files.ReadNum(R, k); Files.WriteNum(WF, k);
				IF k >= 0 THEN Files.ReadString(R, name); Files.WriteString(WF, name);
					IF name = "" THEN CNum END
				END ;
				CNum; CNum;
				Files.ReadNum(R, nofnm); Files.ReadNum(R, nofp);
				Files.WriteNum(WF, nofnm); Files.WriteNum(WF, nofp);
				i := 0;
				WHILE i < nofnm DO CNum;
					SNum; Files.WriteNum(WF, entry[nofentr]); INC(nofentr); INC(i)
				END ;
				i := 0;
				WHILE i < nofp DO CNum; INC(i) END
			ELSIF ch = 9X THEN
				SNum; Files.WriteNum(WF, entry[nofentr]); INC(nofentr);
				SNum; Files.WriteNum(WF, link[noflink]); INC(noflink)
			ELSE
				CopyName; CNum;
				IF ch = 3X THEN CNum
				ELSIF ch = 4X THEN SNum; Files.WriteNum(WF, entry[nofentr]); INC(nofentr)
				ELSIF ch = 6X THEN CNum
				END
			END ;
			Files.Read(R, ch); Files.Write(WF, ch)
		END ;
	(* CmdBlk *)
		Copy(1); i := 0;
		WHILE i < nofcom DO
			CopyName; SNum; Files.WriteNum(WF, entry[nofentr]); INC(nofentr); INC(i)
		END ;
	(* PtrBlk *)
		Copy(1); i := 0;
		WHILE i < nofptr DO CNum; INC(i) END ;
	(* ConstBlk *)
		Copy(1+consize+1);
	(* CodeBlk *)
		Skip(4*oldcodesize);
		i := 0;
		WHILE i < codesize DO Files.WriteLInt(WF, code[i]); INC(i) END;
	(* UseBlk *)
		Copy(1); i := 0;
		WHILE i < nofimp DO
			Files.Read(R, ch); Files.Write(WF, ch);
			WHILE ch # 0X DO
				Files.ReadString(R, name); Files.WriteString(WF, name); Files.ReadNum(R, k);
				CASE ch OF
				| 1X, 2X, 5X, 6X, 7X: Files.WriteNum(WF, k)
				| 3X, 4X: Files.WriteNum(WF, k); SNum; Files.WriteNum(WF, link[noflink]); INC(noflink)
				| 8X: IF name = "" THEN Files.WriteNum(WF, k); SNum END ;
						Files.WriteNum(WF, link[noflink]); INC(noflink)
				END ;
				Files.Read(R, ch); Files.Write(WF, ch)
			END ;
			INC(i)
		END ;
	(* RefBlk *)
		Copy(1); i := 0; pos := Files.Pos(WF);
		Files.Read(R, ch);
		WHILE i < nofref DO
			Files.Write(WF, ch); (*0F8X*)
			SNum; Files.WriteNum(WF, ref[i]); CNum; CNum; CNum; CNum; CopyName;
			Files.Read(R, ch);
			WHILE (ch # 0F8X) & ~ R.eof DO Files.Write(WF, ch); Copy(1); CNum; CopyName; Files.Read(R, ch) END;
			INC(i)
		END;
	(* correct refsize *)
		pos := Files.Pos(WF) - pos;
		Files.Set(WF, f, 2);
		Files.WriteLInt(WF, pos);
		Files.Register(f)
	END WriteFile;

PROCEDURE OptimizeMod( filename: Files.FileName);
VAR	i: LONGINT;
		ok: BOOLEAN; c: CHAR;
		oldRider: Files.Rider; 
		name: Files.FileName;
BEGIN
	IF filename="" THEN RETURN END;
	name:=prefix;
	name[6]:="/";
	i:=0;
	REPEAT
		c:=filename[i];
		name[i+7]:= c;
		INC(i);
	UNTIL c=0X;
	IF name[i+5]#"j" THEN RETURN END;	(* *.Sym file *)
	ReadFile(name, ok, oldRider);
	Texts.WriteString(WR, name); Texts.WriteString(WR, " optimizing"); Texts.Append(Oberon.Log, WR.buf);
	IF ~ok THEN RETURN END;
	FindBlocks;
	RedundantBranches;
(*	FillLoadDelaySlots;*)
	FillBranchDelaySlots;
	FindRealAddresses;
	WriteFile(name, oldRider);
	Texts.WriteInt(WR, ((oldcodesize-codesize)*100 + codesize DIV 2) DIV oldcodesize, 5); Texts.Write(WR, "%");
	Texts.WriteLn(WR); Texts.Append(Oberon.Log, WR.buf)
END OptimizeMod;
			
	PROCEDURE Optimize*;
		VAR
			filename: Files.FileName;
	BEGIN
		Texts.OpenScanner(Par, Oberon.Par.text, Oberon.Par.pos);
		LOOP
			GetFilename(filename);
			IF filename[0] = 0X THEN EXIT END;
			OptimizeMod( filename);
		END
	END Optimize;

PROCEDURE OptimizeAll*;
VAR res, size: LONGINT;
	i, dir, rbytes: LONGINT;
	buf: ARRAY 128000 OF CHAR;
	de: DirEntP;
BEGIN
	dir:=Kernel.Open0(SYSTEM.ADR(prefix), Kernel.RDonly, 0);
	rbytes:= Kernel.GetDents0( dir, SYSTEM.ADR( buf), LEN( buf));
	IF rbytes<=0 THEN rbytes:=-rbytes; Kernel.WriteString(" error "); END;
	res:=Kernel.Close0( dir);
	i:=0; 
	de:=SYSTEM.VAL( DirEntP, SYSTEM.ADR( buf[ i]));
	WHILE (i<rbytes)  DO
		OptimizeMod(de.dname);
		INC(i,LONG(de.dreclen));
		de:=SYSTEM.VAL( DirEntP, SYSTEM.ADR( buf[ i]));
	END;
END OptimizeAll;
	
(*	PROCEDURE OptPartial*;
		VAR
			filename: Filename;
			ok: BOOLEAN;
			oldRider: Files.Rider;
		
	BEGIN
		Texts.OpenScanner(Par, Oberon.Par.text, Oberon.Par.pos);
		GetFilename(filename);
		ReadFile(filename, ok, oldRider);
		IF ~ok THEN RETURN END;
		Texts.WriteString(WR, filename); Texts.WriteString(WR, " optimizing"); Texts.Append(Oberon.Log, WR.buf);
		IF BooleanPar() THEN
			Texts.WriteString(WR, " FB");
			FindBlocks;
			IF BooleanPar() THEN Texts.WriteString(WR, " RB"); RedundantBranches END;
			IF BooleanPar() THEN Texts.WriteString(WR, " FLDS"); FillLoadDelaySlots END;
			IF BooleanPar() THEN Texts.WriteString(WR, " FBDS"); FillBranchDelaySlots END;
			FindRealAddresses
		END;
		WriteFile(filename, oldRider);
		Texts.WriteInt(WR, ((oldcodesize-codesize)*100 + codesize DIV 2) DIV oldcodesize, 5); Texts.Write(WR, "%");
		Texts.WriteLn(WR); Texts.Append(Oberon.Log, WR.buf)
	END OptPartial; *)

BEGIN
	Texts.OpenWriter(WR)
END MPeephole.OptimizeAll
