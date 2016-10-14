# this is a port of https://github.com/MircoT/pyTGA
import streams, strutils


type
  Header = object
  #[
    Here we have some details for each field:
    Field(1)
    ID LENGTH (1 byte):
      Number of bites of field 6, max 255.
      Is 0 if no image id is present.

    Field(2)
    COLOR MAP TYPE (1 byte):
      - 0 : no color map included with the image
      - 1 : color map included with the image

    Field(3)
    IMAGE TYPE (1 byte):
      - 0  : no data included
      - 1  : uncompressed color map image
      - 2  : uncompressed true color image
      - 3  : uncompressed black and white image
      - 9  : run-length encoded color map image
      - 10 : run-length encoded true color image
      - 11 : run-length encoded black and white image

    Field(4)
    COLOR MAP SPECIFICATION (5 bytes):
      - first_entry_index (2 bytes) : index of first color map entry
      - color_map_length  (2 bytes)
      - color_map_entry_size (1 byte)

     Field(5)
    IMAGE SPECIFICATION (10 bytes):
      - x_origin  (2 bytes)
      - y_origin  (2 bytes)
      - image_width   (2 bytes)
      - image_height  (2 bytes)
      - pixel_depht   (1 byte):
          - 8 bit  : grayscale
          - 16 bit : RGB (5-5-5-1) bit per color
                     Last one is alpha (visible or not)
          - 24 bit : RGB (8-8-8) bit per color
          - 32 bit : RGBA (8-8-8-8) bit per color
      - image_descriptor (1 byte):
          - bit 3-0 : number of attribute bit per pixel
          - bit 5-4 : order in which pixel data is transferred
                      from the file to the screen
     +-----------------------------------+-------------+-------------+
     | Screen destination of first pixel | Image bit 5 | Image bit 4 |
     +-----------------------------------+-------------+-------------+
     | bottom left                       |           0 |           0 |
     | bottom right                      |           0 |           1 |
     | top left                          |           1 |           0 |
     | top right                         |           1 |           1 |
     +-----------------------------------+-------------+-------------+
          - bit 7-6 : must be zero to insure future compatibility

    ]#

    # Field(1)
    id_length: int
    # Field(2)
    color_map_type: int
    # Field(3)
    image_type: int
    # Field(4)
    first_entry_index: int
    color_map_length: int
    color_map_entry_size: int
    # Field(5)
    x_origin: int
    y_origin: int
    image_width: int
    image_height: int
    pixel_depth: int
    image_descriptor: int

  Footer = object
    extension_area_offset: int  # 4 bytes
    developer_directory_offset: int # 4 bytes
    signature, dot, eend: string
  PixelKind = enum
    pkBW,
    pkRGB,
    pkRGBA
  Pixel = object
    case kind: PixelKind
    of pkBW: bw_val: int
    of pkRGB: rgb_val: tuple[r, g, b: int]
    of pkRGBA: rgba_val: tuple[r, g, b, a: int]
  Image* = object
    header: Header
    footer: Footer
    new_tga_format: bool
    first_pixel: int
    bottom_left: int
    bottom_right: int
    top_left: int
    top_right: int
    pixels: seq[seq[Pixel]]

proc get_rgb_from_16(data: int16): tuple[r, g, b: int] =
    #[
    Construct an RGB color from 16 bit of data.
    Args:
        second_byte (bytes): the first bytes read
        first_byte (bytes): the second bytes read
    Returns:
        tuple(int, int, int): the RGB color
    ]#
    let c_r = cast[uint8]((data and 0b1111100000000000) shr 11)
    let c_g = cast[uint8]((data and 0b0000011111000000) shr 6)
    let c_b = cast[uint8]((data and 0b111110) shr 1)
    result.r = c_r.int
    result.g = c_g.int
    result.b = c_b.int

proc ImageNew(): Image =
  result.header = Header()
  result.footer = Footer()
  result.pixels = @[]
  result.pixels.add(@[])
  result.new_tga_format = false

  # Screen destination of first pixel
  result.bottom_left = 0b0
  result.bottom_right = 0b1 shl 4
  result.top_left = 0b1 shl 5
  result.top_right = 0b1 shl 4 or 0b1 shl 5

  # Default values
  result.first_pixel = result.top_left


