(* ETH Oberon, Copyright 1990-2003 Computer Systems Institute, ETH Zurich, CH-8092 Zurich.
Refer to the license.txt file provided with this distribution. *)

MODULE Afi521;	(* afi *)

(* 521 for Gadgets game - Inspired from Damien Guichard's FiveToOne * damien.guichard@wanadoo.fr *.

============================================================
Design objectives:

1 - Apply the principle of re-useability.
		Basic attitude to gadget development:
			Rule 1: Don't do it, use the gadget collection included in the system
			Rule 2: Do it with the intention to extend the gadget collection for the benefit of all
			Rule 3: Design a custom gadget as an exercise and with the intention to adhere to rule 2 later on
2 - Attempt to eliminate global variables in the base module.
	Locate the application state in the gadget(s). Additional attributes can easily be created for
	the purpose of storing state information. Several applications may then be run in parallel.
3 - When meaningful, as is the case for instance in games, extend the application with
	backtracking. This requires accumulating ad-hoc state information in the gadget(s).
3 - Create the user interface and its linked models with LayLa descriptions.
============================================================
Works together with the board defined by the Layla description at the end.
Module without global variable. The state of the game is stored in the document,
hence a game is persistent and can be stored and resumed at will,
and more than one board may be played at a time.
The text in red implements the backtracking (Undo), for the entire game (Max. of 63 steps).
============================================================
Goal
The goal is to fill the grid with 1s.
At each MM-click on a tile, the value on the tiles in the line and in the column is incremented by 1.
After 5, comes 1 again.
The level is the minimum number of clicks needed to reach the goal (i.e. level 0 is just instant win).
============================================================ *)

IMPORT Objects, Attributes, Strings, Gadgets, Oberon, RandomNumbers, Out;
CONST BoardDim = 3;

PROCEDURE Len(x: ARRAY OF CHAR): INTEGER;
VAR j: INTEGER;
BEGIN
	j := 0;
	WHILE x[j] > 0X DO INC(j) END;
	RETURN j
END Len;

PROCEDURE GetObj(pos: LONGINT): Objects.Object;
VAR posname: ARRAY 3 OF CHAR;
BEGIN
	Strings.IntToStr(pos, posname);
	RETURN Gadgets.FindObj(Gadgets.context, posname)
END GetObj;

PROCEDURE Trace;
VAR destobj: Objects.Object; j, k : INTEGER; box: LONGINT;
BEGIN
	FOR j := 1 TO BoardDim DO
		FOR k := 1 TO BoardDim DO
			destobj := GetObj(10*j + k);
			IF destobj # NIL THEN
				Attributes.GetInt(destobj, "Caption", box);
				Out.Int(box, 4)
			END
		END;
		Out.Ln
	END;
	Out.Ln
END Trace;

PROCEDURE Push;
VAR destobj: Objects.Object; j, k : INTEGER; box: ARRAY 2 OF CHAR; numlist: ARRAY 64 OF CHAR;
BEGIN
	FOR j := 1 TO BoardDim DO
		FOR k := 1 TO BoardDim DO
			destobj := GetObj(10*j + k);
			IF destobj # NIL THEN
				Attributes.GetString(destobj, "Caption", box);
				Attributes.GetString(destobj, "History", numlist);
				IF Len(numlist) > 63 THEN Out.String("Too many moves"); HALT(99) END;
				Strings.Append(numlist, box);
				Attributes.SetString(destobj, "History", numlist);
				Gadgets.Update(destobj)
			END
		END
	END
END Push;

PROCEDURE Pop;
VAR destobj: Objects.Object; j, k : INTEGER; box: ARRAY 2 OF CHAR; numlist: ARRAY 64 OF CHAR;
BEGIN
	FOR j := 1 TO BoardDim DO
		FOR k := 1 TO BoardDim DO
			destobj := GetObj(10*j + k);
			IF destobj # NIL THEN
				Attributes.GetString(destobj, "History", numlist);
				IF Len(numlist) < 1 THEN Out.String("Back to starting Point"); Out.Ln; RETURN END;
				box[0] := numlist[Len(numlist)-1]; box[1] := 0X;
				numlist[Len(numlist)-1] := 0X;
				Attributes.SetString(destobj, "History", numlist);
				Attributes.SetString(destobj, "Caption", box);
				Gadgets.Update(destobj)
			END
		END
	END
