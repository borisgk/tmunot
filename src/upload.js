document.addEventListener('alpine:init', () => {
    Alpine.data('uploadState', () => ({
        dragover: false,
        queuedFiles: [],
        uploading: false,
        errorMessage: '',
        defaultThumbnail: 'data:image/svg+xml;utf8,<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="%233858e9"><path d="M21 19V5c0-1.1-.9-2-2-2H5c-1.1 0-2 .9-2 2v14c0 1.1.9 2 2 2h14c1.1 0 2-.9 2-2zM8.5 13.5l2.5 3.01L14.5 12l4.5 6H5l3.5-4.5z"/></svg>',

        formatBytes(bytes) {
            if (bytes === 0) return '0 Bytes';
            const k = 1024;
            const sizes = ['Bytes', 'KB', 'MB', 'GB'];
            const i = Math.floor(Math.log(bytes) / Math.log(k));
            return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
        },

        showError(msg) {
            this.errorMessage = msg;
            setTimeout(() => {
                this.errorMessage = '';
            }, 6000);
        },

        handleFiles(files) {
            for (let i = 0; i < files.length; i++) {
                const file = files[i];
                if (!file.type.startsWith('image/') && !file.type.startsWith('video/')) {
                    this.showError('Only image and video files are allowed.');
                    continue;
                }

                // Avoid duplicates in the visual queue
                if (this.queuedFiles.some(f => f.file.name === file.name && f.file.size === file.size)) {
                    continue;
                }

                this.queuedFiles.push({
                    id: Math.random().toString(36).substring(2, 11),
                    file: file,
                    name: file.name,
                    size: file.size,
                    thumbnail: null,
                    progress: 0,
                    status: 'queued', // queued, processing, done
                    error: false
                });
            }
        },

        removeFile(index) {
            this.queuedFiles.splice(index, 1);
        },

        uploadFiles() {
            if (this.queuedFiles.length === 0) return;
            this.errorMessage = '';
            this.uploading = true;

            const maxConcurrentUploads = 3;
            let uploadIndex = 0;
            let activeUploads = 0;

            const checkAllDone = () => {
                if (activeUploads === 0 && uploadIndex >= this.queuedFiles.length) {
                    const errCount = this.queuedFiles.filter(f => f.error).length;
                    if (errCount > 0) {
                        this.showError(`${errCount} file(s) failed to upload/process properly. Redirecting...`);
                        setTimeout(() => window.location.href = '/', 4000);
                    } else {
                        setTimeout(() => window.location.href = '/', 1150); // Wait for animations
                    }
                }
            };

            const uploadNextFile = () => {
                if (uploadIndex >= this.queuedFiles.length) {
                    return;
                }

                const index = uploadIndex;
                uploadIndex++;
                activeUploads++;

                const activeFile = this.queuedFiles[index];

                // Show the actual image thumbnail while uploading
                if (activeFile.size <= 50 * 1024 * 1024 && activeFile.file.type.startsWith('image/')) {
                    activeFile.thumbnail = URL.createObjectURL(activeFile.file);
                }

                const formData = new FormData();
                formData.append('images', activeFile.file);

                const xhr = new XMLHttpRequest();
                xhr.open('POST', '/upload', true);

                const match = document.cookie.match(new RegExp('(^| )csrf_token=([^;]+)'));
                const csrfToken = match ? match[2] : null;
                if (csrfToken) {
                    xhr.setRequestHeader('X-CSRF-Token', csrfToken);
                }

                xhr.upload.addEventListener('progress', (e) => {
                    if (e.lengthComputable && e.total > 0) {
                        activeFile.progress = Math.min(100, Math.round((e.loaded / e.total) * 100));
                    }
                });

                xhr.upload.addEventListener('load', () => {
                    activeFile.progress = 100;
                    activeFile.status = 'processing';
                });

                xhr.addEventListener('load', () => {
                    activeUploads--;

                    if (xhr.status < 200 || xhr.status >= 300) {
                        activeFile.error = true;
                        checkAllDone();
                    } else {
                        let uuid = null, ext = null;
                        try {
                            const resp = JSON.parse(xhr.responseText);
                            uuid = resp.uuid;
                            ext = resp.ext;
                        } catch (e) { }

                        if (!uuid || !ext) {
                            activeFile.error = true;
                        } else {
                            activeFile.progress = 100;
                            setTimeout(() => {
                                activeFile.status = 'done'; // Triggers 'fade-out' class
                            }, 150);
                        }
                        checkAllDone();
                    }
                    uploadNextFile();
                });

                xhr.addEventListener('error', () => {
                    activeUploads--;
                    activeFile.error = true;
                    checkAllDone();
                    uploadNextFile();
                });

                xhr.send(formData);
            };

            // Start parallel upload
            const toStart = Math.min(maxConcurrentUploads, this.queuedFiles.length);
            for (let i = 0; i < toStart; i++) {
                uploadNextFile();
            }
        }
    }));
});
