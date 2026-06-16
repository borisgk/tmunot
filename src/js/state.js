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
            isVideo: false
        },
        openLightbox(src) {
            this.lightbox.src = src;
            this.lightbox.isVideo = src.match(/\.(mp4|mov|m4v|webm|avi)$/i) !== null;
            this.lightbox.isOpen = true;
        },
        closeLightbox() {
            this.lightbox.isOpen = false;
            this.lightbox.src = '';
        },

        // Metadata HTMX handling
        metadataHtml: 'Loading...',

        openMetadataModal() {
            if (this.activeMenuPhoto) {
                this.activePhoto = this.activeMenuPhoto;
                this.modals.metadata = true;
                this.metadataHtml = 'Loading...';
                this.$nextTick(() => {
                    const el = document.querySelector('[hx-trigger="loadMetadata from:body"]');
                    if (el) {
                        htmx.process(el);
                    }
                    document.body.dispatchEvent(new Event('loadMetadata'));
                });
            }
        },
        openChangeDateModal() {
            if (this.activeMenuPhoto) {
                this.activePhoto = this.activeMenuPhoto;
                this.modals.changeDate = true;
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
        }
    }));
});
