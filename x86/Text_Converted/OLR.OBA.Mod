(*
	Peter Matthias

	2015-06-07: OLR.OBA.Mod: added SDIV, UDIV Mnemonics; removed Strings import

*)

MODULE OBA; (* Andreas Signer *)

(* This modules contains all assembler related stuff *)

IMPORT
	SYSTEM, OC := OBM, OBS, OBC, OBT;

CONST
	clsReg = 0;  clsShift = 3;  clsPSR = 4; clsPSRFields = 5;
	
	maxMnemonics = 1300;
	maxSyms = 256;
	maxLabels = 128;
		
	(*symbol values*)
	mnemo = 100; asmSym = 101; char = 102;

TYPE
	ArgHandler = PROCEDURE():LONGINT;
	
	Mnemonic = RECORD
			name : ARRAY 8 OF CHAR;
			opCode : LONGINT;
			arg : ARRAY 6 OF ArgHandler
		END;
		
	Sym = RECORD
			name : ARRAY 5 OF CHAR;
			class : INTEGER; (* Reg, PSR, PSRFields *)
			a : LONGINT
		END;

	Label = RECORD
			name : ARRAY 128 OF CHAR;
			a,l : LONGINT
		END;
		
VAR
	mnemoTab : ARRAY maxMnemonics OF Mnemonic;
	symTab : ARRAY maxSyms OF Sym;
	labelTab : ARRAY maxLabels OF Label;
	
	symCnt, mnemoCnt, labelCnt : INTEGER;

	sym : INTEGER;
		
PROCEDURE EnterSym(name : ARRAY OF CHAR; class : INTEGER; a : LONGINT);
BEGIN
	IF symCnt=maxSyms THEN HALT(99) END;
	COPY(name,symTab[symCnt].name); symTab[symCnt].class:=class; symTab[symCnt].a:=a;
	INC(symCnt);
END EnterSym;

PROCEDURE EnterMnemo(name : ARRAY OF CHAR; opCode : LONGINT; a0,a1,a2,a3,a4,a5 : ArgHandler);
BEGIN
	IF mnemoCnt=maxMnemonics THEN HALT(98) END;
	COPY(name,mnemoTab[mnemoCnt].name);
	mnemoTab[mnemoCnt].opCode:=opCode;
	mnemoTab[mnemoCnt].arg[0]:=a0; mnemoTab[mnemoCnt].arg[1]:=a1; mnemoTab[mnemoCnt].arg[2]:=a2;
	mnemoTab[mnemoCnt].arg[3]:=a3; mnemoTab[mnemoCnt].arg[4]:=a4; mnemoTab[mnemoCnt].arg[5]:=a5;
	INC(mnemoCnt)
END EnterMnemo;

PROCEDURE EnterDirective(name : ARRAY OF CHAR; a : ArgHandler);
BEGIN
	IF mnemoCnt=maxMnemonics THEN HALT(98) END;
	COPY(name,mnemoTab[mnemoCnt].name);
	mnemoTab[mnemoCnt].opCode:=-1;
	mnemoTab[mnemoCnt].arg[0]:=a; mnemoTab[mnemoCnt].arg[1]:=NIL; mnemoTab[mnemoCnt].arg[2]:=NIL;
	mnemoTab[mnemoCnt].arg[3]:=NIL; mnemoTab[mnemoCnt].arg[4]:=NIL; mnemoTab[mnemoCnt].arg[5]:=NIL;
	INC(mnemoCnt)
END EnterDirective;

