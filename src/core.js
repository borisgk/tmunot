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

function logout() {
    fetch('/logout', { method: 'POST' }).then(() => {
        window.location.href = '/';
    });
}

const originalLeftHtml = document.getElementById('app-bar-left') ? document.getElementById('app-bar-left').innerHTML : '';
const originalTitleText = document.getElementById('app-bar-title') ? document.getElementById('app-bar-title').textContent : 'Image Gallery';

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
/* --- M3 Expressive Selection Mode Logic --- */
const selectedPhotos = new Set();

function toggleSelect(e) {
    e.preventDefault();
    e.stopPropagation();
    
    const card = e.currentTarget.closest('.card') || e.target.closest('.card');
    if (!card) return;
    
    const uuid = card.dataset.uuid;
    if (!uuid) return;
    
    if (selectedPhotos.has(uuid)) {
        selectedPhotos.delete(uuid);
        card.classList.remove('selected');
    } else {
        selectedPhotos.add(uuid);
        card.classList.add('selected');
    }
    
    updateSelectionUI();
}

function updateSelectionUI() {
    const appBar = document.getElementById('app-bar');
    const title = document.getElementById('app-bar-title');
    const left = document.getElementById('app-bar-left');
    const selActions = document.getElementById('selection-actions');
    
    if (!appBar || !title || !left || !selActions) return;
    
    if (selectedPhotos.size > 0) {
        document.body.classList.add('selection-mode');
        appBar.classList.add('selection-mode');
        
        title.textContent = selectedPhotos.size + " selected";
        
        left.innerHTML = `
            <button class="md-selection-icon-btn" onclick="clearSelection()" title="Clear selection" aria-label="Clear selection">
                <svg viewBox="0 0 24 24"><path d="M19 6.41L17.59 5 12 10.59 6.41 5 5 6.41 10.59 12 5 17.59 6.41 19 12 13.41 17.59 19 19 17.59 13.41 12z"/></svg>
            </button>
        `;
        
        selActions.style.display = 'flex';
        
        const isAlbumDetail = window.location.pathname.startsWith('/albums/') && window.location.pathname !== '/albums';
        const bulkBtn = document.getElementById('bulk-add-to-album-btn');
        if (bulkBtn) {
            if (isAlbumDetail) {
                bulkBtn.title = "Delete from album";
                bulkBtn.setAttribute('aria-label', "Delete from album");
                bulkBtn.innerHTML = '<svg viewBox="0 0 24 24"><path fill="currentColor" d="M20 6h-8l-2-2H4c-1.11 0-1.99.89-1.99 2L2 18c0 1.11.89 2 2 2h16c1.11 0 2-.89 2-2V8c0-1.11-.89-2-2-2zm-1 8H11v-2h8v2z"/></svg>';
                bulkBtn.onclick = function() {
                    openBulkDeleteFromAlbum();
                };
            } else {
                bulkBtn.title = "Add to album";
                bulkBtn.setAttribute('aria-label', "Add to album");
                bulkBtn.innerHTML = '<svg viewBox="0 0 24 24"><path fill="currentColor" d="M20 6h-8l-2-2H4c-1.11 0-1.99.89-1.99 2L2 18c0 1.11.89 2 2 2h16c1.11 0 2-.89 2-2V8c0-1.11-.89-2-2-2zm-1 8h-3v3h-2v-3h-3v-2h3V9h2v3h3v2z"/></svg>';
                bulkBtn.onclick = function() {
                    openBulkAddToAlbum();
                };
            }
        }
    } else {
        document.body.classList.remove('selection-mode');
        appBar.classList.remove('selection-mode');
        
        title.textContent = originalTitleText;
        left.innerHTML = originalLeftHtml;
        selActions.style.display = 'none';
    }
}

function clearSelection() {
    selectedPhotos.clear();
    document.querySelectorAll('.card.selected').forEach(card => {
        card.classList.remove('selected');
    });
    updateSelectionUI();
}

function bulkDownload() {
    let delay = 0;
    selectedPhotos.forEach(uuid => {
        const card = document.querySelector(`.card[data-uuid="${uuid}"]`);
        if (card) {
            const img = card.querySelector('img');
            const ext = img ? (img.src.split('.').pop() || 'jpg') : 'jpg';
            setTimeout(() => {
                const a = document.createElement('a');
                a.href = `/previews/${uuid}.${ext}`;
                a.download = `photo_${uuid}.${ext}`;
                document.body.appendChild(a);
                a.click();
                document.body.removeChild(a);
            }, delay);
            delay += 100;
        }
    });
}

function bulkDelete() {
    if (confirm(`Are you sure you want to delete the ${selectedPhotos.size} selected photos?`)) {
        const promises = Array.from(selectedPhotos).map(uuid => {
            return fetch(`/delete/${uuid}`, { method: 'POST' })
                .then(res => {
                    if (res.ok) {
                        const card = document.querySelector(`.card[data-uuid="${uuid}"]`);
                        if (card) {
                            card.style.transition = 'all 350ms var(--md-sys-motion-easing-standard)';
                            card.style.opacity = '0';
                            card.style.transform = 'scale(0.85)';
                            setTimeout(() => {
                                card.style.flex = '0 1 0px';
                                card.style.width = '0px';
                                card.style.marginLeft = '0px';
                                card.style.marginRight = '0px';
                                card.style.padding = '0px';
                            }, 150);
                            setTimeout(() => card.remove(), 350);
                        }
                        return true;
                    }
                    return false;
                });
        });
        
        Promise.all(promises).then(results => {
            const failedCount = results.filter(r => !r).length;
            if (failedCount > 0) {
                alert(`Failed to delete ${failedCount} photos.`);
            }
            selectedPhotos.clear();
            updateSelectionUI();
        });
    }
}
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
