(* OBERON System 3, Release 2.3.

Copyright 1999 ETH Zrich Institute for Computer Systems, 
ETH Center, CH-8092 Zrich. e-mail: oberon@inf.ethz.ch.

This module may be used under the conditions of the general Oberon 
System 3 license contract. The full text can be downloaded from

	"ftp://ftp.inf.ethz.ch/pub/software/Oberon/System3/license.txt;A"

Under the license terms stated it is in particular (a) prohibited to modify
the interface of this module in any way that disagrees with the style
or content of the system and (b) requested to provide all conversions
of the source code to another platform with the name OBERON. *)

MODULE V24;	(** portable *)	(* pjm/ejz / as*)

(** V24/RS232 serial communications interface. *)

(*
		2014-04-30	made dummy Module
		2016-04-03	removed NumberOfPorts, added Open, Close; q&d implementation
		2016-04-07	added ODSYNC flag in Open0; flushing in Stopq
		set parameters via "stty -F " on linux
*)

IMPORT SYSTEM, Linux0;

CONST
	(** port aliases  (check with NumberOfPorts), to be removed*)
	COM1* = 0;  COM2* = 1;  COM3* = 2;  COM4* = 3;
	
	(** parity *)
	ParNo* = 0;  ParOdd* = 1;  ParEven* = 2;  ParMark* = 3;  ParSpace* = 4;
	(** stop bits *)
	Stop1* = 1;  Stop2* = 2;  Stop1dot5* = 3;
	(** modem control - MC *)
	DTR* = 0;  RTS* = 1;	(** output *)
	Break* = 2;	(** input/output *)
	DSR* = 3;  CTS* = 4;  RI* = 5;  DCD* = 6;	(** input *)
	
	Ok* =  0; PortInUse* =  1; NoSuchPort* =  2; WrongBPS* =  3; WrongData* =  4; WrongParity* =  5;
	WrongStop* =  6; Failed* =  MAX(INTEGER);	

PROCEDURE Open*( ttyname: ARRAY OF CHAR): LONGINT;
BEGIN
	RETURN Linux0.Openat0( Linux0.ATFDCWD, SYSTEM.ADR(ttyname[0]), Linux0.ORDWR+Linux0.ODSYNC , 0);
END Open;

PROCEDURE Close*( VAR tty: LONGINT);
BEGIN
	tty:=Linux0.Close0(tty); 
END Close;

(** Start - Open a serial port (numbered from 0).  bps is the required bits per second.
	data is the number of bits per communication unit.  parity is the parity mode (Par 
	values above).  stop is the number of stop bits (Stop values above).  res returns 0 
	if ok, or error code on error.  1 means port already in use.  2 means no such port.  
	3 means bad bps value.  4 means bad data/parity/stop.   DTR and RTS are enabled. *)
	
PROCEDURE Start*(port, bps, data, parity, stop: LONGINT;  VAR res: LONGINT);
BEGIN
	IF port>0 THEN res := Ok
	ELSE res:= Failed;
	END;
END Start;

(** Stop - Close the specified port.  Effect on Modem Control lines is undefined. *)

PROCEDURE Stop*(port: LONGINT);
CONST TCFLSH=540BH; TCIOFLUSH=2; 
VAR res: LONGINT;
BEGIN
	res:=Linux0.IOCtl0(port, TCFLSH, TCIOFLUSH);
END Stop;

(** Available - Return the number of bytes available in the specified port's buffer. *)

PROCEDURE Available*(port: LONGINT): LONGINT;
TYPE	TimeVal= RECORD tvsec, tvusec: LONGINT END;
VAR fd: ARRAY 4 OF SET; i: LONGINT; timeout: TimeVal;
BEGIN
	timeout.tvsec:=0; timeout.tvusec:= 0;		(* don't block at all *)
	FOR i:=0 TO 3 DO fd[i]:={} END;
	INCL(fd[port DIV 32], port MOD 32);
	RETURN Linux0.Select0( port+1, SYSTEM.ADR( fd), 0, 0, SYSTEM.ADR( timeout));
END Available;

(** Receive - Read one byte from the specified port.  Waits until a byte is available.  res = 0 iff ok. *)

PROCEDURE Receive*(port: LONGINT;  VAR x: SYSTEM.BYTE;  VAR res: LONGINT);
BEGIN
	res:=Linux0.Read0( port, SYSTEM.ADR( x), 1);
	IF res=1 THEN res:=Ok
	ELSE res:=Failed
	END;
END Receive;

(** ReceiveBytes - Read n bytes from the specified port.  Waits until n bytes are available.  res = Ok iff ok. *)

PROCEDURE ReceiveBytes*(port: LONGINT;  VAR x: ARRAY OF SYSTEM.BYTE;  n: LONGINT;  VAR res: LONGINT);
BEGIN
	res:=Linux0.Read0( port, SYSTEM.ADR( x), n);
	IF res=n THEN res:=Ok
	ELSE res:=Failed
	END;
END ReceiveBytes;

(** Send - Send a byte to the specified port.  Waits until buffer space is available.  res = Ok iff ok. *)

PROCEDURE Send*(port: LONGINT;  x: SYSTEM.BYTE;  VAR res: LONGINT);
BEGIN
	res:=Linux0.Write0( port, SYSTEM.ADR( x), 1);
	IF res=1 THEN res:=Ok
	ELSE res:=Failed
	END;
END Send;

(** SendBytes - Send n bytes to the specified port.  Waits until buffer space is available.  res = Ok iff all ok. *)

PROCEDURE SendBytes*(port: LONGINT;  VAR x: ARRAY OF SYSTEM.BYTE;  n: LONGINT;  VAR res: LONGINT);
BEGIN
	res:=Linux0.Write0( port, SYSTEM.ADR( x), n);
	IF res=n THEN res:=Ok
	ELSE res:=Failed
	END;
END SendBytes;

(** ClearMC - Clear the specified Model Control lines of the specified port.  s may contain DTR, RTS & Break. *)

PROCEDURE ClearMC*(port: LONGINT;  s: SET);
BEGIN
END ClearMC;

(** SetMC - Set the specified Model Control lines of the specified port.  s may contain DTR, RTS & Break. *)

PROCEDURE SetMC*(port: LONGINT;  s: SET);
BEGIN
END SetMC;

(** GetMC - Return the state of the specified Model Control lines of the specified port.  s contains
	the current state of DSR, CTS, RI, DCD & Break. *)
	
PROCEDURE GetMC*(port: LONGINT;  VAR s: SET);
BEGIN
END GetMC;

BEGIN
END V24.
