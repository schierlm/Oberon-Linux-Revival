(* ETH Oberon, Copyright 1990-2003 Computer Systems Institute, ETH Zurich, CH-8092 Zurich.
Refer to the license.txt file provided with this distribution. *)

MODULE Marble;	(* afi *)

(* Marble solitaire game.
Works together with the board defined by the Layla description at the end.
Module without global variable. The state of the game is stored in the document,
hence a game is persistent and can be stored and resumed at will,
and more than one board may be played at a time.
A game can be undone in its entirety.
The text in red implements the backtracking. *)

IMPORT Attributes, Gadgets, Links, Objects, Strings, Out;
CONST red = 1; green = 2; grey = 13; black = 15; BoardDim = 7; debug = FALSE;
VAR delta: ARRAY 4 OF INTEGER;

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

PROCEDURE PanelUpd8;
VAR panobj: Objects.Object;
BEGIN
	panobj := Gadgets.FindObj(Gadgets.context, "Panel");
	Gadgets.Update(panobj)
END PanelUpd8;

PROCEDURE ResetRed(name: LONGINT);
VAR j: INTEGER; col: LONGINT; destobj: Objects.Object;
BEGIN
	FOR j := 0 TO 3 DO
		destobj := GetObj(name+delta[j]);
		IF destobj # NIL THEN
			Attributes.GetInt(destobj, "Color", col);
			IF col = red THEN Attributes.SetInt(destobj, "Color", green) END
		END
	END
END ResetRed;

PROCEDURE Undo*;
VAR pivotobj, objdest, model: Objects.Object; name, direction, undecidable: LONGINT;
		namestr, predstr, predmem, directstr, prevdir, memdir, undecstr: ARRAY 64 OF CHAR;
		j: INTEGER;
BEGIN
	pivotobj := Gadgets.FindObj(Gadgets.context, "LastPivot");
	Attributes.GetString(pivotobj, "Value", namestr);
	Strings.StrToInt(namestr, name);
	Attributes.GetString(pivotobj, "LastDirect", directstr);
	Strings.StrToInt(directstr, direction);
	Attributes.GetString(pivotobj, "Undecidable", undecstr);
	Strings.StrToInt(undecstr, undecidable);
	IF debug THEN Out.String("Undo pivot= "); Out.String(namestr); Out.Char(" "); Out.String(directstr) END;
	IF undecstr = "" THEN
		objdest := GetObj(name); Attributes.SetInt(objdest, "Color", green);
		Links.GetLink(objdest, "Model", model);
		
		(* PopModel(model) *)
		Attributes.GetString(model, "Direction", memdir);
		Attributes.GetString(model, "Value", predmem);
		j := Len(predmem);
		IF j > 1 THEN
			predstr[0] := predmem[j-2]; predstr[1] := predmem[j-1]; predstr[2] := 0X;
			predmem[j-2] := 0X;
			prevdir[0] := memdir[j-2]; prevdir[1] := memdir[j-1]; prevdir[2] := 0X;
			memdir[j-2] := 0X
		END;
		Attributes.SetString(model, "Value", predmem);
		Attributes.SetString(model, "Direction", memdir);
		Attributes.SetString(pivotobj, "Value", predstr);
		Attributes.SetString(pivotobj, "LastDirect", prevdir);
		IF debug THEN Out.String(" Next to undo= "); Out.String(predstr); Out.Char(" "); Out.String(prevdir); Out.Ln END;

		objdest := GetObj(name-delta[direction]); Attributes.SetInt(objdest, "Color", green);
		objdest := GetObj(name+delta[direction]); Attributes.SetInt(objdest, "Color", grey);

	ELSE
		ResetRed(undecidable);	(* Reset the remaining red marbles around this name to green *)
		objdest := GetObj(undecidable); Attributes.SetInt(objdest, "Color", green);
		Attributes.SetString(pivotobj, "Undecidable", "")
	END;
	PanelUpd8
END Undo;

