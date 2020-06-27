MODULE M2Decoder;	(* rc 20.11.89 / 5.5.93 *)	(* object model 4.12.93 *)

(* peter matthias

		2015-04-08	using "arm6/" directory; added BNEL, BEQL, BLEZL, BGTZL instructions
		2015-08-14	added MkLabels, made Decode single pass
		2015-10-04	merged with test decoder, renamed Obj to Oba and Obm
		2015-10-10	using dir prefix, and .Obj extension
		2015-11-14	added Special2 and MUL
		2015-11-26	fixed code in RT3

*)

	IMPORT Texts, Oberon, Viewers, MenuViewers, TextFrames, Files, Fonts, SYSTEM;
	
	CONST
		OptionChar = "\";
		Taga=36FAH;
		ObjExt = ".Obj";
		Tagm=36F9H;
		BinExt = ".Bin";
		DecExt = ".Dec";
		
		(* instruction format *)
		OP = 4000000H; RS = 200000H; RTi = 10000H; RD = 800H; IMM = 10000H; SHAMT = 40H;
		CO = 2000000H; FMT = RS; FT = RTi; FS = RD; FD = SHAMT; LUI = 15;
		
		(* structure forms *)
		Undef = 0; Byte = 1; Bool = 2; Char = 3; SInt = 4; Int = 5; LInt = 6;
		Real = 7; LReal = 8; Set = 9; String = 10; NilTyp = 11; NoTyp = 12;
		Pointer = 13; ProcTyp = 14; Comp = 15;

		nlen = 64;
		CodeLength = 32000;
		
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
		ELS	*)
		IF r = 29 THEN Texts.WriteString(W, "sp")
		ELSIF r = 30 THEN Texts.WriteString(W, "fp")
		ELSIF r = 31 THEN Texts.WriteString(W, "ra")
		ELSE Texts.Write(W, "r"); Texts.WriteInt(W, r, 0)
		END
	END Reg;
	
	PROCEDURE FReg(f: LONGINT);
	BEGIN
		Texts.Write(W, "f"); Texts.WriteInt(W, f, 0)
	END FReg;
	
	PROCEDURE Base(b: LONGINT);
	BEGIN
		Texts.Write(W, "("); Reg(b); Texts.Write(W, ")")
	END Base;
	
	PROCEDURE Off(a: LONGINT);
	BEGIN
		Texts.WriteInt(W, a, 0)
	END Off;

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

PROCEDURE IT( s: ARRAY OF CHAR; i: LONGINT);
BEGIN
	Str( s);
	Reg( ASH(i, -21) MOD 20H); Comma;
	Reg( ASH(i, -16) MOD 20H); Comma;
	Texts.WriteInt(W, SYSTEM.LSH(i, 16) DIV 10000H, 0)
END IT;

PROCEDURE ITF( s: ARRAY OF CHAR; i: LONGINT);
BEGIN
	Str( s);
	Reg( ASH(i, -21) MOD 20H); Comma;
	FReg( ASH(i, -16) MOD 20H); Comma;
	Texts.WriteInt(W, SYSTEM.LSH(i, 16) DIV 10000H, 0)
END ITF;

PROCEDURE IT1( s: ARRAY OF CHAR; i: LONGINT);
BEGIN
	Str( s);
	Reg( ASH(i, -16) MOD 20H); Comma;
	Texts.WriteInt(W, SYSTEM.LSH(i, 16) DIV 10000H, 0)
END IT1;

PROCEDURE ITB( s: ARRAY OF CHAR; i: LONGINT);
VAR targ: LONGINT;
BEGIN
	Str( s);
	Reg( ASH(i, -21) MOD 20H); Comma;
	IF ASH(i, -26)#1 THEN Reg( ASH(i, -16) MOD 20H); Comma END;;
	targ := (pc + 1 + SYSTEM.LSH(i, 16) DIV IMM) MOD IMM;
	IF targ < LEN(label) THEN
		IF label[targ] < 0 THEN Texts.WriteString(W, proc[-label[targ]-1]);
		ELSE Texts.Write(W, "L"); Texts.WriteInt(W, label[targ], 0)
		END
	ELSE Texts.WriteString(W, "*****")
	END
END ITB;

PROCEDURE ITL( s: ARRAY OF CHAR; i: LONGINT);
BEGIN
	Str( s);
	Reg( ASH(i, -16) MOD 20H); Comma;
	Texts.WriteInt(W, SYSTEM.LSH(i, 16) DIV 10000H, 0);
	Base(ASH(i, -21) MOD 20H);
