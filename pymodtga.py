import sys
import json

import ntga


class Image(object):

    def __init__(self, filename):
        _data = ntga.loads(filename)
        self._header = json.loads(_data["header"])
        self._footer = json.loads(_data["footer"])
        for section in [self._header, self._footer]:
            for k, v in section.items():
                setattr(self, k, v)
        self.pixels = _data["pixels"]

    def save(self, filename):
        for section in [self._header, self._footer]:
            for k in section:
                section[k] = getattr(self, k)
        ntga.saves(json.dumps(self._header), json.dumps(self._footer),
                   self.pixels, filename)


def main(image_path=None):
    image_path = image_path if image_path else sys.argv[1]
    image = Image(image_path)
    pixel = (255, 0, 0)
    middle = image.image_height // 2

    for row in range(middle):
        for i in range(image.image_width):
            image.pixels[(image.image_width * row) + i] = pixel

    image.save("dump.tga")


if __name__ == "__main__":
    main()