PROCEDURE New*;
VAR row, col: INTEGER; destobj: Objects.Object;
BEGIN
	FOR row := 1 TO BoardDim DO
		FOR col := 1 TO BoardDim DO
			destobj := GetObj(10*row + col);
			IF destobj # NIL THEN
				IF 10*row + col = 44 THEN Attributes.SetInt(destobj, "Color", grey)
				ELSE Attributes.SetInt(destobj, "Color", green)
				END
			END
		END
	END;
	PanelUpd8
END New;

PROCEDURE Go*;
VAR j: INTEGER; col, name, redname: LONGINT; WNES: SET;
		namestr, pivot: ARRAY 64 OF CHAR; dir: ARRAY 3 OF CHAR;
		objdest, objfinal, pivotobj, model: Objects.Object;
		candidate: ARRAY 4 OF Objects.Object;
		
	PROCEDURE PushModel(model: Objects.Object);
	VAR pivotobj: Objects.Object; prevpivot, mempivot, prevdir, memdir: ARRAY 64 OF CHAR;
	BEGIN
		pivotobj := Gadgets.FindObj(Gadgets.context, "LastPivot");
		Attributes.GetString(pivotobj, "Value", prevpivot);
		Attributes.GetString(pivotobj, "LastDirect", prevdir);

		Attributes.GetString(model, "Value", mempivot);	(* Memorize the previous pivot name in the next pivot's model *)
		Attributes.GetString(model, "Direction", memdir);
		IF debug THEN Out.String("Previous pivot= "); Out.String(prevpivot); Out.Char(" "); Out.String(prevdir) END;
		IF Len(mempivot) > 62 THEN Out.String("Too many moves"); HALT(99) END;
		IF Len(mempivot) # 0 THEN
			Strings.Append(mempivot, prevpivot);
			COPY(mempivot, prevpivot);
			Strings.Append(memdir, prevdir);
			COPY(memdir, prevdir);
			IF debug THEN Out.String("Next passage on pivot "); Out.String(prevpivot); Out.Char(" "); Out.String(prevdir) END;
		END;
		Attributes.SetString(model, "Value", prevpivot);
		Attributes.SetString(model, "Direction", prevdir);
		Gadgets.Update(model)
	END PushModel;

BEGIN
	Attributes.GetInt(Gadgets.executorObj, "Color", col);
	IF col = grey THEN	(* Not a valid point *)
	ELSIF col = red THEN	(* Decision taken over which red marble to hop *)
		pivotobj := Gadgets.FindObj(Gadgets.context, "LastPivot");
		Attributes.GetInt(pivotobj, "Undecidable", name);
		Attributes.GetInt(Gadgets.executorObj, "Name", redname);
		IF redname = name+delta[0] THEN j := 0
		ELSIF redname = name+delta[1] THEN j := 1
		ELSIF redname = name+delta[2] THEN j := 2
		ELSIF redname = name+delta[3] THEN j := 3
		END;
		Strings.IntToStr(redname+delta[j], namestr);
		dir := " ";
		Strings.AppendCh(dir, CHR(j + ORD("0")));
		Attributes.SetInt(Gadgets.executorObj, "Color", grey);	(* Gadgets.executorObj is the pivot chosen *)
		Attributes.GetString(Gadgets.executorObj, "Name", pivot);
		Links.GetLink(Gadgets.executorObj, "Model", model);
		PushModel(model);
		objdest := Gadgets.FindObj(Gadgets.context, namestr); Attributes.SetInt(objdest, "Color", green);

		ResetRed(name);	(* Reset the remaining red marbles around this name to green *)

		objdest := GetObj(name); Attributes.SetInt(objdest, "Color", grey);	(* Turn the black to grey (invisible) *)
		
		(* Memorize this move in global variable *)
		pivotobj := Gadgets.FindObj(Gadgets.context, "LastPivot");
		Attributes.SetString(pivotobj, "Value", pivot);
		Attributes.SetString(pivotobj, "LastDirect", dir);
		Attributes.SetString(pivotobj, "Undecidable", "");
		IF debug THEN Out.String(" LastPivot= "); Out.String(pivot); Out.Char(" "); Out.String(dir); Out.Ln END;
		Gadgets.Update(pivotobj);

	ELSE	(* Marble pointed to *)
		Attributes.GetInt(Gadgets.executorObj, "Name", name);
		WNES := {};	(* Explore the marbles in the four cardinal directions *)
		FOR j := 0 TO 3 DO
			candidate[j] := GetObj(name+delta[j]);
			IF candidate[j] # NIL THEN
				Attributes.GetInt(candidate[j], "Color", col);
				IF col = green THEN
					objdest := GetObj(name+2*delta[j]);
					IF objdest # NIL THEN
						Attributes.GetInt(objdest, "Color", col);
						IF col = grey THEN
							objfinal := objdest; WNES := WNES + {j}
						END
					END
				END
			END
		END;

		IF WNES = {} THEN 	(* No move possible *)
		ELSIF (WNES = {0}) OR (WNES = {1}) OR (WNES = {2}) OR (WNES = {3}) THEN	(* Unique next pivot *)
			IF WNES = {0} THEN j := 0
			ELSIF WNES = {1} THEN j := 1
			ELSIF WNES = {2} THEN j := 2
			ELSIF WNES = {3} THEN j := 3
			END;
			Attributes.SetInt(candidate[j], "Color", grey);
			Attributes.GetString(candidate[j], "Name", pivot);
			Links.GetLink(candidate[j], "Model", model);
			dir := " ";
			Strings.AppendCh(dir, CHR(j + ORD("0")));
			PushModel(model);
			Attributes.SetInt(objfinal, "Color", green);
			Attributes.SetInt(Gadgets.executorObj, "Color", grey);
			(* Memorize this move in global variable *)
			pivotobj := Gadgets.FindObj(Gadgets.context, "LastPivot");
			Attributes.SetString(pivotobj, "Value", pivot);
			Attributes.SetString(pivotobj, "LastDirect", dir);
			IF debug THEN Out.String(" LastPivot= "); Out.String(pivot); Out.Char(" "); Out.String(dir); Out.Ln END;
			Gadgets.Update(pivotobj)

		ELSE	(* Multiple choice: signal in red *)
			IF 0 IN WNES THEN Attributes.SetInt(candidate[0], "Color", red) END;
			IF 1 IN WNES THEN Attributes.SetInt(candidate[1], "Color", red) END;
			IF 2 IN WNES THEN Attributes.SetInt(candidate[2], "Color", red) END;
			IF 3 IN WNES THEN Attributes.SetInt(candidate[3], "Color", red) END;
			Attributes.SetInt(Gadgets.executorObj, "Color", black);
			objdest := Gadgets.FindObj(Gadgets.context, "LastPivot");
			Strings.IntToStr(name, namestr);
			Attributes.SetString(objdest, "Undecidable", namestr);	(* Name of the marble with undecidable destination *)
			Gadgets.Update(objdest)
		END
	END;
	PanelUpd8
END Go;

BEGIN
	delta[0] := -1; delta[1] := -10; delta[2] := 1; delta[3] := 10
END Marble.

Damien GUICHARD" <Damien.Guichard@wanadoo.fr> Sun, 19 Nov 2000 23:45:58
Mettre l'attribut GridSnap = 207 bloque les billes, donc mettre Locked = TRUE n'est pas suffisant  scuriser un tel jeu.
Test:  GridSnap = 102 is still OK. GridSnap = 103 blocks the marbles!!

System.Free Marble~

LayLa.OpenAsDoc
{ This game board definition is parameterized, i.e. more compact but not straightforward readable.
  Another one follows shown below. }
(CONFIG
	(DEF Border (NEW Panel (w=100 h=100) (ATTR Flat=TRUE Color=12)))
	(DEF Marble
		(CONFIG
			(DEF me "")
			(DEF mycolor 2)
			(NEW Circle (ATTR Name=me Color=mycolor Filled=TRUE Cmd="Marble.Go") (LINKS Model=(NEW String (ATTR Direction=""))))
		)
	)

		(TABLE Panel (border=8 cols=7)
		(ATTR Name="Panel" Locked=TRUE) (LINKS Model=(NEW String (ATTR Name="LastPivot" LastDirect="" Undecidable="")))

		(SPAN 2 2 (NEW Border))

		(NEW Marble (PARAMS me="13"))
		(NEW Marble (PARAMS me="14"))
		(NEW Marble (PARAMS me="15"))

		(SPAN 2 2 (NEW Border))

		(NEW Marble (PARAMS me="23"))
		(NEW Marble (PARAMS me="24"))
		(NEW Marble (PARAMS me="25"))

		(NEW Marble (PARAMS me="31"))
		(NEW Marble (PARAMS me="32"))
		(NEW Marble (PARAMS me="33"))
		(NEW Marble (PARAMS me="34"))
		(NEW Marble (PARAMS me="35"))
		(NEW Marble (PARAMS me="36"))
		(NEW Marble (PARAMS me="37"))

		(NEW Marble (PARAMS me="41"))
		(NEW Marble (PARAMS me="42"))
		(NEW Marble (PARAMS me="43"))
		(NEW Marble (PARAMS me="44" mycolor=13))
		(NEW Marble (PARAMS me="45"))
		(NEW Marble (PARAMS me="46"))
		(NEW Marble (PARAMS me="47"))

		(NEW Marble (PARAMS me="51"))
		(NEW Marble (PARAMS me="52"))
		(NEW Marble (PARAMS me="53"))
		(NEW Marble (PARAMS me="54"))
		(NEW Marble (PARAMS me="55"))
		(NEW Marble (PARAMS me="56"))
		(NEW Marble (PARAMS me="57"))

		(SPAN 2 2 (NEW Border))

		(NEW Marble (PARAMS me="63"))
		(NEW Marble (PARAMS me="64"))
		(NEW Marble (PARAMS me="65"))

		(SPAN 1 2 (NEW Panel (w=100 h=50) (ATTR Flat=TRUE Color=12)))

		(NEW Marble (PARAMS me="73"))
		(NEW Marble (PARAMS me="74"))
		(NEW Marble (PARAMS me="75"))
		(NEW Button (vjustifyMe=CENTER) (ATTR Caption="Undo" Cmd="Marble.Undo"))
		(NEW Button (vjustifyMe=CENTER) (ATTR Caption="New game" Cmd="Marble.New"))
		)))