END ITL;

PROCEDURE JT( s: ARRAY OF CHAR; i: LONGINT);
BEGIN
	Str( s); Texts.WriteHex(W, i);
END JT;

PROCEDURE RT0( s: ARRAY OF CHAR; i: LONGINT);
BEGIN
	Str( s);
	Texts.WriteInt(W, ASH( i, -6), 1);
END RT0;

PROCEDURE RT1( s: ARRAY OF CHAR; i: LONGINT);
BEGIN
	Str( s);
	Reg( ASH( i, -21));
END RT1;

PROCEDURE RT2( s: ARRAY OF CHAR; i: LONGINT);
BEGIN
	Str( s);
	Reg( ASH( i, -11) MOD 20H); Comma;
	Reg( ASH( i, -21));
END RT2;

PROCEDURE RT3( s: ARRAY OF CHAR; i: LONGINT);
BEGIN
	Str( s);
	Reg(ASH(i, -21) MOD 20H); Comma; 
	Reg( ASH(i, -16) MOD 20H); Comma;
	Texts.WriteInt(W, ASH( i, -6) MOD 400H, 2);
END RT3;

PROCEDURE RT( s: ARRAY OF CHAR; i: LONGINT);
BEGIN
	Str( s);
	Reg(ASH(i, -21) MOD 20H); Comma; 
	Reg( ASH(i, -16) MOD 20H); Comma;
	Reg( ASH(i, -11) MOD 20H); Comma; 
	Texts.WriteInt(W, ASH( i, -6) MOD 20H, 2);
END RT;

PROCEDURE COP0( i: LONGINT);
BEGIN
	Str("COP0"); Texts.WriteHex(W, i);
END COP0;

PROCEDURE SubCOP1(s: ARRAY OF CHAR; i: LONGINT);
BEGIN
	Str(s);
	Reg( ASH(i, -16)MOD 20H); Comma;
	FReg( ASH(i, -11) MOD 20H);
END SubCOP1;

PROCEDURE SubCOP1BC( i: LONGINT);
BEGIN
	CASE ASH(i, -16) MOD 20H OF
	|	0:	Str("BCF");
	|	1:	Str("BCT");
	|	2:	Str("BCFL*");
	|	3:	Str("BCTL*");
	ELSE
		Str("<BC not known>"); RETURN;
	END;
	Comma; Texts.WriteHex(W, i MOD 10000H);
END SubCOP1BC;

PROCEDURE Float2(str: ARRAY OF CHAR; i: LONGINT);
BEGIN
	Str(str); 
	FReg(ASH(i, -6)MOD 32); Comma;
	FReg(ASH(i, -11)MOD 32); 
END Float2;

PROCEDURE Float3(str: ARRAY OF CHAR; i: LONGINT);
BEGIN
	Str(str); 
	FReg(ASH(i, -6)MOD 32); Comma;
	FReg(ASH(i, -11)MOD 32); Comma;
	FReg(ASH(i, -16)MOD 32);
END Float3;

PROCEDURE Float(c: CHAR; i: LONGINT);
VAR str: ARRAY 12 OF CHAR;
BEGIN
	CASE i MOD 64 OF
	|	0:	Float3("ADD.F", i);
	|	1:	Float3("SUB.F", i);
	|	2:	Float3("MUL.F", i);
	|	3:	Float3("DIV.F", i)
	|	4:	Float2("SQRT", i);
	|	5:	Float2("ABS", i);
	|	6:	Float2("MOV", i);
	|	7:	Float2("NEG", i);
	|	12:	Float2("ROUND", i);
	|	13:	Float2("TRUNC", i);
	|	14:	Float2("CEIL", i);
	|	15:	Float2("FLOOR", i);
	|	32:	Float2("CVT.S", i);
	|	33:	Float2("CVT.D", i);
	|	36:	Float2("CVT.W", i);
	ELSE
		Str("<Float not known>");
	END;
END Float;

PROCEDURE COP1( i: LONGINT);
BEGIN
	CASE ASH(i, -21) MOD 32 OF
	|	0:	SubCOP1("MFC1", i);
	|	2:	SubCOP1("CFC1", i);
	|	4:	SubCOP1("MTC1", i);
	|	6:	SubCOP1("CTC1", i);
	|	8:	SubCOP1BC( i);
	|	16:	Float("S", i);
	|	17:	Float("D", i);
	|	20:	Float("W", i);
	ELSE
		Str("<COP1 not known>");
	END;
END COP1;