(* Append this to to. *)
	PROCEDURE Append(VAR to(** in/out *): ARRAY OF CHAR; this: ARRAY OF CHAR);
		VAR i, j, l: LONGINT;
	BEGIN
		i := 0;
		WHILE to[i] # 0X DO
			INC(i)
		END;
		l := LEN(to)-1; j := 0;
		WHILE (i < l) & (this[j] # 0X) DO
			to[i] := this[j]; INC(i); INC(j)
		END;
		to[i] := 0X
	END Append;


PROCEDURE EnterMnemonic(name, suffix : ARRAY OF CHAR; opCode : LONGINT; a0,a1,a2,a3,a4,a5 : ArgHandler);
VAR s : ARRAY 8 OF CHAR;
BEGIN
	COPY(name,s); Append(s,"EQ"); Append(s,suffix); EnterMnemo(s,opCode+00000000H,a0,a1,a2,a3,a4,a5);
	COPY(name,s); Append(s,"NE"); Append(s,suffix); EnterMnemo(s,opCode+10000000H,a0,a1,a2,a3,a4,a5);
	COPY(name,s); Append(s,"CS"); Append(s,suffix); EnterMnemo(s,opCode+20000000H,a0,a1,a2,a3,a4,a5);
	COPY(name,s); Append(s,"CC"); Append(s,suffix); EnterMnemo(s,opCode+30000000H,a0,a1,a2,a3,a4,a5);
	COPY(name,s); Append(s,"MI"); Append(s,suffix); EnterMnemo(s,opCode+40000000H,a0,a1,a2,a3,a4,a5);
	COPY(name,s); Append(s,"PL"); Append(s,suffix); EnterMnemo(s,opCode+50000000H,a0,a1,a2,a3,a4,a5);
	COPY(name,s); Append(s,"VS"); Append(s,suffix); EnterMnemo(s,opCode+60000000H,a0,a1,a2,a3,a4,a5);
	COPY(name,s); Append(s,"VC"); Append(s,suffix); EnterMnemo(s,opCode+70000000H,a0,a1,a2,a3,a4,a5);
	COPY(name,s); Append(s,"HI"); Append(s,suffix); EnterMnemo(s,opCode+80000000H,a0,a1,a2,a3,a4,a5);
	COPY(name,s); Append(s,"LS"); Append(s,suffix); EnterMnemo(s,opCode+90000000H,a0,a1,a2,a3,a4,a5);
	COPY(name,s); Append(s,"GE"); Append(s,suffix); EnterMnemo(s,opCode+0A0000000H,a0,a1,a2,a3,a4,a5);
	COPY(name,s); Append(s,"LT"); Append(s,suffix); EnterMnemo(s,opCode+0B0000000H,a0,a1,a2,a3,a4,a5);
	COPY(name,s); Append(s,"GT"); Append(s,suffix); EnterMnemo(s,opCode+0C0000000H,a0,a1,a2,a3,a4,a5);
	COPY(name,s); Append(s,"LE"); Append(s,suffix); EnterMnemo(s,opCode+0D0000000H,a0,a1,a2,a3,a4,a5);
	COPY(name,s); Append(s,"AL"); Append(s,suffix); EnterMnemo(s,opCode+0E0000000H,a0,a1,a2,a3,a4,a5);
	COPY(name,s); Append(s,suffix); EnterMnemo(s,opCode+0E0000000H,a0,a1,a2,a3,a4,a5);
END EnterMnemonic;

PROCEDURE FindMnemo() : INTEGER;
VAR i : INTEGER;
BEGIN
	FOR i:=0 TO mnemoCnt-1 DO
		IF mnemoTab[i].name=OBS.name THEN RETURN i END
	END; 
	RETURN -1
END FindMnemo;

PROCEDURE FindSym() : INTEGER;
VAR i : INTEGER;
BEGIN
	FOR i:=0 TO symCnt-1 DO
		IF symTab[i].name=OBS.name THEN RETURN i END
	END;
	RETURN -1
END FindSym;

PROCEDURE FindLabel() : INTEGER;
VAR i : INTEGER; obj : OBT.Object;
BEGIN
	(* Check in the local label tab *)
	FOR i:=0 TO labelCnt-1 DO
		IF labelTab[i].name=OBS.name THEN RETURN i END
	END;
	
	(* Check symtab. perhaps it's a proc *)
	OBT.Find(obj,i);
	IF (obj=NIL) OR (i#0) THEN RETURN -1 END;
	IF obj.mode=OC.LProc THEN
		(* Insert Label into Label-Tab. Dont use AddLabel! *)
		IF labelCnt=maxLabels THEN OBS.Mark(404); DEC(labelCnt) END;
		COPY(OBS.name,labelTab[labelCnt].name); labelTab[labelCnt].a:=obj.a0; labelTab[labelCnt].l:=0; 
		IF obj.a0=-1 THEN OBS.Mark(415) END;
		INC(labelCnt); 
		RETURN labelCnt-1
	END;
	RETURN -1
END FindLabel;

PROCEDURE AddLabel;
VAR i : INTEGER;
BEGIN
	i:=FindLabel();
	IF i=-1 THEN
		IF labelCnt=maxLabels THEN OBS.Mark(404); DEC(labelCnt) END;
		COPY(OBS.name,labelTab[labelCnt].name); labelTab[labelCnt].a:=OBC.pc; labelTab[labelCnt].l:=0; 
		INC(labelCnt); 
	ELSE
		IF labelTab[i].a#-1 THEN OBS.Mark(403) END;
		labelTab[i].a:=OBC.pc; OBC.FixLink(labelTab[i].l); labelTab[i].l:=0
	END
END AddLabel;

PROCEDURE CheckUndefLabels;
VAR i : INTEGER;
BEGIN
	i:=0;
	LOOP
		IF i=labelCnt THEN EXIT END;
		IF labelTab[i].a=-1 THEN 
			OBS.Mark(411); (*Out.String(labelTab[i].name); Out.String(" undefined"); Out.Ln; *) EXIT END;
		INC(i)
	END
END CheckUndefLabels;

(* ------------------------------------------------------------------------------ *)
(* Scanner *)
(* ------------------------------------------------------------------------------ *)
PROCEDURE Get(VAR sym : INTEGER);
VAR i : INTEGER;
BEGIN
	OBS.Get(sym);
	IF sym=OC.ident THEN
		i:=FindMnemo(); 
		IF i#-1 THEN
			sym:=mnemo; OBS.intval:=i;
		ELSE
			i:=FindSym();
			IF i#-1 THEN sym:=asmSym; OBS.intval:=i END;
		END
	ELSIF (sym=OC.number) & (OBS.numtyp=1) THEN
		sym:=char;
	ELSIF (sym=OC.number) & (OBS.numtyp#2) THEN
		OBS.Mark(401); OBS.numtyp:=2; OBS.intval:=0;
	END
END Get;

PROCEDURE Match(s : INTEGER);
BEGIN
	IF sym = s THEN Get(sym) ELSE OBS.Mark(s) END
END Match;

(* ------------------------------------------------------------------------------ *)
(* Argument Handlers *)
(* ------------------------------------------------------------------------------ *)
PROCEDURE LabelArg() : LONGINT;
VAR res : LONGINT; i : INTEGER;
BEGIN
	IF sym#OC.ident THEN OBS.Mark(402); RETURN 0 END;
	i:=FindLabel(); 
	IF i=-1 THEN (* forward jump (first occurence) *)
		IF OBC.pc=0 THEN 
			(* A fixlist entry at 0 will corrupt the fixlist, so we have to emit a NOP *)
			OBC.PutDP(OBC.MOV,0,0,0,0)
		END;
		AddLabel; i:=FindLabel(); labelTab[i].l:=OBC.pc; labelTab[i].a:=-1;
		res := 0;
	ELSIF labelTab[i].a=-1 THEN 
		res := labelTab[i].l; labelTab[i].l:=OBC.pc;
	ELSE 
		res:=(labelTab[i].a-(OBC.pc+2)) MOD 1000000H;
	END;
	Get(sym);
	RETURN res;
END LabelArg;

PROCEDURE Reg() : LONGINT;
VAR res : LONGINT; 
BEGIN
	IF (sym#asmSym) OR (symTab[OBS.intval].class#clsReg) THEN OBS.Mark(405); res:=0 
	ELSE res:=symTab[OBS.intval].a
	END;
	Get(sym);
	RETURN res
END Reg;

PROCEDURE Reg8() : LONGINT;
BEGIN
	RETURN Reg()*100H
END Reg8;

PROCEDURE Reg12() : LONGINT;
BEGIN
	RETURN Reg()*1000H
END Reg12;

PROCEDURE Reg16() : LONGINT;
BEGIN
	RETURN Reg()*10000H
END Reg16;

PROCEDURE Reg16W() : LONGINT;
VAR res : LONGINT;
BEGIN
	res:=Reg16();
	IF sym=OC.exclamation THEN Get(sym); res:=res+200000H END;
	RETURN res
END Reg16W;

PROCEDURE RegInd16() : LONGINT;
VAR res : LONGINT;
BEGIN
	Match(OC.lbrak);
	res:=Reg16();
	Match(OC.rbrak);
	RETURN res
END RegInd16;

PROCEDURE RegListS() : LONGINT;
VAR res : LONGINT; one : LONGINT;
BEGIN
	res:=0; one:=1;
	Match(OC.lbrace);
	IF sym=asmSym THEN
		IF symTab[OBS.intval].class#clsReg THEN OBS.Mark(405);
		ELSE res:=res + SYSTEM.LSH(one,symTab[OBS.intval].a); Get(sym)
		END;
		WHILE sym=OC.comma DO
			Get(sym);
			IF (sym#asmSym) OR (symTab[OBS.intval].class#clsReg) THEN OBS.Mark(405)
			ELSE res:=res + SYSTEM.LSH(one,symTab[OBS.intval].a); Get(sym)
			END
		END
	END;
	Match(OC.rbrace);
	IF sym=OC.arrow THEN Get(sym); res:=res+400000H END;
	RETURN res
END RegListS;
	
PROCEDURE Oprnd2() : LONGINT;
VAR rm, shift, shiftop, imm, rot, res : LONGINT;
BEGIN
	res:=0;
	IF sym=OC.number THEN (* 32-bit unsigned imm *)
		imm:=OBS.intval; Get(sym);
		IF OBC.DecomposeConst(imm,imm,rot) THEN res:=rot*256+imm+2000000H;
		ELSE OBS.Mark(406); res:=0
		END;
	ELSIF (sym=asmSym) & (symTab[OBS.intval].class=clsReg) THEN
		rm:=symTab[OBS.intval].a; Get(sym);
		IF sym=OC.comma THEN
			Get(sym);
			IF (sym=asmSym) & (symTab[OBS.intval].class=clsShift) THEN
				shiftop:=symTab[OBS.intval].a; Get(sym);
				IF shiftop#4 THEN (* #RRX *) 
					IF sym=OC.number THEN (* Rm SHIFT #imm *)
						shift:=OBS.intval; Get(sym);
						CASE shiftop OF
							0 : (* LSL *)
								IF (shift<0) OR (shift>=32) THEN OBS.Mark(408); shift:=0 END;
							|1, 2 : (* LSR, ASR *)
								IF (shift<=0) OR (shift>32) THEN OBS.Mark(408); shift:=1 END; 
								IF shift=32 THEN shift:=0 END; (* xSR #32 wird mir xSR #0 codiert *)
							|3: (* ROR *) 
								IF (shift<=0) OR (shift>=32) THEN OBS.Mark(408); shift:=1 END; 
						END;
						res:=shift*128+shiftop*32+rm;
					ELSIF (sym=asmSym) & (symTab[OBS.intval].class=clsReg) THEN (* Rm SHIFT Rs *)
						shift:=symTab[OBS.intval].a; Get(sym); res:= shift*256+shiftop*32+16+rm; 
					ELSE OBS.Mark(410)
					END
				ELSE (* Rm RRX *)
					res:=3*32+rm; (* wird als ROR #0 codiert! *)
				END
			ELSE OBS.Mark(407)
			END
		ELSE res:=rm
		END
	ELSE OBS.Mark(410)
	END;
	RETURN res
END Oprnd2;

PROCEDURE RegWithShift() : LONGINT;
VAR res, shift, shiftop : LONGINT;
BEGIN
	res:=0;
	Match(OC.comma);
	IF (sym=OC.plus) OR (sym=OC.minus) THEN
		IF sym=OC.plus THEN res:=res+800000H END;
		Get(sym)
	ELSE
		res:=res+800000H
	END;
	IF sym=OC.number THEN
		(* 12bit-immediate plus sign *)
		IF OBS.intval>=4096 THEN OBS.Mark(406); OBS.intval:=0 END;
		res:=res+OBS.intval;
		Get(sym);
		RETURN res
	ELSE
		res:=res+2000000H;
		IF (sym#asmSym) OR (symTab[OBS.intval].class#clsReg) THEN OBS.Mark(405); OBS.intval:=0 END;
		res:=res+symTab[OBS.intval].a; Get(sym);
		IF sym=OC.comma THEN
			Get(sym);
			IF (sym#asmSym) OR (symTab[OBS.intval].class#clsShift) THEN OBS.Mark(407) END;
			shiftop:=symTab[OBS.intval].a; Get(sym);
			IF shiftop=4 THEN (* RRX *)
				res:=res+3*32; (* Wird als ROR #0 codiert! *)
			ELSE
				IF sym#OC.number THEN OBS.Mark(401); OBS.intval:=0 END;
				shift:=OBS.intval; Get(sym); 
				CASE shiftop OF
					1,2: (* LSR, ASR *)
						IF (shift<=0) OR (shift>32) THEN OBS.Mark(408); shift:=0 END;
						IF shift=32 THEN shift:=0 END; (* xSR 32 wird mit xSR 0 codiert *)
					|3: (* ROR *)
						IF (shift<=0) OR (shift>32) THEN OBS.Mark(408); shift:=0 END;
					|0: (* LSL *)
						IF (shift<0) OR (shift>=32) THEN OBS.Mark(408); shift:=0 END;
				END;
				res:=res + shift*128 + shiftop*32
			END
		END
	END;
	RETURN res
END RegWithShift;

PROCEDURE AMode1() : LONGINT;
VAR res : LONGINT;
BEGIN
	Match(OC.lbrak);
	IF (sym#asmSym) OR (symTab[OBS.intval].class#clsReg) THEN OBS.Mark(405); OBS.intval:=0 END;
	res:=symTab[OBS.intval].a * 10000H; Get(sym);
	IF sym=OC.rbrak THEN (* post indexed *)
		Get(sym); res:=res+RegWithShift()
	ELSE (* pre indexed *)
		res:=res+1000000H+RegWithShift();
		Match(OC.rbrak);
		IF sym=OC.exclamation THEN Get(sym); res:=res+200000H END
	END;
	RETURN res
END AMode1;

PROCEDURE AMode2() : LONGINT;
VAR res : LONGINT;
BEGIN
	Match(OC.lbrak);
	IF (sym#asmSym) OR (symTab[OBS.intval].class#clsReg) THEN OBS.Mark(405); OBS.intval:=0; END;
	res:=symTab[OBS.intval].a * 10000H; Get(sym);
	Match(OC.rbrak);
	RETURN res+RegWithShift()
END AMode2;

PROCEDURE AMode3Part2() : LONGINT;
VAR res : LONGINT;
BEGIN
	Match(OC.comma);
	IF sym=OC.minus THEN res:=0 ELSE res:=800000H END;
	IF (sym=OC.plus) OR (sym=OC.minus) THEN Get(sym) END;
	IF sym=OC.number THEN (* 8-bit imm plus sign *)
		res:=res+400000H;
		IF OBS.intval>=256 THEN OBS.Mark(406); OBS.intval:=0 END;
		res:=res+OBS.intval DIV 16 * 256;
		res:=res+OBS.intval MOD 16;
		Get(sym)
	ELSE
		IF (sym#asmSym) OR (symTab[OBS.intval].class#clsReg) THEN OBS.Mark(405); OBS.intval:=0 END;
		res:=res+symTab[OBS.intval].a; Get(sym)
	END;
	RETURN res
END AMode3Part2;

PROCEDURE AMode3() : LONGINT;
VAR res : LONGINT;
BEGIN
	Match(OC.lbrak);
	IF (sym#asmSym) OR (symTab[OBS.intval].class#clsReg) THEN OBS.Mark(405); OBS.intval:=0 END;
	res:=symTab[OBS.intval].a*10000H; Get(sym);
	IF sym=OC.rbrak THEN (* post-indexed *)
		Get(sym); res:=res+AMode3Part2()
	ELSE (* pre-indexed *)
		res:=res+1000000H+AMode3Part2();
		Match(OC.rbrak);
		IF sym=OC.exclamation THEN res:=res+200000H; Get(sym) END
	END;
	RETURN res
END AMode3;

PROCEDURE Imm24() : LONGINT;
VAR res : LONGINT;
BEGIN
	res:=0;
	IF sym#OC.number THEN OBS.Mark(401); 
	ELSE res:=OBS.intval MOD 1000000H
	END;
	Get(sym);
	RETURN res
END Imm24;

PROCEDURE RegOrImm() : LONGINT;
VAR res, rot, imm : LONGINT;
BEGIN
	res:=0;
	IF (sym=asmSym) & (symTab[OBS.intval].class=clsReg) THEN res:=symTab[OBS.intval].a 
	ELSIF sym=OC.number THEN 
		IF OBC.DecomposeConst(OBS.intval,imm,rot) THEN res:=rot*256+imm
		ELSE OBS.Mark(406)
		END
	ELSE OBS.Mark(410)
	END;
	Get(sym);
	RETURN res
END RegOrImm;

PROCEDURE PSR() : LONGINT;
VAR res : LONGINT;
BEGIN
	IF (sym#asmSym) OR (symTab[OBS.intval].class#clsPSR) THEN OBS.Mark(409); OBS.intval:=0 END;
	res:=symTab[OBS.intval].a*400000H;
	Get(sym);
	RETURN res
END PSR;

PROCEDURE PSRFields() : LONGINT;
VAR res : LONGINT;
BEGIN
	IF (sym#asmSym) OR (symTab[OBS.intval].class#clsPSRFields) THEN OBS.Mark(409); OBS.intval:=0 END;
	res:=symTab[OBS.intval].a*10000H;
	Get(sym);
	RETURN res
END PSRFields;

PROCEDURE AddrArgs() : LONGINT; (* Has no return value, but must be compatible with ArgHandler *)
VAR reg, ofs : LONGINT; lev : INTEGER; obj : OBT.Object; 
BEGIN
	reg:=Reg(); Match(OC.comma);
	IF sym#OC.ident THEN OBS.Mark(412) 
	ELSE
		OBT.Find(obj,lev);
		IF obj=NIL THEN OBS.Mark(0)
		ELSIF lev#0 THEN OBS.Mark(413)
		ELSIF ~(obj.mode IN {OC.Var, OC.LProc}) THEN OBS.Mark(414)
		ELSIF (obj.mode=OC.LProc) & (obj.a0=-1) THEN OBS.Mark(415)
		ELSE
			IF obj.mode=OC.LProc THEN ofs:=4*obj.a0 ELSE ofs:=obj.a0 END;
			OBC.FreeRegs(-{reg});
			OBC.PutDP1(OBC.ADD,reg,OBC.PC,ofs - OBC.pc*4 - 8);
			OBC.FreeRegs({})
		END;
		Get(sym)
	END;
	RETURN 0
END AddrArgs;

PROCEDURE DcdArgs() : LONGINT; (* Has no return value, but must be compatible with ArgHandler *)
BEGIN
	LOOP
		IF sym#OC.number THEN OBS.Mark(401); Get(sym); EXIT END;
		OBC.PutWord(OBS.intval); Get(sym);
		IF sym#OC.comma THEN EXIT END;
		Get(sym)
	END;
	RETURN 0
END DcdArgs;

PROCEDURE DcwArgs() : LONGINT; (* Has no return value, but must be compatible with ArgHandler *)
VAR str : ARRAY 512 OF INTEGER; pos, i,l : LONGINT; 
BEGIN
	pos:=0;
	LOOP
		IF sym=OC.number THEN
			IF (OBS.intval>=MIN(INTEGER)) & (OBS.intval<=MAX(INTEGER)) THEN str[pos]:=SHORT(OBS.intval); INC(pos)
			ELSE OBS.Mark(406)
			END
		ELSE OBS.Mark(401); Get(sym); EXIT
		END;
		Get(sym);
		IF sym#OC.comma THEN EXIT END;
		Get(sym)
	END;
	WHILE pos MOD 2 # 0 DO str[pos]:=0; INC(pos) END;
	FOR i:=0 TO (pos DIV 2)-1 DO
		SYSTEM.GET(SYSTEM.ADR(str[i*2]),l); OBC.PutWord(l)
	END;
	RETURN 0
END DcwArgs;

PROCEDURE DcbArgs() : LONGINT; (* Has no return value, but must be compatible with ArgHandler *)
VAR str : ARRAY 512 OF CHAR; pos, i, l : LONGINT;
BEGIN
	pos:=0;
	LOOP
		IF sym=OC.string THEN i:=0; WHILE OBS.name[i]#0X DO str[pos]:=OBS.name[i]; INC(i); INC(pos) END
		ELSIF sym=char THEN str[pos]:=CHR(OBS.intval); INC(pos)
		ELSE OBS.Mark(416); Get(sym); EXIT
		END;
		Get(sym);
		IF sym#OC.comma THEN EXIT END;
		Get(sym)
	END;
	WHILE pos MOD 4#0 DO str[pos]:=0X; INC(pos) END;
	FOR i:=0 TO (pos DIV 4)-1 DO
		SYSTEM.GET(SYSTEM.ADR(str[i*4]),l); OBC.PutWord(l)
	END;
	RETURN 0
END DcbArgs;


(* ------------------------------------------------------------------------------ *)
(* Assembler *)
(* ------------------------------------------------------------------------------ *)
PROCEDURE Assemble*;
VAR i : INTEGER; op,cw : LONGINT;
BEGIN
	labelCnt:=0;
	Get(sym);
	LOOP
		IF sym=OC.end THEN EXIT END;
		WHILE sym=OC.ident DO AddLabel; Get(sym) END;
		IF sym=OC.end THEN EXIT END;
		IF sym#mnemo THEN 
			OBS.Mark(400);
			WHILE (sym#mnemo) & (sym#OC.end) & (sym#OC.eof) DO Get(sym) END;
			IF (sym=OC.end) OR (sym=OC.eof) THEN RETURN END;
		END;
		cw := mnemoTab[OBS.intval].opCode;
		op:=OBS.intval;
		Get(sym); 
		IF cw=-1 THEN (* Directive *)
			IF mnemoTab[op].arg[0]#NIL THEN cw:=mnemoTab[op].arg[0](); END;
		ELSE (* mnemonic *)
			i:=0;
			LOOP
				cw := cw + mnemoTab[op].arg[i](); INC(i);
				IF mnemoTab[op].arg[i]#NIL THEN Match(OC.comma) ELSE EXIT END
			END;
			OBC.PutWord(cw);
		END
	END;
	IF sym#OC.end THEN OBS.Mark(OC.end) END;
	CheckUndefLabels();
END Assemble;

BEGIN
	(* Set up all directives and mnemonics *)
	EnterDirective("ADDR",AddrArgs);
	EnterDirective("DCD",DcdArgs);
	EnterDirective("DCW",DcwArgs);
	EnterDirective("DCB",DcbArgs);
	
	EnterMnemonic("B","",    0A000000H,LabelArg,NIL,NIL,NIL,NIL,NIL);
	EnterMnemonic("BL","",   0B000000H,LabelArg,NIL,NIL,NIL,NIL,NIL);

	EnterMnemonic("ADD","",  00800000H,Reg12,Reg16,Oprnd2,NIL,NIL,NIL); 
	EnterMnemonic("ADD","S", 00900000H,Reg12,Reg16,Oprnd2,NIL,NIL,NIL);
	EnterMnemonic("ADC","",  00A00000H,Reg12,Reg16,Oprnd2,NIL,NIL,NIL); 
	EnterMnemonic("ADC","S", 00B00000H,Reg12,Reg16,Oprnd2,NIL,NIL,NIL);
	EnterMnemonic("SUB","",  00400000H,Reg12,Reg16,Oprnd2,NIL,NIL,NIL); 
	EnterMnemonic("SUB","S", 00500000H,Reg12,Reg16,Oprnd2,NIL,NIL,NIL);
	EnterMnemonic("SBC","",  00C00000H,Reg12,Reg16,Oprnd2,NIL,NIL,NIL); 
	EnterMnemonic("SBC","S", 00D00000H,Reg12,Reg16,Oprnd2,NIL,NIL,NIL);
	EnterMnemonic("RSB","",  00600000H,Reg12,Reg16,Oprnd2,NIL,NIL,NIL); 
	EnterMnemonic("RSB","S", 00700000H,Reg12,Reg16,Oprnd2,NIL,NIL,NIL);
	EnterMnemonic("RSC","",  00E00000H,Reg12,Reg16,Oprnd2,NIL,NIL,NIL); 
	EnterMnemonic("RSC","S", 00F00000H,Reg12,Reg16,Oprnd2,NIL,NIL,NIL);

	EnterMnemonic("AND","",  00000000H,Reg12,Reg16,Oprnd2,NIL,NIL,NIL); 
	EnterMnemonic("AND","S", 00100000H,Reg12,Reg16,Oprnd2,NIL,NIL,NIL);
	EnterMnemonic("EOR","",  00200000H,Reg12,Reg16,Oprnd2,NIL,NIL,NIL); 
	EnterMnemonic("EOR","S", 00300000H,Reg12,Reg16,Oprnd2,NIL,NIL,NIL);
	EnterMnemonic("ORR","",  01800000H,Reg12,Reg16,Oprnd2,NIL,NIL,NIL); 
	EnterMnemonic("ORR","S", 01900000H,Reg12,Reg16,Oprnd2,NIL,NIL,NIL);
	EnterMnemonic("BIC","",  01C00000H,Reg12,Reg16,Oprnd2,NIL,NIL,NIL); 
	EnterMnemonic("BIC","S", 01D00000H,Reg12,Reg16,Oprnd2,NIL,NIL,NIL);
	
	EnterMnemonic("MUL","",  00000090H,Reg16,Reg,Reg8,NIL,NIL,NIL); 
	EnterMnemonic("MUL","S", 00100090H,Reg16,Reg,Reg8,NIL,NIL,NIL);
	EnterMnemonic("MLA","",  00200090H,Reg16,Reg,Reg8,Reg12,NIL,NIL); 
	EnterMnemonic("MLA","S", 00300090H,Reg16,Reg,Reg8,Reg12,NIL,NIL);
	EnterMnemonic("UMULL","",  00800090H,Reg12,Reg16,Reg,Reg8,NIL,NIL); 
	EnterMnemonic("UMULL","S", 00900090H,Reg12,Reg16,Reg,Reg8,NIL,NIL);
	EnterMnemonic("SMULL","",  00C00090H,Reg12,Reg16,Reg,Reg8,NIL,NIL); 
	EnterMnemonic("SMULL","S", 00D00090H,Reg12,Reg16,Reg,Reg8,NIL,NIL);
	EnterMnemonic("UMLAL","",  00A00090H,Reg12,Reg16,Reg,Reg8,NIL,NIL); 
	EnterMnemonic("UMLAL","S", 00B00090H,Reg12,Reg16,Reg,Reg8,NIL,NIL);
	EnterMnemonic("SMLAL","",  00E00090H,Reg12,Reg16,Reg,Reg8,NIL,NIL); 
	EnterMnemonic("SMLAL","S", 00F00090H,Reg12,Reg16,Reg,Reg8,NIL,NIL);

	EnterMnemonic("SDIV","", 0710F010H,Reg16,Reg,Reg8,NIL,NIL,NIL); 
	EnterMnemonic("UDIV","", 0730F010H,Reg16,Reg,Reg8,NIL,NIL,NIL);


	EnterMnemonic("TST","",  01100000H,Reg16,Oprnd2,NIL,NIL,NIL,NIL);
	EnterMnemonic("TEQ","",  01300000H,Reg16,Oprnd2,NIL,NIL,NIL,NIL);
	EnterMnemonic("CMP","",  01500000H,Reg16,Oprnd2,NIL,NIL,NIL,NIL);
	EnterMnemonic("CMN","",  01700000H,Reg16,Oprnd2,NIL,NIL,NIL,NIL);

	EnterMnemonic("MOV","",  01A00000H,Reg12,Oprnd2,NIL,NIL,NIL,NIL); 
	EnterMnemonic("MOV","S", 01B00000H,Reg12,Oprnd2,NIL,NIL,NIL,NIL);
	EnterMnemonic("MVN","",  01E00000H,Reg12,Oprnd2,NIL,NIL,NIL,NIL); 
	EnterMnemonic("MVN","S", 01F00000H,Reg12,Oprnd2,NIL,NIL,NIL,NIL);

	EnterMnemonic("LDM","ED",09900000H,Reg16W,RegListS,NIL,NIL,NIL,NIL); 
	EnterMnemonic("LDM","IB",09900000H,Reg16W,RegListS,NIL,NIL,NIL,NIL); 
	EnterMnemonic("LDM","FD",08900000H,Reg16W,RegListS,NIL,NIL,NIL,NIL); 
	EnterMnemonic("LDM","IA",08900000H,Reg16W,RegListS,NIL,NIL,NIL,NIL); 
	EnterMnemonic("LDM","EA",09100000H,Reg16W,RegListS,NIL,NIL,NIL,NIL); 
	EnterMnemonic("LDM","DB",09100000H,Reg16W,RegListS,NIL,NIL,NIL,NIL); 
	EnterMnemonic("LDM","FA",08100000H,Reg16W,RegListS,NIL,NIL,NIL,NIL); 
	EnterMnemonic("LDM","DA",08100000H,Reg16W,RegListS,NIL,NIL,NIL,NIL); 
	
	EnterMnemonic("STM","FA",09800000H,Reg16W,RegListS,NIL,NIL,NIL,NIL); 
	EnterMnemonic("STM","IB",09800000H,Reg16W,RegListS,NIL,NIL,NIL,NIL); 
	EnterMnemonic("STM","EA",08800000H,Reg16W,RegListS,NIL,NIL,NIL,NIL); 
	EnterMnemonic("STM","IA",08800000H,Reg16W,RegListS,NIL,NIL,NIL,NIL); 
	EnterMnemonic("STM","FD",09000000H,Reg16W,RegListS,NIL,NIL,NIL,NIL); 
	EnterMnemonic("STM","DB",09000000H,Reg16W,RegListS,NIL,NIL,NIL,NIL); 
	EnterMnemonic("STM","ED",08000000H,Reg16W,RegListS,NIL,NIL,NIL,NIL); 
	EnterMnemonic("STM","DA",08000000H,Reg16W,RegListS,NIL,NIL,NIL,NIL); 

	EnterMnemonic("STR","",  04000000H,Reg12,AMode1,NIL,NIL,NIL,NIL); 
	EnterMnemonic("STR","T", 04200000H,Reg12,AMode2,NIL,NIL,NIL,NIL); 
	EnterMnemonic("STR","B", 04400000H,Reg12,AMode1,NIL,NIL,NIL,NIL); 
	EnterMnemonic("STR","BT",04600000H,Reg12,AMode2,NIL,NIL,NIL,NIL); 
	EnterMnemonic("LDR","",  04100000H,Reg12,AMode1,NIL,NIL,NIL,NIL); 
	EnterMnemonic("LDR","T", 04300000H,Reg12,AMode2,NIL,NIL,NIL,NIL); 
	EnterMnemonic("LDR","B", 04500000H,Reg12,AMode1,NIL,NIL,NIL,NIL); 
	EnterMnemonic("LDR","BT",04700000H,Reg12,AMode2,NIL,NIL,NIL,NIL); 

	EnterMnemonic("STR","H", 000000B0H,Reg12,AMode3,NIL,NIL,NIL,NIL); 
	EnterMnemonic("LDR","H", 001000B0H,Reg12,AMode3,NIL,NIL,NIL,NIL); 
	EnterMnemonic("LDR","SB",001000D0H,Reg12,AMode3,NIL,NIL,NIL,NIL); 
	EnterMnemonic("LDR","SH",001000F0H,Reg12,AMode3,NIL,NIL,NIL,NIL); 

	EnterMnemonic("SWP","",  01000090H,Reg12,Reg,RegInd16,NIL,NIL,NIL); 
	EnterMnemonic("SWP","B", 01400090H,Reg12,Reg,RegInd16,NIL,NIL,NIL); 

	EnterMnemonic("SWI","",  0F000000H,Imm24,NIL,NIL,NIL,NIL,NIL); 

	EnterMnemonic("MSR","",  0120F000H,PSR,PSRFields,RegOrImm,NIL,NIL,NIL); 
	EnterMnemonic("MRS","",  010F0000H,Reg12,PSR,NIL,NIL,NIL,NIL); 
	
	(* Enter all symbols *)
	(* Registers *)
	EnterSym("R0",clsReg,0); EnterSym("R1",clsReg,1); EnterSym("R2",clsReg,2); EnterSym("R3",clsReg,3);
	EnterSym("R4",clsReg,4); EnterSym("R5",clsReg,5); EnterSym("R6",clsReg,6); EnterSym("R7",clsReg,7);
	EnterSym("R8",clsReg,8); EnterSym("R9",clsReg,9); EnterSym("R10",clsReg,10); EnterSym("R11",clsReg,11);
	EnterSym("R12",clsReg,12); EnterSym("R13",clsReg,13); EnterSym("R14",clsReg,14); EnterSym("R15",clsReg,15);
	EnterSym("PC",clsReg,OBC.PC); EnterSym("LR",clsReg,OBC.LR); EnterSym("SP",clsReg,OBC.SP); EnterSym("FP",clsReg,OBC.FP);

	(* PSR-Registers *)
	EnterSym("CPSR",clsPSR,0); EnterSym("SPSR",clsPSR,1);
	
	(* PSR-Fields *)
	EnterSym("f",clsPSRFields,8); EnterSym("c",clsPSRFields,1); EnterSym("all",clsPSRFields,9);

	(* Shifts *)
	EnterSym("LSL",clsShift,0); EnterSym("LSR",clsShift,1); EnterSym("ASR",clsShift,2);
	EnterSym("ROR",clsShift,3); EnterSym("RRX",clsShift,4);

END OBA.