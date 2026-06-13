const originalLeftHtml = document.getElementById('app-bar-left') ? document.getElementById('app-bar-left').innerHTML : '';
const originalTitleText = document.getElementById('app-bar-title') ? document.getElementById('app-bar-title').textContent : 'Image Gallery';

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

/* --- Albums Logic --- */
function openCreateAlbumModal() {
    const modal = document.getElementById('create-album-modal');
    if (modal) {
        modal.style.display = 'flex';
        void modal.offsetWidth; // force reflow
        modal.classList.add('active');
    }
}

function closeCreateAlbumModal(e) {
    if (e.target.id === 'create-album-modal') {
        const modal = document.getElementById('create-album-modal');
        modal.classList.remove('active');
        setTimeout(() => {
            if (!modal.classList.contains('active')) {
                modal.style.display = 'none';
            }
        }, 300);
    }
}

function submitCreateAlbum() {
    const nameInput = document.getElementById('album-name');
    const descInput = document.getElementById('album-desc');
    const name = nameInput.value.trim();
    const desc = descInput.value.trim();
    if (!name) {
        alert("Album name is required.");
        return;
    }
    fetch('/api/albums', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ name: name, description: desc || null })
    }).then(res => {
        if (res.ok) {
            window.location.reload();
        } else {
            alert("Failed to create album.");
        }
    }).catch(err => {
        console.error(err);
        alert("Error creating album.");
    });
}

/* --- Add to Album Logic --- */
let photosToAdd = [];

function openAddToAlbumModal(uuids) {
    photosToAdd = uuids;
    const modal = document.getElementById('album-select-modal');
    const container = document.getElementById('album-list-container');
    if (!modal || !container) return;

    container.innerHTML = '<p style="text-align: center; color: var(--md-sys-color-outline); padding: 16px 0;">Loading albums...</p>';
    
    modal.style.display = 'flex';
    void modal.offsetWidth; // trigger reflow
    modal.classList.add('active');

    fetch('/api/albums')
        .then(res => {
            if (!res.ok) throw new Error("Failed to load albums");
            return res.json();
        })
        .then(albums => {
            container.innerHTML = '';
            if (albums.length === 0) {
                container.innerHTML = '<p style="text-align: center; color: var(--md-sys-color-outline); padding: 16px 0;">No albums created yet.</p>';
                return;
            }
            albums.forEach(album => {
                const label = document.createElement('label');
                label.style.display = 'flex';
                label.style.alignItems = 'center';
                label.style.gap = '12px';
                label.style.padding = '12px';
                label.style.borderRadius = '12px';
                label.style.background = 'var(--md-sys-color-surface-container-high)';
                label.style.cursor = 'pointer';
                label.style.transition = 'background 0.2s';
                
                label.innerHTML = `
                    <input type="radio" name="selected-album" value="${album.uuid}" style="accent-color: var(--md-sys-color-primary);">
                    <div style="display: flex; flex-direction: column;">
                        <span style="color: var(--md-sys-color-on-surface); font-weight: 500;">${album.name}</span>
                        <span style="font-size: 0.8rem; color: var(--md-sys-color-outline);">${album.photo_count} photos</span>
                    </div>
                `;
                container.appendChild(label);
            });
        })
        .catch(err => {
            console.error(err);
            container.innerHTML = '<p style="text-align: center; color: var(--md-sys-color-error); padding: 16px 0;">Error loading albums.</p>';
        });
}

function closeAlbumSelectModal(e) {
    if (e.target.id === 'album-select-modal') {
        const modal = document.getElementById('album-select-modal');
        modal.classList.remove('active');
        setTimeout(() => {
            if (!modal.classList.contains('active')) {
                modal.style.display = 'none';
                photosToAdd = [];
            }
        }, 300);
    }
}

function openBulkAddToAlbum() {
    if (typeof selectedPhotos !== 'undefined' && selectedPhotos.size > 0) {
        openAddToAlbumModal(Array.from(selectedPhotos));
    }
}