proc load*(self: var Image, file_name: string) =

  template to_int(expr: untyped): int =
    cast[uint8](expr).int

  proc parse_pixel(self: var Image, fs: var FileStream): Pixel =
    if self.header.image_type in [3, 11]:
      let val = fs.readInt8().to_int
      # echo val
      result = Pixel(kind: pkBW, bw_val: val)
    elif self.header.image_type in [2, 10]:
      case self.header.pixel_depth
      of 16:
        result = Pixel(
          kind: pkRGB,
          rgb_val: get_rgb_from_16(fs.readInt16()))
      of 24:
        result = Pixel(
          kind: pkRGB,
          rgb_val: (fs.readInt8().to_int, fs.readInt8().to_int, fs.readInt8().to_int)
        )
      of 32:
        result = Pixel(
          kind: pkRGBA,
          rgba_val: (fs.readInt8().to_int, fs.readInt8().to_int, fs.readInt8().to_int, fs.readInt8().to_int)
        )
      else: raise newException(ValueError, "unsupported image type")

  var
    f: File
    fs: FileStream
  if not open(f, file_name, fmRead):
    raise newException(IOError, "Failed to open file: $#" % file_name)

  fs = newFileStream(f)
  if isNil(fs):
    raise newException(IOError, "Failed to open file: $#" % file_name)

  defer: fs.close()

  self.header.id_length = fs.readInt8().int
  self.header.color_map_type = fs.readInt8().int
  self.header.image_type = fs.readInt8().int
  self.header.first_entry_index = fs.readInt16().int
  self.header.color_map_length = fs.readInt16().int
  self.header.color_map_entry_size = fs.readInt8().int
  self.header.x_origin = fs.readInt16().int
  self.header.y_origin = fs.readInt16().int
  self.header.image_width = fs.readInt16().int
  self.header.image_height = fs.readInt16().int
  self.header.pixel_depth = fs.readInt8().int
  self.header.image_descriptor = fs.readInt8().int

  let original_position = fs.getPosition()

  fs.setPosition(getFileSize(f).int - 26)
  self.footer.extension_area_offset = fs.readInt32().int
  self.footer.developer_directory_offset = fs.readInt32().int
  self.footer.signature = fs.readStr(16)
  self.footer.dot = fs.readStr(1)
  self.footer.eend = fs.readStr(1)

  if self.footer.signature == "TRUEVISION-XFILE":
    self.new_tga_format = true
  fs.setPosition(original_position)

  # no compression
  if self.header.image_type in [2, 3]:
    for row in 0 .. self.header.image_height - 1:
      self.pixels.add(@[])
      for col in 0 .. self.header.image_width - 1:
        self.pixels[row].add(self.parse_pixel(fs))
  # compressed
  elif self.header.image_type in [10, 11]:
    # echo "compressed"
    let
      tot_pixels = self.header.image_height * self.header.image_width
    var
      pixel_count = 0
      row = 0
    while pixel_count <= tot_pixels:
      if self.pixels[row].high >= self.header.image_width:
        self.pixels.add(@[])
        # echo self.pixels[row].high
        # echo row
        inc(row)
      let repetition_count = fs.readInt8()
      let RLE: bool = (repetition_count and 0b10000000) shr 7 == 1
      let count: int = (repetition_count and 0b01111111).int + 1
      pixel_count += count
      # echo pixel_count
      if RLE:
        let pixel = self.parse_pixel(fs)
        for num in 0 .. count:
          self.pixels[row].add(pixel)
      else:
        for num in 0 .. count:
          self.pixels[row].add(self.parse_pixel(fs))

template write_value(f: typed, data: typed) =
  # echo data
  let data_size = sizeof(data)
  let written_data = f.writeBuffer(addr data, data_size)
  assert written_data == data_size

proc write_header(f: var File, image: ptr Image) =
  f.write_value(image.header.id_length)
  f.write_value(image.header.color_map_type)
  f.write_value(image.header.image_type)
  f.write_value(image.header.first_entry_index)
  f.write_value(image.header.color_map_length)
  f.write_value(image.header.color_map_entry_size)
  f.write_value(image.header.x_origin)
  f.write_value(image.header.y_origin)
  f.write_value(image.header.image_width)
  f.write_value(image.header.image_height)
  f.write_value(image.header.pixel_depth)
  f.write_value(image.header.image_descriptor)

proc write_footer(f: var File, image: ptr Image) =
  f.write_value(image.footer.extension_area_offset)
  f.write_value(image.footer.developer_directory_offset)
  f.write_value(image.footer.signature)
  f.write_value(image.footer.dot)
  f.write_value(image.footer.eend)

proc save*(self: var Image, filename: string, compress=false, force_16_bit=false) =
  echo self.pixels[0].len
  echo self.pixels.len
  # ID LENGTH
  self.header.id_length = 0
  # COLOR MAP TYPE
  self.header.color_map_type = 0
  # COLOR MAP SPECIFICATION
  self.header.first_entry_index = 0
  self.header.color_map_length = 0
  self.header.color_map_entry_size = 0
  # IMAGE SPECIFICATION
  self.header.x_origin = 0
  self.header.y_origin = 0
  self.header.image_width = self.pixels[0].len
  self.header.image_height = self.pixels.len
  self.header.image_descriptor = 0b0 or self.first_pixel

  # IMAGE TYPE
  # IMAGE SPECIFICATION (pixel_depht)
  let tmp_pixel = self.pixels[0][0]
  case tmp_pixel.kind
  of pkBW:
    self.header.image_type = 3
    self.header.pixel_depth = 8
  of pkRGB:
    self.header.image_type = 2
    if force_16_bit:
      self.header.pixel_depth = 16
    else:
      self.header.pixel_depth = 24
  of pkRGBA:
    self.header.image_type = 2
    self.header.pixel_depth = 32
  else: raise newException(ValueError, "invalid pixel kind")

  if compress:
    case self.header.image_type
    of 3: self.header.image_type = 11
    of 2: self.header.image_type = 10
    else: discard

  var f = open(filename & ".tga", fmWrite)
  defer: f.close()
  if isNil(f):
    raise newException(IOError, "Failed to open/create file: $#" % filename)

  var p: Pixel
  f.write_header(addr self)
  if not compress:
    for row in self.pixels:
      for pixel in row:
        case self.header.image_type
        # of 3: p = pixel; f.write_value(p)
        of 3: discard
        of 2:
          case self.header.pixel_depth
          of 16: discard
          of 24: discard
          of 32: discard
          else: raise newException(ValueError, "invalid pixel depth")
        else: raise newException(ValueError, "invalid pixel kind")
        # if self._header.image_type == 3:
        # elif self._header.image_type == 2:
        #   if self._header.pixel_depht == 16:
        #     image_file.write(gen_pixel_rgb_16(*pixel))
        #   elif self._header.pixel_depht == 24:
        #     image_file.write(gen_pixel_rgba(*pixel))
        #   elif self._header.pixel_depht == 32:
        #     image_file.write(gen_pixel_rgba(*pixel))

  f.write_footer(addr self)

var image = ImageNew()
image.load("image_bw.tga")
image.save("ceva")
echo repr(image.header)
