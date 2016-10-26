# this is a port of https://github.com/MircoT/pyTGA

import streams, strutils, colors


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
    id_length: uint8
    # Field(2)
    color_map_type: uint8
    # Field(3)
    image_type: uint8
    # Field(4)
    first_entry_index: uint16
    color_map_length: uint16
    color_map_entry_size: uint8
    # Field(5)
    x_origin: uint16
    y_origin: uint16
    image_width: uint16
    image_height: uint16
    pixel_depth: uint8
    image_descriptor: uint8

  Footer = object
    extension_area_offset: uint32  # 4 bytes
    developer_directory_offset: uint32 # 4 bytes
    signature, dot, eend: string
  PixelKind* = enum
    pkBW,
    pkRGB,
    pkRGBA
  Pixel* = object
    case kind: PixelKind
    of pkBW: bw_val: tuple[a: uint8]
    of pkRGB: rgb_val: tuple[r, g, b: uint8]
    of pkRGBA: rgba_val: tuple[r, g, b, a: uint8]
  EncodedPixel = tuple[rep_count: uint8, value: Pixel]
  Image* = ref object
    header: Header
    footer: Footer
    new_tga_format: bool
    first_pixel: int
    bottom_left: int
    bottom_right: int
    top_left: int
    top_right: int
    pixels: seq[seq[Pixel]]

proc `==`*(a, b: Pixel): bool =
  if a.kind == b.kind:
    case a.kind
    of pkBW: result = a.bw_val == b.bw_val
    of pkRGB: result = a.rgb_val == b.rgb_val
    of pkRGBA: result = a.rgba_val == b.rgba_val
    else: result = false
  else:
    result = false
  # echo "$# and $# are equal = $#" % [$a, $b, $result]

proc height*(self: Image): int =
  result = self.header.image_height.int

proc width*(self: Image): int =
  result = self.header.image_width.int

proc get_rgb_from_16(data: int16): tuple[r, g, b: uint8] =
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
    result.r = c_r.uint8
    result.g = c_g.uint8
    result.b = c_b.uint8

proc toColor*(pixel: Pixel): Color =
  # TODO: this is ugly as fuck
  case pixel.kind
  of pkBW: return rgb(pixel.bw_val.a.int, pixel.bw_val.a.int, pixel.bw_val.a.int)
  of pkRGB: return rgb(pixel.rgb_val.r.int, pixel.rgb_val.g.int, pixel.rgb_val.b.int)
  of pkRGBA: return rgb(pixel.rgba_val.r.int, pixel.rgba_val.g.int, pixel.rgba_val.b.int)
  else: discard

proc setPixel*(self: var Image, x, y: int, value: Pixel) =
  self.pixels[y][x] = value

proc getPixel*(self: var Image, x, y: int): Pixel =
  result = self.pixels[y][x]

proc load*(self: var Image, file_name: string) =

  template to_int(expr: untyped): uint8 =
    cast[uint8](expr).uint8

  proc parse_pixel(self: var Image, fs: var FileStream): Pixel =
    if self.header.image_type.int in [3, 11]:
      let val = fs.readInt8().to_int
      result = Pixel(kind: pkBW, bw_val: (a: val))
    elif self.header.image_type.int in [2, 10]:
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

  self.header.id_length = fs.readInt8().uint8
  self.header.color_map_type = fs.readInt8().uint8
  self.header.image_type = fs.readInt8().uint8
  self.header.first_entry_index = fs.readInt16().uint16
  self.header.color_map_length = fs.readInt16().uint16
  self.header.color_map_entry_size = fs.readInt8().uint8
  self.header.x_origin = fs.readInt16().uint16
  self.header.y_origin = fs.readInt16().uint16
  self.header.image_width = fs.readInt16().uint16
  self.header.image_height = fs.readInt16().uint16
  self.header.pixel_depth = fs.readInt8().uint8
  self.header.image_descriptor = fs.readInt8().uint8

  let original_position = fs.getPosition()

  fs.setPosition(getFileSize(f).int - 26)
  self.footer.extension_area_offset = fs.readInt32().uint32
  self.footer.developer_directory_offset = fs.readInt32().uint32
  self.footer.signature = fs.readStr(16)
  self.footer.dot = fs.readStr(1)
  self.footer.eend = fs.readStr(1)

  if self.footer.signature == "TRUEVISION-XFILE":
    self.new_tga_format = true
  fs.setPosition(original_position)

  # no compression
  if self.header.image_type.int in [2, 3]:
    for row in 0 .. self.header.image_height.int - 1:
      self.pixels.add(@[])
      for col in 0 .. self.header.image_width.int - 1:
        self.pixels[row].add(self.parse_pixel(fs))
  # compressed
  elif self.header.image_type.int in [10, 11]:
    let
      tot_pixels = self.header.image_height.int * self.header.image_width.int
    var
      pixel_count = 0
      row = 0
    self.pixels.add(@[])
    while pixel_count <= tot_pixels.int:
      if self.pixels[row].len >= self.header.image_width.int:
        if pixel_count == tot_pixels.int:
          break
        self.pixels.add(@[])
        inc(row)
      let repetition_count = fs.readInt8()
      let RLE: bool = (repetition_count and 0b10000000) shr 7 == 1
      let count: int = (repetition_count and 0b01111111).int + 1
      pixel_count += count
      if RLE:
        let pixel = self.parse_pixel(fs)
        for num in 0 .. count - 1:
          self.pixels[row].add(pixel)
      else:
        for num in 0 .. count - 1:
          self.pixels[row].add(self.parse_pixel(fs))


