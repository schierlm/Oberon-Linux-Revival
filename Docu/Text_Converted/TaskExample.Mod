(* ETH Oberon, Copyright 1990-2003 Computer Systems Institute, ETH Zurich, CH-8092 Zurich.
Refer to the license.txt file provided with this distribution. *)

MODULE TaskExample;	(* es *)

(* An simple example for using a task. It just prints the time every 10 seconds. *)

IMPORT Modules, Input, Oberon, Out, System;

VAR
	task : Oberon.Task;

PROCEDURE *Hello(me : Oberon.Task);
BEGIN
	System.Time;
	me.time := Input.Time() + Input.TimeUnit * 10 (* wait 10 seconds *)
END Hello;

PROCEDURE Start* ();
BEGIN
	IF task = NIL THEN
		NEW(task); task.handle := Hello; task.safe := FALSE; (* I'm written by a user :-) *)
		task.time := Input.Time();
		Oberon.Install(task)
	END
END Start;

PROCEDURE Stop* ();
BEGIN
	IF task # NIL THEN 
		Oberon.Remove(task); task := NIL;
		Out.String("Task stopped"); Out.Ln
	END
END Stop;

BEGIN
	Modules.InstallTermHandler(Stop);
	task := NIL
END TaskExample.

TaskExample.Start
TaskExample.Stop

System.Free TaskExample ~
