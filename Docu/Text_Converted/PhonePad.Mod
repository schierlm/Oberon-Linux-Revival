(* ETH Oberon, Copyright 1990-2003 Computer Systems Institute, ETH Zurich, CH-8092 Zurich.
Refer to the license.txt file provided with this distribution. *)

MODULE PhonePad; (*JG 27.7.94*)

  IMPORT Objects, Texts, Gadgets, Attributes, Links;

  VAR W: Texts.Writer;

  PROCEDURE Search*;
    VAR log: Objects.Object; T: Texts.Text;
      Name, FName, Business, Street, City, PhoneNo: ARRAY 64 OF CHAR;
  BEGIN
    Attributes.GetString(Gadgets.FindObj(Gadgets.context, "Name"), "Value", Name);
    Attributes.GetString(Gadgets.FindObj(Gadgets.context, "FName"), "Value", FName);
    Attributes.GetString(Gadgets.FindObj(Gadgets.context, "Business"), "Value", Business);
    Attributes.GetString(Gadgets.FindObj(Gadgets.context, "Street"), "Value", Street);
    Attributes.GetString(Gadgets.FindObj(Gadgets.context, "City"), "Value", City);
    Attributes.GetString(Gadgets.FindObj(Gadgets.context, "PhoneNo"), "Value", PhoneNo);
    Links.GetLink(Gadgets.FindObj(Gadgets.context, "Log"), "Model", log);
    T := log(Texts.Text);
    IF PhoneNo[0] # 0X THEN
        Texts.WriteString(W, "T-Query ");
        Texts.WriteString(W, PhoneNo)
    ELSIF Name[0] # 0X THEN
      IF FName[0] # 0X THEN
        Texts.WriteString(W, "NFC-Query ");
        Texts.WriteString(W, Name); Texts.Write(W, " ");
        Texts.WriteString(W, FName); Texts.Write(W, " ");
        Texts.WriteString(W, City)
      ELSE Texts.WriteString(W, "NC-Query ");
        Texts.WriteString(W, Name); Texts.Write(W, " ");
        Texts.WriteString(W, City)
      END
    ELSIF Street[0] # 0X THEN
      Texts.WriteString(W, "SC-Query ");
        Texts.WriteString(W, Street); Texts.Write(W, " ");
        Texts.WriteString(W, City)
    ELSIF Business[0] # 0X THEN
      Texts.WriteString(W, "BC-Query ");
        Texts.WriteString(W, Business); Texts.Write(W, " ");
        Texts.WriteString(W, City)
    ELSE Texts.WriteString(W, "incomplete")
    END;
    Texts.WriteLn(W);
    Texts.Append(T, W.buf)
  END Search;

BEGIN Texts.OpenWriter(W)
END PhonePad.
