(* ETH Oberon, Copyright 1990-2003 Computer Systems Institute, ETH Zurich, CH-8092 Zurich.
Refer to the license.txt file provided with this distribution. *)

MODULE TestComplex;	(** non-portable *)	(* pjm *)

IMPORT ComplexMath, Out;

PROCEDURE OutComplex(a: ComplexMath.Complex);
BEGIN
	Out.LongReal(ComplexMath.Re(a), 12);
	Out.LongReal(ComplexMath.Im(a), 12);
END OutComplex;

PROCEDURE Test*;
VAR a, b, c, d, e: ComplexMath.Complex;
BEGIN
	a := ComplexMath.Gen(1.0, 2.0);
	b := ComplexMath.Gen(2.0, 3.0);
	OutComplex(a + b);  Out.Ln;
	OutComplex(a * b);  Out.Ln;
	OutComplex(a + (-b));  Out.Ln;
	OutComplex(a - b);  Out.Ln;
	OutComplex(~a);  Out.Ln;
	e := a + b * b + ~(-a) - b;
	OutComplex(e);  Out.Ln;
	c := b*b;  c := a + c;  d := -a;  d := ~d;  c := c + d;  c := c - b;
	OutComplex(c);  Out.Ln;
	IF e = c THEN Out.String("ok") ELSE Out.String("error") END
END Test;

END TestComplex.

TestComplex.Test

System.Free TestComplex ComplexMath ~