PROCEDURE COP2( i: LONGINT);
BEGIN
	Str("COP2"); Texts.WriteHex(W, i);
END COP2;

PROCEDURE COP3( i: LONGINT);
BEGIN
	Str("COP3"); Texts.WriteHex(W, i);
END COP3;

PROCEDURE Special( i: LONGINT);
BEGIN
	IF i=0 THEN Texts.WriteString(W, "NOP")
	ELSE
		CASE i MOD 64 OF
			0:	RT("SLL",i)
		|	2:	RT("SRL",i)
		|	3:	RT("SRA",i)
		|	4:	RT("SLLV",i)
		|	6:	RT("SRLV",i)
		|	7:	RT("SRAV",i)
		|	8:	RT1("JR",i)
		|	9:	RT2("JALR",i)
		|	12:	RT0("SYSCALL",i)
		|	13:	RT0("BREAK",i)
		|	15:	RT("SYNC",i)
		|	16:	RT("MFHI",i)
		|	17:	RT("MTHI",i)
		|	18:	RT("MFLO",i)
		|	19:	RT("MTLO",i)
		|	24:	RT("MULT",i)
		|	25:	RT("MULTU",i)
		|	26:	RT("DIV",i)
		|	27:	RT("DIVU",i)
		|	32:	RT("ADD",i)
		|	33:	RT("ADDU",i)
		|	34:	RT("SUB",i)
		|	35:	RT("SUBU",i)
		|	36:	RT("AND",i)
		|	37:	RT("OR",i)
		|	38:	RT("XOR",i)
		|	39:	RT("NOR",i)
		|	42:	RT("SLT",i)
		|	43:	RT("SLTU",i)
		|	48:	RT3("TGE", i)
		|	49:	RT3("TGEU", i)
		|	50:	RT3("TLT", i)
		|	51:	RT3("TLTU", i)
		|	52:	RT3("TEQ", i)
		|	54:	RT3("TNE", i)
		ELSE
			Str("<SPECIAL not known>"); WriteHex(i MOD 64, 8);
		END;
	END
END Special;

PROCEDURE Special2( i: LONGINT);
BEGIN
	CASE i MOD 64 OF
		2:	RT("MUL", i);
	ELSE
		Str("<SPECIAL2 not known>"); WriteHex(i MOD 64, 8);
	END;
END Special2;

PROCEDURE Regimm( i: LONGINT);
BEGIN
	CASE ASH(i, -16) MOD 32 OF
	|	0:	ITB("BLTZ", i)
	|	1:	ITB("BGEZ", i)
	|	16:	ITB("BLTZAL", i)
	|	17:	ITB("BGEZAL", i)
	ELSE
		Str("<REGIMM not known>"); WriteHex(i MOD 64, 8);
	END;
END Regimm;
	
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
		CASE ASH(instr, -26) MOD 40H OF
			0:	Special( instr )
		|	1:	Regimm( instr )
		|	2:	JT("J", instr )
		|	3:	JT("JAL", instr)
		|	4:	ITB("BEQ", instr)
		|	5:	ITB("BNE", instr)
		|	6:	ITB("BLEZ", instr)
		|	7:	ITB("BGTZ", instr)
		|	8:	IT("ADDI", instr)
		|	9:	IT("ADDIU", instr)
		|	10:	IT("SLTI", instr)
		|	11:	IT("SLTIU", instr)
		|	12:	IT("ANDI", instr)
		|	13:	IT("ORI", instr)
		|	14:	IT("XORI", instr)
		|	15:	IT1("LUI", instr)
		|	16:	COP0( instr)
		|	17:	COP1( instr)
		|	18:	COP2( instr)
		|	19:	COP3( instr)
		|	20:	ITB("BEQL*", instr)
		|	21:	ITB("BNEL*", instr)
		|	22:	ITB("BLEZL*", instr)
		|	23:	ITB("BGTZL*", instr)
		|	28:	Special2( instr )
		|	32:	ITL("LB", instr)
		|	33:	ITL("LH", instr)
		|	34:	ITL("LWL", instr)
		|	35:	ITL("LW", instr)
		|	36:	ITL("LBU",  instr)
		|	37:	ITL("LHU", instr)
		|	38:	ITL("LWR", instr)
		|	40:	ITL("SB", instr)
		|	41:	ITL("SH", instr)
		|	42:	ITL("SWL", instr)
		|	43:	ITL("SW", instr)
		|	46:	ITL("SWR", instr)
		|	47:	IT("CACHE", instr)
		|	48:	IT("LL", instr)
		|	49:	ITF("LWC1", instr)
		|	50:	IT("LWC2", instr)
		|	51:	IT("LWC3", instr)
		|	53:	ITF("LDC1", instr)
		|	54:	IT("LDC2", instr)
		|	55:	IT("LDC3", instr)
		|	56:	IT("SC", instr)
		|	57:	ITF("SWC1", instr)
		|	58:	IT("SWC2", instr)
		|	59:	IT("SWC3", instr)
		|	61:	ITF("SDC1", instr)
		|	62:	IT("SDC2", instr)
		|	63:	IT("SDC3", instr)
		ELSE	Texts.WriteString(W, "< not known>");
		END;
		Texts.WriteLn(W)
	END Decode;

