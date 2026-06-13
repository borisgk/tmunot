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
let currentMetadataUuid = null;

let currentChangeDateUuid = null;

function openChangeDateModal(uuid) {
    currentChangeDateUuid = uuid;
    
    let dateStr = "";
    const card = document.querySelector(`.card[data-uuid="${uuid}"]`);
    if (card && card.dataset.date) {
        let rawDate = card.dataset.date.trim();
        if (rawDate.length >= 10 && rawDate[4] === ':' && rawDate[7] === ':') {
            rawDate = rawDate.substring(0, 4) + '-' + rawDate.substring(5, 7) + '-' + rawDate.substring(8);
        }
        dateStr = rawDate.replace(' ', 'T');
    }
    document.getElementById('change-date-input').value = dateStr;
    
    const modal = document.getElementById('change-date-modal');
    modal.style.display = 'flex';
    void modal.offsetWidth;
    modal.classList.add('active');
}

function closeChangeDateModal(event) {
    if (event.target.id === 'change-date-modal') {
        const modal = document.getElementById('change-date-modal');
        modal.classList.remove('active');
        setTimeout(() => {
            modal.style.display = 'none';
        }, 200);
        currentChangeDateUuid = null;
    }
}

function submitChangeDate() {
    if (!currentChangeDateUuid) return;
    let dateInput = document.getElementById('change-date-input').value;
    if (!dateInput) {
        alert('Please select a date and time.');
        return;
    }
    if (dateInput.length === 16) {
        dateInput += ":00";
    }
    fetch(`/api/photos/${currentChangeDateUuid}/date`, {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ date: dateInput })
    })
    .then(response => {
        if (response.ok) {
            closeChangeDateModal({ target: { id: 'change-date-modal' } });
            window.location.reload();
        } else {
            alert('Failed to change date.');
        }
    })
    .catch(error => {
        console.error('Error changing date:', error);
        alert('Failed to change date.');
    });
}

function openMetadataModal(uuid) {
    currentMetadataUuid = uuid;
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

function refreshMetadata() {
    if (!currentMetadataUuid) return;
    const btn = document.getElementById('metadata-refresh-btn');
    const originalText = btn.textContent;
    btn.textContent = 'Refreshing...';
    btn.disabled = true;

    fetch(`/api/photos/${currentMetadataUuid}/metadata/refresh`, { method: 'POST' })
        .then(res => {
            if (!res.ok) throw new Error("Failed to refresh metadata");
            // Reload the metadata modal content
            openMetadataModal(currentMetadataUuid);
        })
        .catch(err => {
            console.error(err);
            alert("Error refreshing metadata.");
        })
        .finally(() => {
            btn.textContent = originalText;
            btn.disabled = false;
        });
}
