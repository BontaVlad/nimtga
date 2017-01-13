import sys
import json

import _ntga


class Image(object):

    def __init__(self, filename):
        _data = _ntga.loads(filename)
        self._header = json.loads(_data["header"])
        self._footer = json.loads(_data["footer"])
        for section in [self._header, self._footer]:
            for k, v in section.items():
                setattr(self, k, v)
        self.pixels = _data["pixels"]

    def save(self, filename, compress=False):
        for section in [self._header, self._footer]:
            for k in section:
                section[k] = getattr(self, k)
        _ntga.saves(json.dumps(self._header), json.dumps(self._footer),
                    self.pixels, filename, int(compress))

    @property
    def pixel_size(self):
        if self._header['image_type'] in [3, 11]:
            return 1
        elif self._header['image_type'] in [2, 10]:
            if self._header['pixel_depth'] == 16 or self._header['pixel_depth'] == 24:
                return 3
            elif self._header['pixel_depth'] == 32:
                return 4
            else:
                raise ValueError("Invalid pixel depth")
        else:
            raise ValueError("Invalid pixel depth")


def main(image_path=None):
    image_path = image_path if image_path else sys.argv[1]
    image = Image(image_path)

    if image.pixel_size == 1:
        pixel = (255, )
    elif image.pixel_size == 3:
        pixel = (255, 0, 0)
    elif image.pixel_size == 4:
        pixel = (255, 0, 0, 255)
    else:
        raise ValueError("this should not happen")

    for i in range(5):
        image.pixels[i] = pixel

    image.save("dump.tga", compress=True)


if __name__ == "__main__":
    main()
