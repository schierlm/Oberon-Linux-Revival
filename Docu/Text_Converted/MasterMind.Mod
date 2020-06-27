(* ETH Oberon, Copyright 1990-2003 Computer Systems Institute, ETH Zurich, CH-8092 Zurich.
Refer to the license.txt file provided with this distribution. *)

MODULE MasterMind;	(* afi *)
IMPORT Attributes, Gadgets, Links, Oberon, Objects, RandomNumbers, Strings;
CONST White = 0; Red = 1; Green = 2; Blue = 3; Pink = 4; Yellow = 5; Cyan = 6; Black = 15; NoColor = 16;
			colors = 6; pegs = 4; rounds = 7;

PROCEDURE GetObj(pos: LONGINT): Objects.Object;
VAR posname: ARRAY 4 OF CHAR;
BEGIN
	Strings.IntToStr(pos, posname);
	RETURN Gadgets.FindObj(Gadgets.context, posname)
END GetObj;

PROCEDURE Roll*;
VAR color: LONGINT;
BEGIN
	Attributes.GetInt(Gadgets.executorObj, "Color", color);
	Attributes.SetInt(Gadgets.executorObj, "Color", (color+1) MOD 7);
	Gadgets.Update(Gadgets.executorObj)
END Roll;

PROCEDURE Uncover*;
VAR solution: LONGINT; j: INTEGER; obj, modobj: Objects.Object;
BEGIN
	FOR j := 0 TO pegs-1 DO
		obj := GetObj((rounds+1)*10 + j);
		Links.GetLink(obj, "Model", modobj);
		Attributes.GetInt(modobj, "Value", solution);
		Attributes.SetInt(obj, "Color", solution);
		Gadgets.Update(obj)
	END
END Uncover;

PROCEDURE Score*;
VAR solution, guess: ARRAY pegs OF LONGINT; row: LONGINT;
		j, k, blacks, whites: INTEGER; obj: Objects.Object; Complete, Stop: BOOLEAN;
BEGIN
	Attributes.GetInt(Gadgets.executorObj, "Row", row);
	(* Verify that a peg is placed in each hole of this row. *)
	Complete := TRUE;
	FOR j := 0 TO pegs-1 DO
		obj := GetObj(row*10 + j);
		Attributes.GetInt(obj, "Color", guess[j]);
		IF guess[j] = White THEN Complete := FALSE END
	END;
	ASSERT(Complete, 99);
	(* Count the number pegs having the same color in the same positions. *)
	blacks := 0;
	FOR j := 0 TO pegs-1 DO
		obj := GetObj((rounds+1)*10 + j);
		Links.GetLink(obj, "Model", obj);
		Attributes.GetInt(obj, "Value", solution[j]);
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
	IF (row = rounds) OR (blacks = pegs) THEN Uncover END
END Score;

PROCEDURE Start*;
VAR solution: LONGINT; j, k: INTEGER; obj: Objects.Object;
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
	FOR k := 0 TO pegs-1 DO
		obj := GetObj((rounds+1)*10 + k);
		Attributes.SetInt(obj, "Color", 13);
		Gadgets.Update(obj)
	END;
	obj := Gadgets.FindObj(Gadgets.context, "score");
	Attributes.SetInt(obj, "Row", 1);
	Gadgets.Update(obj);

	solution := 1;
	FOR j := 0 TO pegs-1 DO solution := solution * colors END;
	solution := ENTIER(RandomNumbers.Uniform() * solution);
	FOR j := 0 TO pegs-1 DO
		obj := GetObj((rounds+1)*10 + j);
		Links.GetLink(obj, "Model", obj);
		Attributes.SetInt(obj, "Value", (solution MOD colors) + 1);
		Gadgets.Update(obj);
		solution := solution DIV colors
	END
END Start;

BEGIN
	RandomNumbers.InitSeed(Oberon.Time())
END MasterMind.

System.Free MasterMind~

