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
    let c_r = (data and 0b1111100000000000) shr 11
    let c_g = (data and 0b0000011111000000) shr 6
    let c_b = (data and 0b111110) shr 1
    result.r = c_r.int
    result.g = c_g.int
    result.b = c_b.int

proc ImageNew(): Image =
  result.header = Header()
  result.footer = Footer()
  result.pixels = @[]
  result.new_tga_format = false

proc load*(self: var Image, file_name: string) =
  var
    f: File
    fs: FileStream
    # fs = newFileStream(file_name, fmRead)
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

  fs.setPosition(getFileSize(f).int - 26)
  self.footer.extension_area_offset = fs.readInt32().int
  self.footer.developer_directory_offset = fs.readInt32().int
  self.footer.signature = fs.readStr(16)
  self.footer.dot = fs.readStr(1)
  self.footer.eend = fs.readStr(1)

  if self.footer.signature == "TRUEVISION-XFILE":
    self.new_tga_format = true

  echo repr(self)

  # no compression
  if self.header.image_type in [2, 3]:
    for row in 0 .. self.header.image_height:
      self.pixels.add(@[])
      for col in 0 .. self.header.image_width:
        var pixel: Pixel
        if self.header.image_type == 3:
          pixel = Pixel(kind: pkBW, bw_val: fs.readInt8().int)
        elif self.header.image_type == 2:
          discard
          case self.header.pixel_depth
          of 16:
            pixel = Pixel(
              kind: pkRGB,
              rgb_val: get_rgb_from_16(fs.readInt16()))
          of 24:
            pixel = Pixel(
              kind: pkRGB,
              rgb_val: (fs.readInt8().int, fs.readInt8().int, fs.readInt8().int)
            )
          of 32:
            pixel = Pixel(
              kind: pkRGBA,
              rgba_val: (fs.readInt8().int, fs.readInt8().int, fs.readInt8().int, fs.readInt8().int)
            )
          else: raise newException(ValueError, "unsupported image type")

        self.pixels[row].add(pixel)
  # compressed
  elif self.header.image_type in [10, 11]:
    echo "compressed"
    self.pixels.add(@[])
    let tot_pixels = self.header.image_height * self.header.image_width
    var pixel_count = 0

var image = ImageNew()
image.load("african_head_diffuse.tga")
