import unittest
from PIL import Image

from dt108b.constants import RASTER_HEIGHT, RASTER_WIDTH, WIDTH_BYTES
from dt108b.raster import pack_windows_driver_format, parse_pages
from dt108b.tspl import build_print_job


class RasterTests(unittest.TestCase):
    def test_page_selection(self):
        self.assertEqual(parse_pages("1,3-5", 6), [1, 3, 4, 5])

    def test_white_and_black_polarity(self):
        white = Image.new("1", (RASTER_WIDTH, RASTER_HEIGHT), 1)
        black = Image.new("1", (RASTER_WIDTH, RASTER_HEIGHT), 0)
        self.assertEqual(pack_windows_driver_format(white)[0], 0xFF)
        self.assertEqual(pack_windows_driver_format(black)[0], 0x00)

    def test_msb_is_leftmost(self):
        image = Image.new("1", (RASTER_WIDTH, RASTER_HEIGHT), 1)
        image.putpixel((0, 0), 0)
        self.assertEqual(pack_windows_driver_format(image)[0], 0x7F)

    def test_tspl_payload_size(self):
        raster = bytes([0xFF]) * (WIDTH_BYTES * RASTER_HEIGHT)
        payload = build_print_job(raster, 8)
        self.assertIn(b"BITMAP 0,1,102,1216,1,", payload)
        self.assertTrue(payload.endswith(b"\r\nPRINT 1,1\r\n"))


if __name__ == "__main__":
    unittest.main()
