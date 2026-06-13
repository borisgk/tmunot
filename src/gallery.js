function openLightbox(src) {
    if (typeof selectedPhotos !== 'undefined' && selectedPhotos.size > 0) {
        const ev = window.event;
        if (ev) {
            const card = ev.target.closest('.card');
            if (card) {
                toggleSelect(ev);
                return;
            }
        }
    }
    const lightbox = document.getElementById('lightbox');
    const img = document.getElementById('lightbox-img');
    
    // Remove any existing video element
    const existingVideo = document.getElementById('lightbox-video');
    if (existingVideo) existingVideo.remove();

    const isVideo = src.endsWith('.mp4') || src.endsWith('.mov') || src.endsWith('.m4v') || src.endsWith('.webm') || src.endsWith('.avi');
    if (isVideo) {
        img.style.display = 'none';
        
        const video = document.createElement('video');
        video.id = 'lightbox-video';
        video.src = src;
        video.controls = true;
        video.autoplay = true;
        video.preload = 'auto';
        video.playsInline = true;
        video.style.maxWidth = '90vw';
        video.style.maxHeight = '80vh';
        video.style.borderRadius = '8px';
        video.style.boxShadow = '0 12px 30px rgba(0,0,0,0.5)';
        video.style.zIndex = '1001';
        video.style.outline = 'none';
        // Prevent clicks on the video from closing the lightbox
        video.onclick = (e) => e.stopPropagation();

        lightbox.appendChild(video);
    } else {
        img.src = src;
        img.style.display = 'block';
    }
    
    lightbox.style.display = 'flex';
    void lightbox.offsetWidth; // Trigger reflow
    lightbox.classList.add('active');
}

function closeLightbox(e) {
    if (e.target.id === 'lightbox' || e.target.classList.contains('close-btn')) {
        const lightbox = document.getElementById('lightbox');
        lightbox.classList.remove('active');
        
        const video = document.getElementById('lightbox-video');
        if (video) {
            video.pause();
        }

        setTimeout(() => {
            lightbox.style.display = 'none';
            document.getElementById('lightbox-img').src = '';
            const v = document.getElementById('lightbox-video');
            if (v) v.remove();
        }, 300);
    }
}

document.addEventListener('keydown', function(e) {
    if (e.key === 'Escape') {
        const menu = document.getElementById('global-menu');
        if (menu && menu.classList.contains('active')) {
            closeMenu();
        } else {
            closeLightbox({target: {id: 'lightbox'}});
        }
    }
});
/* --- M3 Expressive Overflow Menu Logic --- */
let activeMenuPhoto = null;

function toggleMenu(e, uuid, ext) {
    e.preventDefault();
    e.stopPropagation(); // Stop propagation to prevent lightbox opening
    
    const menu = document.getElementById('global-menu');
    if (!menu) return;
    
    if (activeMenuPhoto === uuid && menu.classList.contains('active')) {
        closeMenu();
        return;
    }
    
    activeMenuPhoto = uuid;
    
    const rect = e.currentTarget.getBoundingClientRect();
    
    menu.style.display = 'block';
    
    // Trigger reflow
    void menu.offsetWidth;
    
    // Position menu: relative to viewport
    const menuWidth = 140; // width of menu
    let left = rect.right - menuWidth;
    let top = rect.bottom + 4;
    
    // Ensure bounds protection
    if (left < 16) left = 16;
    if (top + menu.offsetHeight > window.innerHeight) {
        top = rect.top - menu.offsetHeight - 4;
    }
    
    menu.style.left = `${left}px`;
    menu.style.top = `${top}px`;
    
    menu.classList.add('active');
    
    // Set active class to card parent to preserve hover style when cursor moves inside the menu
    const card = e.currentTarget.closest('.card');
    if (card) {
        card.classList.add('menu-open');
    }
    
    // Click actions
    document.getElementById('menu-download').onclick = function(event) {
        event.stopPropagation();
        const a = document.createElement('a');
        a.href = `/previews/${uuid}.${ext}`;
        a.download = `photo_${uuid}.${ext}`;
        document.body.appendChild(a);
        a.click();
        document.body.removeChild(a);
        closeMenu();
    };
    document.getElementById('menu-metadata').onclick = function(event) {
        event.stopPropagation();
        openMetadataModal(uuid);
        closeMenu();
    };
    
    document.getElementById('menu-change-date').onclick = function(event) {
        event.stopPropagation();
        openChangeDateModal(uuid);
        closeMenu();
    };
    
    document.getElementById('menu-delete').onclick = function(event) {
        event.stopPropagation();
        if (confirm("Are you sure you want to delete this photo?")) {
            deletePhoto(uuid);
        }
        closeMenu();
    };
    
    const isAlbumDetail = window.location.pathname.startsWith('/albums/') && window.location.pathname !== '/albums';
    const addToAlbumBtn = document.getElementById('menu-add-to-album');
    if (addToAlbumBtn) {
        const textSpan = addToAlbumBtn.querySelector('span');
        const svgIcon = addToAlbumBtn.querySelector('svg');
        if (isAlbumDetail) {
            if (textSpan) textSpan.textContent = 'Delete from album';
            if (svgIcon) {
                svgIcon.innerHTML = '<path fill="currentColor" d="M20 6h-8l-2-2H4c-1.11 0-1.99.89-1.99 2L2 18c0 1.11.89 2 2 2h16c1.11 0 2-.89 2-2V8c0-1.11-.89-2-2-2zm-1 8H11v-2h8v2z"/>';
            }
            addToAlbumBtn.onclick = function(event) {
                event.stopPropagation();
                const albumUuid = window.location.pathname.split('/').pop();
                if (confirm("Are you sure you want to delete this photo from the album?")) {
                    deletePhotoFromAlbum(albumUuid, uuid);
                }
                closeMenu();
            };
        } else {
            if (textSpan) textSpan.textContent = 'Add to album';
            if (svgIcon) {
                svgIcon.innerHTML = '<path fill="currentColor" d="M20 6h-8l-2-2H4c-1.11 0-1.99.89-1.99 2L2 18c0 1.11.89 2 2 2h16c1.11 0 2-.89 2-2V8c0-1.11-.89-2-2-2zm-1 8h-3v3h-2v-3h-3v-2h3V9h2v3h3v2z"/>';
            }
            addToAlbumBtn.onclick = function(event) {
                event.stopPropagation();
                openAddToAlbumModal([uuid]);
                closeMenu();
            };
        }
    }
}

