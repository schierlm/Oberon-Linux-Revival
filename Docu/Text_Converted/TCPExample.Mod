(* ETH Oberon, Copyright 1990-2003 Computer Systems Institute, ETH Zurich, CH-8092 Zurich.
Refer to the license.txt file provided with this distribution. *)

(* TCPExample.Mod, ejz 

	This module illustrates how to use the TCP based part of NetSystem.
	A command Time is implemented, which ask your time server for the current time. *)

MODULE TCPExample;	(** portable *)
	IMPORT Input, NetSystem, Texts, Oberon;

	CONST
	(* your local time server *)
		TimeHost = "129.132.134.2"; TimePort = 13;
		TimeOut =  10;

	VAR
		W: Texts.Writer;

(** TCPExample.Time
	ask your time server for the current time. *)
	PROCEDURE Time*;
		VAR
			IP: NetSystem.IPAdr;
			C: NetSystem.Connection;
			str: ARRAY 64 OF CHAR;
			n, time: LONGINT;
			res: INTEGER;
	BEGIN
	(* connect to TimeHost:TimePort *)
		NetSystem.GetIP(TimeHost, IP);
		NetSystem.OpenConnection(C, NetSystem.anyport, IP, TimePort, res);
		IF res = NetSystem.done THEN
		(* wait for a response *)
			n := NetSystem.Available(C); time := Input.Time()+TimeOut*Input.TimeUnit;
			WHILE (n <= 0) & (Input.Time() - time < 0) DO
				n := NetSystem.Available(C)
			END;
			IF n > 0 THEN
		(* read the response *)
				NetSystem.ReadString(C, str);
				Texts.WriteString(W, str)
			ELSE
				Texts.WriteString(W, "time out")
			END;
		(* release the connection *)
			NetSystem.CloseConnection(C)
		ELSE
			Texts.WriteString(W, "connecting failed")
		END;
		Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
	END Time;

BEGIN
	Texts.OpenWriter(W)
END TCPExample.

TCPExample.Time