PROCEDURE MkLabels;
VAR pc, instr, i2, targ: LONGINT;
BEGIN
	pc:=0;
	WHILE pc< codesize DO
		instr:= ASH(code[pc], -16) MOD 10000H;
		i2:= ASH( instr, -12);
		IF (i2=1) OR (i2=5) OR ((i2=4) &  (ASH(instr, -5) MOD 20H=8)) OR ((ASH(instr , -10)=1) & ~(ODD( ASH(instr, -3)))) THEN (* branch instructions *)
			targ:=(pc+1+ SYSTEM.LSH(code[pc], 16) DIV IMM) MOD IMM;
			IF targ < LEN(label) THEN
				IF label[targ] = 0 THEN label[targ] := nextLabel; INC(nextLabel) END
			ELSE (* error *)
			END;
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

	PROCEDURE Obj;
		VAR x, y: INTEGER;
			v: Viewers.Viewer; S: Texts.Scanner;
			f: Files.File; nameObj, nameDec, dummy: Name;
			c, offset, L, L1, L2: LONGINT;
			tag, i: INTEGER;
	BEGIN
		GetArgs(S);
		IF S.class # Texts.Name THEN RETURN END ;
		QualIdent(S.s, nameObj, dummy);
		Append( dir, nameObj);
		COPY( dir, nameObj);
		COPY( dir, nameDec);
		Append(nameObj, ObjExt);
		Append(nameDec, DecExt);
		f := Files.Old(nameObj);
		IF f = NIL THEN Texts.WriteString(W, "file not found"); Texts.WriteLn(W); Texts.Append(T, W.buf); RETURN END ;
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
						IF L >= codesize - 1 THEN
							Texts.WriteString(W, "******* Link chain error at "); WriteHex(L1*4, 5);
							Texts.WriteString(W, " starting from "); WriteHex(4*datalinks[i], 5);
							Texts.WriteLn(W); Texts.Append(T, W.buf); L1 := L
						ELSE L1 := L;
							c := code[L1]; offset := code[L1+1];
							L := L1 + SYSTEM.LSH(c, 16) DIV IMM + 1;
							IF L = L1 - 1 THEN (* 8 bytes access, for LONGREAL *)
								Texts.WriteString(W, "warning: 8 bytes access "); WriteHex(L*4, 8);Texts.WriteLn(W);
								code[L1] := IMM*(c DIV IMM) + (offset + 4) MOD IMM;
								DEC(L1); c := code[L1];
								L := L1 + SYSTEM.LSH(c, 16) DIV IMM + 1; L2 := L1 + 2
							ELSE L2 := L1 + 1
							END ;
							code[L1] := LUI*OP + RTi*((c DIV RS) MOD 32) + (offset DIV IMM) MOD IMM;
							code[L2] := IMM*(c DIV IMM) + offset MOD IMM
						END
					UNTIL L = L1
				END ;
				INC(i)
			END ;
			Texts.WriteString(W, "code:   (pos "); Texts.WriteInt(W, codepos, 0);
			Texts.Write(W, ")"); Texts.WriteLn(W); Texts.Append(T, W.buf);
			MkLabels;
			pc := 0;
			WHILE pc < codesize DO Decode(code[pc]); INC(pc) END;
		ELSE Texts.WriteString(W, "not a MIPS (*.Oba) object file"); Texts.WriteLn(W); 
		END ;
		Texts.Append(T, W.buf);
		Files.Close(f)
	END Obj;

PROCEDURE Obt*;
BEGIN
	dir:="test/";
	fileTag:=Taga;
	Obj;
END Obt;

PROCEDURE Obm*;
BEGIN
	dir:="mips/";
	fileTag:=Tagm;
	Obj;
END Obm;
	
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
END M2Decoder.
