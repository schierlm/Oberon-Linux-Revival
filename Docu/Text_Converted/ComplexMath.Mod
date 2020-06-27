(* ETH Oberon, Copyright 1990-2003 Computer Systems Institute, ETH Zurich, CH-8092 Zurich.
Refer to the license.txt file provided with this distribution. *)

MODULE ComplexMath;	(** non-portable *)	(* pjm *)

(* Note: Operator overloading is an experimental feature 
available in Native Oberon only *)

TYPE
	Complex* = RECORD
		r, i: LONGREAL
	END;

PROCEDURE Gen*(real, imag: LONGREAL): Complex;
VAR t: Complex;
BEGIN
	t.r := real;  t.i := imag;
	RETURN t
END Gen;

PROCEDURE "-"*(a: Complex): Complex;
BEGIN
	a.r := -a.r;
	a.i := -a.i;
	RETURN a
END "-";

PROCEDURE "+"*(a, b: Complex): Complex;
VAR t: Complex;
BEGIN
	t.r := a.r + b.r;
	t.i := a.i + b.i;
	RETURN t
END "+";

PROCEDURE "-"*(a, b: Complex): Complex;
BEGIN
	RETURN a + (-b)
END "-";

PROCEDURE "*"*(a, b: Complex): Complex;
VAR t: Complex;
BEGIN
	t.r := a.r * b.r - a.i * b.i;
	t.i := a.r * b.i + b.r * a.i;
	RETURN t
END "*";

PROCEDURE "~" *(a: Complex): Complex;
VAR t: Complex;  x: LONGREAL;
BEGIN
	x := a.r * a.r + a.i * a.i;
	t.r := a.r / x;
	t.i := -a.i / x;
	RETURN t
END "~";

PROCEDURE "="*(a, b: Complex): BOOLEAN;
BEGIN
	RETURN (a.r = b.r) & (a.i = b.i)
END "=";

PROCEDURE Re*(a: Complex): LONGREAL;
BEGIN
	RETURN a.r
END Re;

PROCEDURE Im*(a: Complex): LONGREAL;
BEGIN
	RETURN a.i
END Im;

END ComplexMath.