END Pop;

PROCEDURE StepBox(row, col, delta: INTEGER);
VAR destobj: Objects.Object; j : INTEGER; box: LONGINT;
BEGIN
	FOR j := 1 TO BoardDim DO
		destobj := GetObj(10*row + j);
		IF destobj # NIL THEN
			Attributes.GetInt(destobj, "Caption", box);
			INC(box, delta);
			IF box > 5 THEN box := 1
			ELSIF box < 1 THEN box := 5
			END;
			Attributes.SetInt(destobj, "Caption", box);
			Gadgets.Update(destobj)
		END
	END;
	FOR j := 1 TO BoardDim DO
		destobj := GetObj(10*j + col);
		IF (destobj # NIL) & (j # row) THEN
			Attributes.GetInt(destobj, "Caption", box);
			INC(box, delta);
			IF box > 5 THEN box := 1
			ELSIF box < 1 THEN box := 5
			END;
			Attributes.SetInt(destobj, "Caption", box);
			Gadgets.Update(destobj)
		END
	END
END StepBox;

PROCEDURE Start*;
VAR row, col, lev: INTEGER; destobj, levobj: Objects.Object; box, level: LONGINT;
BEGIN
	FOR row := 1 TO BoardDim DO
		FOR col := 1 TO BoardDim DO
			destobj := GetObj(10*row + col);
			IF destobj # NIL THEN
				Attributes.SetInt(destobj, "Caption", 1);
				Gadgets.Update(destobj)
			END;
		END
	END;
	levobj := Gadgets.FindObj(Gadgets.context, "Lev");
	Attributes.GetInt(levobj, "Value", level);
	FOR lev := 0 TO SHORT(level) - 1 DO
		box := ENTIER(RandomNumbers.Uniform()*9);
		row := SHORT(box DIV BoardDim) + 1;
		col := SHORT(box MOD BoardDim) + 1;
		StepBox(row, col, -1)	(* Step backward 1 unit *)
	END;
END Start;

PROCEDURE Undo*;
BEGIN
	Pop;
END Undo;

PROCEDURE Play*;
VAR name: ARRAY 3 OF CHAR; row, col: INTEGER;
BEGIN
	Push;
	Attributes.GetString(Gadgets.executorObj, "Name", name);
	row := ORD(name[0]) - ORD("0");
	col := ORD(name[1]) - ORD("0");
	StepBox(row, col, 1);	(* Step foreward 1 unit *)
(*	Trace;	*)
END Play;

BEGIN
	RandomNumbers.InitSeed(Oberon.Time())
END Afi521.

System.Free Afi521~

LayLa.OpenAsDoc
{ This game board definition is parameterized. }
(CONFIG
	(DEF Box
		(CONFIG
			(DEF me "")
			(NEW Button (w=60 h=60) (ATTR Name=me Caption="1" Led=FALSE Cmd="Afi521.Play" History=""))
		)
	)
	(DEF Level (NEW Integer (ATTR Value=0))
	)

		(TABLE Panel (w= 200 border=8 cols=3 dist=0) (ATTR Name="Panel" Locked=TRUE)
			(NEW Box (PARAMS me="11"))
			(NEW Box (PARAMS me="12"))
			(NEW Box (PARAMS me="13"))
			(NEW Box (PARAMS me="21"))
			(NEW Box (PARAMS me="22"))
			(NEW Box (PARAMS me="23"))
			(NEW Box (PARAMS me="31"))
			(NEW Box (PARAMS me="32"))
			(NEW Box (PARAMS me="33"))
			(SPAN 1 3
				(NEW VIRTUAL (h=10))
			)
			(NEW Caption (ATTR Value="       Level"))
			(NEW TextField (w=[]) (ATTR Name="Lev") (LINKS Model=Level))
			(NEW Scrollbar (w=[]) (ATTR Vertical=FALSE Min=0 Max=32) (LINKS Model=Level))
			(SPAN 1 3
				(NEW VIRTUAL (h=10))
			)
			(NEW Button (w=[]) (ATTR Caption="New game" Cmd="Afi521.Start"))
			VIRTUAL
			(NEW Button (w=[]) (ATTR Caption="Undo" Cmd="Afi521.Undo"))
		)
)
~
