MODULE A32Decoder;	(* rc 20.11.89 / 5.5.93 *)	(* object model 4.12.93 *)

(* peter matthias

		2015-08-14	added MkLabels, made Decode single pass
		2015-08-31	started OP2 ARM32 version using root dir; decode copied from StrongARM port
		2015-12-01	using armv7/ dir
		2016-03-20	added MOVW, MOVT
		2016-10-28	added B(L)X, XTRAP (illegal instruction used for traps)
		2017-03-05	ReadIn: mods changed from 32 to 48
*)

	IMPORT Texts, Oberon, Viewers, MenuViewers, TextFrames, Files, Fonts, SYSTEM;
	
	CONST
		OptionChar = "\";
		ObjExt = ".Obj";
		BinExt = ".Bin";
		DecExt = ".Dec";
			
		(* structure forms *)
		Undef = 0; Byte = 1; Bool = 2; Char = 3; SInt = 4; Int = 5; LInt = 6;
		Real = 7; LReal = 8; Set = 9; String = 10; NilTyp = 11; NoTyp = 12;
		Pointer = 13; ProcTyp = 14; Comp = 15;

		nlen = 64;
		CodeLength = 32000;

		Taga= 36FBH;		(* MIPS: 36F9H; MIPS test: 36FAH; ARM32 OP2: 36FBH; ARM ns compiler: ??; MIPS *)
		IMM28=10000000H; IMM16= 10000H; IMM12=1000H;
		
	TYPE
		Name = ARRAY nlen OF CHAR;
		
	VAR
		W: Texts.Writer;
		T: Texts.Text;
		R: Files.Rider;
		codepos, codesize: LONGINT;
		pc, nextLabel, noflink: LONGINT;
		showref: BOOLEAN;
		code: ARRAY CodeLength OF LONGINT;
		label: ARRAY CodeLength OF LONGINT;
		proc: ARRAY 500 OF Name;
		datalinks: ARRAY 1000 OF LONGINT;

		name0, name1, branch, branchl, dfloat, mfloat, cptnf, tnf, bnf, CC, Rot, Psr, Reg, FReg: ARRAY 128 OF CHAR;
		halfword: ARRAY 16 OF CHAR; 

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
			mods: ARRAY 48 OF Name;
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
	
	PROCEDURE Ch(ch: CHAR);
	BEGIN Texts.Write(W, ch)
	END Ch;

	PROCEDURE Str(s: ARRAY OF CHAR);
	BEGIN Texts.WriteString(W, s)
	END Str;
	
	PROCEDURE int(i: LONGINT);
	BEGIN Texts.WriteInt(W, i, 0)
	END int;
	
	PROCEDURE tab;
	BEGIN Texts.Write(W, 09X)
	END tab;
	
	PROCEDURE Ln;
	BEGIN Texts.WriteLn(W)
	END Ln;

	PROCEDURE FixHex(n: LONGINT);
	BEGIN
		Texts.WriteHex(W, n)
	END FixHex;

	PROCEDURE Hex(n: LONGINT);
		VAR i, j: INTEGER; s, t : ARRAY 10 OF CHAR;
	BEGIN
		i := 0;			
		REPEAT
			IF n MOD 10H < 10 THEN s[i] := CHR(n MOD 10H +ORD("0")) ELSE s[i] := CHR(n MOD 10H - 10 + ORD("A")) END;
			n := n DIV 10H MOD 10000000H; INC(i);
		UNTIL n = 0;
		j := 0;
		WHILE i>0 DO DEC(i); t[j] := s[i]; INC(j) END; t[j]:="H"; t[j+1] := 0X;
		(* IF t[0]>"9" THEN Texts.Write(W,"0") END; *)
		Texts.WriteString(W, t)
	END Hex;
	
	PROCEDURE word(VAR n: ARRAY OF CHAR; p: LONGINT);
	BEGIN
		p := p*4;
		Texts.Write(W, n[p]); Texts.Write(W, n[p+1]); Texts.Write(W, n[p+2]); 
	END word;
	
	PROCEDURE word2(VAR n: ARRAY OF CHAR; p : LONGINT);
	BEGIN
		p := p*4;
		Texts.Write(W, n[p]); Texts.Write(W, n[p+1]); Texts.Write(W, n[p+2]); Texts.Write(W, n[p+3]); 
	END word2;

	PROCEDURE word3(VAR n : ARRAY OF CHAR; p : LONGINT);
	BEGIN
		p:=p*2;
		Texts.Write(W, n[p]); Texts.Write(W, n[p+1])
	END word3;
	
	PROCEDURE cond(cc: LONGINT);
	BEGIN
		cc:= cc*3;
		Texts.Write(W, CC[cc]); Texts.Write(W, CC[cc+1])
	END cond;
	
	PROCEDURE s;
	BEGIN Texts.Write(W, "S");
	END s;	
	
	PROCEDURE byte;
	BEGIN Texts.Write(W, "B");
	END byte;

	PROCEDURE reg(n: LONGINT);
	BEGIN
		n:= n*3;
		Texts.Write(W, Reg[n]); Texts.Write(W, Reg[n + 1])
	END reg;
	
	PROCEDURE freg(n: LONGINT);
	BEGIN
		n:= n*3;
		Texts.Write(W, FReg[n]); Texts.Write(W, FReg[n + 1]);
	END freg;
	
	PROCEDURE psr(s, a: LONGINT);
		VAR i: LONGINT;
	BEGIN a := (a MOD 2 + a DIV 4)*8 - 8 + s*24 ;
		IF (a >= 0) & (a<48) THEN
			FOR i:= a TO a + 7 DO
				Texts.Write(W, Psr[i]) 
			END
		END
	END psr;
	
	PROCEDURE rot(t, c: LONGINT);
		VAR n: LONGINT;
	BEGIN
		IF ODD(t) THEN (* register form*)
			DEC(t); (* t MOD 8 isn't needed, since t.3=0 *)
			Texts.Write(W, Rot[t*2]); Texts.Write(W, Rot[t*2+1]);
			Texts.Write(W, Rot[t*2+2]); Texts.Write(W, Rot[t*2+3]);
			reg(c)
		ELSE
			n := c*2 + t DIV 8;
			IF n # 0 THEN
				Texts.Write(W, Rot[(t MOD 8)*2]); Texts.Write(W, Rot[(t MOD 8)*2+1]);
				Texts.Write(W, Rot[(t MOD 8)*2+2]); Texts.Write(W, Rot[(t MOD 8)*2+3]);
				Texts.WriteInt(W, n, 0)
			ELSIF (t MOD 8) = 6 THEN (* rrx *) 
				Texts.WriteString(W, "RRX");
			ELSIF ((t MOD 8) = 2) OR ( (t MOD 8) = 4) THEN (* rotate 32*)
				Texts.Write(W, Rot[(t MOD 8)*2]); Texts.Write(W, Rot[(t MOD 8)*2+1]);
				Texts.Write(W, Rot[(t MOD 8)*2+2]); Texts.Write(W, Rot[(t MOD 8)*2+3]);
				Texts.WriteInt(W, 32, 0)
			END				
		END
	END rot;
	
	PROCEDURE imm(i, r: LONGINT);
	BEGIN Hex(SYSTEM.ROT(i, -2*r))
	END imm;

	PROCEDURE PCRelAddr(adr, sign, ofs : LONGINT);
	BEGIN
		tab; tab; Str("( = "); int((adr+8)+sign*ofs); Str(" (");  FixHex((adr+8)+sign*ofs); Str("H)  )");
	END PCRelAddr;
	
	PROCEDURE decode(adr, code: LONGINT);
		VAR cc, a, b, c, d, e, f, g, i: LONGINT; regset: SET; sign : LONGINT;
	BEGIN
		g := code MOD 10H; code := code DIV 10H;	(* split instruction *)
		f := code MOD 10H; code := code DIV 10H;
		e := code MOD 10H; code := code DIV 10H;
		d := code MOD 10H; code := code DIV 10H;
		c := code MOD 10H; code := code DIV 10H;
		b := code MOD 10H; code := code DIV 10H;
		a := code MOD 10H; code := code DIV 10H;
		cc :=  code MOD 10H;
		CASE a OF
			0..3:
				IF (f = 9) & (a = 0) THEN (*mul / mull *)
					IF ODD(b DIV 8) THEN (* mull *)
						IF ODD(b DIV 4) THEN Ch("S") ELSE Ch("U") END;
						word(name0, (b DIV 2) MOD 2 + 16 ); Ch("L"); 
						cond(cc); IF ODD(b) THEN s ELSE Ch(" ") END; tab; Str("  ");
						reg(c); Ch(":"); reg(d); Ch(","); reg(g); Ch(","); reg(e);
					ELSE
						word(name0, (b DIV 2) MOD 2 + 16 );
						cond(cc); IF ODD(b) THEN s ELSE Ch(" ") END; tab; tab;
						reg(c); IF ODD(b DIV 8) THEN Ch(":"); reg(d) END;
						Ch(","); reg(g); Ch(","); reg(e);
						IF ODD(b DIV 2) THEN Ch(","); reg(d) END;
					END
				ELSIF (f>9) & ODD(f) & (a<2) THEN (* ldrh/strh *)
					word(name1,(b MOD 2)+1);  word3(halfword,(f-9) DIV 2); cond(cc);
					Str("   "); tab; reg(d); Str(",[");
					reg(c); IF ~ODD(a) THEN Ch("]") END; Ch(",");
					IF ODD(b DIV 8) THEN Ch("+"); sign:=1 ELSE Ch("-"); sign:=-1 END;
					IF ODD(b DIV 4) THEN (* immidiate data transfer*)
						imm(e*10H +  g, 0);
					ELSE	(* reg data transfer *)
						sign:=0;
						reg(g) 
					END;
					IF ODD(a) THEN Ch("]") END;
					IF ODD(b DIV 2) THEN Ch("!") END;
					IF (c=15) & (sign#0) THEN PCRelAddr(adr,sign,e*10H+g) END;
				ELSIF (f = 9) & (a=1) THEN (*single swap *)
					Str("SWP"); cond(cc); IF ODD(b DIV 4) THEN Ch("B") ELSE Ch(" ") END; tab; tab;
					reg(d); Ch(","); reg(g); Str(",["); reg(c); Ch("]");
				ELSIF (a = 1) & (b = 2) & (c=0FH) &(d=0FH) & (e=0FH) THEN	(* B(L)X *)
					word( bnf, f); cond(cc); Ch(" "); tab; tab; reg( g);
				ELSIF (a = 3) & (b = 2) & (d=0FH) THEN Texts.WriteString(W, "NOP" );
				ELSIF (a = 1) & ((b = 2) OR (b = 6) OR (b = 0) OR (b = 4)) OR (a = 3)&((b = 2) OR (b = 6)) THEN(* msr /mrs *)
					word(tnf, b DIV 2 MOD 2); cond(cc); Ch(" "); tab; tab;
					IF (b = 0) OR (b = 4) THEN reg(d); Ch(","); psr(b DIV 4, 9)
					ELSE psr(b DIV 4, c); Ch(",");
						IF a = 3 THEN imm(f*10H + g, e) ELSE reg(g) END
					END
				ELSE
					IF (a=3) & (b=0) THEN Str("MOVW    "); cond(cc); tab; reg(d); Ch(","); Hex(((c*10H+ e)*10H+f)*10H+g);
					ELSIF (a=3) & (b=4) THEN Str("MOVT    "); cond(cc); tab; reg(d); Ch(","); Hex(((c*10H+ e)*10H+f)*10H+g);
					ELSE
						word(name0, b DIV 2 + a*8 MOD 10H); cond(cc); IF ODD(b) THEN s ELSE Ch(" ") END; tab; tab;
						IF (b DIV 2 + a*8 MOD 10H = 0DH) OR (b DIV 2 + a*8 MOD 10H = 0FH) THEN (* Mov, Mvn*)
							reg(d) 
						ELSIF (b DIV 2 + a*8 MOD 10H >= 8H) & (b DIV 2 + a*8 MOD 10H <=  0BH) THEN (* cmp, tst*)
							reg(c)
						ELSE reg(d); Ch(","); reg(c) 
						END;
						IF ODD(a DIV 2) THEN Ch(","); imm(f*10H + g, e)	(* Immidiate Data processing *)
						ELSE Ch(","); reg(g); Ch(" "); rot(f, e)	(* Data processing *)
						END
					END;
				END	
			| 4..7: (*ldr, str *)
				IF (a >= 6) & ODD(f) THEN
					IF (a=7) THEN
						IF (b=1) THEN Str("SDIV    "); cond(cc); tab; reg(c); Ch(","); reg(g); Ch(","); reg(e);
						ELSIF (b=3) THEN  Str("UDIV    "); cond(cc); tab; reg(c); Ch(","); reg(g); Ch(","); reg(e);
						ELSIF (b=15) & (f=15) THEN Str("XTRAP     "); tab; int(d*16+e);
						ELSIF (b DIV 2= 7) THEN Str("UBFX    "); cond(cc); tab; reg(d); Ch(","); reg(g); Ch(","); int(e+d MOD 2 * 16); Ch(","); int(c+b MOD 2 * 16); 
						END;
					ELSE
						word(name1, 0)	(* undef *)
					END;
				ELSE
					word(name1, (b MOD 2) + 1); cond(cc);	(*ldr, str *)
					IF ODD(b DIV 4) THEN byte ELSE Ch(" ") END; 
					IF ~ODD(a) & ODD(b DIV 2) THEN (* postindex & writeback *) Ch("T") ELSE Ch(" ") END;
					Str("   "); tab;
					reg(d); Ch(",");Ch("[");
					reg(c); IF ~ODD(a) THEN Ch("]") END; Ch(",");
					IF ODD(b DIV 8) THEN Ch("+"); sign:=1 ELSE Ch("-"); sign:=-1 END;
					IF (a < 6) THEN (* immidiate data transfer*)
						imm(e*100H + f*10H + g, 0);
					ELSE	(* reg data transfer *)
						sign:=0;
						reg(g); Ch(" "); rot(f, e) 
					END;
					IF ODD(a) THEN Ch("]") END;
					IF ODD(a) & ODD(b DIV 2) THEN (*preindexed & writeback *) Ch("!") END;
					IF (c=15) & (sign#0) THEN PCRelAddr(adr,sign,e*100H + f*10H + g) END;
				END
			| 8, 9: (* ldm, stm *)
				word(name1, (b MOD 2) + 3); 
				IF b >= 8 THEN Ch("I") ELSE Ch("D") END;
				IF ODD(a) THEN Ch("B") ELSE Ch("A") END;
				cond(cc);
				Str("   "); tab;
				reg(c); IF ODD(b DIV 2) THEN Ch("!") END; Ch(","); Ch(" ");
				Ch("{");
				regset := SYSTEM.VAL(SET, d*1000H + e*100H + f*10H +g);
				FOR i := 0 TO 15 DO
					IF i IN regset THEN reg(i); Ch(" "); END;
				END;
				Ch("}");
				IF ODD(b DIV 4) THEN Ch("^") END
			| 0AH: word(branch, cc); Str("   "); tab; tab; (* branch *)
					INC( adr, SYSTEM.LSH((((((b*10H + c)*10H + d)*10H + e)*10H + f)*10H +g)+2, 8) DIV 64);
					ASSERT(adr>=0, 72);
					IF (label[ adr DIV 4]#0) THEN Texts.Write(W, "L"); Texts.WriteInt(W, label[adr DIV 4], 0); Texts.Write(W, " ") END;
					imm(adr , 0); 
			| 0BH: word2(branchl, cc); Str("  "); tab; tab; (* branch link*)
					INC( adr, SYSTEM.LSH((((((((b-b)*10H + c-c)*10H + d)*10H + e)*10H + f)*10H +g)+2) , 16) DIV (64*256));
					ASSERT(adr>=0, 73);
					IF label[ adr DIV 4]<0 THEN  Texts.WriteString(W, proc[-label[adr DIV 4]-1]); Texts.Write(W, " ") END;
					IF label[ adr DIV 4]>0 THEN  Texts.WriteInt(W, label[adr DIV 4]-1, 0); Texts.Write(W, " ") END;
					imm(adr , 0); 
			| 0CH: (* floating point push/pop*)
				IF (b=1) & (c=0FH) & (d=0) & (e=7) THEN Str( "XTRAP"); cond(cc); Str("   "); tab; int( f*16 +g);
				ELSE
					word(cptnf, b MOD 2 + 2); Str("   "); tab; tab;
					freg(d); Ch(","); Ch(" "); Ch("["); f := (f*10H+ g) * 4;
(*					IF c = 13 THEN c := 15; (*correction of pc relative index, due to emulation hacks*)
						DEC(f, 4)
					END;*)
					reg(c); Ch("]"); Ch(",");
					IF ODD(b DIV 8) THEN Ch("+") ELSE Ch("-") END; imm(f, 0);
				END;
			| 0DH: (* floating point ldc/stc*)
				word(cptnf, b MOD 2); Str("   "); tab; tab;
				freg(d); Ch(","); Ch(" "); Ch("["); f := ( f*10H+g) * 4;
(*				IF c = 13 THEN c := 15; (*correction of pc relative index, due to emulation hacks*)
					DEC(f, 4)
				END;*)
				reg(c); Ch(",");
				IF ODD(b DIV 8) THEN Ch("+") ELSE Ch("-") END; imm(f, 0);
				Ch("]");
			| 0EH:
				IF (e = 1) & (f = 0) THEN 	(* floating operation *)
					b := b + d DIV 8 * 8; d := d MOD 8;
					word(dfloat, b ); Str("   "); tab; tab;
					IF b < 5 THEN freg(d); Ch(","); freg(c); Ch(","); freg(g)
					ELSIF b <= 10 THEN freg(d); Ch(","); freg(g)
					END
				ELSIF (e = 1) & (f =1) THEN
					word(mfloat, b ); Str("   "); tab; tab;
					IF b = 0 THEN  freg(c); Ch(","); reg(d)
					ELSIF b = 1 THEN  reg(d); Ch(","); freg(g)
					ELSIF b = 2 THEN reg(d); Ch(","); freg(g)
					ELSIF b = 3 THEN freg(c); Ch(","); reg(d)
					ELSIF b = 9 THEN freg(c); Ch(","); freg(g)
					END
				ELSIF e DIV 2=5 THEN
					IF b=0 THEN Str("VMOVV ");
					ELSIF b=1 THEN Str("VMOVA ");
					ELSIF b=2 THEN Str("VMUL  ");
					ELSIF b=3 THEN
						IF f=0 THEN Str("VADD  ");
						ELSIF f=4 THEN Str("VSUB  ");
						END;
					ELSIF b=8 THEN Str("VDIV  ");
					ELSIF b=0BH THEN
						IF c=0 THEN Str("VABS  ");
						ELSIF c=1 THEN Str("VNEG  ");
						ELSIF c=4 THEN Str("VCMP  ");
						ELSE Str("VCVT?  ");
						END;
					ELSIF b=0FH THEN Str("VMRS  ");
					ELSE Str("VFP??  ");
					END;
					tab; tab; freg(d); Ch(",");freg(c); Ch(","); freg(g);
				ELSE	(* mrc/ mcr *)
					word(cptnf, 2 + b MOD 2); cond(cc); Ch(" "); tab; tab;
					IF ODD(b) THEN reg(d); Ch(","); Ch("#"); imm(e, 0); Ch("-"); reg(c); Ch(","); imm(f*10H +g, 0); Ch(" ") 
					ELSE Ch("#"); imm(e, 0); Ch("-"); reg(c); Ch(","); imm(f*10H +g, 0); Ch(" "); Ch(","); reg(d);
					END
				END
			| 0FH: (* SWI *)
				word(name1,7); cond(cc); Ch(" "); tab; tab; Hex(b*100000H + c*10000H + d*1000H + e*100H + f*10H +g);
		END
	END decode;

	PROCEDURE MkLabels;
	VAR pc, instr, targ: LONGINT;
	BEGIN
		pc:=0;
		WHILE pc< codesize DO
			instr:= ASH(code[pc], -24) MOD 10H;
			IF instr=0AH THEN (* branch instructions *)
				targ:= pc+2+ASH( SYSTEM.LSH( code[pc], 8), -8);
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
		IF S.class = 3 THEN decode(0, S.i); Texts.Append(Oberon.Log, W.buf) END
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
		CONST MOVW= 0E3000000H; MOVT= 0E3400000H;
		VAR x, y: INTEGER;
			v: Viewers.Viewer; S: Texts.Scanner;
			f: Files.File; nameObj, nameDec, dummy: Name;
			c, offset, L, L1, cd: LONGINT;
			tag, i: INTEGER;
	BEGIN
		dir:="armv7/";
		fileTag:=Taga;
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
						L1 := L;
						IF (L >= codesize - 1) OR (L<0) THEN
							Texts.WriteString(W, "******* Link chain error at "); WriteHex(L1*4, 5);
							Texts.WriteString(W, " starting from "); WriteHex(4*datalinks[i], 5);
							Texts.WriteLn(W); Texts.Append(T, W.buf);
						ELSE
							c := code[L1]; offset := code[L1+1];
							L := L1 + ASH( SYSTEM.LSH(c, 16), -16) + 1;
							code[L1] :=  MOVW+offset DIV IMM12 MOD 10H*IMM16+ c DIV IMM16 MOD 10H*IMM12+offset MOD IMM12;
							code[L1+1] := MOVT+offset DIV IMM28 MOD 10H*IMM16+ c DIV IMM16 MOD 10H*IMM12+offset DIV IMM16 MOD IMM12;
						END
					UNTIL L = L1
				END ;
				INC(i)
			END ;
			Texts.WriteString(W, "code:   (pos "); Texts.WriteInt(W, codepos, 0);
			Texts.Write(W, ")"); Texts.WriteLn(W); Texts.Append(T, W.buf);
			MkLabels;
			pc := 0;
			WHILE pc < codesize DO
				cd:=code[pc]; WriteHex(pc*4, 5); FixHex(cd); Texts.Write(W, " ");
				IF label[pc] < 0 THEN Texts.WriteString(W, proc[-label[pc]-1]); Texts.Write(W, " ");
				ELSIF label[pc] = 0 THEN Texts.WriteString(W, "                 ")
				ELSE Texts.WriteString(W, "           L"); Texts.WriteInt(W, label[pc], 0);
					IF label[pc] < 10 THEN Texts.WriteString(W, "    ")
					ELSIF label[pc] < 100 THEN Texts.WriteString(W, "   ")
					ELSIF label[pc] < 1000 THEN Texts.WriteString(W, "  ")
					ELSE Texts.Write(W, " ")
					END
				END;
(*				IF pc*4=nextStart THEN Ln; TF; Str("Procedure "); Str(nextProc); Str(":"); DF; Ln; GetProcName(nextProc,nextStart) END;*)
				decode(pc*4, cd); Ln; INC(pc);
			 END;
		ELSE Texts.WriteString(W, "not an ARMv7 object file"); Texts.WriteLn(W); 
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
		WHILE pc < codesize DO decode(pc*4, code[pc]); INC(pc) END ;
		Texts.Append(T, W.buf);
		Files.Close(f)
	END Bin;

BEGIN
	Texts.OpenWriter(W); Texts.SetFont(W, Fonts.This("Courier10.Scn.Fnt"));
	CC := "EQ NE CS CC MI PL VS VC HI LS GE LT GT LE    NV";	
	name0 := "AND EOR SUB RSB ADD ADC SBC RSC TST TEQ CMP CMN OR  MOV BIC MVN MUL MLA ";
	name1 := "UDF STR LDR STM LDM B   BL  SWI";
	branch := "BEQ BNE BCS BCC BMI BPL BVS BVC BHI BLS BGE BLT BGT BLE B   BNV ";
	branchl := "BLEQBLNEBLCSBLCCBLMIBLPLBLVSBLVCBLHIBLLSBLGEBLLTBLGTBLLEBL  BLNV";
	dfloat := "ADF MUF SUF ??? DVF ??? ??? ??? MVF MNF ABF";
	mfloat := "FLT FIX UPK PCK ??? ??? ??? ??? ??? CMF";
	cptnf := "STC LDC PSH POP MCR MRC ";
	tnf := "MRS MSR";
	bnf :="    BX  1234BLX ";
	Psr := "CPSRcnt CPSRflg CPSRall SPSRcnt SPSRflg SPSRall     ";
	Reg := "R0 R1 R2 R3 R4 R5 R6 R7 R8 R9 RA RB FP SP LR PC ";
	FReg := "F0 F1 F2 F3 F4 F5 F6 F7 F8 F9 FA FB FC FD FE FF ";
	Rot:= "LSL LSR ASR ROR ";
	halfword:="??H SBSH"; 

END A32Decoder.