LayLa.OpenAsDoc
{ This game board definition is parameterized. }
(CONFIG
	(DEF Solution
		(CONFIG
			(DEF me "")
			(DEF mycolor 13)
			(NEW Circle (ATTR Name=me Color=mycolor Filled=TRUE) (LINKS Model= (NEW Integer (ATTR Value=mycolor))))
		)
	)
	(DEF Plug
		(CONFIG
			(DEF me "")
			(DEF mycolor 0)
			(NEW Circle (ATTR Name=me Color=mycolor Filled=TRUE Cmd="MasterMind.Roll"))
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
		(TABLE Panel (border=8 cols=6 dist=10 vjustify=CENTER)
		(ATTR Name="Panel" Locked=TRUE)

		(NEW Plug (PARAMS me="10"))
		(NEW Plug (PARAMS me="11"))
		(NEW Plug (PARAMS me="12"))
		(NEW Plug (PARAMS me="13"))
		(NEW Score (PARAMS s0="110" s1="111" s2="112" s3="113"))
		(NEW Caption (w=10) (ATTR Value="1"))

		(NEW Plug (PARAMS me="20"))
		(NEW Plug (PARAMS me="21"))
		(NEW Plug (PARAMS me="22"))
		(NEW Plug (PARAMS me="23"))
		(NEW Score (PARAMS s0="120" s1="121" s2="122" s3="123"))
		(NEW Caption (w=[]) (ATTR Value="2"))

		(NEW Plug (PARAMS me="30"))
		(NEW Plug (PARAMS me="31"))
		(NEW Plug (PARAMS me="32"))
		(NEW Plug (PARAMS me="33"))
		(NEW Score (PARAMS s0="130" s1="131" s2="132" s3="133"))
		(NEW Caption (w=[]) (ATTR Value="3"))

		(NEW Plug (PARAMS me="40"))
		(NEW Plug (PARAMS me="41"))
		(NEW Plug (PARAMS me="42"))
		(NEW Plug (PARAMS me="43"))
		(NEW Score (PARAMS s0="140" s1="141" s2="142" s3="143"))
		(NEW Caption (w=[]) (ATTR Value="4"))

		(NEW Plug (PARAMS me="50"))
		(NEW Plug (PARAMS me="51"))
		(NEW Plug (PARAMS me="52"))
		(NEW Plug (PARAMS me="53"))
		(NEW Score (PARAMS s0="150" s1="151" s2="152" s3="153"))
		(NEW Caption (w=[]) (ATTR Value="5"))

		(NEW Plug (PARAMS me="60"))
		(NEW Plug (PARAMS me="61"))
		(NEW Plug (PARAMS me="62"))
		(NEW Plug (PARAMS me="63"))
		(NEW Score (PARAMS s0="160" s1="161" s2="162" s3="163"))
		(NEW Caption (w=[]) (ATTR Value="6"))

		(NEW Plug (PARAMS me="70"))
		(NEW Plug (PARAMS me="71"))
		(NEW Plug (PARAMS me="72"))
		(NEW Plug (PARAMS me="73"))
		(NEW Score (PARAMS s0="170" s1="171" s2="172" s3="173"))
		(NEW Caption (w=[]) (ATTR Value="7"))

{ Hidden solution row. Each visual gadget in this row has an Integer model which hides the solution until uncovered. }
		(NEW Solution (PARAMS me="80"))
		(NEW Solution (PARAMS me="81"))
		(NEW Solution (PARAMS me="82"))
		(NEW Solution (PARAMS me="83"))
		(SPAN 1 2
		(NEW Caption (w=[] h=[]) (ATTR Value="Master
mind
Setter" Font="Oberon14b.Scn.Fnt"))
		)

{ Color palette }
		(SPAN 1 6
			(NEW Palette)
		)
		(NEW Button (ATTR Caption="New game" Cmd="MasterMind.Start"))
		VIRTUAL
		VIRTUAL
		(NEW Button (ATTR Name="score" Caption="Score" Cmd="MasterMind.Score" Row=0))
		(NEW Button (ATTR Caption="Uncover" Cmd="MasterMind.Uncover"))
		)))
~

