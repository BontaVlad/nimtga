import marshal, streams, msgpack, strutils

import pymod
import pymodpkg/docstrings
import pymodpkg/pyarrayobject

import nimtga

proc loads*(filename: string): tuple[header, footer: string, pixels: ptr PyArrayObject] {.exportpy, returnDict.}=
  let
    image = newImage(filename)
  result.header = $$image.header
  result.footer = $$image.footer
  result.pixels = createSimpleNew([image.pixels.len, 3], np_uint8)
  doFILLWBYTE(result.pixels, 255)

  # TODO this has image pixel depth hardcoded for rgb
  var i = 0
  for mval in result.pixels.accessFlat(uint8).mitems:  # Forward-iterate through the array.
    mval = image.getPixelValue(i div 3, i mod 3)
    # echo "loaded mval: " & $mval
    inc(i)

proc saves*(header, footer: string, pixels: ptr PyArrayObject, filename: string) {.discardable, exportpy.}=
  var
    image = newImage(to[Header](header), to[Footer](footer))
    i = 0
    pixel = newPixel(0, 0, 0)
    index = 0

  # TODO this has image pixel depth hardcoded for rgb
  # TODO: use shape value
  for mval in pixels.accessFlat(uint8).mitems:  # Forward-iterate through the array.
    case i
    of 0:
      pixel.rgb_val.r = mval
      inc(i)
    of 1:
      pixel.rgb_val.g = mval
      inc(i)
    of 2:
      i = 0
      pixel.rgb_val.b = mval
      image.pixels[index] = pixel
      inc(index)
    else: discard
  image.save(filename)

initPyModule("_ntga", loads, saves)
