MODULE OBM;	(* as 8.2.99 *)

	CONST
			MaxImps* = 64;	(* max 256 for fixup list *)
			MaxOpenDims* = 7;

		(* common file name extensions *)
			OFext* = ".Obj";
			SFext* = ".Sym";
		
		(*object and item modes*)
			Var*   =  1; Var1* =  2; Par*   =  3; Par1* = 4; Const* = 5; Reg*  = 6;
			RegX*  =  7;  (* Two Regs are used: r and r1 *)
			CC*  = 8;  Var2* = 9; 

			Fld*   = 13; Typ*   = 14; LProc* = 15; SProc* = 16;  Mod*   = 19; Head*  = 20;

		(*structure forms*)
			Undef* = 0; Byte* = 1; Bool* = 2; Char* = 3; SInt* = 4; Int* = 5; LInt* = 6;
			Real* = 7; LReal* = 8; Set* = 9; String* = 10; NilTyp* = 11; NoTyp* = 12;
			Pointer* = 13; ProcTyp* = 14; SysPtr * = 16; Array* = 17; DynArr* = 18; Record* = 19;

		(*symbol values*)
			null* = 0;times* = 1; slash* = 2; div* = 3; mod* = 4;
			and* = 5; plus* = 6; minus* = 7; or* = 8; eql* = 9;
			neq* = 10; lss* = 11; leq* = 12; gtr* = 13; geq* = 14;
			in* = 15; is* = 16; arrow* = 17; period* = 18; comma* = 19;
			colon* = 20; upto* = 21; rparen* = 22; rbrak* = 23; rbrace* = 24;
			of* = 25; then* = 26; do* = 27; to* = 28; lparen* = 29;
			lbrak* = 30; lbrace* = 31; not* = 32; becomes* = 33; number* = 34;
			nil* = 35; string* = 36; ident* = 37; semicolon* = 38; bar* = 39;
			end* = 40; else* = 41; elsif* = 42; until* = 43; if* = 44;
			case* = 45; while* = 46; repeat* = 47; loop* = 48; with* = 49;
			exit* = 50; return* = 51; for* = 52; by* = 53;
			array* = 54; record* = 55; pointer* = 56;
			begin* = 57; const* = 58; type* = 59; var* = 60; procedure* = 61;
			import* = 62; module* = 63; eof* = 64; exclamation* = 65; code* = 66;
		
		(* Trap Numbers  *)
			WithGuardTrap* = 1;
			CaseTrap* = 2;
			NoReturnTrap* = 3;
			ImplTypeGuardTrap* = 5;
			TypeGuardTrap* = 6;
			IndexTrap* = 7;
			AssertTrap* = 8;
			DimErrTrap* = 9;
			DivByZeroTrap* = 10;
			OverflowTrap* = 11;
			
			EnableInterruptsTrap* = 100H;
			DisableInterruptsTrap* = 104H;
			RestoreInterruptsTrap* = 108H;

	VAR
		prefix* : ARRAY 32 OF CHAR;
		
	PROCEDURE MakeFileName*(name : ARRAY OF CHAR; VAR FName: ARRAY OF CHAR; ext: ARRAY OF CHAR);
		VAR i, j: INTEGER; ch: CHAR;
	BEGIN 
		i := 0;
		LOOP ch := prefix[i];
			IF ch = 0X THEN EXIT END ;
			FName[i] := ch; INC(i)
		END ;
		j := 0;
		LOOP ch := name[j];
			IF ch = 0X THEN EXIT END ;
			FName[i] := ch; INC(i); INC(j)
		END ;
		j := 0;
		REPEAT ch := ext[j]; FName[i] := ch; INC(i); INC(j)
		UNTIL ch = 0X
	END MakeFileName;
	
	PROCEDURE IsSYSTEMName*(VAR a : ARRAY OF CHAR) : BOOLEAN;
	BEGIN
		RETURN a="SYSTEM"
	END IsSYSTEMName;
	
	PROCEDURE IsSoftFloatName*(VAR a : ARRAY OF CHAR) : BOOLEAN;
	BEGIN
		RETURN a="SoftFloat";
	END IsSoftFloatName;
	
	PROCEDURE Init;
	BEGIN
		prefix[0]:=0X;
	END Init;	
	
BEGIN
	Init	
END OBM.
