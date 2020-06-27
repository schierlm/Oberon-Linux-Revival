MODULE VDecoder;	(* rc 20.11.89 / 5.5.93 *)	(* object model 4.12.93 *)

(* peter matthias

		2015-04-08	using "arm6/" directory; added BNEL, BEQL, BLEZL, BGTZL instructions
		2015-08-14	added MkLabels, made Decode single pass
		2015-10-04	merged with test decoder, renamed Obj to Oba and Obm
		2015-10-10	using dir prefix, and .Obj extension
		2016-05-08	started RISC-V decoder todo: RV32F, RV32D, test
		2016-09-05	added FMV.X.S

*)

	IMPORT Texts, Oberon, Viewers, MenuViewers, TextFrames, Files, Fonts, SYSTEM;
	
	CONST
		OptionChar = "\";
		Taga=36FAH;
		Tagm=36F9H;
		Tagv=36FDH;
		ObjExt = ".Obj";
		BinExt = ".Bin";
		DecExt = ".Dec";
				
		(* structure forms *)
		Undef = 0; Byte = 1; Bool = 2; Char = 3; SInt = 4; Int = 5; LInt = 6;
		Real = 7; LReal = 8; Set = 9; String = 10; NilTyp = 11; NoTyp = 12;
		Pointer = 13; ProcTyp = 14; Comp = 15;

		nlen = 64;
		CodeLength = 32000;

		RA=1; T0=7;	(* temp reg *)
		B32=8;
		IMM8=100H; IMM12 = 1000H; IMM13 = 2000H; IMM14=4000H; IMM15=8000H; IMM16=10000H; IMM20=100000H; IMM24=1000000; 
		SB=23H; LB=3H; LUI=37H; ADDI= 13H; JALR=67H; JAL=6FH;
		FLW=2007H; FSW= 2027H; 
		FLD=3007H; FSD= 3027H;

		LADDI=28H;
		XTRAP=702BH;

	TYPE
		Name = ARRAY nlen OF CHAR;
		
	VAR
		W: Texts.Writer;
		T: Texts.Text;
		R: Files.Rider;
		codepos, codesize: LONGINT;
		pc, nextLabel, noflink: INTEGER;
		showref: BOOLEAN;
		code: ARRAY CodeLength OF LONGINT;
		label: ARRAY CodeLength OF INTEGER;
		proc: ARRAY 500 OF Name;
		datalinks: ARRAY 1000 OF LONGINT;
		fileTag: LONGINT;
		dir: Name;

PROCEDURE GetSimm(i: LONGINT): LONGINT;	(* in byte *)
BEGIN
	RETURN ASH( ASH(i, -25), 5)+ ASH(i , -7) MOD 20H;
END GetSimm;

PROCEDURE SetSimm( imm: LONGINT): LONGINT;
BEGIN	(* imm in byte *)
	RETURN ASH(ASH( imm, -5), 25)+ ASH( imm MOD 20H, 7);
