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
    
    # Process index.html
    with open(os.path.join(src_dir, 'index.html'), 'r', encoding='utf-8') as f:
        index_html = f.read()
    
    css_replacement = f'<style>{min_css}</style>'
    index_html = re.sub(r'<link\s+rel="stylesheet"\s+href="/styles\.css"[^>]*>', css_replacement, index_html)
    
    js_replacement = f'<script>{min_js}</script>'
    index_html = re.sub(r'<script\s+src="/script\.js"[^>]*>\s*</script>', js_replacement, index_html)
    
    with open(os.path.join(src_dir, 'index_gen.html'), 'w', encoding='utf-8') as f:
        f.write(index_html)
        
    # Process login.html
    with open(os.path.join(src_dir, 'login.html'), 'r', encoding='utf-8') as f:
        login_html = f.read()
        
    login_html = re.sub(r'<link\s+rel="stylesheet"\s+href="/styles\.css"[^>]*>', css_replacement, login_html)
    
    with open(os.path.join(src_dir, 'login_gen.html'), 'w', encoding='utf-8') as f:
        f.write(login_html)

    # Process upload.html
    upload_path = os.path.join(src_dir, 'upload.html')
    if os.path.exists(upload_path):
        with open(upload_path, 'r', encoding='utf-8') as f:
            upload_html = f.read()
            
        upload_html = re.sub(r'<link\s+rel="stylesheet"\s+href="/styles\.css"[^>]*>', css_replacement, upload_html)
        
        with open(os.path.join(src_dir, 'upload_gen.html'), 'w', encoding='utf-8') as f:
            f.write(upload_html)
        
    print("Minification and embedding complete successfully.")

if __name__ == '__main__':
    main()
