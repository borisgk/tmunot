document.addEventListener('alpine:init', () => {
    Alpine.data('galleryState', () => ({
        selectedPhotos: [],
        filterYear: new URLSearchParams(window.location.search).get('year') || 'all',
        init() {
            window.addEventListener('popstate', () => {
                this.filterYear = new URLSearchParams(window.location.search).get('year') || 'all';
            });
        },
        modals: {
            metadata: false,
            changeDate: false,
            createAlbum: false,
            addToAlbum: false
        },
        activeMenuPhoto: null,
        activePhoto: null,
        
        toggleSelection(uuid) {
            const index = this.selectedPhotos.indexOf(uuid);
            if (index > -1) {
                this.selectedPhotos.splice(index, 1);
            } else {
                this.selectedPhotos.push(uuid);
            }
        },
        clearSelection() {
            this.selectedPhotos = [];
        },
        
        toggleMenu(uuid, event) {
            if (this.activeMenuPhoto === uuid) {
                this.activeMenuPhoto = null;
            } else {
                this.activeMenuPhoto = uuid;
                if (event) {
                    const targetEl = event.currentTarget || event.target;
                    this.$nextTick(() => {
                        const menu = document.getElementById('global-menu');
                        if (menu && targetEl) {
                            const rect = targetEl.getBoundingClientRect();
                            const menuWidth = menu.offsetWidth || 140;
                            const menuHeight = menu.offsetHeight || 180;
                            let left = rect.right - menuWidth;
                            let top = rect.bottom + 4;
                            
                            if (left + menuWidth > window.innerWidth) {
                                left = window.innerWidth - menuWidth - 12;
                            }
                            if (left < 12) {
                                left = 12;
                            }
                            if (top + menuHeight > window.innerHeight) {
                                top = rect.top - menuHeight - 4;
                            }
                            if (top < 12) {
                                top = 12;
                            }
                            
                            menu.style.left = `${left}px`;
                            menu.style.top = `${top}px`;
                        }
                    });
                }
            }
        },
        closeMenu() {
            this.activeMenuPhoto = null;
        },

        // Lightbox state
        lightbox: {
            isOpen: false,
            src: '',
            isVideo: false,
            items: [],
            currentIndex: -1
        },
        openLightbox(src) {
            this.lightbox.src = src;
            this.lightbox.isVideo = src.match(/\.(mp4|mov|m4v|webm|avi)$/i) !== null;
            
            if (!this.lightbox.isOpen) {
                this.lightbox.items = this.getLightboxItems();
            }
            
            this.lightbox.currentIndex = this.lightbox.items.findIndex(item => {
                try {
                    const url1 = new URL(item, window.location.origin);
                    const url2 = new URL(src, window.location.origin);
                    return url1.pathname === url2.pathname;
                } catch(e) {
                    return item === src;
                }
            });
            
            this.lightbox.isOpen = true;
        },
        closeLightbox() {
            this.lightbox.isOpen = false;
            this.lightbox.src = '';
            this.lightbox.items = [];
            this.lightbox.currentIndex = -1;
        },
        getLightboxItems() {
            const cards = Array.from(document.querySelectorAll('.card'));
            return cards.map(card => {
                const img = card.querySelector('img');
                if (img) {
                    const src = img.getAttribute('src');
                    if (src) {
                        return src.replace('/thumbnails/', '/previews/');
                    }
                }
                return null;
            }).filter(Boolean);
        },
        nextLightboxItem() {
            if (!this.lightbox.isOpen || this.lightbox.items.length === 0) return;
            if (this.lightbox.currentIndex !== -1) {
                const nextIndex = (this.lightbox.currentIndex + 1) % this.lightbox.items.length;
                this.openLightbox(this.lightbox.items[nextIndex]);
            }
        },
        prevLightboxItem() {
            if (!this.lightbox.isOpen || this.lightbox.items.length === 0) return;
            if (this.lightbox.currentIndex !== -1) {
                const prevIndex = (this.lightbox.currentIndex - 1 + this.lightbox.items.length) % this.lightbox.items.length;
                this.openLightbox(this.lightbox.items[prevIndex]);
            }
        },

        // Metadata State & Handling
        metadata: null,
        metadataFilename: '',
        metadataThumbnail: '',
        metadataIsVideo: false,
        metadataVideoSrc: '',

        async openMetadataModal() {
            if (this.activeMenuPhoto) {
                this.activePhoto = this.activeMenuPhoto;
                this.modals.metadata = true;
                this.metadata = null; // Show loading state

                const card = document.querySelector(`[data-uuid="${this.activePhoto}"]`);
                if (card) {
                    const titleEl = card.querySelector('p');
                    this.metadataFilename = titleEl ? titleEl.textContent : 'Unknown File';
                    
                    const isVideo = card.classList.contains('video-card');
                    this.metadataIsVideo = isVideo;

                    const imgEl = card.querySelector('img');
                    if (imgEl) {
                        const previewSrc = imgEl.src.replace('/thumbnails/', '/previews/');
                        if (isVideo) {
                            this.metadataVideoSrc = `/hover_previews/${this.activePhoto}.mp4`;
                            this.metadataThumbnail = '';
                        } else {
                            this.metadataThumbnail = previewSrc;
                            this.metadataVideoSrc = '';
                        }
                    }
                }

                try {
                    const response = await fetch(`/api/photos/${this.activePhoto}/metadata`);
                    if (response.ok) {
                        this.metadata = await response.json();
                    } else {
                        this.metadata = { error: "Metadata not found" };
                    }
                } catch (e) {
                    this.metadata = { error: "Failed to load metadata" };
                }
            }
        },
        async openChangeDateModal() {
            if (this.activeMenuPhoto) {
                this.activePhoto = this.activeMenuPhoto;
                this.modals.changeDate = true;
                
                const input = document.getElementById('change-date-input');
                if (input) {
                    input.value = '';
                }
                
                try {
                    const response = await fetch(`/api/photos/${this.activePhoto}/date`);
                    if (response.ok) {
                        const data = await response.json();
                        if (data && data.date) {
                            // Convert YYYY-MM-DD HH:MM:SS format to YYYY-MM-DDTHH:MM:SS for datetime-local
                            const formattedDate = data.date.trim().replace(' ', 'T');
                            if (input) {
                                input.value = formattedDate;
                            }
                        }
                    } else {
                        console.error('Failed to fetch photo date');
                    }
                } catch (e) {
                    console.error('Error fetching photo date:', e);
                }
            }
        },
        async changePhotoDate() {
            const input = document.getElementById('change-date-input');
            if (!input || !this.activePhoto) return;

            const dateValue = input.value;
            if (!dateValue) {
                alert("Please select a date and time.");
                return;
            }

            const saveBtn = document.querySelector('#change-date-modal button[type="submit"]');
            const originalText = saveBtn ? saveBtn.textContent : 'Save';
            if (saveBtn) {
                saveBtn.disabled = true;
                saveBtn.textContent = 'Saving...';
            }

            try {
                const response = await fetch(`/api/photos/${this.activePhoto}/date`, {
                    method: 'PUT',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ date: dateValue })
                });

                if (response.ok) {
                    this.closeAllModals();
                    showToast("Photo date updated successfully!");
                    setTimeout(() => window.location.reload(), 500);
                } else {
                    const text = await response.text();
                    alert(`Failed to update photo date: ${text}`);
                }
            } catch (e) {
                console.error(e);
                alert("Error updating photo date.");
            } finally {
                if (saveBtn) {
                    saveBtn.disabled = false;
                    saveBtn.textContent = originalText;
                }
            }
        },
        openAddToAlbumModal() {
            if (this.activeMenuPhoto) {
                this.activePhoto = this.activeMenuPhoto;
            }
            this.modals.addToAlbum = true;
            this.$nextTick(() => {
                document.body.dispatchEvent(new Event('loadAlbums'));
            });
        },
        closeAllModals() {
            for (let key in this.modals) {
                this.modals[key] = false;
            }
            this.activePhoto = null;
        },
        bulkDownload() {
            // Placeholder for bulk download
            alert('Bulk download initiated');
        },
        addSelectedPhotosToAlbum() {
            const selectedRadio = document.querySelector('input[name="selected-album"]:checked');
            if (!selectedRadio) {
                alert("Please select an album.");
                return;
            }
            const albumUuid = selectedRadio.value;
            const photos = this.activePhoto ? [this.activePhoto] : this.selectedPhotos;
            if (photos.length === 0) return;

            const submitBtn = document.getElementById('submit-add-to-album');
            const originalText = submitBtn.textContent;
            submitBtn.disabled = true;
            submitBtn.textContent = 'Adding...';

            fetch(`/api/albums/${albumUuid}/photos`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ photos: photos })
            })
            .then(res => {
                submitBtn.disabled = false;
                submitBtn.textContent = originalText;
                if (res.ok) {
                    this.closeAllModals();
                    this.clearSelection();
                    showToast("Photos added to album successfully!");
                } else {
                    alert("Failed to add photos to album.");
                }
            })
            .catch(err => {
                submitBtn.disabled = false;
                submitBtn.textContent = originalText;
                console.error(err);
                alert("Error adding photos to album.");
            });
        }
    }));
});
