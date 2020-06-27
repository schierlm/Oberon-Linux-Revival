(* ETH Oberon, Copyright 1990-2003 Computer Systems Institute, ETH Zurich, CH-8092 Zurich.
Refer to the license.txt file provided with this distribution. *)

MODULE Slide5;	(* afi *)
IMPORT Attributes, Gadgets, Oberon, Objects, RandomNumbers, Strings, Out;

(* Silde is a simple strategy game opposing two players. The game board is a 5 x 5 square.
	A player wins by getting 5 in a line, either in a row, a column, or a diagonal.
	If the moving player doesn't win, but makes 5 in a line for the other player, then
	the other player wins. *)
(* This game uses the global variable PlayFld of type "board" to store the state of the game.
	For performance reasons, the state is not stored in the GUI components.

	The two players are named black and white and are represented on the play board internally
	by "1" and "-1" and externally by a color defined by Player1 and Player2.
	"0" and FrameColor denote an empty board position.
	Black always starts first.
	
	Each player may be a person or the computer. player1 = TRUE means: the computer plays "black".
*)

(* The maximum board width and height is 9 *)
CONST width = 5; height = 5; maxdepth = 2; portMax = 10;
		black = 1; white = -1; empty = 0;
		Player1 = 1; Player2 = 5;	(* Color of the tokens of the players. *)
		FrameColor = 10; Trace = FALSE;
TYPE board = ARRAY width, height OF INTEGER;
VAR player1, player2: BOOLEAN; count1, count2: INTEGER;
		PlayFld: board;
		MoveSeq: ARRAY 8 OF INTEGER;

PROCEDURE NextPlayer(player: INTEGER): INTEGER;
BEGIN IF player = black THEN RETURN white ELSE RETURN black END
END NextPlayer;

PROCEDURE GetObj(pos: INTEGER): Objects.Object;
VAR posname: ARRAY 4 OF CHAR;
BEGIN
	Strings.IntToStr(pos, posname);
	RETURN Gadgets.FindObj(Gadgets.context, posname)
END GetObj;

(* Remove all the arrowed icons. *)
PROCEDURE Inhibit;
VAR j: INTEGER; obj: Objects.Object;
BEGIN
	FOR j := 0 TO portMax DO	(* Note: 0 is included in the list *)
		obj := GetObj(j);
		Attributes.SetInt(obj, "Color", FrameColor);
		Gadgets.Update(obj)
	END
END Inhibit;

(* Set-up the board for the next player. *)
PROCEDURE SetUp(player: INTEGER);
VAR j: INTEGER; obj: Objects.Object; color: LONGINT;
BEGIN
	Inhibit();
	IF (player = black) THEN color := Player1 ELSE color := Player2 END;
	IF ((player = black) & player1) OR ((player = white) & player2) THEN
		FOR j := 1 TO portMax DO
			obj := GetObj(j);
			Attributes.SetInt(obj, "Color", color);
			Gadgets.Update(obj)
		END
	END;
	IF ((player = black) & ~player1) OR ((player = white) & ~player2) THEN
		obj := GetObj(0);
		Attributes.SetInt(obj, "Color", color);
		Gadgets.Update(obj)
	END
END SetUp;

	PROCEDURE Print (b: board);
	VAR x, y: INTEGER;
	BEGIN
		Out.Ln;
		FOR y := 0 TO height-1 DO Out.Ln;
			FOR x := 0 TO width-1 DO Out.Int(b[x, y], 3) END
		END
	END Print;

