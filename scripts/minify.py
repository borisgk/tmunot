import re
import os

def minify_css(css):
    out = []
    i = 0
    n = len(css)
    in_string = False
    string_char = None
    in_comment = False
    
    while i < n:
        if in_comment:
            if i + 1 < n and css[i] == '*' and css[i+1] == '/':
                in_comment = False
                i += 2
            else:
                i += 1
            continue
            
        if not in_string and (css[i] == '"' or css[i] == "'"):
            in_string = True
            string_char = css[i]
            out.append(css[i])
            i += 1
            continue
        elif in_string:
            if css[i] == '\\' and i + 1 < n:
                out.append(css[i])
                out.append(css[i+1])
                i += 2
                continue
            if css[i] == string_char:
                in_string = False
            out.append(css[i])
            i += 1
            continue
            
        if i + 1 < n and css[i] == '/' and css[i+1] == '*':
            in_comment = True
            i += 2
            continue
            
        out.append(css[i])
        i += 1
        
    css_no_comments = "".join(out)
    # Remove whitespaces around selectors, properties, delimiters
    css_min = re.sub(r'\s*([\{\}:;,])\s*', r'\1', css_no_comments)
    # Replace multiple whitespaces with single space
    css_min = re.sub(r'\s+', ' ', css_min)
    return css_min.strip()

def minify_js(js):
    out = []
    i = 0
    n = len(js)
    in_string = False
    string_char = None
    in_single_comment = False
    in_multi_comment = False
    
    while i < n:
        if in_single_comment:
            if js[i] == '\n':
                in_single_comment = False
                out.append('\n')
            i += 1
            continue
        if in_multi_comment:
            if i + 1 < n and js[i] == '*' and js[i+1] == '/':
                in_multi_comment = False
                i += 2
            else:
                i += 1
            continue
        
        # Check for string literals
        if not in_string and (js[i] == '"' or js[i] == "'" or js[i] == '`'):
            in_string = True
            string_char = js[i]
            out.append(js[i])
            i += 1
            continue
        elif in_string:
            if js[i] == '\\' and i + 1 < n:
                out.append(js[i])
                out.append(js[i+1])
                i += 2
                continue
            if js[i] == string_char:
                in_string = False
            out.append(js[i])
            i += 1
            continue
            
        # Check for comments
        if i + 1 < n and js[i] == '/' and js[i+1] == '/':
            in_single_comment = True
            i += 2
            continue
        elif i + 1 < n and js[i] == '/' and js[i+1] == '*':
            in_multi_comment = True
            i += 2
            continue
            
        out.append(js[i])
        i += 1
        
    js_no_comments = "".join(out)
    
    # Now minify whitespaces
    # Remove unnecessary spaces around symbols
    js_min = re.sub(r'\s*([=+\-*/{}()\[\];,<>:!?&|])\s*', r'\1', js_no_comments)
    # Replace multiple whitespaces/newlines with a single space
    js_min = re.sub(r'\s+', ' ', js_min)
    return js_min.strip()

