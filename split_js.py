import os

with open("src/script.js", "r", encoding="utf-8") as f:
    lines = f.readlines()

def get_lines(start, end):
    return "".join(lines[start-1:end])

core_js = (
    get_lines(1, 3) +
    get_lines(83, 93) +
    get_lines(270, 408) +
    get_lines(669, 699)
)

gallery_js = (
    get_lines(4, 81) +
    get_lines(95, 268) +
    get_lines(410, 428) +
    get_lines(430, 479)
)

modals_js = (
    get_lines(481, 526) +
    get_lines(528, 668) +
    get_lines(700, 748) +
    get_lines(750, 845) +
    get_lines(848, 1002)
)

with open("src/core.js", "w", encoding="utf-8") as f:
    f.write(core_js)
with open("src/gallery.js", "w", encoding="utf-8") as f:
    f.write(gallery_js)
with open("src/modals.js", "w", encoding="utf-8") as f:
    f.write(modals_js)

print("Split completed.")
