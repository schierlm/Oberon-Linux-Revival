(* ETH Oberon, Copyright 1990-2003 Computer Systems Institute, ETH Zurich, CH-8092 Zurich.
Refer to the license.txt file provided with this distribution. *)

MODULE MasterMindG;	(* afi *)
IMPORT Attributes, Gadgets, Links, Oberon, Objects, RandomNumbers, Strings, Out;
CONST White = 0; Red = 1; Green = 2; Blue = 3; Pink = 4; Yellow = 5; Cyan = 6; Black = 15; NoColor = 16;
			colors = 6; pegs = 4; rounds = 7;

PROCEDURE GetObj(pos: LONGINT): Objects.Object;
VAR posname: ARRAY 4 OF CHAR;
BEGIN
	Strings.IntToStr(pos, posname);
	RETURN Gadgets.FindObj(Gadgets.context, posname)
END GetObj;

PROCEDURE Score(VAR blacks, whites: INTEGER);
VAR solution, guess: ARRAY pegs OF LONGINT; row: LONGINT;
		j, k: INTEGER; obj: Objects.Object; Stop: BOOLEAN;
BEGIN
	Attributes.GetInt(Gadgets.executorObj, "Row", row);
	FOR j := 0 TO pegs-1 DO
		obj := GetObj(row*10 + j);
		Attributes.GetInt(obj, "Color", guess[j]);
	END;
	(* Count the number pegs having the same color in the same positions. *)
	blacks := 0;
	FOR j := 0 TO pegs-1 DO
		obj := GetObj((rounds+1)*10 + j);
		Attributes.GetInt(obj, "Color", solution[j]);
		IF guess[j] = solution[j] THEN
			obj := GetObj(100 + row* 10 + blacks);
			Attributes.SetInt(obj, "Color", Black);
			Attributes.SetBool(obj, "Filled", TRUE);
			Gadgets.Update(obj);
			INC(blacks);
			solution[j] := NoColor;
			guess[j] := NoColor
		END
	END;

	(* Count the number pegs having the same color in the guess and the solution. *)
	whites := 0;
	FOR j := 0 TO pegs-1 DO
		IF guess[j] # NoColor THEN
			Stop := FALSE;
			FOR k := 0 TO pegs-1 DO
				IF ~Stop & (guess[j] = solution[k]) THEN
					obj := GetObj(100 + row* 10 + blacks + whites);
					Attributes.SetInt(obj, "Color", White);
					Attributes.SetBool(obj, "Filled", TRUE);
					Gadgets.Update(obj);
					INC(whites);
					solution[k] := NoColor;
					Stop := TRUE
				END
			END
		END
	END;
	Attributes.SetInt(Gadgets.executorObj, "Row", row+1);
	Gadgets.Update(Gadgets.executorObj);
END Score;

PROCEDURE ScoreX(VAR blacks, whites, row: INTEGER; x: LONGINT);
VAR X, guess: ARRAY pegs OF LONGINT;
		j, k: INTEGER; obj: Objects.Object; Stop: BOOLEAN;
BEGIN
	FOR j := 0 TO pegs-1 DO
		X[j] := (x MOD colors) + 1;
		x := x DIV colors
	END;
	FOR j := 0 TO pegs-1 DO
		obj := GetObj(row*10 + j);
		Attributes.GetInt(obj, "Color", guess[j]);
	END;
	(* Count the number pegs having the same color in the same positions. *)
	blacks := 0;
	FOR j := 0 TO pegs-1 DO
		IF guess[j] = X[j] THEN
			INC(blacks);
			X[j] := NoColor;
			guess[j] := NoColor
		END
	END;

	(* Count the number pegs having the same color in the guess. *)
	whites := 0;
	FOR j := 0 TO pegs-1 DO
		IF guess[j] # NoColor THEN
			Stop := FALSE;
			FOR k := 0 TO pegs-1 DO
				IF ~Stop & (guess[j] = X[k]) THEN
					INC(whites);
					X[k] := NoColor;
					Stop := TRUE
				END
			END
		END
	END
END ScoreX;

PROCEDURE Start*;
VAR solution: LONGINT; j, k: INTEGER; obj: Objects.Object; guess: ARRAY 8 OF LONGINT;
		blacks, whites: INTEGER; scores: ARRAY 8, 2 OF INTEGER;

	PROCEDURE ShowIt(guess: LONGINT; row: INTEGER);
	VAR j: INTEGER;
	BEGIN
		FOR j := 0 TO pegs-1 DO
			obj := GetObj(row*10 + j);
			Attributes.SetInt(obj, "Color", (guess MOD colors) + 1);
			Gadgets.Update(obj);
			guess := guess DIV colors
		END;
	END ShowIt;

	PROCEDURE Consistent(x: LONGINT; j: INTEGER): BOOLEAN;
	VAR k: INTEGER; blacks, whites: INTEGER;
	BEGIN
		k := 0;
		REPEAT
			INC(k);
			ScoreX(blacks, whites, k, x);
(*			Out.Int(x, 6); Out.Int(k, 6); Out.Int(scores[k, 0], 6); Out.Int(scores[k, 1], 6);
			Out.Int(blacks, 6); Out.Int(whites, 6); Out.Ln;
*)
		UNTIL (k > j) OR ~((blacks = scores[k, 0]) & (whites = scores[k, 1]));
		IF k > j THEN RETURN TRUE ELSE RETURN FALSE END
	END Consistent;

	PROCEDURE NextGuess(j: INTEGER): LONGINT;
	VAR x: LONGINT;
	BEGIN
		x := guess[j];
		REPEAT INC(x) UNTIL Consistent(x, j);
		Out.String("X consistent: "); Out.Int(x, 6); Out.Ln;
		RETURN x
	END NextGuess;

