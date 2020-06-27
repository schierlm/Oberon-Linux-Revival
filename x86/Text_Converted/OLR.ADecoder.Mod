MODULE ADecoder;   (*ms 30.06.97 / as 24.11.98 *)
(*
	peter matthias
	2014-04-18	added Trap in extCallFixlist
	2015-04-08	using "arm/" directory
	2015-06-07	added SDIV, UDIV mnemonic

*)

	IMPORT Files, Texts, Oberon, MenuViewers, TextFrames, Fonts, SYSTEM, OBM, Out;
	
	VAR
		W: Texts.Writer; 
		txt: Texts.Text;
		name0, name1, branch, branchl, dfloat, mfloat, cptnf, tnf, CC, Rot, Psr, Reg, FReg: ARRAY 128 OF CHAR;
		halfword: ARRAY 16 OF CHAR; 
		defaultFont, titleFont: Fonts.Font;
		code : ARRAY 20000 OF LONGINT;
		strings : ARRAY 20000 OF CHAR;

	PROCEDURE TF;
	BEGIN Texts.SetFont(W,titleFont);
	END TF;
	
	PROCEDURE DF;
	BEGIN Texts.SetFont(W,defaultFont);
	END DF;
		
	PROCEDURE Ch(ch: CHAR);
	BEGIN Texts.Write(W, ch)
	END Ch;

	PROCEDURE Str(s: ARRAY OF CHAR);
	BEGIN Texts.WriteString(W, s)
	END Str;
	
	PROCEDURE Int(i: LONGINT);
	BEGIN Texts.WriteInt(W, i, 0)
	END Int;
	
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
		Texts.Write(W, FReg[n]); Texts.Write(W, FReg[n + 1]); Texts.Write(W, FReg[n + 2]);
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
		tab; tab; Str("( = "); Int((adr+8)+sign*ofs); Str(" (");  FixHex((adr+8)+sign*ofs); Str("H)  )");
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
				ELSIF (a = 1) & ((b = 2) OR (b = 6) OR (b = 0) OR (b = 4)) OR (a = 3)&((b = 2) OR (b = 6)) THEN(* msr /mrs *)
					word(tnf, b DIV 2 MOD 2); cond(cc); Ch(" "); tab; tab;
					IF (b = 0) OR (b = 4) THEN reg(d); Ch(","); psr(b DIV 4, 9)
					ELSE psr(b DIV 4, c); Ch(",");
						IF a = 3 THEN imm(f*10H + g, e) ELSE reg(g) END
					END
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
				END	
			| 4..7: (*ldr, str *)
				IF (a >= 6) & ODD(f) THEN
					IF (a=7) & (b=1) THEN
						Str("SDIV    "); cond(cc); tab; reg(c); Ch(","); reg(g); Ch(","); reg(e);
					ELSIF (a=7) & (b=3) THEN
 						Str("UDIV    "); cond(cc); tab; reg(c); Ch(","); reg(g); Ch(","); reg(e);
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
					imm(adr +  8 + ASH(b*10000000H + c*1000000H + d*100000H + e*10000H + f*1000H +g*100H, -6 ), 0)
			| 0BH: word2(branchl, cc); Str("  "); tab; tab; (* branch link*)
					imm(adr +  8 + ASH(b*10000000H + c*1000000H + d*100000H + e*10000H + f*1000H +g*100H, -6 ), 0)
			| 0CH: (* floating point push/pop*)
				word(cptnf, b MOD 2 + 2); Str("   "); tab; tab;
				freg(d); Ch(","); Ch(" "); Ch("["); f := (f*10H + g) * 4;
				IF c = 13 THEN c := 15; (*correction of pc relative index, due to emulation hacks*)
					DEC(f, 4)
				END;
				reg(c); Ch("]"); Ch(",");
				IF ODD(b DIV 8) THEN Ch("+") ELSE Ch("-") END; imm(f, 0);
			| 0DH: (* floating point ldc/stc*)
				word(cptnf, b MOD 2); Str("   "); tab; tab;
				freg(d); Ch(","); Ch(" "); Ch("["); f := (f*10H + g) * 4;
				IF c = 13 THEN c := 15; (*correction of pc relative index, due to emulation hacks*)
					DEC(f, 4)
				END;
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
	
	PROCEDURE  Decode*;
		VAR s: Texts.Scanner; f: Files.File; r: Files.Rider; text: Texts.Text;
			tag, tag2: CHAR; 
			nofImports, nofEntries, nofPtrs, nofComs, nofRecs : INTEGER;
			datasize, strconstsize, codesize, refpos, key : LONGINT;
			i, x, cd, beg ,end, time, tmp, endPC, mno, pno, cw, ldummy : LONGINT;
			name, modname: ARRAY 32 OF CHAR;
			str : ARRAY 128 OF CHAR;
			V: MenuViewers.Viewer; X, Y, j, dummy : INTEGER; 
			nextProc : ARRAY 128 OF CHAR;
			nextStart : LONGINT;
			
			extcallfixlist, extaddrfixlist, fixlist : LONGINT;

		PROCEDURE GetProcName(VAR str : ARRAY OF CHAR; VAR startPC : LONGINT);
		VAR ch : CHAR; addr : LONGINT;
		BEGIN
			LOOP
				Files.Read(r,ch);
				IF r.eof THEN str[0]:=0X; endPC:=-1; EXIT END;
				IF ch=0F8X THEN Files.ReadNum(r, startPC); Files.ReadString(r,str); EXIT
				ELSE 
					Files.Read(r,ch); IF ch>080X THEN Files.ReadNum(r,addr) (* dim *) END;
					Files.ReadNum(r,addr); Files.ReadString(r,str)
				END
			END
		END GetProcName;
		
		PROCEDURE Expect(tag : CHAR) : BOOLEAN;
		VAR ch : CHAR;
		BEGIN
			Files.Read(r,ch); 
			IF ch#tag THEN Out.String("corrupt object file"); Out.Ln END;
			RETURN tag=ch;
		END Expect;
		
	BEGIN
		Texts.OpenScanner(s, Oberon.Par.text, Oberon.Par.pos); Texts.Scan(s);
		IF (s.class = Texts.Char) & (s.c = "^") THEN
			Oberon.GetSelection(text, beg, end, time);
			IF time>=0 THEN Texts.OpenScanner(s, text, beg); Texts.Scan(s) ELSE s.class := Texts.Inval END
		ELSIF ~(s.class IN {Texts.Name, Texts.String}) OR (s.line # 0) THEN s.class := Texts.Inval;
		END;
		IF s.class = Texts.Name THEN
			i := 0; WHILE (s.s[i] # 0X) & (s.s[i] # ".") DO INC(i) END;
			s.s[i] := 0X;
			OBM.prefix:="arm/";

			OBM.MakeFileName(s.s, name, OBM.OFext);
(*
			i:=0;
			WHILE name[i]#0X DO INC(i) END;
			WHILE i>=0 DO
				name[i+4]:= name[i];
				DEC(i);
			END;
			name[0]:="a";
			name[1]:="r";
			name[2]:="m";
			name[3]:="/";
*)
			f := Files.Old(name);
			IF f # NIL THEN Files.Set(r, f, 0);

				TF; Str("Object file dump"); DF; Ln; Ln;
				
			(* header *)
				Files.Read(r, tag); Files.Read(r,tag2); 
				Files.ReadLInt(r,refpos);
				Files.ReadLInt(r,x); (* module body entry point *)
				Files.ReadInt(r,nofImports);
				Files.ReadInt(r,nofEntries);
				Files.ReadInt(r,nofPtrs);
				Files.ReadInt(r,nofComs);
				Files.ReadLInt(r,strconstsize);
				Files.ReadLInt(r,datasize);
				Files.ReadLInt(r,codesize);
				Files.ReadInt(r,nofRecs);
				Files.ReadLInt(r,key);
				Files.ReadString(r,modname);
							
				OBM.MakeFileName(modname, name, ".Dec");
				OBM.prefix:="";
(*
			i:=0;
			WHILE name[i]#0X DO INC(i) END;
			WHILE i>=0 DO
				name[i+4]:= name[i];
				DEC(i);
			END;
			name[0]:="a";
			name[1]:="r";
			name[2]:="m";
			name[3]:="/";
*)
				TF; Str("Name: "); DF; Str(modname); tab;
				TF; Str("Tag: "); DF; Int(ORD(tag)); Ch(" "); Int(ORD(tag2)); tab;
				TF; Str("Key: "); DF; FixHex(key);Ln;Ln;
	
				TF; Str("Code size: "); DF; Int(codesize); tab;
				TF; Str("Var size: ");  DF; Int(datasize); tab;
				TF; Str("Strconst size: "); DF; Int(strconstsize); tab;
				TF; Str("Entries: "); DF; Int(nofEntries); tab;
				TF; Str("Pointers: "); DF; Int(nofPtrs); tab;
				TF; Str("TDescs: "); DF; Int(nofRecs); tab;
				TF; Str("Imports: "); DF; Int(nofImports); Ln;
				Ln;

			(* Import block *)
				IF ~Expect(085X) THEN RETURN END;
				TF; Str("Imports:"); DF; Ln;
				FOR i:=0 TO nofImports-1 DO
					Files.ReadLInt(r,key); Files.ReadString(r,modname);
					tab; FixHex(key); Ch(" "); Str(modname); Ln
				END; Ln;
				
			(* entry block *)
				IF ~Expect(082X) THEN RETURN END;
				TF; Str("Entries: "); DF; Ln;
				FOR i:=0 TO nofEntries-1 DO
					Files.ReadLInt(r, x); 
					tab; Int(i); FixHex(x*4); Ln
				END; Ln;
			
			(* pointer block *)
				IF ~Expect(084X) THEN RETURN END;
				TF; Str("Pointers: "); DF; Ln; tab;
				i:=0;
				WHILE i<nofPtrs DO
					Files.ReadLInt(r,x); Hex(x); Str("  ");
					INC(i); 
					IF (i MOD 5 = 0) OR (i = nofPtrs) THEN Ln; tab END
				END; Ln;
								
			(* command block *)
				IF ~Expect(083X) THEN RETURN END;
				TF; Str("Commands: "); DF; Ln;
				i:=0;
				WHILE i<nofComs DO
					Files.ReadString(r,str); Files.ReadLInt(r,x); INC(i);
					tab; FixHex(x); tab; Str(str); Ln
				END; Ln;		
			
			(* code & string consts block & fixups*)
				IF ~Expect(088X) THEN RETURN END;
				Files.ReadBytes(r,code,codesize);
				IF ~Expect(087X) THEN RETURN END;
				Files.ReadBytes(r,strings,strconstsize);
				IF ~Expect(086X) THEN RETURN END;
				Files.ReadLInt(r,extcallfixlist); extcallfixlist:=extcallfixlist DIV 4;
				Files.ReadLInt(r,extaddrfixlist); extaddrfixlist:=extaddrfixlist DIV 4;
				Files.ReadLInt(r,fixlist); fixlist:=fixlist DIV 4;

			(* tdesc block *) 
				IF ~Expect(089X) THEN RETURN END; 
				TF; Str("Tags: "); DF; Ln;
				FOR i:=0 TO nofRecs-1 DO
					Files.ReadLInt(r,x); 
					Files.ReadInt(r,dummy); (* nofPtrs *)
					Files.ReadLInt(r,ldummy); (* Record size *)
					Files.ReadString(r,str); (* name *)
					Files.Read(r,tag); (* nr of basetypes *)
					FOR j:=0 TO ORD(tag)-1 DO Files.ReadLInt(r,ldummy) END;
					FOR j:=0 TO dummy-1 DO Files.ReadLInt(r,ldummy) END;
					tab; Hex(x); Str("  tag for "); Str(str); Ln;
				END; Ln;	
								
				TF; Str("Extern Call Fixlist:"); DF; Ln;
				i:=0;
				WHILE extcallfixlist#0 DO 
					cw:=code[extcallfixlist];
					mno:=cw DIV 100H MOD 100H(*32*);
					pno:=cw MOD 100H;
					tab; FixHex(extcallfixlist*4); Str("  ");
					IF mno=0 THEN
						CASE pno OF
							0: Str("NEW (Record)")
							|1: Str("SYSTEM.NEW")
							|2: Str("NEW (Array)")
							|3: Str("DivMod")
						ELSE
							Str("Trap")
						END
					ELSE
						Str("Mod "); Int(mno); Str("  Entry "); Int(pno)
					END;
					Ln;
					code[extcallfixlist]:=0EB000000H + mno*100H + pno;	(*always BL*)
					(*code[extcallfixlist]:=cw DIV 10000000H * 10000000H + 11*1000000H + mno*100H + pno;*)
					extcallfixlist:=SYSTEM.LSH(cw,-17(*-13*)) MOD 8000H;
 				END; 
				IF i MOD 9 # 1 THEN Ln END;
				Ln;
				
				TF; Str("Extern Addr Fixlist:"); DF; Ln;
				i:=0;
				WHILE extaddrfixlist#0 DO
					cw:=code[extaddrfixlist];
					mno:=cw DIV 100H MOD 100H(*32*);
					pno:=cw MOD 100H;
					tab; FixHex(extaddrfixlist*4); Str("  Mod "); Int(mno); Str("  Entry "); Int(pno); Ln;
					extaddrfixlist:=SYSTEM.LSH(cw,-17) MOD 8000H
				END;
				IF i MOD 9 # 1 THEN Ln END;
				Ln;

				TF; Str("Fixlist:"); DF;
				i:=0;
				(* Do Code Fixups *)				
				WHILE fixlist#0 DO
					IF i MOD 9 = 0 THEN Ln; tab END; INC(i);
					tmp:=SYSTEM.LSH(code[fixlist],-17) MOD 8000H; 
					FixHex(fixlist*4); code[fixlist]:=code[fixlist] MOD 20000H; fixlist:=tmp;
				END;				
				IF i MOD 9 # 1 THEN Ln END;
				Ln;
				
				TF; Str("Code:"); DF; Ln;
				Files.Set(r,f,2); Files.ReadLInt(r,x); Files.Set(r,f,x+1); 
				GetProcName(nextProc,nextStart);
				i := 0;
				WHILE i<codesize DIV 4 DO
					IF i*4=nextStart THEN Ln; TF; Str("Procedure "); Str(nextProc); Str(":"); DF; Ln; GetProcName(nextProc,nextStart) END;
					cd:=code[i]; FixHex(i*4); tab; FixHex(cd); tab; decode(i*4, cd); Ln; INC(i);
				END;
				Ln;
				
				TF; Str("String Constants :"); DF; Ln;
				i:=0;
				WHILE (i<strconstsize) DO
					FixHex(i+codesize); tab; Ch(CHR(34)); WHILE strings[i]#0X DO Ch(strings[i]); INC(i) END; Ch(CHR(34)); Ln; INC(i);
					i:=(i+3) DIV 4 * 4
				END;
				
				NEW(txt); Texts.Open(txt,""); 
				Texts.Append(txt, W.buf); 			
				Oberon.OpenText(name, txt, 600, 300);
			ELSE Out.String(name); Out.String(" not found"); Out.Ln; 
			END
		ELSE Out.String("no module name"); Out.Ln;
		END
	END Decode;
	
BEGIN
	Texts.OpenWriter(W); Str("Decoder, ms 20.06.97 / as 2.12.98"); Ln; Texts.Append(Oberon.Log, W.buf);
	defaultFont:=Fonts.This("Courier10.Scn.Fnt");
	titleFont:=Fonts.This("Oberon12b.Scn.Fnt");
	CC := "EQ NE CS CC MI PL VS VC HI LS GE LT GT LE    NV";	
	name0 := "AND EOR SUB RSB ADD ADC SBC RSC TST TEQ CMP CMN OR  MOV BIC MVN MUL MLA ";
	name1 := "UDF STR LDR STM LDM B   BL  SWI";
	branch := "BEQ BNE BCS BCC BMI BPL BVS BVC BHI BLS BGE BLT BGT BLE B   BNV ";
	branchl := "BLEQBLNEBLCSBLCCBLMIBLPLBLVSBLVCBLHIBLLSBLGEBLLTBLGTBLLEBL  BLNV";
	dfloat := "ADF MUF SUF ??? DVF ??? ??? ??? MVF MNF ABF";
	mfloat := "FLT FIX UPK PCK ??? ??? ??? ??? ??? CMF";
	cptnf := "STC LDC PSH POP MCR MRC ";
	tnf := "MRS MSR";
	Psr := "CPSRcnt CPSRflg CPSRall SPSRcnt SPSRflg SPSRall     ";
	Reg := "R0 R1 R2 R3 R4 R5 R6 R7 R8 R9 RA RB FP SP LR PC ";
	FReg := "F0 F1 F2 F3 F4 F5 F6 F7 F8 F9 FA FB FC FD FE FF ";
	Rot:= "LSL LSR ASR ROR ";
	halfword:="??H SBSH"; 
END ADecoder.

