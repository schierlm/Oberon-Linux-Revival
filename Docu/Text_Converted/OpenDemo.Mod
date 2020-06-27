(* ETH Oberon, Copyright 1990-2003 Computer Systems Institute, ETH Zurich, CH-8092 Zurich.
Refer to the license.txt file provided with this distribution. *)

(*
	OpenDemo.Mod, jm 03.11.93

	This is a example program for opening your own panel documents from
	program control. Note that only panels and their extensions can be
	handled here. Using any other gadget class will cause a trap.
	Note that the menubar is fixed. Your panel will be able
	to save itself and can be reloaded again from disk exactly as
	it was created.
	
	If you need to change certain attributes of your panel,
	for example the icon used, or the menu bar required, 
	please inspect the files OpenDemo2.Mod and 
	DocumentSkeleton.Mod 
*)

MODULE OpenDemo;

IMPORT
	Objects, Gadgets, PanelDocs, Documents, Desktops;
	
PROCEDURE ShowGadget(name: ARRAY OF CHAR; main: Gadgets.Frame);
VAR D: Documents.Document;
BEGIN
	PanelDocs.NewDoc; (* create a new document *)
	D := Objects.NewObj(Documents.Document);
	
	COPY(name, D.name); 
	Documents.Init(D, main);
	
	Desktops.ShowDoc(D)
END ShowGadget;

PROCEDURE Do*;
VAR P: Objects.Object;
BEGIN
	P := Gadgets.CreateObject("Panels.NewPanel");
	
	ShowGadget("Test.Panel", P(Gadgets.Frame))
END Do;


(* Second example *)

PROCEDURE Open*;
VAR D: Documents.Document;
BEGIN
	D := Documents.Open("Desktops.Tool");
	IF D # NIL THEN Desktops.ShowDoc(D) END
END Open;

END OpenDemo.

OpenDemo.Do
OpenDemo.Open