template write_value[T](f: var File, data: T) =
  var tmp: T
  shallowCopy(tmp, data)
  let sz = sizeof(tmp)
  let written_bytes = f.writeBuffer(addr(tmp), sz)
  doAssert(sz == written_bytes, "Wrong number of bytes written")

template write_data(f: var File, data: string) =
  for str in data:
    f.write_value(str)

template write_pixel(f: var File, pixel: Pixel) =
  for name, value in pixel.fieldPairs:
    when name != "kind":
      for v in value.fields:
        f.write_value(v)

proc write_header(f: var File, image: Image) =
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

proc write_footer(f: var File, image: Image) =
  f.write_value(image.footer.extension_area_offset)
  f.write_value(image.footer.developer_directory_offset)
  f.write_data(image.footer.signature)
  f.write_data(image.footer.dot)
  f.write_data(image.footer.eend)

iterator encode(row: seq[Pixel]): EncodedPixel {.inline.}=
  #[
    ##
    # Run-length encoded (RLE) images comprise two types of data
    # elements:Run-length Packets and Raw Packets.
    #
    # The first field (1 byte) of each packet is called the
    # Repetition Count field. The second field is called the
    # Pixel Value field. For Run-length Packets, the Pixel Value
    # field contains a single pixel value. For Raw
    # Packets, the field is a variable number of pixel values.
    #
    # The highest order bit of the Repetition Count indicates
    # whether the packet is a Raw Packet or a Run-length
    # Packet. If bit 7 of the Repetition Count is set to 1, then
    # the packet is a Run-length Packet. If bit 7 is set to
    # zero, then the packet is a Raw Packet.
    #
    # The lower 7 bits of the Repetition Count specify how many
    # pixel values are represented by the packet. In
    # the case of a Run-length packet, this count indicates how
    # many successive pixels have the pixel value
    # specified by the Pixel Value field. For Raw Packets, the
    # Repetition Count specifies how many pixel values
    # are actually contained in the next field. This 7 bit value
    # is actually encoded as 1 less than the number of
    # pixels in the packet (a value of 0 implies 1 pixel while a
    # value of 0x7F implies 128 pixels).
    #
    # Run-length Packets should never encode pixels from more than
    # one scan line. Even if the end of one scan
    # line and the beginning of the next contain pixels of the same
    # value, the two should be encoded as separate
    # packets. In other words, Run-length Packets should not wrap
    # from one line to another. This scheme allows
    # software to create and use a scan line table for rapid, random
    # access of individual lines. Scan line tables are
    # discussed in further detail in the Extension Area section of
    # this document.
    #
    #
    # Pixel format data example:
    #
    # +=======================================+
    # | Uncompressed pixel run                |
    # +=========+=========+=========+=========+
    # | Pixel 0 | Pixel 1 | Pixel 2 | Pixel 3 |
    # +---------+---------+---------+---------+
    # | 144     | 144     | 144     | 144     |
    # +---------+---------+---------+---------+
    #
    # +==========================================+
    # | Run-length Packet                        |
    # +============================+=============+
    # | Repetition Count           | Pixel Value |
    # +----------------------------+-------------+
    # | 1 bit |       7 bit        |             |
    # +----------------------------|     144     |
    # |   1   |  3 (num pixel - 1) |             |
    # +----------------------------+-------------+
    #
    # +====================================================================================+
    # | Raw Packet                                                                         |
    # +============================+=============+=============+=============+=============+
    # | Repetition Count           | Pixel Value | Pixel Value | Pixel Value | Pixel Value |
    # +----------------------------+-------------+-------------+-------------+-------------+
    # | 1 bit |       7 bit        |             |             |             |             |
    # +----------------------------|     144     |     144     |     144     |     144     |
    # |   0   |  3 (num pixel - 1) |             |             |             |             |
    # +----------------------------+-------------+-------------+-------------+-------------+
    #
  ]#

  ##
  # States:
  # - 0: init
  # - 1: run-length packet
  # - 2: raw packet
  #
  var
    state = 0
    index = 0
    repetition_count: uint8 = 0
    pixel_value: Pixel

  while index < row.high:
    echo "index: " & $index
    if state == 0:
      echo "state 0"
      repetition_count = 0
      pixel_value = row[index]
      if row[index] == row[index + 1]:
        repetition_count = repetition_count or 0b10000000
        state = 1
      else:
        state = 2
      inc(index)

    if state == 1:
      echo "state 1"
      if row[index] == pixel_value:
        if (repetition_count and 0b1111111) == 127:
          repetition_count = 0b10000000
        else:
          inc(repetition_count)
          echo "repetition_count" & $repetition_count
        inc(index)
      else:
        state = 0
        yield (repetition_count, pixel_value)

    if state == 2 and row[index] != pixel_value:
      echo "state 2"
      echo pixel_value
      if (repetition_count and 0b1111111) == 127:
        repetition_count = 0
        yield (repetition_count, pixel_value)
      else:
        inc(repetition_count)
      yield (repetition_count, pixel_value)
      state = 0

