import marshal
# import jsmn
# import  sam

import pymod
import pymodpkg/docstrings
import pymodpkg/pyarrayobject

import nimtga

proc getShape(header: Header): int =
  case header.image_type.int
    of 3, 11:
      result = 1
    of 2, 10:
      case header.pixel_depth
      of 16:
        result = 3
      of 24:
        result = 3
      of 32:
        result = 4
      else: raise newException(ValueError, "unsupported pixel depth")
    else: raise newException(ValueError, "unsupported image type")

proc loads*(filename: string): tuple[header, footer: string, pixels: ptr PyArrayObject] {.exportpy, returnDict.}=
  let image = newImage(filename)
  let shape = getShape(image.header)
  result.header = $$image.header
  result.footer = $$image.footer
  result.pixels = createSimpleNew([image.pixels.high, shape], np_uint8)
  doFILLWBYTE(result.pixels, 0)

  var i = 0
  for mval in result.pixels.accessFlat(uint8).mitems:  # Forward-iterate through the array.
    mval = image.pixels[i div shape][i mod shape]
    discard image.pixels[i div shape]
    inc(i)

proc saves*(header, footer: string, pixels: ptr PyArrayObject, filename: string, compress: int) {.discardable, exportpy.}=
  var
    image = newImage(to[Header](header), to[Footer](footer))
    i = 0

  let shape = pixels.strides[0]
  var pixel_data = newSeq[uint](shape)

  for v in pixels.accessFlat(uint8).items:
    pixel_data[i] = v
    if i == shape - 1:
      image.pixels.add(newPixel(pixel_data))
      pixel_data = newSeq[uint](shape)
      i = -1
    inc(i)

  image.save(filename, compress.bool)

initPyModule("_ntga", loads, saves)
