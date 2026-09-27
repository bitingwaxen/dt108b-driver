from dt108b.engine import WIDTH_DOTS, HEIGHT_DOTS, BYTES_PER_ROW, media_command

def test_geometry():
    assert WIDTH_DOTS == 816
    assert HEIGHT_DOTS == 1216
    assert BYTES_PER_ROW == 102

def test_media_commands():
    assert media_command("gap", 4) == "GAP 4 mm,0 mm"
    assert media_command("notch", 4) == "GAP 4 mm,0 mm"
    assert media_command("continuous", 4) == "GAP 0,0"
    assert media_command("blackmark", 4) == "BLINE 4 mm,0 mm"