BEGIN
	(* Clear the entire game board. *)
	FOR j := 1 TO rounds DO
		FOR k := 0 TO pegs-1 DO
			obj := GetObj(j*10 + k);
			Attributes.SetInt(obj, "Color", White); 
			Gadgets.Update(obj);
			obj := GetObj(100+ j*10 + k);
			Attributes.SetInt(obj, "Color", Black); 
			Attributes.SetBool(obj, "Filled", FALSE); 
			Gadgets.Update(obj);
		END
	END;
	obj := Gadgets.FindObj(Gadgets.context, "start");
	Attributes.SetInt(obj, "Row", 1);
	Gadgets.Update(obj);

	solution := 1;
	FOR j := 0 TO pegs-1 DO solution := solution * colors END;
	solution := ENTIER(RandomNumbers.Uniform() * solution);
	ShowIt(solution, 8);

	guess[1] := 0;
	j := 0;
	REPEAT
		INC(j);
		ShowIt(guess[j], j);
		Score(blacks, whites);
		scores[j, 0] := blacks; scores[j, 1] := whites;
		IF blacks # pegs THEN guess[j + 1] := NextGuess(j) END;
	UNTIL blacks = pegs;
END Start;

BEGIN
	RandomNumbers.InitSeed(Oberon.Time())
END MasterMindG.
System.Free MasterMindG~

LayLa.OpenAsDoc
{ This game board definition is parameterized. }
(CONFIG
	(DEF Solution
		(CONFIG
			(DEF me "")
			(DEF mycolor 0)
			(NEW Circle (ATTR Name=me Color=mycolor Filled=TRUE))
		)
	)
	(DEF Plug
		(CONFIG
			(DEF me "")
			(DEF mycolor 0)
			(NEW Circle (ATTR Name=me Color=mycolor Filled=TRUE))
		)
	)
	(DEF Score
		(CONFIG
			(DEF width 22) (DEF height 22)
			(DEF s0 "") (DEF s1 "") (DEF s2 "") (DEF s3 "")
			(DEF mycolor 15)
			(TABLE VIRTUAL (cols=2)
				(NEW Circle (w=width h=height) (ATTR Name=s0))
				(NEW Circle (w=width h=height) (ATTR Name=s1))
				(NEW Circle (w=width h=height) (ATTR Name=s2))
				(NEW Circle (w=width h=height) (ATTR Name=s3))
			)
		 )
	)
	(DEF Palette
		(CONFIG
			(HLIST VIRTUAL
				(NEW Panel (w=40 h=20) (ATTR Color=1))
				(NEW Panel (w=40 h=20) (ATTR Color=2))
				(NEW Panel (w=40 h=20) (ATTR Color=3))
				(NEW Panel (w=40 h=20) (ATTR Color=4))
				(NEW Panel (w=40 h=20) (ATTR Color=5))
				(NEW Panel (w=40 h=20) (ATTR Color=6))
			)
		)
	)
		(TABLE Panel (border=8 cols=5 dist=10 w=310)
		(ATTR Name="Panel" Locked=TRUE)

		(NEW Plug (PARAMS me="10"))
		(NEW Plug (PARAMS me="11"))
		(NEW Plug (PARAMS me="12"))
		(NEW Plug (PARAMS me="13"))
		(NEW Score (PARAMS s0="110" s1="111" s2="112" s3="113"))

		(NEW Plug (PARAMS me="20"))
		(NEW Plug (PARAMS me="21"))
		(NEW Plug (PARAMS me="22"))
		(NEW Plug (PARAMS me="23"))
		(NEW Score (PARAMS s0="120" s1="121" s2="122" s3="123"))

		(NEW Plug (PARAMS me="30"))
		(NEW Plug (PARAMS me="31"))
		(NEW Plug (PARAMS me="32"))
		(NEW Plug (PARAMS me="33"))
		(NEW Score (PARAMS s0="130" s1="131" s2="132" s3="133"))

		(NEW Plug (PARAMS me="40"))
		(NEW Plug (PARAMS me="41"))
		(NEW Plug (PARAMS me="42"))
		(NEW Plug (PARAMS me="43"))
		(NEW Score (PARAMS s0="140" s1="141" s2="142" s3="143"))

		(NEW Plug (PARAMS me="50"))
		(NEW Plug (PARAMS me="51"))
		(NEW Plug (PARAMS me="52"))
		(NEW Plug (PARAMS me="53"))
		(NEW Score (PARAMS s0="150" s1="151" s2="152" s3="153"))

		(NEW Plug (PARAMS me="60"))
		(NEW Plug (PARAMS me="61"))
		(NEW Plug (PARAMS me="62"))
		(NEW Plug (PARAMS me="63"))
		(NEW Score (PARAMS s0="160" s1="161" s2="162" s3="163"))

		(NEW Plug (PARAMS me="70"))
		(NEW Plug (PARAMS me="71"))
		(NEW Plug (PARAMS me="72"))
		(NEW Plug (PARAMS me="73"))
		(NEW Score (PARAMS s0="170" s1="171" s2="172" s3="173"))

{  Assignment row. }
		(NEW Solution (PARAMS me="80"))
		(NEW Solution (PARAMS me="81"))
		(NEW Solution (PARAMS me="82"))
		(NEW Solution (PARAMS me="83"))
		(NEW Caption (w=[] h=[]) (ATTR Value="Master
mind
Guesser" Font="Oberon14b.Scn.Fnt"))

{ Color palette }
		(SPAN 1 5
			(NEW Palette)
		)
		(NEW Button (ATTR Name="start" Caption="New game" Cmd="MasterMindG.Start" Row=0))
		)))
~