(* Create the successor board resulting from sliding a token at port. *)
PROCEDURE Successor(port: INTEGER; player: INTEGER; VAR succboard: board);
VAR k, row: INTEGER;
BEGIN
	k := 0;
	IF port < width THEN
		WHILE (k < height-1) & (succboard[port, k] # empty) DO INC(k) END;
		WHILE k >= 1 DO
			succboard[port, k] := succboard[port, k-1];
			DEC(k)
		END;
		ASSERT(k = 0);
		succboard[port, k] := player
	ELSE
		row := port - width;
		WHILE (k < width-1) & (succboard[k, row] # empty) DO INC(k) END;
		WHILE k >= 1 DO
			succboard[k, row] := succboard[k-1, row];
			DEC(k)
		END;
		ASSERT(k = 0);
		succboard[k, row] := player
	END
END Successor;

(* Attempt to push a token at a port and create the corresponding successor board state. *)
PROCEDURE TryPush(thisboard: board; port: INTEGER; player: INTEGER; VAR nextboard: board);
VAR x, y: INTEGER;
BEGIN
	FOR y := 0 TO height-1 DO	(* Copy entire board in successor *)
		FOR x := 0 TO width-1 DO nextboard[x, y] := thisboard[x, y] END
	END;
	Successor(port, player, nextboard)
END TryPush;

(* Exteriorize the board state. The entire board is refreshed because
	an entire row or column was modified. *)
PROCEDURE BoardImage;
VAR x, y: INTEGER;

	PROCEDURE SetToken (x, y: INTEGER);
	VAR posname, ord: ARRAY 6 OF CHAR; obj: Objects.Object;
	BEGIN
		Strings.IntToStr(x, posname); Strings.AppendCh(posname, ".");
		Strings.IntToStr(y, ord); Strings.Append(posname, ord);
		obj := Gadgets.FindObj(Gadgets.context, posname);
		CASE PlayFld[x, y] OF
			  black : Attributes.SetInt(obj, "Color", Player1);
			| white : Attributes.SetInt(obj, "Color", Player2);
			| empty : Attributes.SetInt(obj, "Color", 0)
		END;
		Gadgets.Update(obj)
	END SetToken;

BEGIN
	FOR y := 0 TO height-1 DO
		FOR x := 0 TO width-1 DO SetToken(x, y) END
	END
END BoardImage;

(* Evaluate a score w for the current board state: which player has 5 tokens in row?
	w = 0: no player;  w = 1: black has; w = 2: white has; w = 3: both players have *)
PROCEDURE Wins(thisboard: board): INTEGER;
VAR j, k, major, minor, w: INTEGER; col, row: ARRAY 6 OF INTEGER;
		P1Wins, P2Wins: BOOLEAN;
BEGIN
	FOR j := 0 TO width-1 DO row[j] := 0; col[j] := 0 END;
	major := 0; minor := 0; w := 0;
	FOR j := 0 TO height-1 DO
		FOR k := 0 TO width-1 DO
			row[j] := row[j] + thisboard[j, k];
			col[k] := col[k] + thisboard[j, k]
		END;
		major := major + thisboard[j, j];
		minor := minor + thisboard[j, width-1-j]
	END;
	P1Wins := FALSE; P2Wins := FALSE;
	FOR j := 0 TO width-1 DO
		IF (row[j] = width) OR (col[j] = width) THEN P1Wins := TRUE END;
		IF (row[j] = -width) OR (col[j] = -width) THEN P2Wins := TRUE END
	END;
	IF (major = width) OR (minor = width) THEN P1Wins := TRUE END;
	IF (major = -width) OR (minor = -width) THEN P2Wins := TRUE END;
	IF P1Wins THEN w := 1 END;
	IF P2Wins THEN w := w + 2 END;
	RETURN w
END Wins;

(* MiniMax algorithm to apply to the current play field PlayFld *)
PROCEDURE MiniMax(depth, player: INTEGER; thisboard: board; bestmove: INTEGER): INTEGER;
VAR tryport, res, min, max: INTEGER; nextboard: board; winval: INTEGER; bmove: INTEGER;
(* Blue text controls the creation of all the successors at a given depth. *)
	PROCEDURE diff (): INTEGER;
	VAR x,y, d: INTEGER;
	BEGIN	d := 0;
		FOR y := 0 TO height-1 DO
			FOR x := 0 TO width-1 DO d := d + thisboard[x, y] END
		END;
		RETURN d
	END diff;

BEGIN
	IF depth = maxdepth THEN RETURN diff()
	ELSE
		tryport := 0;
		IF (depth MOD 2) = 0 THEN	(* Even depth = Maximize score of this player - MAX ply *)
			max := -100;
			WHILE (tryport < portMax) & ((res = 0) OR (res = 2)) DO
				TryPush(thisboard, tryport, player, nextboard);	(* Create next board configuration *)
				winval := Wins(nextboard);
				IF Trace THEN Out.Int(tryport, 2); Out.Char("("); Out.Int(res, 2); Out.Char(")") END;
				IF winval = 0 THEN
					res := MiniMax(depth+1, NextPlayer(player), nextboard, bmove);
					IF res > max THEN max := res; bestmove := tryport END
				ELSIF (winval = 1) OR (winval = 3) THEN bestmove := tryport; max := 100
				(* ELSIF winval = 2 THEN there certainly exists a better solution than conceiding a defeat; continue searching
					OR even better jump on that to counter the adversary. *)
				END;
				INC(tryport); IF depth=0 THEN Out.Ln END;
			END;
			IF Trace THEN Out.String("  max"); Out.Int(max, 2); Out.Int(bestmove, 4) END;
			RETURN max
		ELSE	(* Odd depth = Minimize score of the opponent - MIN ply *)
			min := 100;
			WHILE (tryport < portMax) & ((res = 0) OR (res = 1)) DO
				TryPush(thisboard, tryport, player, nextboard);	(* Create next board configuration *)
				winval := Wins(nextboard);
				IF Trace THEN Out.Int(tryport, 2); Out.Char("["); Out.Int(res, 2); Out.Char("]") END;
				IF winval = 0 THEN
					res := MiniMax(depth+1, NextPlayer(player), nextboard, bmove);
					IF res < min THEN min := res; bestmove := tryport END
				ELSIF (winval = 2) OR (winval = 3) THEN bestmove := tryport; min := -100
				(* ELSIF winval = 1 THEN certainly exists a better solution than conceiding a defeat; continue searching
					OR even better jump on that to counter the adversary. *)
				END;
				INC(tryport); IF depth=0 THEN Out.Ln END;
			END;
			IF Trace THEN Out.String("  min"); Out.Int(min, 2); Out.Int(bestmove, 4) END;
			RETURN min
		END
	END;
END MiniMax;

PROCEDURE CollectMoves(mov: INTEGER);
VAR k: INTEGER;
BEGIN
	FOR k := 0 TO 6 DO MoveSeq[k] := MoveSeq[k+1] END;
	MoveSeq[7] := mov
END CollectMoves;

PROCEDURE istie(): BOOLEAN;
VAR k: INTEGER; flag: BOOLEAN;
BEGIN
	flag := TRUE;
	FOR k := 0 TO 2 DO
		IF MoveSeq[2*k] # MoveSeq[2*k+2] THEN flag := FALSE END;
		IF MoveSeq[2*k+1] # MoveSeq[2*k+3] THEN flag := FALSE END
	END;
	RETURN flag
END istie;

PROCEDURE Play*;
VAR port: LONGINT; ctrlobj, obj: Objects.Object; player: LONGINT; gameon: BOOLEAN; winval, res: INTEGER;
	best: INTEGER;
BEGIN
	ctrlobj := Gadgets.FindObj(Gadgets.context, "GameOn");
	Attributes.GetBool(ctrlobj, "Value", gameon);
	IF gameon THEN
		obj := Gadgets.FindObj(Gadgets.context, "Player");
		Attributes.GetInt(obj, "Value", player);
		Attributes.GetInt(Gadgets.executorObj, "Name", port);
		IF port = 0 THEN	(* The computer plays: the two first moves are random moves. *)
			IF (count1 < 2) & (count2 < 2) THEN
				 best := SHORT(ENTIER(RandomNumbers.Uniform()* 2*width));
				 IF player = black THEN INC(count1) ELSE INC(count2) END
			ELSE	(* Let the computer evaluate the best move *)
				res := MiniMax(0, SHORT(player), PlayFld, best); Out.Ln
			END
		ELSE
			best := SHORT(port-1);
		END;
		Successor(best, SHORT(player), PlayFld);
		CollectMoves(best);	(* Use to detect a tie. *)
		IF ~istie() THEN
			player := NextPlayer(SHORT(player));
			Attributes.SetInt(obj, "Value", player);
			Gadgets.Update(obj);
			SetUp(SHORT(player));
			BoardImage();
			winval := Wins(PlayFld); IF Trace THEN Out.Int(res, 6); Out.Ln END
		ELSE
			res := 4; Out.String("Is tie"); Out.Ln
		END;
		IF res # 0 THEN
			Inhibit();
			Attributes.SetBool(ctrlobj, "Value", FALSE);
			Gadgets.Update(ctrlobj)
		END
	END
END Play;

(** Ready the PlayFld and the GUI for a new game, and note who the 2 players are. *)
PROCEDURE Start*;
VAR x, y: INTEGER; obj: Objects.Object;
BEGIN
	FOR y := 0 TO height-1 DO
		FOR x := 0 TO width-1 DO PlayFld[x, y] := empty END
	END;
	BoardImage();
	obj := Gadgets.FindObj(Gadgets.context, "Player1");
	Attributes.GetBool(obj, "Value", player1);
	obj := Gadgets.FindObj(Gadgets.context, "Player2");
	Attributes.GetBool(obj, "Value", player2);
	obj := Gadgets.FindObj(Gadgets.context, "Player");	(* He who starts *)
	Attributes.SetInt(obj, "Value", black);
	Gadgets.Update(obj);
	obj := Gadgets.FindObj(Gadgets.context, "GameOn");
	Attributes.SetBool(obj, "Value", TRUE);
	Gadgets.Update(obj);
	FOR x := 0 TO 7 DO MoveSeq[x] := -1 END;
	count1 :=  0; count2 := 0;
	SetUp(black)
END Start;

BEGIN	RandomNumbers.InitSeed(Oberon.Time())
END Slide5.

System.Free Slide5~
Slide5.Desc
LayLa.OpenAsDoc
{ This game board definition is parameterized. }
(CONFIG
	(DEF Arrow
		(CONFIG
			(DEF me "")
			(SCOPY Connect4.Arrow (ATTR Name=me Color=13 Cmd="Slide5.Play")))
	)
	(DEF ArrowR
		(CONFIG
			(DEF me "")
			(SCOPY Connect4.ArrowR (ATTR Name=me Color=13 Cmd="Slide5.Play")))
	)
	(DEF ArrowC
		(CONFIG
			(DEF me "")
			(SCOPY Connect4.Arrow (ATTR Name=me Color=13 Cmd="Slide5.Play" Turn=0)))
	)
	(DEF Token
		(CONFIG
			(DEF me "")
			(DEF mycolor 0)
			(NEW Circle (ATTR Name=me Color=mycolor Filled=TRUE)))
	)
	(DEF player1 (NEW Integer))

	(DEF player2 (NEW Integer))

		(TABLE Panel (border=8 cols=7 hjustify=CENTER vjustify=CENTER)
		(ATTR Name="Panel" Color=10 Locked=TRUE)
		(LINKS Model=(NEW String (ATTR Name="Player" Value="0")))

		(SPAN 1 6
			(NEW Caption (ATTR Value="Person plays"))
		)
		(NEW Caption (ATTR Value="Computer plays"))

		VIRTUAL
		(NEW Arrow (PARAMS me="1")) (NEW Arrow (PARAMS me="2")) (NEW Arrow (PARAMS me="3"))
		(NEW Arrow (PARAMS me="4")) (NEW Arrow (PARAMS me="5")) (NEW ArrowC (PARAMS me="0"))

	{ The object named "0.0" is a the upper left corner of the board.
		The attribute Name denotes the cartesian coordinates of a tile. }
		(NEW ArrowR (PARAMS me="6"))
		(NEW Token (PARAMS me="0.0")) (NEW Token (PARAMS me="1.0")) (NEW Token (PARAMS me="2.0"))
		(NEW Token (PARAMS me="3.0")) (NEW Token (PARAMS me="4.0"))  VIRTUAL

		(NEW ArrowR (PARAMS me="7"))
		(NEW Token (PARAMS me="0.1")) (NEW Token (PARAMS me="1.1")) (NEW Token (PARAMS me="2.1"))
		(NEW Token (PARAMS me="3.1")) (NEW Token (PARAMS me="4.1")) VIRTUAL

		(NEW ArrowR (PARAMS me="8"))
		(NEW Token (PARAMS me="0.2")) (NEW Token (PARAMS me="1.2")) (NEW Token (PARAMS me="2.2"))
		(NEW Token (PARAMS me="3.2")) (NEW Token (PARAMS me="4.2")) VIRTUAL

		(NEW ArrowR (PARAMS me="9"))
		(NEW Token (PARAMS me="0.3")) (NEW Token (PARAMS me="1.3")) (NEW Token (PARAMS me="2.3"))
		(NEW Token (PARAMS me="3.3")) (NEW Token (PARAMS me="4.3")) VIRTUAL

		(NEW ArrowR (PARAMS me="10"))
		(NEW Token (PARAMS me="0.4")) (NEW Token (PARAMS me="1.4")) (NEW Token (PARAMS me="2.4"))
		(NEW Token (PARAMS me="3.4")) (NEW Token (PARAMS me="4.4")) VIRTUAL

		(NEW Caption (ATTR Value="Player 1"))
		(NEW Caption (ATTR Value="Person"))
		(NEW CheckBox (ATTR Name="Player1" SetVal=0) (LINKS Model=player1))
		(NEW Caption (ATTR Value="Player 2"))
		(NEW Caption (ATTR Value="Person"))
		(NEW CheckBox (ATTR Name="Player2" SetVal=0) (LINKS Model=player2))

		(SPAN 2 1
		(NEW Button (vjustifyMe=CENTER) (ATTR Caption="New game" Cmd="Slide5.Start")
					(LINKS Model=(NEW Boolean (ATTR Name="GameOn" Value=TRUE))))
		)

		VIRTUAL
		(NEW Caption (ATTR Value="Computer"))
		(NEW CheckBox (ATTR SetVal=1) (LINKS Model=player1))
		VIRTUAL
		(NEW Caption (ATTR Value="Computer"))
		(NEW CheckBox (ATTR SetVal=1) (LINKS Model=player2))

)))
~

=====================
(* MiniMax algorithm to apply to the current play field PlayFld *)
PROCEDURE MiniMax(alpha, beta, level: INTEGER; thisboard: board; VAR bestmove: INTEGER; VAR value: INTEGER);
VAR j, k, tryat: INTEGER; nextboard: board; res: INTEGER; bmove, bvalue: INTEGER; finished: BOOLEAN;
BEGIN
	bestmove := 0;
	finished := FALSE;
	Out.String(" ( lev"); Out.Int(level, 2);
	IF level < 2 THEN
		tryat := 1;
		IF (level MOD 2) = 0 THEN
			WHILE (tryat <= portMax) & ((res = 0) OR (res = 2) OR ~finished) DO
				Out.Ln; Out.String("Yellow (-1):"); Out.Int(tryat, 3);
				TryPush(thisboard, tryat, white, nextboard);	(* white ???????? *)
				res := Wins(nextboard);
				IF res = 0 THEN
					MiniMax(alpha, beta, level+1, nextboard, bmove, bvalue);
					IF bvalue # -100 THEN
						IF bvalue > alpha THEN alpha := bvalue; bestmove := tryat END;
						IF alpha >= beta THEN (* value := alpha; *) finished := TRUE END
					END;
				ELSIF (res = 1) OR (res = 3) THEN Out.String(" Wins");
					bestmove := tryat;
					alpha := 100
				END;
				INC(tryat)
			END;
			value := alpha
		ELSE
			WHILE (tryat <= portMax) & ((res = 0) OR (res = 1) OR ~finished) DO
				Out.Ln; Out.String("Red (1) at:"); Out.Int(tryat, 3);
				TryPush(thisboard, tryat, black, nextboard);	(* black ???????? *)
				res := Wins(nextboard);
				IF res = 0 THEN
					MiniMax(alpha, beta, level+1, nextboard, bmove, bvalue);
					IF bvalue # 100 THEN
						IF bvalue < beta THEN beta := bvalue; bestmove := tryat END;
						IF alpha >= beta THEN (* value := beta; *) finished := TRUE END
					END;
				ELSIF (res = 2) OR (res = 3) THEN Out.String(" Wins");
					bestmove := tryat;
					beta := -100
				END;
				INC(tryat)
			END;
			value := beta
		END
	ELSE
		value := 0;
		FOR j := 1 TO height DO
			FOR k := 1 TO width DO value := value + thisboard[j, k] END
		END
	END;
	Out.String(") "); 
	Out.String(" A"); Out.Int(alpha, 5); Out.String(" B"); Out.Int(beta, 5); Out.String(" val"); Out.Int(value, 5);
END MiniMax;

