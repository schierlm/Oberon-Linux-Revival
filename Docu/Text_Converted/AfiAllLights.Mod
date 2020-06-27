(* ETH Oberon, Copyright 1990-2003 Computer Systems Institute, ETH Zurich, CH-8092 Zurich.
Refer to the license.txt file provided with this distribution. *)

MODULE AfiAllLights;	(* afi *)

(* All Lights State Change game - Inspired from Scopie Games All Lights *.
    See: http://www.scopie.com/games/alllights/
The objective of the game is to turn all 25 "lights" on. MM clicking a square
will toggle its light (as well as the lights of all horizontally and vertically
adjacent squares) on and off.

Works together with the board defined by the Layla description at the end.
Module without global variable. The state of the game is stored in the document,
hence a game is persistent and can be stored and resumed at will,
and more than one board may be played at a time.
Works with system supplied gadgets - no custom gadget needed.
Backtracking (Undo) is included by definition for one step. *)

IMPORT Attributes, Gadgets, Objects, Strings;
CONST BoardDim = 5; dim = 15;

PROCEDURE GetObj(pos: LONGINT): Objects.Object;
VAR posname: ARRAY 3 OF CHAR;
BEGIN
	Strings.IntToStr(pos, posname);
	RETURN Gadgets.FindObj(Gadgets.context, posname)
END GetObj;

PROCEDURE FlipLight(row, col: INTEGER);
VAR destobj: Objects.Object; color: LONGINT;
BEGIN
	destobj := GetObj(10*row + col);
	Attributes.GetInt(destobj, "Color", color);
	Attributes.SetInt(destobj, "Color", 15-color);
	Gadgets.Update(destobj)
END FlipLight;

PROCEDURE Play*;
VAR pos: LONGINT; row, col: INTEGER;
BEGIN
	Attributes.GetInt(Gadgets.executorObj, "Name", pos);
	row := SHORT(pos) DIV 10;
	col := SHORT(pos) MOD 10;
	(* Change the state of the adjacent lights *)
	IF col < BoardDim THEN FlipLight(row, col+1) END;
	IF col > 1 THEN FlipLight(row, col-1) END;
	IF row < BoardDim THEN FlipLight(row+1, col) END;
	IF row > 1 THEN FlipLight(row-1, col) END;
	FlipLight(row, col)
END Play;

PROCEDURE Start*;
VAR row, col: INTEGER; destobj: Objects.Object;
BEGIN
	FOR row := 1 TO BoardDim DO
		FOR col := 1 TO BoardDim DO
			destobj := GetObj(10*row + col);
			ASSERT(destobj # NIL);
			Attributes.SetInt(destobj, "Color", dim);
			Gadgets.Update(destobj)
		END
	END
END Start;

END AfiAllLights.

System.Free AfiAllLights~

This board definition is parameterized.

LayLa.OpenAsDoc
(CONFIG
	(DEF Border (NEW Panel (w=100 h=100) (ATTR Flat=TRUE Color=12)))
	(DEF Light
		(CONFIG
			(DEF me "")
			(DEF mycolor 15)
			(NEW Rectangle (w=40 h=40) (ATTR Name=me Color=mycolor Filled=TRUE Cmd="AfiAllLights.Play"))
		)
	)

	(TABLE Panel (border=8 cols=5 dist=1) (ATTR Name="Panel" Locked=TRUE)

		(NEW Light (PARAMS me="11"))
		(NEW Light (PARAMS me="12"))
		(NEW Light (PARAMS me="13"))
		(NEW Light (PARAMS me="14"))
		(NEW Light (PARAMS me="15"))

		(NEW Light (PARAMS me="21"))
		(NEW Light (PARAMS me="22"))
		(NEW Light (PARAMS me="23"))
		(NEW Light (PARAMS me="24"))
		(NEW Light (PARAMS me="25"))

		(NEW Light (PARAMS me="31"))
		(NEW Light (PARAMS me="32"))
		(NEW Light (PARAMS me="33"))
		(NEW Light (PARAMS me="34"))
		(NEW Light (PARAMS me="35"))

		(NEW Light (PARAMS me="41"))
		(NEW Light (PARAMS me="42"))
		(NEW Light (PARAMS me="43"))
		(NEW Light (PARAMS me="44"))
		(NEW Light (PARAMS me="45"))

		(NEW Light (PARAMS me="51"))
		(NEW Light (PARAMS me="52"))
		(NEW Light (PARAMS me="53"))
		(NEW Light (PARAMS me="54"))
		(NEW Light (PARAMS me="55"))

		(NEW Button (vjustifyMe=CENTER) (ATTR Caption="New game" Cmd="AfiAllLights.Start"))
		)))
~
