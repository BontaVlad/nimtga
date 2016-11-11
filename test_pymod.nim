# import msgpack, streams

import pymod
import pymodpkg/docstrings

type
  ImageTuple = tuple[
    id_length,
    color_map_type,
    image_type,
    first_entry_index,
    color_map_length,
    color_map_entry_size,
    x_origin,
    y_origin,
    image_width,
    image_height,
    pixel_depth,
    image_descriptor: int
    ]

import nimtga

# proc pack_type*(s: Stream, img: Image) =
#   s.pack(img.header)
#   s.pack(img.pixels)
#   s.pack(img.footer)

# proc unpack_type*(s: Stream, img: var Image) =
#   s.unpack(img.header)
#   s.unpack(img.pixels)
#   s.unpack(img.footer)

# type
#   #not really complex, just for example
#   mycomplexobject = object
#     a: someSimpleType
#     b: someSimpleType

#help the compiler to decide
# proc pack_type*(s: Stream, x: mycomplexobject) =
#   s.pack(x.a) # let the compiler decide
#   s.pack(x.b) # let the compiler decide

# #help the compiler to decide
# proc unpack_type*(s: Stream, x: var complexobject) =
#   s.unpack(x.a)
#   s.unpack(x.b)

# var s: newStringStream()
# var x: mycomplexobject

# s.pack(x) #pack as usual

# s.setPosition(0)
# s.unpack(x) #unpack as usual

proc loads*(filename: string) {.exportpy.} =
  var image = newImage(filename)
  var foo: ImageTuple
  foo.id_length = image.header.id_length.int
  foo.color_map_type = image.header.color_map_type.int
  foo.image_type = image.header.image_type.int
  foo.first_entry_index = image.header.first_entry_index.int
  foo.color_map_length = image.header.color_map_length.int
  foo.color_map_entry_size = image.header.color_map_entry_size.int
  foo.x_origin = image.header.x_origin.int
  foo.y_origin = image.header.y_origin.int
  foo.image_width = image.header.image_width.int
  foo.image_height = image.header.image_height.int
  foo.pixel_depth = image.header.pixel_depth.int
  foo.image_descriptor = image.header.image_descriptor.int
  return foo

# proc saves*(img_str, filename: string) {.discardable, exportpy.}=
#   var image: Image
#   img_str.unpack(image)
#   image.save(filename)

initPyModule("ntga", loads)
