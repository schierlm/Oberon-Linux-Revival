Overview
Color objects, color conversions, and color gadgets come as part of the Images package for ETH Oberon.


Installation
	Compress.Extract
		Images102.Arc Colors.Mod ColorGadgets.Mod Colors.Panel ~
	Compiler.Compile \s
		Colors.Mod ColorGadgets.Mod ~


The Colors Panel

	Desktops.OpenDoc Colors.Panel

The colored gadgets in the Colors.Panel are called color wells and represent the color they display. Using drag&drop (middle+right mouse buttons), color values can be dragged from one color well to another or from a color well to a gadget with a "Color" attribute. There are also buttons for inspecting and changing the color of the current text selection or an attribute of the current gadget selection.

The colored circle in the top right corner displays hue and saturation of the current color, the wedge shaped gadget next to it its saturation and brightness (value). These attributes can be modified by clicking with the middle mouse button in one of the gadgets and dragging the mouse to the location that corresponds to the desired shade. The six sliders in the middle of the panel can also be used to modify color attributes, as can the text fields next to them.

The bottom row of color wells represents the standard colors used within Oberon. Clicking on one of them makes the corresponding color value the new current color.

Note: The color disc and wedge look blocky if your Oberon display driver does not support true color. Colors can still be specified accurately but can only be approximated on the display.


The Colors Module

	Watson.ShowDef Colors ~