def main():
    base_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    src_dir = os.path.join(base_dir, 'src')
    
    # Read CSS and JS
    with open(os.path.join(src_dir, 'styles.css'), 'r', encoding='utf-8') as f:
        css = f.read()
    with open(os.path.join(src_dir, 'script.js'), 'r', encoding='utf-8') as f:
        js = f.read()
        
    min_css = minify_css(css)
    min_js = minify_js(js)
    
    # Read version from build.zig.zon
    version = "0.0.0"
    zon_path = os.path.join(base_dir, 'build.zig.zon')
    if os.path.exists(zon_path):
        with open(zon_path, 'r', encoding='utf-8') as f:
            zon_content = f.read()
            match = re.search(r'\.version\s*=\s*"([^"]+)"', zon_content)
            if match:
                version = match.group(1)
    
    # Process index.html
    with open(os.path.join(src_dir, 'index.html'), 'r', encoding='utf-8') as f:
        index_html = f.read()
    
    css_replacement = f'<style>{min_css}</style>'
    index_html = re.sub(r'<link\s+rel="stylesheet"\s+href="/styles\.css"[^>]*>', css_replacement, index_html)
    
    js_replacement = f'<script>{min_js}</script>'
    index_html = re.sub(r'<script\s+src="/script\.js"[^>]*>\s*</script>', js_replacement, index_html)
    
    index_html = index_html.replace('<!-- APP_VERSION -->', version)
    with open(os.path.join(src_dir, 'index_gen.html'), 'w', encoding='utf-8') as f:
        f.write(index_html)
        
    # Process login.html
    with open(os.path.join(src_dir, 'login.html'), 'r', encoding='utf-8') as f:
        login_html = f.read()
        
    login_html = re.sub(r'<link\s+rel="stylesheet"\s+href="/styles\.css"[^>]*>', css_replacement, login_html)
    login_html = login_html.replace('<!-- APP_VERSION -->', version)
    
    with open(os.path.join(src_dir, 'login_gen.html'), 'w', encoding='utf-8') as f:
        f.write(login_html)

    # Process albums.html
    albums_path = os.path.join(src_dir, 'albums.html')
    if os.path.exists(albums_path):
        with open(albums_path, 'r', encoding='utf-8') as f:
            albums_html = f.read()
            
        albums_html = re.sub(r'<link\s+rel="stylesheet"\s+href="/styles\.css"[^>]*>', css_replacement, albums_html)
        
        albums_js_replacement = f'<script>{min_js}</script>'
        albums_html = re.sub(r'<script\s+src="/script\.js"[^>]*>\s*</script>', albums_js_replacement, albums_html)
        
        albums_html = albums_html.replace('<!-- APP_VERSION -->', version)
        with open(os.path.join(src_dir, 'albums_gen.html'), 'w', encoding='utf-8') as f:
            f.write(albums_html)

    # Process album_detail.html
    album_detail_path = os.path.join(src_dir, 'album_detail.html')
    if os.path.exists(album_detail_path):
        with open(album_detail_path, 'r', encoding='utf-8') as f:
            album_detail_html = f.read()
            
        album_detail_html = re.sub(r'<link\s+rel="stylesheet"\s+href="/styles\.css"[^>]*>', css_replacement, album_detail_html)
        
        album_detail_js_replacement = f'<script>{min_js}</script>'
        album_detail_html = re.sub(r'<script\s+src="/script\.js"[^>]*>\s*</script>', album_detail_js_replacement, album_detail_html)
        
        album_detail_html = album_detail_html.replace('<!-- APP_VERSION -->', version)
        with open(os.path.join(src_dir, 'album_detail_gen.html'), 'w', encoding='utf-8') as f:
            f.write(album_detail_html)

    # Process upload.html
    upload_path = os.path.join(src_dir, 'upload.html')
    if os.path.exists(upload_path):
        with open(upload_path, 'r', encoding='utf-8') as f:
            upload_html = f.read()
            
        upload_html = re.sub(r'<link\s+rel="stylesheet"\s+href="/styles\.css"[^>]*>', css_replacement, upload_html)
        
        upload_css_path = os.path.join(src_dir, 'upload.css')
        if os.path.exists(upload_css_path):
            with open(upload_css_path, 'r', encoding='utf-8') as f:
                upload_css = f.read()
            min_upload_css = minify_css(upload_css)
            upload_css_replacement = f'<style>{min_upload_css}</style>'
            upload_html = re.sub(r'<link\s+rel="stylesheet"\s+href="/upload\.css"[^>]*>', upload_css_replacement, upload_html)
        
        upload_js_path = os.path.join(src_dir, 'upload.js')
        if os.path.exists(upload_js_path):
            with open(upload_js_path, 'r', encoding='utf-8') as f:
                upload_js = f.read()
            min_upload_js = minify_js(upload_js)
            upload_js_replacement = f'<script>{min_upload_js}</script>'
            upload_html = re.sub(r'<script\s+src="/upload\.js"[^>]*>\s*</script>', upload_js_replacement, upload_html)
        
        upload_html = upload_html.replace('<!-- APP_VERSION -->', version)
        with open(os.path.join(src_dir, 'upload_gen.html'), 'w', encoding='utf-8') as f:
            f.write(upload_html)
            
    # Process admin.html
    admin_path = os.path.join(src_dir, 'admin.html')
    if os.path.exists(admin_path):
        with open(admin_path, 'r', encoding='utf-8') as f:
            admin_html = f.read()
            
        admin_html = re.sub(r'<link\s+rel="stylesheet"\s+href="/styles\.css"[^>]*>', css_replacement, admin_html)
        
        admin_js_path = os.path.join(src_dir, 'admin.js')
        if os.path.exists(admin_js_path):
            with open(admin_js_path, 'r', encoding='utf-8') as f:
                admin_js = f.read()
            min_admin_js = minify_js(admin_js)
            admin_js_replacement = f'<script>{min_admin_js}</script>'
            admin_html = re.sub(r'<script\s+src="/admin\.js"[^>]*>\s*</script>', admin_js_replacement, admin_html)
            
        admin_html = admin_html.replace('<!-- APP_VERSION -->', version)
        with open(os.path.join(src_dir, 'admin_gen.html'), 'w', encoding='utf-8') as f:
            f.write(admin_html)
            
    # Process users.html
    users_path = os.path.join(src_dir, 'users.html')
    if os.path.exists(users_path):
        with open(users_path, 'r', encoding='utf-8') as f:
            users_html = f.read()
            
        users_html = re.sub(r'<link\s+rel="stylesheet"\s+href="/styles\.css"[^>]*>', css_replacement, users_html)
        
        users_js_path = os.path.join(src_dir, 'users.js')
        if os.path.exists(users_js_path):
            with open(users_js_path, 'r', encoding='utf-8') as f:
                users_js = f.read()
            min_users_js = minify_js(users_js)
            users_js_replacement = f'<script>{min_users_js}</script>'
            users_html = re.sub(r'<script\s+src="/users\.js"[^>]*>\s*</script>', users_js_replacement, users_html)
            
        users_html = users_html.replace('<!-- APP_VERSION -->', version)
        with open(os.path.join(src_dir, 'users_gen.html'), 'w', encoding='utf-8') as f:
            f.write(users_html)
        
    print("Minification and embedding complete successfully.")

if __name__ == '__main__':
    main()
