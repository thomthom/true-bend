# Icon Creation Process

## Model in SketchUp

* Use SafeFrames to set aspect ratio to 1:1 for guidance

## Import SKP in LayOut

* Set Render Mode to Vector
* Export to PDF

## Import PDF in Illustrator

* Set up artboard for 32x32 and 24x24
* Place (Embed) PDF
* Adjust stroke to better match pixel grid
* Export SVG
  * Styling > Inline Styling (Otherwise SU doesn't draw SVG correctly)

## Convert SVG with Inkscape

"C:\Program Files\Inkscape\inkscape.exe" -f "src\tt_truebend\images\bend-32.svg" -A "src\tt_truebend\images\bend-32.pdf" -z
"C:\Program Files\Inkscape\inkscape.exe" -f "src\tt_truebend\images\bend-24.svg" -A "src\tt_truebend\images\bend-24.pdf" -z

## Convert to PNG with PhotoShop

Illustrator and Inkscape both doesn't downsize the PNG well. Ugly artifacts.
Better to save out a larger version and resize down.

* Import SVG or PDF at larger size; 128x128
* Scale down using Bicubic (Smooth Gradients)
