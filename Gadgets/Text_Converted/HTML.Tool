Simple converter from Oberon text to HTML.

HTML.Compile *	HTML.Compile ^ 
HTML.Show *	HTML.Show ^	HTML.Show @

TestHTML.Text	Test document
			
---  Key:

Filename: Document Title
Heading	Normal text	Italic text	text{anchor}
	
preformatted text (10pt)

* bullet text

- horizontal ruler
	
---

Special characters:

&	&#38;
<	&#60;
>	&#62;

---

Some comments:

HTML.Compile * translates a text to an HTML text.  TestHTML.Text is a sample input file.  Mark it, apply HTML.Compile and you will get a file named TestHTML.html.  The target file name is the first word in the file.  In the input, color of text has significance; header information is in red, links are in blue.  It is explained in TestHTML.Text and also in HTML.Mod.  
