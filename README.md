# TrueBend

SketchUp extension allowing you to bend instances to a given degree or radius, preserving the original length.

## Example Usage

![](docs/TrueBendDemo01.gif)

Use the VCB to enter an accurate bend angle:

![](docs/TrueBendVCBAngle.gif)

Use the VCB to adjust the segmentation by appending "s":

![](docs/TrueBendSegments.gif)

Toggle soft+smooth for the newly created edges:

![](docs/TrueBendSegmentedOption.gif)

## VCB Input

By default the VCB accept bend angle. But you can switch to other modes by appending a unit type:

* Angle Input: `45deg`
* Segment Count: `8s`
* Bend Distance: `500mm` (This should be a value less than the width of the bottom from bounding box segment.)