function closeMenu() {
    const menu = document.getElementById('global-menu');
    if (menu) {
        menu.classList.remove('active');
        activeMenuPhoto = null;
        
        // Remove menu-open class from all cards
        document.querySelectorAll('.card.menu-open').forEach(card => {
            card.classList.remove('menu-open');
        });
        
        setTimeout(() => {
            if (!activeMenuPhoto) menu.style.display = 'none';
        }, 150);
    }
}

function deletePhoto(uuid) {
    fetch(`/delete/${uuid}`, { method: 'POST' })
        .then(response => {
            if (response.ok) {
                // Find card by data-uuid
                const card = document.querySelector(`.card[data-uuid="${uuid}"]`);
                if (card) {
                    // M3 expressive exit animation: quick scale down + fade
                    card.style.transition = 'all 350ms var(--md-sys-motion-easing-standard)';
                    card.style.opacity = '0';
                    card.style.transform = 'scale(0.85)';
                    
                    // Smoothly shrink flex layout width/aspect-ratio for responsive reflow
                    setTimeout(() => {
                        card.style.flex = '0 1 0px';
                        card.style.width = '0px';
                        card.style.marginLeft = '0px';
                        card.style.marginRight = '0px';
                        card.style.padding = '0px';
                    }, 150);

                    setTimeout(() => {
                        card.remove();
                    }, 350);
                }
            } else {
                alert("Failed to delete photo.");
            }
        })
        .catch(err => {
            console.error("Error deleting photo:", err);
            alert("Error deleting photo.");
        });
}

// Close on outside clicks
document.addEventListener('click', function(e) {
    const menu = document.getElementById('global-menu');
    if (menu && menu.classList.contains('active')) {
        if (!menu.contains(e.target) && !e.target.closest('.card-overflow-btn')) {
            closeMenu();
        }
    }
});

// Close menu on scroll or resize for accuracy
window.addEventListener('scroll', closeMenu, { passive: true });
window.addEventListener('resize', closeMenu);
/* --- M3 Expressive Gallery Filtering Logic --- */
function filterGallery() {
    const yearSelect = document.getElementById('filter-year');
    if (!yearSelect) return;
    
    const activeYear = yearSelect.value.trim();
    
    const cards = document.querySelectorAll('.card');
    cards.forEach(card => {
        const cardYear = (card.dataset.year || '').trim();
        const matchYear = activeYear === 'all' || cardYear === activeYear;
        
        if (matchYear) {
            card.style.display = '';
        } else {
            card.style.display = 'none';
        }
    });
}
// Google Photos-style Video Hover Micro-Animation via Event Delegation
document.addEventListener('DOMContentLoaded', () => {
    const grid = document.getElementById('gallery-grid');
    if (!grid) return;

    grid.addEventListener('mouseover', (e) => {
        const card = e.target.closest('.video-card');
        if (!card) return;
        
        // If already playing, do nothing
        if (card.querySelector('video')) return;

        const uuid = card.dataset.uuid;
        if (!uuid) return;

        const video = document.createElement('video');
        video.src = `/hover_previews/${uuid}.mp4`;
        video.autoplay = true;
        video.loop = true;
        video.muted = true;
        video.playsInline = true;
        
        // Match CSS card video dimensions and styling
        video.style.position = 'absolute';
        video.style.top = '0';
        video.style.left = '0';
        video.style.width = '100%';
        video.style.height = '100%';
        video.style.objectFit = 'cover';
        video.style.zIndex = '1';
        video.style.borderRadius = 'inherit';
        video.style.pointerEvents = 'none'; // prevent blocking mouse events

        card.appendChild(video);
    });

    grid.addEventListener('mouseout', (e) => {
        const card = e.target.closest('.video-card');
        if (!card) return;

        // If leaving the card bounds (relatedTarget is not inside card)
        if (!card.contains(e.relatedTarget)) {
            const video = card.querySelector('video');
            if (video) {
                video.pause();
                video.remove();
            }
        }
    });
});
