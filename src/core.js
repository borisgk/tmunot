function getCsrfToken() {
    const match = document.cookie.match(new RegExp('(^| )csrf_token=([^;]+)'));
    return match ? match[2] : null;
}

const originalFetch = window.fetch;
window.fetch = function() {
    let [resource, config] = arguments;
    if(config && config.method && ['POST', 'PUT', 'DELETE', 'PATCH'].includes(config.method.toUpperCase())) {
        config.headers = config.headers || {};
        config.headers['X-CSRF-Token'] = getCsrfToken();
    }
    return originalFetch(resource, config);
};

document.addEventListener('htmx:configRequest', (evt) => {
    const token = getCsrfToken();
    if (token) {
        evt.detail.headers['X-CSRF-Token'] = token;
    }
});

document.addEventListener('htmx:beforeSwap', (evt) => {
    const xhr = evt.detail.xhr;
    const target = evt.detail.target;
    if (xhr.status === 200 && target && target.getAttribute('hx-get') && target.getAttribute('hx-get').includes('/metadata')) {
        try {
            const data = JSON.parse(xhr.responseText);
            let html = '<table class="metadata-table" style="width: 100%; border-collapse: collapse; font-family: inherit; font-size: 14px;">';
            html += '<tbody>';
            let hasData = false;
            for (const key in data) {
                if (data[key] !== null && data[key] !== undefined && data[key] !== "" && key !== "uuid") {
                    hasData = true;
                    const label = key
                        .replace(/_/g, ' ')
                        .replace(/([a-z0-9])([A-Z])/g, '$1 $2')
                        .replace(/([A-Z])([A-Z][a-z])/g, '$1 $2')
                        .replace(/^./, str => str.toUpperCase())
                        .trim();
                    html += `<tr style="border-bottom: 1px solid var(--md-sys-color-outline-variant);"><td style="padding: 12px 0; font-weight: 600; color: var(--md-sys-color-on-surface-variant); width: 45%;">${label}</td><td style="padding: 12px 0; color: var(--md-sys-color-on-surface); word-break: break-all;">${data[key]}</td></tr>`;
                }
            }
            if (!hasData) {
                html += '<tr><td colspan="2" style="padding: 16px 0; color: var(--md-sys-color-on-surface-variant); text-align: center;">No metadata available</td></tr>';
            }
            html += '</tbody></table>';
            evt.detail.serverResponse = html;
        } catch (e) {
            console.error('Failed to parse metadata JSON:', e);
        }
    }
    if (xhr.status === 200 && target && (target.id === 'album-list-container' || (target.getAttribute('hx-get') && target.getAttribute('hx-get').includes('/api/albums')))) {
        try {
            const albums = JSON.parse(xhr.responseText);
            let html = '';
            if (albums.length === 0) {
                html = '<p style="text-align: center; color: var(--md-sys-color-outline); padding: 16px 0;">No albums created yet.</p>';
            } else {
                albums.forEach(album => {
                    html += `
                        <label style="display: flex; align-items: center; gap: 12px; padding: 12px; border-radius: 12px; background: var(--md-sys-color-surface-container-high); cursor: pointer; transition: background 0.2s;">
                            <input type="radio" name="selected-album" value="${album.uuid}" style="accent-color: var(--md-sys-color-primary);">
                            <div style="display: flex; flex-direction: column;">
                                <span style="color: var(--md-sys-color-on-surface); font-weight: 500;">${album.name}</span>
                                <span style="font-size: 0.8rem; color: var(--md-sys-color-outline);">${album.photo_count} photos</span>
                            </div>
                        </label>
                    `;
                });
            }
            evt.detail.serverResponse = html;
        } catch (e) {
            console.error('Failed to parse albums JSON:', e);
        }
    }
});

function logout() {
    fetch('/logout', { method: 'POST' }).then(() => {
        window.location.href = '/';
    });
}

const originalLeftHtml = '';
const originalTitleText = 'Image Gallery';

// M3 Sticky App Bar elevation shadow on scroll
window.addEventListener('scroll', () => {
    const header = document.querySelector('.md-top-app-bar');
    if (header) {
        if (window.scrollY > 0) {
            header.classList.add('scrolled');
        } else {
            header.classList.remove('scrolled');
        }
    }
});
/* --- Legacy Selection Logic Removed --- */
function showToast(message) {
    const toast = document.createElement('div');
    toast.textContent = message;
    toast.style.position = 'fixed';
    toast.style.bottom = '24px';
    toast.style.left = '50%';
    toast.style.transform = 'translateX(-50%)';
    toast.style.background = 'var(--md-sys-color-inverse-surface, #313033)';
    toast.style.color = 'var(--md-sys-color-inverse-on-surface, #f4eff4)';
    toast.style.padding = '12px 24px';
    toast.style.borderRadius = '100px';
    toast.style.boxShadow = '0 4px 12px rgba(0,0,0,0.15)';
    toast.style.zIndex = '9999';
    toast.style.fontSize = '0.9rem';
    toast.style.fontWeight = '500';
    toast.style.opacity = '0';
    toast.style.transition = 'opacity 0.3s';
    
    document.body.appendChild(toast);
    
    // trigger reflow
    void toast.offsetWidth;
    toast.style.opacity = '1';
    
    setTimeout(() => {
        toast.style.opacity = '0';
        setTimeout(() => {
            toast.remove();
        }, 300);
    }, 3000);
}