END SetSimm;

		
	PROCEDURE WriteHex(i: LONGINT; n: INTEGER);
		VAR a: ARRAY 8 OF CHAR; j, dig: INTEGER;
	BEGIN j := 0;
		 WHILE j < 8  DO
			dig := SHORT(i MOD 16); i := i DIV 16;
			IF dig > 9 THEN INC(dig, ORD("A") - ORD("9") - 1) END ;
			a[j] := CHR(dig + ORD("0")); INC(j)
		END ;
		WHILE n > 0 DO DEC(n); Texts.Write(W, a[n]) END
	END WriteHex;
		
	PROCEDURE WriteSet(i: LONGINT);
		VAR j: SHORTINT;
	BEGIN
		j := 0;
		WHILE i#0 DO
			IF ODD(i) THEN Texts.WriteInt(W, j, 0); Texts.Write(W, " ") END;
			i:=i DIV 2 MOD 80000000H;
			INC(j)
		END
	END WriteSet;

	PROCEDURE Block(tag: CHAR; bn: ARRAY OF CHAR);
		VAR ch: CHAR;
	BEGIN
		Texts.WriteLn(W); Texts.Append(T, W.buf);
		Files.Read(R, ch); IF ch # tag THEN HALT(96) END ;
		Texts.WriteString(W, bn); Texts.WriteString(W, "   (pos ");
		Texts.WriteInt(W, Files.Pos(R), 0); Texts.Write(W, ")"); Texts.WriteLn(W)
	END Block;

	PROCEDURE ReadIn;
		VAR fprint, refsize, datasize, lastEnd, procpc, saver, savef, fsize, carea, k, nofmod: LONGINT;
			newreclink, newsyslink, newarrlink, datalink, consize, nofnewmeth, noflocptr: LONGINT;
			nofexp, nofdesc, nofcom, nofptr, i, j: INTEGER;
			modname, name: Name;
			mods: ARRAY 32 OF Name;
			ch: CHAR;		
	BEGIN
	(* HeaderBlk *)
		Files.ReadLInt(R, refsize); Files.ReadInt(R, nofexp); Files.ReadInt(R, nofdesc); Files.ReadInt(R, nofcom);
		Files.ReadInt(R, nofptr); Files.ReadNum(R, nofmod); Files.ReadNum(R, newreclink); Files.ReadNum(R, newsyslink);
		Files.ReadNum(R, newarrlink); Files.ReadNum(R, datalink); Files.ReadNum(R, datasize); Files.ReadNum(R, consize);
		Files.ReadNum(R, codesize); Files.ReadString(R, modname);
		Texts.WriteString(W, modname); Texts.WriteLn(W); Texts.WriteLn(W);
		Texts.WriteString(W, "code size  : "); Texts.WriteInt(W, 4*codesize, 0); Texts.WriteLn(W);
		Texts.WriteString(W, "data size  : "); Texts.WriteInt(W, datasize, 0); Texts.WriteLn(W);
		Texts.WriteString(W, "const size : "); Texts.WriteInt(W, consize, 0); Texts.WriteLn(W);
		Texts.WriteString(W, "newrec link: "); WriteHex(4*newreclink, 5); Texts.WriteLn(W);
		Texts.WriteString(W, "newsys link: "); WriteHex(4*newsyslink, 5); Texts.WriteLn(W);
		Texts.WriteString(W, "newarr link: "); WriteHex(4*newarrlink, 5); Texts.WriteLn(W);
		Texts.WriteString(W, "data link  : "); WriteHex(4*datalink, 5); Texts.WriteLn(W); datalinks[0] := datalink; noflink := 1;
	(* ImpBlk *)
		Block(81X, "imports:"); i := 0;
		WHILE i < nofmod DO INC(i); Files.ReadString(R, mods[i]); Texts.WriteString(W, mods[i]); Texts.WriteLn(W) END ;
	(* ExpBlk *)
		Block(82X, "exports:"); Files.Read(R, ch);
		WHILE ch # 0X DO
			IF ch # 9X THEN Files.ReadString(R, name); Files.ReadNum(R, fprint);
				CASE ch OF
				| 1X: Texts.WriteString(W, "Const  "); Texts.WriteString(W, name); Texts.Write(W, " "); WriteHex(fprint, 8)
				| 2X: Texts.WriteString(W, "Type   "); Texts.WriteString(W, name); Texts.Write(W, " "); WriteHex(fprint, 8)
				| 3X: Texts.WriteString(W, "Var    "); Texts.WriteString(W, name); Texts.Write(W, " "); WriteHex(fprint, 8);
							Files.ReadNum(R, k); Texts.WriteString(W, " offset="); Texts.WriteInt(W, k, 0)
				| 4X: Texts.WriteString(W, "Proc   "); Texts.WriteString(W, name); Texts.Write(W, " "); WriteHex(fprint, 8);
							Files.ReadNum(R, k); Texts.WriteString(W, " entry="); WriteHex(4*k, 5)
				| 5X: Texts.WriteString(W, "CProc  "); Texts.WriteString(W, name); Texts.Write(W, " "); WriteHex(fprint, 8)
				| 6X: Texts.WriteString(W, "Struct "); Texts.WriteString(W, name); Texts.WriteString(W, " pbfp="); WriteHex(fprint, 8);
							Files.ReadNum(R, fprint); Texts.WriteString(W, " pvfp="); WriteHex(fprint, 8)
				| 8X: Texts.WriteString(W, "TDesc ");
							IF name = "" THEN Texts.WriteString(W, "'anonymous'  pvfp="); WriteHex(fprint, 8); Files.ReadNum(R, k)
							ELSE Texts.WriteString(W, name); k := fprint
							END ;
							Texts.WriteString(W, " link="); WriteHex(4*k, 5); datalinks[noflink] := k; INC(noflink);
							Texts.WriteLn(W); Texts.Append(T, W.buf);
							Files.ReadNum(R, k); Texts.WriteString(W, "  recsize="); Texts.WriteInt(W, k, 0); Files.ReadNum(R, k);
							IF k # -1 THEN Texts.WriteString(W, " (");
								Texts.WriteString(W, mods[k]); Texts.Write(W, "."); Files.ReadString(R, name);
								IF name = "" THEN Texts.WriteString(W, "'anonymous'  pvfp="); Files.ReadNum(R, k); WriteHex(k, 8)
								ELSE Texts.WriteString(W, name)
								END ;
								Texts.WriteString(W, ") ")
							END ;
							Files.ReadNum(R, k); Texts.WriteString(W, " nofmeth="); Texts.WriteInt(W, k, 0);
							Files.ReadNum(R, k); Texts.WriteString(W, " nofinhmeth="); Texts.WriteInt(W, k, 0);
							Files.ReadNum(R, nofnewmeth); Texts.WriteString(W, " nofnewmeth="); Texts.WriteInt(W, nofnewmeth, 0);
							Files.ReadNum(R, noflocptr); Texts.WriteString(W, " nofptr="); Texts.WriteInt(W, noflocptr, 0);
							WHILE nofnewmeth > 0 DO
								Texts.WriteLn(W); DEC(nofnewmeth);
 								Files.ReadNum(R, k); Texts.WriteString(W, "    mthno="); Texts.WriteInt(W, k, 0);
								Files.ReadNum(R, k); Texts.WriteString(W, " entry="); WriteHex(4*k, 5)
							END ;
							WHILE noflocptr > 0 DO
								Texts.WriteLn(W); DEC(noflocptr);
								Files.ReadNum(R, k); Texts.WriteString(W, "    ptroff="); Texts.WriteInt(W, k, 0);
							END
				END
			ELSE
				Texts.WriteString(W, "LinkProc "); Files.ReadNum(R, k); Texts.WriteString(W, "entry="); WriteHex(4*k, 5);
				Files.ReadNum(R, k); Texts.WriteString(W, " link="); WriteHex(4*k, 5)
			END ;
			Texts.WriteLn(W); Texts.Append(T, W.buf); Files.Read(R, ch)
		END ;
	(* CmdBlk *)
		Block(83X, "commands:"); i := 0;
		WHILE i < nofcom DO
			Files.ReadString(R, name); Files.ReadNum(R, k);
			Texts.WriteString(W, name); Texts.WriteString(W, "  "); WriteHex(4*k, 5); Texts.WriteLn(W); INC(i)
		END ;
	(* PtrBlk *)
		Block(84X, "pointers:"); i := 0;
		WHILE i < nofptr DO
			Files.ReadNum(R, k); Texts.WriteInt(W, k, 0); Texts.WriteLn(W); INC(i)
		END ;
	(* ConstBlk *)
		Block(87X, "constants:"); i := 0; j := 0;
		WHILE i < consize DO
			WriteHex(i, 4); Texts.WriteString(W, ":  "); j := 0;
			WHILE (i < consize) & (j < 8) DO
				Files.Read(R, ch); WriteHex(ORD(ch), 2); Texts.WriteString(W, "  "); INC(i); INC(j)
			END ;
			Texts.WriteLn(W)
		END ;
	(* CodeBlk *)
		Files.Read(R, ch); IF ch # 88X THEN HALT(97) END ;
		codepos := Files.Pos(R);
		i := 0;
		WHILE i < codesize DO Files.ReadLInt(R, code[i]); INC(i) END ;
	(* UseBlk *)
		Block(89X, "uses:"); i := 0;
		WHILE i < nofmod DO
			INC(i); Texts.WriteString(W, "from "); Texts.WriteString(W, mods[i]); Texts.Write(W, ":"); Texts.WriteLn(W);
			Files.Read(R, ch);
			WHILE ch # 0X DO Files.ReadString(R, name); Files.ReadNum(R, fprint);
				CASE ch OF
				| 1X: Texts.WriteString(W, "  Const     "); Texts.WriteString(W, name); Texts.WriteString(W, "  "); WriteHex(fprint, 8)
				| 2X: Texts.WriteString(W, "  Type      "); Texts.WriteString(W, name); Texts.WriteString(W, "  "); WriteHex(fprint, 8)
				| 3X: Texts.WriteString(W, "  Var       "); Texts.WriteString(W, name); Texts.WriteString(W, "  "); WriteHex(fprint, 8);
							Files.ReadNum(R, k); Texts.WriteString(W, " link="); WriteHex(4*k, 5); datalinks[noflink] := k; INC(noflink);
				| 4X: Texts.WriteString(W, "  Proc      "); Texts.WriteString(W, name); Texts.WriteString(W, "  "); WriteHex(fprint, 8);
							Files.ReadNum(R, k); Texts.WriteString(W, " link="); WriteHex(4*k, 5)
				| 5X: Texts.WriteString(W, "  CProc     "); Texts.WriteString(W, name); Texts.WriteString(W, "  "); WriteHex(fprint, 8)
				| 6X: Texts.WriteString(W, "  pbStruct  "); Texts.WriteString(W, name); Texts.WriteString(W, "  "); WriteHex(fprint, 8)
				| 7X: Texts.WriteString(W, "  pvStruct  "); Texts.WriteString(W, name); Texts.WriteString(W, "  "); WriteHex(fprint, 8)
				| 8X: Texts.WriteString(W, "  LinkTDesc ");
							IF name = "" THEN Texts.WriteString(W, "'anonymous'  pvfp="); WriteHex(fprint, 8); Files.ReadNum(R, k)
							ELSE Texts.WriteString(W, name); k := fprint
							END ;
							Texts.WriteString(W, " link="); WriteHex(4*k, 5); datalinks[noflink] := k; INC(noflink)
				END ;
				Texts.WriteLn(W); Files.Read(R, ch)
			END
		END ;
	(* RefBlk *)
		i := 0; WHILE i < codesize DO label[i] := 0; INC(i) END ;
		nextLabel := 0; lastEnd := 0;
		IF showref THEN
			Block(8AX, "refs:");
			Files.Read(R, ch);
			WHILE ~R.eof DO
				IF ch # 0F8X THEN HALT(99) END ;
				procpc := 4*lastEnd;
				label[lastEnd] := -nextLabel-1; Files.ReadNum(R, lastEnd);
				Files.ReadNum(R, saver); Files.ReadNum(R, savef); Files.ReadNum(R, fsize); Files.ReadNum(R, carea);
				Files.ReadString(R, name); i := 0;
				Texts.WriteString(W, name); Texts.WriteString(W, "  pc=");
				WriteHex(procpc, 5); Texts.WriteLn(W);
				Texts.WriteString(W, "  saved.r="); WriteSet(saver); Texts.WriteLn(W);
				Texts.WriteString(W, "  saved.f="); WriteSet(savef); Texts.WriteLn(W);
				Texts.WriteString(W, "  frameSize="); Texts.WriteInt(W, fsize, 0);
				Texts.WriteString(W, "  callArea="); Texts.WriteInt(W, carea, 0); Texts.WriteLn(W);
				WHILE (i < 16) & (name[i] # 0X) DO INC(i) END ;
				WHILE i < 16 DO name[i] := " "; INC(i) END ;
				name[16] := 0X;
				proc[nextLabel] := name; INC(nextLabel);
				Files.Read(R, ch);	(* mode1 *)
				WHILE ~R.eof & (ch # 0F8X) DO
					IF ch = 3X THEN Texts.WriteString(W, "  VAR ")
					ELSE Texts.WriteString(W, "  ")
					END ;
					Files.Read(R, ch);	(* form1 *)
					Files.ReadNum(R, k);	(* adr *)
					Files.ReadString(R, name); Texts.WriteString(W, name);
					CASE ORD(ch) OF
					| Byte: Texts.WriteString(W, "  Byte");
					| SInt: Texts.WriteString(W, "  SInt");
					| Int: Texts.WriteString(W, "  Int");
					| LInt: Texts.WriteString(W, "  LInt");
					| Bool: Texts.WriteString(W, "  Bool");
					| Char: Texts.WriteString(W, "  Char");
					| Pointer: Texts.WriteString(W, "  Pointer");
					| ProcTyp: Texts.WriteString(W, "  ProcTyp");
					| Set: Texts.WriteString(W, "  Set");
					| Real: Texts.WriteString(W, "  Real");
					| LReal: Texts.WriteString(W, "  LReal");
					| Comp: Texts.WriteString(W, "  Comp");
					ELSE HALT(95)
					END ;
					Texts.WriteString(W, "  adr=");
					IF (k >= 0) & (k < 32) THEN Texts.Write(W, "r")
					ELSIF (k >= 32) & (k < 64) THEN Texts.Write(W, "f"); DEC(k, 32)
					ELSIF k >= 64 THEN DEC(k, 64)
					END ;
					Texts.WriteInt(W, k, 0); Texts.WriteLn(W);
					Files.Read(R, ch)	(* mode1 *)
				END
			END
		ELSE
			Files.Read(R, ch); IF ch # 8AX THEN HALT(98) END ;
			Files.Read(R, ch);
			WHILE ~R.eof DO
				IF ch # 0F8X THEN HALT(99) END ;
				label[lastEnd] := -nextLabel-1; Files.ReadNum(R, lastEnd);
				(* saved.r, saved.f, frameSize, callArea *)
				Files.ReadNum(R, k); Files.ReadNum(R, k); Files.ReadNum(R, k); Files.ReadNum(R, k);
				Files.ReadString(R, name); i := 0;
				WHILE (i < 16) & (name[i] # 0X) DO INC(i) END ;
				WHILE i < 16 DO name[i] := " "; INC(i) END ;
				name[16] := 0X;
				proc[nextLabel] := name; INC(nextLabel);
				Files.Read(R, ch);	(* mode1 *)
				WHILE ~R.eof & (ch # 0F8X) DO
					Files.Read(R, ch);	(* form1 *)
					Files.ReadNum(R, k);	(* adr *)
					Files.ReadString(R, name);
					Files.Read(R, ch)	(* mode1 *)
				END
			END
		END ;
		Texts.WriteLn(W); Texts.Append(T, W.buf)
	END ReadIn;
	
	PROCEDURE Comma;
	BEGIN
		Texts.WriteString(W, ", ")
	END Comma;
		
	PROCEDURE Reg(r: LONGINT);
	BEGIN
(*
		IF r = 0 THEN Texts.WriteString(W, "r0")
		ELSIF r = 1 THEN Texts.WriteString(W, "at")
		ELSIF r = 26 THEN Texts.WriteString(W, "k0");
		ELSIF r = 27 THEN Texts.WriteString(W, "k1");
		ELSIF r = 28 THEN Texts.WriteString(W, "gp");
		ELS *)
		IF r=0 THEN Texts.WriteString(W, "zero")
		ELSIF r = 1 THEN Texts.WriteString(W, "ra")
		ELSIF r = 2 THEN Texts.WriteString(W, "sp")
		ELSIF r = 8 THEN Texts.WriteString(W, "fp")
		ELSE Texts.Write(W, "r");
			Texts.WriteInt(W, r , 0)
		END
	END Reg;
	
	PROCEDURE FReg(f: LONGINT);
	BEGIN
		Texts.Write(W, "f"); Texts.WriteInt(W, f, 0)
	END FReg;
		
	PROCEDURE Str( s: ARRAY OF CHAR);
	VAR i: LONGINT;
	BEGIN
		i:=LEN(s);
		Texts.WriteString(W, s);
		REPEAT
			INC(i);
			Texts.Write(W, " ");
		UNTIL i>=10;
	END Str;

PROCEDURE RType0(s: ARRAY OF CHAR;  i: LONGINT);
BEGIN
	Str( s);
	Reg( ASH(i, -7) MOD 20H); Comma;
	Reg( ASH(i, -15) MOD 20H); Comma;
	Reg( ASH(i, -20) MOD 20H);
END RType0;

PROCEDURE FType0(s: ARRAY OF CHAR;  i: LONGINT);
VAR k: LONGINT; t: ARRAY 10 OF CHAR;
BEGIN
	k:=0;
	WHILE s[k]#0X DO t[k]:=s[k]; INC(k) END;
	t[k]:="."; INC(k);
	IF ODD(ASH( i ,-25)) THEN t[k]:="D";
	ELSE t[k]:="S";
	END;
	INC(k);
	WHILE k<8 DO t[k]:=" "; INC(k) END;		
	t[k]:=0X;
	Str( t);
	IF (SYSTEM.LSH(i, -27) = 14H) OR (SYSTEM.LSH(i, -27) = 1CH) THEN Reg( ASH(i, -7) MOD 20H);	(* FCMP, FMV.X, FCLASS *)
	ELSE FReg( ASH(i, -7) MOD 20H); 
	END;
	Comma;
	FReg( ASH(i, -15) MOD 20H);
	IF (SYSTEM.LSH(i, -27) # 1CH) THEN Comma; FReg( ASH(i, -20) MOD 20H) END;
END FType0;

PROCEDURE OP( i: LONGINT);
VAR funct3: LONGINT;
BEGIN
	funct3:= i DIV 1000H MOD 8;	
	IF ASH(i, -25)= 0 THEN
		CASE  funct3 OF
		|	0: RType0("ADD", i)
		|	1: RType0("SLL", i)
		|	2: RType0("SLT", i)
		|	3: RType0("SLTU", i)
		|	4: RType0("XOR", i)
		|	5: RType0("SRL", i)
		|	6: RType0("OR", i)
		|	7: RType0("AND", i)
		ELSE RType0("<NAI OP1>", i)
		END;
	ELSIF ASH(i, -25)= 1 THEN	(* RV32M *)
		CASE  funct3 OF
		|	0: RType0("MUL", i)
		|	1: RType0("MULH", i)
		|	2: RType0("MULHSU", i)
		|	3: RType0("MULHU", i)
		|	4: RType0("DIV", i)
		|	5: RType0("DIVU", i)
		|	6: RType0("REM", i)
		|	7: RType0("REMU", i)
		ELSE RType0("<NAI OP2>", i)
		END;
	ELSIF ASH(i, -25)= 20H THEN
		CASE  funct3 OF
		|	0: RType0("SUB", i)
		|	5: RType0("SRA", i)
		ELSE RType0("<NAI OP3>", i)
		END;
	ELSE RType0("<NAI OP4>", i)
	END;
END OP;

PROCEDURE OP32( i: LONGINT);
VAR funct3: LONGINT;
BEGIN
	funct3:= i DIV 1000H MOD 8;	
	IF ASH(i, -25)= 0 THEN
		CASE  funct3 OF
		|	0: RType0("ADDW", i)
		|	1: RType0("SLLW", i)
		|	2: RType0("SLT?", i)
		|	3: RType0("SLTU?", i)
		|	4: RType0("XOR?", i)
		|	5: RType0("SRL?", i)
		|	6: RType0("OR?", i)
		|	7: RType0("AND?", i)
		ELSE RType0("<NAI OP1/32>", i)
		END;
	ELSIF ASH(i, -25)= 1 THEN	(* RV32M *)
		CASE  funct3 OF
		|	0: RType0("MULW", i)
		|	1: RType0("MULH?", i)
		|	2: RType0("MULHSU?", i)
		|	3: RType0("MULHU?", i)
		|	4: RType0("DIVW", i)
		|	5: RType0("DIVUW", i)
		|	6: RType0("REMW", i)
		|	7: RType0("REMUW", i)
		ELSE RType0("<NAI OP2/32>", i)
		END;
	ELSIF ASH(i, -25)= 20H THEN
		CASE  funct3 OF
		|	0: RType0("SUBW", i)
		|	5: RType0("SRAW", i)
		ELSE RType0("<NAI OP3/32>", i)
		END;
	ELSE RType0("<NAI OP4/32>", i)
	END;
END OP32;

PROCEDURE IType0(s: ARRAY OF CHAR;  i: LONGINT);
BEGIN
	IF i=ADDI THEN Str("NOP");
	ELSE
		IF i MOD IMM14=067H THEN Str("JR");
		ELSE Str( s);
			IF s[0]="F" THEN FReg( ASH(i, -7) MOD 20H);
			ELSE Reg( ASH(i, -7) MOD 20H);
			END;
			Comma;
		END;
		Reg( ASH(i, -15) MOD 20H); Comma;
		Texts.WriteInt(W, ASH(i, -20), 0);
	END;
END IType0;

PROCEDURE OPFP( i: LONGINT);
BEGIN
	CASE ASH(i, -27) MOD 20H OF
	|	0: FType0("FADD", i)
	|	1: FType0("FSUB", i)
	|	2: FType0("FMUL", i)
	|	3: FType0("FDIV", i)
	|	4: FType0("FSGNxx", i)
	|	5: FType0("F", i)
	|	14H: FType0("FCMP", i)
	|	18H: FType0("FCVT1", i)
	|	1AH: FType0("FCVT2", i)
	|	1CH: IF ASH(i, -12) MOD 8 =0 THEN FType0("FMV.X", i);
					ELSIF ASH(i, -12) MOD 8 = 1 THEN FType0("FCLASS", i);
					END;
	|	1EH: FType0("FMV", i)
	ELSE IType0("<NAI FP>", i)
	END;
END OPFP;

PROCEDURE System( i: LONGINT);
BEGIN
	IF ASH(i, -7)=0 THEN Str("ECALL");
	ELSIF ASH(i, -7)=2000H THEN Str("SBRK");
	ELSE Str("<NAI Sys>");
	END;
END System;

PROCEDURE MiscMem( i: LONGINT);
BEGIN
	IF i MOD 100000H =0FH THEN Str("FENCE");
	ELSIF i MOD 100000H =100FH THEN Str("FENCE.I")
	ELSE Str("<MISC-MEM>")
	END;
END MiscMem;

PROCEDURE Load( i: LONGINT);
BEGIN
	CASE i DIV 1000H MOD 8 OF
	|	0: IType0("LB", i)
	|	1: IType0("LH", i)
	|	2: IType0("LW", i)
	|	4: IType0("LBU", i)
	|	5: IType0("LHU", i)
	|	6: IType0("LWU", i)
	ELSE IType0("<NAI LD>", i)
	END;
END Load;

PROCEDURE LoadFP( i: LONGINT);
BEGIN
	CASE i DIV 1000H MOD 8 OF
	|	2: IType0("FLW", i)
	|	3: IType0("FLD", i)
	ELSE IType0("<NAI LDFP>", i)
	END;
END LoadFP;

PROCEDURE SIType0(i: LONGINT);
BEGIN
	IF ASH(i, -12) MOD 8 =1 THEN Str("SLLI")
	ELSIF ASH(i, -12) MOD 8 = 5 THEN
		IF ASH(i, -26)=0 THEN Str("SRLI")
		ELSIF ASH(i, -26)=10H THEN Str("SRAI")
		ELSE Str("<NAI Shift>")
		END
	ELSE Str("<NAI SI>")
	END;
	Reg( ASH(i, -7) MOD 20H); Comma;
	Reg( ASH(i, -15) MOD 20H); Comma;
	IF ASH(i, -12) MOD 4=1 THEN Texts.WriteInt(W, ASH(i, -20) MOD 64, 0);
	ELSE Texts.WriteInt(W, ASH(i, -20), 0);
	END;
END SIType0;

PROCEDURE OPImm( i: LONGINT);
BEGIN
	CASE i DIV 1000H MOD 8 OF
	|	0: IType0("ADDI", i)
	|	1: SIType0( i)
	|	2: IType0("SLTI", i)
	|	3: IType0("SLTIU", i)
	|	4: IType0("XORI", i)
	|	5: SIType0( i)
	|	6: IType0("ORI", i)
	|	7: IType0("ANDI", i)
	ELSE IType0("<NAI Imm>", i)
	END;
END OPImm;

PROCEDURE OPImm32( i: LONGINT);
BEGIN
	CASE i DIV 1000H MOD 8 OF
	|	0: IType0("ADDIW", i)
	|	1: SIType0( i)
	|	2: IType0("SLTIW?", i)
	|	3: IType0("SLTIU?", i)
	|	4: IType0("XORI?", i)
	|	5: SIType0( i)
	|	6: IType0("ORI?", i)
	|	7: IType0("ANDI?", i)
	ELSE IType0("<NAI Imm32>", i)
	END;
END OPImm32;

PROCEDURE SType0(s: ARRAY OF CHAR;  i: LONGINT);
BEGIN
	Str( s);
	IF s[0]="F" THEN	FReg( ASH(i, -20) MOD 20H) ELSE Reg( ASH(i, -20) MOD 20H) END;
	Comma;
	Reg( ASH(i, -15) MOD 20H);
	Comma;
	Texts.WriteInt(W, ASH( ASH(i, -25), 5)+ SYSTEM.LSH(i , -7) MOD 20H , 0);
END SType0;

PROCEDURE Store( i: LONGINT);
BEGIN
	CASE i DIV 1000H MOD 8 OF
	|	0: SType0("SB", i)
	|	1: SType0("SH", i)
	|	2: SType0("SW", i)
	ELSE SType0("<NAI ST>", i)
	END;
END Store;

PROCEDURE StoreFP( i: LONGINT);
BEGIN
	CASE i DIV 1000H MOD 8 OF
	|	2: SType0("FSW", i)
	|	3: SType0("FSD", i)
	ELSE SType0("<NAI STFP>", i)
	END;
END StoreFP;

PROCEDURE WriteLabel( t: LONGINT);
BEGIN
	IF (t < LEN(label))& (t>=0) THEN
		IF label[t] < 0 THEN Texts.WriteString(W, proc[-label[t]-1]);
		ELSE Texts.WriteString(W, " L"); Texts.WriteInt(W, label[t], 0)
		END
	ELSE Texts.WriteString(W, "*****")
	END
END WriteLabel;

PROCEDURE GetSBimm(i: LONGINT): LONGINT;
BEGIN
	RETURN ASH( ASH(i, -31), 10)+ ASH( ASH(i , -25) MOD 40H , 3)+ ASH(i , -9) MOD 8H+ ASH( ASH(i, -7) MOD 2, 9);
END GetSBimm;

(*
PROCEDURE SetSBimm( imm: LONGINT): LONGINT;
BEGIN	(* imm in words *)
	RETURN ASH(ASH( imm, -10), 31)+ASH( ASH( imm, -3) MOD 40H, 25)+ASH(imm MOD 8H, 9)+ ASH( ASH(imm, -9) MOD 2, 7);
END SetSBimm;
*)

PROCEDURE SBType0(s: ARRAY OF CHAR;  i: LONGINT);
BEGIN
	Str( s);
	Reg( ASH(i, -15) MOD 20H); Comma;
	Reg( ASH(i, -20) MOD 20H); Comma;
	Texts.WriteInt(W, GetSBimm(i)*4, 0);
END SBType0;

PROCEDURE SBType(  i: LONGINT);
BEGIN
	CASE i DIV 1000H MOD 8 OF
	|	0: SBType0("BEQ", i)
	|	1: SBType0("BNE", i)
	|	4: SBType0("BLT", i)
	|	5: SBType0("BGE", i)
	|	6: SBType0("BLTU", i)
	|	7: SBType0("BGEU", i)
	ELSE SBType0("<NAI SB>", i)
	END;
	WriteLabel( pc  + GetSBimm(i));
END SBType;

PROCEDURE UType( s: ARRAY OF CHAR; i: LONGINT);
BEGIN
	Str( s);
	Reg( ASH(i, -7) MOD 20H); Comma;
	Texts.WriteInt(W, ASH(i, -12), 0)
END UType;

PROCEDURE GetUJimm( op: LONGINT): LONGINT;	(* in words *)
BEGIN
	RETURN ASH(ASH( op, -31), 18)+ASH( op, -22) MOD 200H+ASH( ASH(op, -20) MOD 2, 9)+ASH( ASH(op, -12) MOD 100H, 10);
END GetUJimm;

PROCEDURE UJType( s: ARRAY OF CHAR; i: LONGINT);
VAR t: LONGINT;
BEGIN
	Str( s);
	Reg( ASH(i, -7) MOD 20H); Comma;
	Texts.WriteInt(W, GetUJimm( i)*4, 0);
	WriteLabel( pc + 0 + GetUJimm(i));
END UJType;

PROCEDURE Custom1( i: LONGINT);
BEGIN
	IF i MOD 8000H = XTRAP THEN Str("XTRAP"); Texts.WriteInt( W, ASH(i, -15), 1);
	ELSE Str ( "<custom-2>");
	END;
END Custom1;
	
PROCEDURE Decode(instr: LONGINT);
BEGIN
	WriteHex(LONG(pc)*4, 5); Texts.Write(W, " "); WriteHex(instr, 8); Texts.Write(W, " ");
	IF label[pc] < 0 THEN Texts.WriteString(W, proc[-label[pc]-1]); Texts.Write(W, " ");
	ELSIF label[pc] = 0 THEN Texts.WriteString(W, "                 ")
	ELSE Texts.WriteString(W, "           L"); Texts.WriteInt(W, label[pc], 0);
		IF label[pc] < 10 THEN Texts.WriteString(W, "    ")
		ELSIF label[pc] < 100 THEN Texts.WriteString(W, "   ")
		ELSIF label[pc] < 1000 THEN Texts.WriteString(W, "  ")
		ELSE Texts.Write(W, " ")
		END
	END;
	IF instr MOD 4 =3 THEN
		CASE instr DIV 4 MOD 20H OF
		|	0:	Load( instr)
		|	1:	LoadFP( instr)
		|	2:	Str("<custom-0>")
		|	3:	MiscMem( instr)
		|	4:	OPImm( instr)
		|	5:	UType( "AUIPC", instr )
		|	6:	OPImm32( instr)
		|	7:	Str("<op-48b>")
		|	8:	Store( instr)
		|	9:	StoreFP( instr)
		|	10:	Custom1( instr )
		|	11:	Str("<AMO>")
		|	12:	OP( instr)
		|	13:	UType( "LUI", instr )
		|	14:	OP32( instr)
		|	15:	Str("<op-64b>")
		|	16:	Str("<MADD>")
		|	17:	Str("<MSUB>")
		|	18:	Str("<NMSUB>")
		|	19:	Str("<NMADD>")
		|	20:	OPFP( instr)
		|	21:	Str("<reserved>")
		|	22:	Str("<custom-2>")
		|	23:	Str("<op-48b>")
		|	24:	SBType( instr )
		|	25:	IType0("JALR", instr)
		|	26:	Str("<reserved>")
		|	27:	UJType("JAL", instr)
		|	28:	System( instr)
		|	29:	Str("<reserved>")
		|	30:	Str("<custom-3>")
		|	31:	Str("<op>=80b>")
		END;
	ELSE Texts.WriteInt( W, instr MOD 4, 0);
	END;
	Texts.WriteLn(W);
END Decode;

PROCEDURE MkLabels;
VAR pc, t, c: LONGINT;
BEGIN
	pc:=0;
	WHILE (pc< codesize) (*& (pc>0)*) DO
		c:= code[pc];
		IF c MOD 80H= 63H THEN	(* B *)
			t:= pc+0+GetSBimm(c);
			IF (t < LEN(label)) & (t>=0 ) THEN
				IF label[t] = 0 THEN label[t] := nextLabel; INC(nextLabel) END
			ELSE (* error *)
			END;
		ELSIF c MOD 80H= 6FH THEN	(* JAL *)
			t:= pc+0+GetUJimm(c);
			IF (t < LEN(label)) & (t>=0 ) THEN
				IF label[t] = 0 THEN label[t] := nextLabel; INC(nextLabel) END
			ELSE (* error *)
			END;
		ELSE 	(* Trap *)
		END;
		INC(pc);
	END;
END MkLabels;

	PROCEDURE GetArgs(VAR S: Texts.Scanner);
		VAR text: Texts.Text; beg, end, time: LONGINT;
	BEGIN
		Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos); Texts.Scan(S);
		IF (S.line#0) OR (S.class#Texts.Name) THEN
			Oberon.GetSelection(text, beg, end, time);
			IF time>=0 THEN Texts.OpenScanner(S, text, beg); Texts.Scan(S) END
		END
	END GetArgs;
	
	PROCEDURE This*;
		VAR S: Texts.Scanner;
	BEGIN
		GetArgs(S);
		IF S.class = 3 THEN Decode(S.i); Texts.Append(Oberon.Log, W.buf) END
	END This;
	
	PROCEDURE Append(VAR d: ARRAY OF CHAR; s: ARRAY OF CHAR);
		VAR i, j: INTEGER; ch: CHAR;
	BEGIN
		i := 0; WHILE d[i] # 0X DO INC(i) END ;
		j := 0; REPEAT ch := s[j]; d[i] := ch; INC(i); INC(j) UNTIL ch = 0X
	END Append;

	PROCEDURE QualIdent(VAR name, first, second: ARRAY OF CHAR);
		VAR i, j: INTEGER; ch: CHAR;
	BEGIN
		i := 0; ch := name[0];
		WHILE (ch # ".") & (ch # 0X) DO first[i] := ch; INC(i); ch := name[i] END ;
		first[i] := 0X; INC(i); j := 0; ch := name[i];
		WHILE ch # 0X DO second[j] := ch; INC(i); INC(j); ch := name[i] END ;
		second[j] := 0X
	END QualIdent;

	PROCEDURE Obj*;
		VAR x, y: INTEGER;
			v: Viewers.Viewer; S: Texts.Scanner;
			f: Files.File; nameObj, nameDec, dummy: Name;
			c, offset, L, L1: LONGINT;
			tag, i: INTEGER;
	BEGIN
		dir:="riscv/";
		fileTag:=Tagv;
		GetArgs(S);
		IF S.class # Texts.Name THEN RETURN END ;
		QualIdent(S.s, nameObj, dummy);
		Append( dir, nameObj);
		COPY( dir, nameObj);
		COPY( dir, nameDec);
		Append(nameObj, ObjExt);
		Append(nameDec, DecExt);
		f := Files.Old(nameObj);
		IF f = NIL THEN Texts.WriteString(W, nameObj); Texts.WriteString(W, " file not found"); Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf);
			RETURN
		END ;
		Texts.Scan(S);
		showref := (S.class=Texts.Char) & (S.c=OptionChar) & (S.nextCh = "r");
		Files.Set(R, f, 0);
		Oberon.AllocateUserViewer(0, x, y);
		T := TextFrames.Text("");
		v := MenuViewers.New(
			TextFrames.NewMenu(nameDec, "System.Close  System.Copy  System.Grow  Edit.Search "),
			TextFrames.NewText(T, 0), TextFrames.menuH, x, y);
		Files.ReadInt(R, tag);
		IF tag = fileTag THEN
			ReadIn;
			i := 0;
			WHILE i < noflink DO
				L := datalinks[i];
				IF L # 0 THEN L1 := -1;
					REPEAT
						IF (L >= codesize - 1) OR ( L<0) THEN
							Texts.WriteString(W, "******* Link chain error at "); WriteHex(L1*4, 5);
							Texts.WriteString(W, " starting from "); WriteHex(4*datalinks[i], 5);
							Texts.WriteLn(W); Texts.Append(T, W.buf); L1 := L
						ELSE
							L1 := L; c := code[L1];
							offset:=code[L1+1];
							code[L1] := LUI+ ASH( T0, 7) + ASH( ASH( offset, -12)+ASH(offset, -11) MOD 2, 12);
							IF c MOD 80H= JAL THEN	(* procedure call, UJ format *)	(* to be fixed in OPL.Exit, adjustLink ? *)
								L:= L1 + GetUJimm(c)+1;
								code[L1+1] := JALR+ASH(RA, 7)+ASH(T0, 15)+ASH( offset MOD IMM12, 20);
							ELSE
								L:= L1 + ASH(c, -15)+1;	(* interim coding *)
								IF (c MOD 80H DIV 8=SB DIV 8) THEN	(* store, store fp *)
									code[L1+1] := ASH( ASH(c,-7) MOD 20H, 20) +ASH(T0, 15)+ ASH( ASH(c, -12) MOD 8, 12) + c MOD 80H+ SetSimm(offset);
								ELSE								(* load, loadfp, addi *)
									code[L1+1] := SYSTEM.LSH( offset , 20) + ASH( T0, 15)+ c MOD IMM15;
								END;
							END;
						END
					UNTIL (L = L1);
				END;
				INC(i)
			END;
			Texts.WriteString(W, "code:   (pos "); Texts.WriteInt(W, codepos, 0);
			Texts.Write(W, ")"); Texts.WriteLn(W); Texts.Append(T, W.buf);
			MkLabels;
			pc := 0;
			WHILE pc < codesize DO Decode(code[pc]); INC(pc) END;
		ELSE Texts.WriteString(W, "not a Risc-V (*.Obj) object file"); Texts.WriteLn(W); 
		END ;
		Texts.Append(T, W.buf);
		Files.Close(f)
	END Obj;
	
	PROCEDURE Bin*;
		VAR x, y: INTEGER; ch: CHAR;
			v: Viewers.Viewer; S: Texts.Scanner;
			f: Files.File; nameBin, nameDec, dummy: Name;
			i: INTEGER;
	BEGIN
		GetArgs(S);
		IF S.class # Texts.Name THEN RETURN END ;
		QualIdent(S.s, nameBin, dummy);
		COPY(nameBin, nameDec);
		Append(nameBin, BinExt);
		Append(nameDec, DecExt);
		f := Files.Old(nameBin);
		IF f = NIL THEN RETURN END ;
		Files.Set(R, f, 0);
		Oberon.AllocateUserViewer(0, x, y);
		T := TextFrames.Text("");
		v := MenuViewers.New(
			TextFrames.NewMenu(nameDec, "System.Close  System.Copy  System.Grow  Edit.Search "),
			TextFrames.NewText(T, 0), TextFrames.menuH, x, y);
		pc := 0;
		WHILE ~R.eof DO Files.ReadLInt(R, code[pc]); label[pc] := 0; INC(pc) END ;
		codesize := pc;
		MkLabels;
		pc := 0;
		WHILE pc < codesize DO Decode(code[pc]); INC(pc) END ;
		Texts.Append(T, W.buf);
		Files.Close(f)
	END Bin;

BEGIN
	Texts.OpenWriter(W); Texts.SetFont(W, Fonts.This("Courier10.Scn.Fnt")); 
END VDecoder.
