import os

base_dir = '/home/ubuntu/zig/tmunot/src'
styles_path = os.path.join(base_dir, 'styles.css')
upload_css_path = os.path.join(base_dir, 'upload.css')

with open(styles_path, 'r', encoding='utf-8') as f:
    lines = f.readlines()

split_index = -1
for i, line in enumerate(lines):
    if '/* --- Upload Layout & Containers --- */' in line:
        split_index = i
        break

if split_index != -1:
    common_css = lines[:split_index]
    upload_css = lines[split_index:]

    with open(styles_path, 'w', encoding='utf-8') as f:
        f.writelines(common_css)

    with open(upload_css_path, 'w', encoding='utf-8') as f:
        f.writelines(upload_css)
    print("Successfully split styles.css into styles.css and upload.css")
else:
    print("Could not find the split marker in styles.css")