~

You may also use this straightforward board definition:

LayLa.OpenAsDoc
	(TABLE Panel (border=8 cols=7)
		(ATTR Name="Panel" Locked=TRUE) (LINKS Model=(NEW String (ATTR Name="LastPivot" LastDirect="" Undecidable="")))

		(SPAN 2 2 (NEW Panel (w=100 h=100) (ATTR Flat=TRUE Color=12)))

		(NEW Circle (ATTR Name="13" Color = 2 Filled=TRUE Cmd="Marble.Go") (LINKS Model=(NEW String (ATTR Direction=""))))
		(NEW Circle (ATTR Name="14" Color = 2 Filled=TRUE Cmd="Marble.Go") (LINKS Model=(NEW String (ATTR Direction=""))))
		(NEW Circle (ATTR Name="15" Color = 2 Filled=TRUE Cmd="Marble.Go") (LINKS Model=(NEW String (ATTR Direction=""))))

		(SPAN 2 2 (NEW Panel (w=100 h=100) (ATTR Flat=TRUE Color=12)))

		(NEW Circle (ATTR Name="23" Color = 2 Filled=TRUE Cmd="Marble.Go") (LINKS Model=(NEW String (ATTR Direction=""))))
		(NEW Circle (ATTR Name="24" Color = 2 Filled=TRUE Cmd="Marble.Go") (LINKS Model=(NEW String (ATTR Direction=""))))
		(NEW Circle (ATTR Name="25" Color = 2 Filled=TRUE Cmd="Marble.Go") (LINKS Model=(NEW String (ATTR Direction=""))))

		(NEW Circle (ATTR Name="31" Color = 2 Filled=TRUE Cmd="Marble.Go") (LINKS Model=(NEW String (ATTR Direction=""))))
		(NEW Circle (ATTR Name="32" Color = 2 Filled=TRUE Cmd="Marble.Go") (LINKS Model=(NEW String (ATTR Direction=""))))
		(NEW Circle (ATTR Name="33" Color = 2 Filled=TRUE Cmd="Marble.Go") (LINKS Model=(NEW String (ATTR Direction=""))))
		(NEW Circle (ATTR Name="34" Color = 2 Filled=TRUE Cmd="Marble.Go") (LINKS Model=(NEW String (ATTR Direction=""))))
		(NEW Circle (ATTR Name="35" Color = 2 Filled=TRUE Cmd="Marble.Go") (LINKS Model=(NEW String (ATTR Direction=""))))
		(NEW Circle (ATTR Name="36" Color = 2 Filled=TRUE Cmd="Marble.Go") (LINKS Model=(NEW String (ATTR Direction=""))))
		(NEW Circle (ATTR Name="37" Color = 2 Filled=TRUE Cmd="Marble.Go") (LINKS Model=(NEW String (ATTR Direction=""))))

		(NEW Circle (ATTR Name="41" Color = 2 Filled=TRUE Cmd="Marble.Go") (LINKS Model=(NEW String (ATTR Direction=""))))
		(NEW Circle (ATTR Name="42" Color = 2 Filled=TRUE Cmd="Marble.Go") (LINKS Model=(NEW String (ATTR Direction=""))))
		(NEW Circle (ATTR Name="43" Color = 2 Filled=TRUE Cmd="Marble.Go") (LINKS Model=(NEW String (ATTR Direction=""))))
		(NEW Circle (ATTR Name="44" Color = 13 Filled=TRUE Cmd="Marble.Go") (LINKS Model=(NEW String (ATTR Direction=""))))
		(NEW Circle (ATTR Name="45" Color = 2 Filled=TRUE Cmd="Marble.Go") (LINKS Model=(NEW String (ATTR Direction=""))))
		(NEW Circle (ATTR Name="46" Color = 2 Filled=TRUE Cmd="Marble.Go") (LINKS Model=(NEW String (ATTR Direction=""))))
		(NEW Circle (ATTR Name="47" Color = 2 Filled=TRUE Cmd="Marble.Go") (LINKS Model=(NEW String (ATTR Direction=""))))

		(NEW Circle (ATTR Name="51" Color = 2 Filled=TRUE Cmd="Marble.Go") (LINKS Model=(NEW String (ATTR Direction=""))))
		(NEW Circle (ATTR Name="52" Color = 2 Filled=TRUE Cmd="Marble.Go") (LINKS Model=(NEW String (ATTR Direction=""))))
		(NEW Circle (ATTR Name="53" Color = 2 Filled=TRUE Cmd="Marble.Go") (LINKS Model=(NEW String (ATTR Direction=""))))
		(NEW Circle (ATTR Name="54" Color = 2 Filled=TRUE Cmd="Marble.Go") (LINKS Model=(NEW String (ATTR Direction=""))))
		(NEW Circle (ATTR Name="55" Color = 2 Filled=TRUE Cmd="Marble.Go") (LINKS Model=(NEW String (ATTR Direction=""))))
		(NEW Circle (ATTR Name="56" Color = 2 Filled=TRUE Cmd="Marble.Go") (LINKS Model=(NEW String (ATTR Direction=""))))
		(NEW Circle (ATTR Name="57" Color = 2 Filled=TRUE Cmd="Marble.Go") (LINKS Model=(NEW String (ATTR Direction=""))))

		(SPAN 2 2 (NEW Panel (w=100 h=100) (ATTR Flat=TRUE Color=12)))

		(NEW Circle (ATTR Name="63" Color = 2 Filled=TRUE Cmd="Marble.Go") (LINKS Model=(NEW String (ATTR Direction=""))))
		(NEW Circle (ATTR Name="64" Color = 2 Filled=TRUE Cmd="Marble.Go") (LINKS Model=(NEW String (ATTR Direction=""))))
		(NEW Circle (ATTR Name="65" Color = 2 Filled=TRUE Cmd="Marble.Go") (LINKS Model=(NEW String (ATTR Direction=""))))
		
		(SPAN 1 2 (NEW Panel (w=100 h=50) (ATTR Flat=TRUE Color=12)))

		(NEW Circle (ATTR Name="73" Color = 2 Filled=TRUE Cmd="Marble.Go") (LINKS Model=(NEW String (ATTR Direction=""))))
		(NEW Circle (ATTR Name="74" Color = 2 Filled=TRUE Cmd="Marble.Go") (LINKS Model=(NEW String (ATTR Direction=""))))
		(NEW Circle (ATTR Name="75" Color = 2 Filled=TRUE Cmd="Marble.Go") (LINKS Model=(NEW String (ATTR Direction=""))))
		(NEW Button (vjustifyMe=CENTER) (ATTR Caption="Undo" Cmd="Marble.Undo"))
		(NEW Button (vjustifyMe=CENTER) (ATTR Caption="New game" Cmd="Marble.New"))
	)))