function deletePhotoFromAlbum(albumUuid, photoUuid) {
    fetch(`/api/albums/${albumUuid}/photos/${photoUuid}`, { method: 'DELETE' })
        .then(res => {
            if (res.ok) {
                const card = document.querySelector(`.card[data-uuid="${photoUuid}"]`);
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
                showToast("Photo deleted from album successfully!");
            } else {
                alert("Failed to delete photo from album.");
            }
        })
        .catch(err => {
            console.error(err);
            alert("Error deleting photo from album.");
        });
}

function openBulkDeleteFromAlbum() {
    if (typeof selectedPhotos !== 'undefined' && selectedPhotos.size > 0) {
        const albumUuid = window.location.pathname.split('/').pop();
        if (confirm(`Are you sure you want to delete the ${selectedPhotos.size} selected photos from this album?`)) {
            const promises = Array.from(selectedPhotos).map(uuid => {
                return fetch(`/api/albums/${albumUuid}/photos/${uuid}`, { method: 'DELETE' })
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
                    alert(`Failed to delete ${failedCount} photos from the album.`);
                }
                clearSelection();
                showToast("Photos deleted from album successfully!");
            });
        }
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

// Bind Submit
document.addEventListener('DOMContentLoaded', () => {
    const submitBtn = document.getElementById('submit-add-to-album');
    if (submitBtn) {
        submitBtn.onclick = function() {
            const selectedRadio = document.querySelector('input[name="selected-album"]:checked');
            if (!selectedRadio) {
                alert("Please select an album.");
                return;
            }
            const albumUuid = selectedRadio.value;
            if (photosToAdd.length === 0) return;

            submitBtn.disabled = true;
            submitBtn.textContent = 'Adding...';

            fetch(`/api/albums/${albumUuid}/photos`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ photos: photosToAdd })
            })
            .then(res => {
                submitBtn.disabled = false;
                submitBtn.textContent = 'Add';
                if (res.ok) {
                    // Success
                    const modal = document.getElementById('album-select-modal');
                    if (modal) {
                        modal.classList.remove('active');
                        setTimeout(() => { modal.style.display = 'none'; }, 300);
                    }
                    if (typeof clearSelection === 'function') {
                        clearSelection();
                    }
                    showToast("Photos added to album successfully!");
                } else {
                    alert("Failed to add photos to album.");
                }
            })
            .catch(err => {
                submitBtn.disabled = false;
                submitBtn.textContent = 'Add';
                console.error(err);
                alert("Error adding photos to album.");
            });
        };
    }
});

/* --- Profile Modal Logic --- */
function openProfileModal() {
    const modal = document.getElementById('profile-modal');
    if (!modal) return;
    
    // Reset form
    document.getElementById('profile-form').reset();
    
    // Fetch current user data
    fetch('/api/users/me')
        .then(res => {
            if (!res.ok) throw new Error("Failed to fetch profile");
            return res.json();
        })
        .then(user => {
            document.getElementById('profile-real-name').value = user.real_name || user.username;
        })
        .catch(err => {
            console.error(err);
            showToast("Failed to load profile data.");
        });

    modal.style.display = 'flex';
    void modal.offsetWidth; // force reflow
    modal.classList.add('active');
}

function closeProfileModal(e) {
    if (e.target.id === 'profile-modal') {
        const modal = document.getElementById('profile-modal');
        modal.classList.remove('active');
        setTimeout(() => {
            if (!modal.classList.contains('active')) {
                modal.style.display = 'none';
            }
        }, 300);
    }
}