proc save*(self: var Image, filename: string, compress=false, force_16_bit=false) =
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
  self.header.image_width = self.pixels[0].len.uint16
  self.header.image_height = self.pixels.len.uint16

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

  var f = open(filename, fmWrite)
  if isNil(f):
    raise newException(IOError, "Failed to open/create file: $#" % filename)

  defer: f.close()

  f.write_header(self)
  if not compress:
    for row in self.pixels:
      for pixel in row:
        case self.header.image_type
        of 3: f.write_pixel(pixel)
        of 2:
          case self.header.pixel_depth
          of 16: raise newException(ValueError, "16 bites pixels not yet implemented")
          of 24, 32: f.write_pixel(pixel)
          else: raise newException(ValueError, "invalid pixel depth")
        else: raise newException(ValueError, "invalid pixel kind")
  elif compress:
    for i, row in pairs(self.pixels):
      echo "row " & $i
      for count, value in encode(row):
        echo "count: $# value: $#" % [$count, $value]
        # if count > 127.uint8:
        #   f.write_pixel(value)
        # else:
        #   f.write_pixel(value)
  f.write_footer(self)


proc newPixel* (data: tuple[r, g, b: range[0..255]]): Pixel =
  # TODO: see the forums for a cleaner implementation
  result.kind = pkRGB
  var data_uint8: tuple[r, g, b: uint8]
  data_uint8.r = data.r.uint8
  data_uint8.g = data.g.uint8
  data_uint8.b = data.b.uint8
  result.rgb_val = data_uint8

proc newImage*(): Image =
  new(result)
  result.header = Header()
  result.footer = Footer()
  result.pixels = @[]
  result.new_tga_format = false

  # Screen destination of first pixel
  result.bottom_left = 0b0
  result.bottom_right = 0b1 shl 4
  result.top_left = 0b1 shl 5
  result.top_right = 0b1 shl 4 or 0b1 shl 5

  # Default values
  result.header.image_descriptor = result.top_left.uint8

proc newImage*(filename: string): Image =
  result = newImage()
  result.load(filename)

proc newImage*(data: seq[seq[Pixel]]): Image =
  result = newImage()
  result.pixels = data


when isMainModule:
  # var image = newImage("african_head_diffuse.tga")
  # image.save("compressed_african_head.tga", compress=true)
  # var image = newImage("image_bw.tga")
  # image.save("compressed_african_head.tga", compress=true)
  var image = newImage("image_bw.tga")
  image.save("compressed_image_bw.tga", compress=true)