~

French board
See http://omegalima.free.fr/solitaire/histoire.html

LayLa.OpenAsDoc

(CONFIG
	(DEF Border (NEW Panel (w=50 h=50) (ATTR Flat=TRUE Color=12)))
	(DEF Marble
		(CONFIG
			(DEF me "")
			(DEF mycolor 2)
			(NEW Circle (ATTR Name=me Color=mycolor Filled=TRUE Cmd="Marble.Go") (LINKS Model=(NEW String (ATTR Direction=""))))
		)
	)

		(TABLE Panel (border=8 cols=7)
		(ATTR Name="Panel" Locked=TRUE) (LINKS Model=(NEW String (ATTR Name="LastPivot" LastDirect="" Undecidable="")))

		(NEW Border)
		(NEW Border)
		(NEW Marble (PARAMS me="13"))
		(NEW Marble (PARAMS me="14"))
		(NEW Marble (PARAMS me="15"))
		(NEW Border)
		(NEW Border)

		(NEW Border)
		(NEW Marble (PARAMS me="22"))
		(NEW Marble (PARAMS me="23"))
		(NEW Marble (PARAMS me="24"))
		(NEW Marble (PARAMS me="25"))
		(NEW Marble (PARAMS me="26"))
		(NEW Border)

		(NEW Marble (PARAMS me="31"))
		(NEW Marble (PARAMS me="32"))
		(NEW Marble (PARAMS me="33"))
		(NEW Marble (PARAMS me="34"))
		(NEW Marble (PARAMS me="35"))
		(NEW Marble (PARAMS me="36"))
		(NEW Marble (PARAMS me="37"))

		(NEW Marble (PARAMS me="41"))
		(NEW Marble (PARAMS me="42"))
		(NEW Marble (PARAMS me="43"))
		(NEW Marble (PARAMS me="44" mycolor=13))
		(NEW Marble (PARAMS me="45"))
		(NEW Marble (PARAMS me="46"))
		(NEW Marble (PARAMS me="47"))

		(NEW Marble (PARAMS me="51"))
		(NEW Marble (PARAMS me="52"))
		(NEW Marble (PARAMS me="53"))
		(NEW Marble (PARAMS me="54"))
		(NEW Marble (PARAMS me="55"))
		(NEW Marble (PARAMS me="56"))
		(NEW Marble (PARAMS me="57"))

		(NEW Border)
		(NEW Marble (PARAMS me="62"))
		(NEW Marble (PARAMS me="63"))
		(NEW Marble (PARAMS me="64"))
		(NEW Marble (PARAMS me="65"))
		(NEW Marble (PARAMS me="66"))
		(NEW Border)

		(NEW Border)
		(NEW Border)
		(NEW Marble (PARAMS me="73"))
		(NEW Marble (PARAMS me="74"))
		(NEW Marble (PARAMS me="75"))
		(NEW Button (w=[ ] h=[ ]) (ATTR Caption="Undo" Cmd="Marble.Undo"))
		(NEW Button (w=[ ] h=[ ]) (ATTR Caption="New game" Cmd="Marble.New"))
		
		)))
~