document.addEventListener('DOMContentLoaded', () => {
    const profileForm = document.getElementById('profile-form');
    if (profileForm) {
        profileForm.addEventListener('submit', async (e) => {
            e.preventDefault();
            
            const submitBtn = profileForm.querySelector('button[type="submit"]');
            submitBtn.disabled = true;
            submitBtn.textContent = 'Saving...';
            
            try {
                // Update text fields
                const rn = document.getElementById('profile-real-name').value.trim();
                const pwd = document.getElementById('profile-password').value;
                const payload = {};
                if (rn) payload.real_name = rn;
                if (pwd) payload.password = pwd;
                
                if (Object.keys(payload).length > 0) {
                    const res = await fetch('/api/users/me', {
                        method: 'PUT',
                        headers: { 'Content-Type': 'application/json' },
                        body: JSON.stringify(payload)
                    });
                    if (!res.ok) throw new Error("Failed to update profile info");
                }
                
                // Update avatar
                const avatarInput = document.getElementById('profile-avatar-upload');
                if (avatarInput.files && avatarInput.files.length > 0) {
                    const file = avatarInput.files[0];
                    const res = await fetch('/api/users/me/avatar', {
                        method: 'POST',
                        headers: {
                            'Content-Type': file.type
                        },
                        body: file
                    });
                    if (!res.ok) throw new Error("Failed to upload avatar");
                }
                
                showToast("Profile updated successfully!");
                closeProfileModal({target: {id: 'profile-modal'}});
                
                // Reload to show new avatar
                setTimeout(() => window.location.reload(), 1000);
                
            } catch (err) {
                console.error(err);
                alert(err.message || "Error updating profile.");
            } finally {
                submitBtn.disabled = false;
                submitBtn.textContent = 'Save';
            }
        });
    }
});


function openMetadataModal(uuid) {
    const modal = document.getElementById('metadata-modal');
    const list = document.getElementById('metadata-list');
    list.innerHTML = '<div style="color: var(--md-sys-color-on-surface-variant); padding: 16px; text-align: center;">Loading...</div>';
    modal.style.display = 'flex';
    requestAnimationFrame(() => {
        modal.classList.add('active');
    });

    fetch(`/api/photos/${uuid}/metadata`)
        .then(response => {
            if (!response.ok) {
                if (response.status === 404) {
                    throw new Error("Metadata not found.");
                }
                throw new Error("Error fetching metadata.");
            }
            return response.json();
        })
        .then(data => {
            list.innerHTML = '';
            let hasData = false;
            for (const [key, value] of Object.entries(data)) {
                if (value !== null && value !== undefined && value !== "") {
                    hasData = true;
                    const item = document.createElement('div');
                    item.style.display = 'flex';
                    item.style.justifyContent = 'space-between';
                    item.style.padding = '8px 12px';
                    item.style.borderBottom = '1px solid var(--md-sys-color-outline-variant)';
                    
                    const keySpan = document.createElement('span');
                    keySpan.style.fontWeight = '500';
                    keySpan.style.color = 'var(--md-sys-color-on-surface)';
                    keySpan.textContent = key;
                    
                    const valSpan = document.createElement('span');
                    valSpan.style.color = 'var(--md-sys-color-on-surface-variant)';
                    valSpan.style.wordBreak = 'break-all';
                    valSpan.style.textAlign = 'right';
                    valSpan.style.maxWidth = '60%';
                    valSpan.textContent = value;
                    
                    item.appendChild(keySpan);
                    item.appendChild(valSpan);
                    list.appendChild(item);
                }
            }
            if (!hasData) {
                list.innerHTML = '<div style="color: var(--md-sys-color-on-surface-variant); padding: 16px; text-align: center;">No metadata available.</div>';
            }
        })
        .catch(err => {
            list.innerHTML = `<div style="color: var(--md-sys-color-error); padding: 16px; text-align: center;">${err.message}</div>`;
        });
}

function closeMetadataModal(e) {
    if (e.target.id === 'metadata-modal' || e.target.closest('#metadata-modal') === null) {
        const modal = document.getElementById('metadata-modal');
        modal.classList.remove('active');
        setTimeout(() => {
            modal.style.display = 'none';
        }, 200);
    }
}
