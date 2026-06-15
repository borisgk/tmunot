(function() {
    const dropzone = document.getElementById('dropzone');
    if (!dropzone) return;
    const fileInput = document.getElementById('file-input');
        const stagedList = document.getElementById('staged-list');
        const stagedTitle = document.getElementById('staged-title');
        const uploadBtn = document.getElementById('upload-btn');
        const errorMessage = document.getElementById('error-message');

        let queuedFiles = [];

        // Trigger file input click when dropzone is clicked
        dropzone.addEventListener('click', () => fileInput.click());

        // File input change
        fileInput.addEventListener('change', (e) => {
            handleFiles(e.target.files);
            fileInput.value = ''; // reset to allow choosing same files
        });

        // Drag events
        ['dragenter', 'dragover'].forEach(eventName => {
            dropzone.addEventListener(eventName, (e) => {
                e.preventDefault();
                dropzone.classList.add('dragover');
            }, false);
        });

        ['dragleave', 'drop'].forEach(eventName => {
            dropzone.addEventListener(eventName, (e) => {
                e.preventDefault();
                dropzone.classList.remove('dragover');
            }, false);
        });

        dropzone.addEventListener('drop', (e) => {
            const dt = e.dataTransfer;
            handleFiles(dt.files);
        });

        // Format bytes to human readable format
        function formatBytes(bytes) {
            if (bytes === 0) return '0 Bytes';
            const k = 1024;
            const sizes = ['Bytes', 'KB', 'MB', 'GB'];
            const i = Math.floor(Math.log(bytes) / Math.log(k));
            return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
        }

        // Process newly added files
        function handleFiles(files) {
            for (let i = 0; i < files.length; i++) {
                const file = files[i];
                if (!file.type.startsWith('image/') && !file.type.startsWith('video/')) {
                    showError('Only image and video files are allowed.');
                    continue;
                }

                // Avoid duplicates in the visual queue
                if (queuedFiles.some(f => f.name === file.name && f.size === file.size)) {
                    continue;
                }

                queuedFiles.push(file);
            }
            updateQueueUI();
        }

        // Update the visual staged list
        function updateQueueUI() {
            stagedList.innerHTML = '';

            if (queuedFiles.length === 0) {
                stagedTitle.style.display = 'none';
                uploadBtn.disabled = true;
                dropzone.style.display = 'flex'; // Restore drop zone
                return;
            }

            stagedTitle.style.display = 'block';
            stagedTitle.textContent = `Staged Files (${queuedFiles.length})`;
            uploadBtn.disabled = false;
            dropzone.style.display = 'none'; // Hide drop zone!

            queuedFiles.forEach((file, index) => {
                const item = document.createElement('div');
                item.className = 'staged-item';

                // Default to generic placeholder icon while staged
                const img = document.createElement('img');
                img.src = `data:image/svg+xml;utf8,<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="%233858e9"><path d="M21 19V5c0-1.1-.9-2-2-2H5c-1.1 0-2 .9-2 2v14c0 1.1.9 2 2 2h14c1.1 0 2-.9 2-2zM8.5 13.5l2.5 3.01L14.5 12l4.5 6H5l3.5-4.5z"/></svg>`;

                const details = document.createElement('div');
                details.className = 'staged-item-details';

                const name = document.createElement('div');
                name.className = 'staged-item-name';
                name.textContent = file.name;

                const size = document.createElement('div');
                size.className = 'staged-item-size';
                size.textContent = formatBytes(file.size);

                details.appendChild(name);
                details.appendChild(size);

                const progressOverlay = document.createElement('div');
                progressOverlay.className = 'staged-item-progress-overlay';
                
                const pctLabel = document.createElement('div');
                pctLabel.className = 'staged-item-pct';
                pctLabel.textContent = '0%'; // show 0% initially
                
                // Keep reference to elements in file object for easy access later
                file.ui = { item, progressOverlay, pctLabel, img, removeBtn: null };

                // Remove button with SVG trash icon
                const removeBtn = document.createElement('button');
                removeBtn.className = 'remove-btn';
                removeBtn.title = 'Remove file';
                removeBtn.innerHTML = `
                    <svg viewBox="0 0 24 24">
                        <path d="M6 19c0 1.1.9 2 2 2h8c1.1 0 2-.9 2-2V7H6v12zM19 4h-3.5l-1-1h-5l-1 1H5v2h14V4z"/>
                    </svg>
                `;
                removeBtn.addEventListener('click', () => removeFile(index));
                file.ui.removeBtn = removeBtn;

                item.appendChild(progressOverlay);
                item.appendChild(img);
                item.appendChild(details);
                item.appendChild(pctLabel);
                item.appendChild(removeBtn);
                stagedList.appendChild(item);
            });
        }

        // Remove a file from queue
        function removeFile(index) {
            queuedFiles.splice(index, 1);
            updateQueueUI();
        }

        // Display an error message
        function showError(msg) {
            errorMessage.textContent = msg;
            errorMessage.style.display = 'block';
            setTimeout(() => {
                errorMessage.textContent = '';
            }, 6000);
        }

        let activeXhr = null;

        let fileStatus = []; // tracks state per queued file

        function checkAllDone() {
            if (queuedFiles.length === 0) return;

            if (activeUploads === 0 && uploadIndex >= queuedFiles.length) {
                const errCount = fileStatus.filter(s => s && s.error).length;
                if (errCount > 0) {
                    showError(`${errCount} file(s) failed to upload/process properly. Redirecting...`);
                    setTimeout(() => window.location.href = '/', 4000);
                } else {
                    setTimeout(() => window.location.href = '/', 1150); // Wait for the final file's animations to finish
                }
            }
        }

        // Progress state:
        //   totalQueueBytes — sum of all file sizes in the queue
        //   uploadedBytes   — sum of sizes for fully uploaded files
        //   currentFileUploadedBytes — bytes sent for the file currently in flight
        //   processedCount  — number of files processed
        //
        const maxConcurrentUploads = 3;
        let uploadIndex = 0;
        let activeUploads = 0;

        // Concurrent Queue Uploader: allows up to maxConcurrentUploads files in flight.
        function uploadNextFile() {
            if (uploadIndex >= queuedFiles.length) {
                return;
            }

            const index = uploadIndex;
            uploadIndex++;
            activeUploads++;

            const activeFile = queuedFiles[index];
            
            // Show the actual image thumbnail while uploading
            if (activeFile.size <= 50 * 1024 * 1024 && activeFile.type.startsWith('image/')) {
                activeFile.ui.img.src = URL.createObjectURL(activeFile);
                activeFile.ui.img.onload = () => URL.revokeObjectURL(activeFile.ui.img.src);
            }

            const formData = new FormData();
            formData.append('images', activeFile);

            const xhr = new XMLHttpRequest();
            xhr.open('POST', '/upload', true);
            
            function getCsrfToken() {
                const match = document.cookie.match(new RegExp('(^| )csrf_token=([^;]+)'));
                return match ? match[2] : null;
            }
            const csrfToken = getCsrfToken();
            if (csrfToken) {
                xhr.setRequestHeader('X-CSRF-Token', csrfToken);
            }

            xhr.upload.addEventListener('progress', (e) => {
                if (e.lengthComputable && e.total > 0) {
                    const pct = Math.min(100, Math.round((e.loaded / e.total) * 100));
                    activeFile.ui.progressOverlay.style.width = pct + '%';
                    activeFile.ui.pctLabel.textContent = pct + '%';
                }
            });

            xhr.upload.addEventListener('load', () => {
                activeFile.ui.progressOverlay.style.width = '100%';
                activeFile.ui.pctLabel.textContent = '100%';
                activeFile.ui.item.classList.add('processing');
            });

            xhr.addEventListener('load', () => {
                activeUploads--;

                if (xhr.status < 200 || xhr.status >= 300) {
                    fileStatus[index].error = true;
                    checkAllDone();
                } else {
                    let uuid = null, ext = null;
                    try {
                        const resp = JSON.parse(xhr.responseText);
                        uuid = resp.uuid;
                        ext = resp.ext;
                    } catch (e) { }

                    if (!uuid || !ext) {
                        fileStatus[index].error = true;
                    } else {
                        fileStatus[index].uuid = uuid;
                        // Snap to 100%, wait for progress animation, fade out, then destroy
                        activeFile.ui.progressOverlay.style.width = '100%';
                        activeFile.ui.pctLabel.textContent = '100%';
                        setTimeout(() => {
                            if (activeFile && activeFile.ui && activeFile.ui.item) {
                                activeFile.ui.item.classList.add('fade-out');
                                setTimeout(() => {
                                    if (activeFile && activeFile.ui && activeFile.ui.item) {
                                        activeFile.ui.item.remove();
                                        activeFile.ui = null; // drop references
                                    }
                                }, 1000); // Wait for fade-out CSS animation
                            }
                        }, 150); // Wait for progress bar width animation
                    }
                    checkAllDone();
                }
                uploadNextFile();
            });

            xhr.addEventListener('error', () => {
                activeUploads--;
                fileStatus[index].error = true;
                checkAllDone();
                uploadNextFile();
            });

            xhr.send(formData);
        }

        // Upload the queue
        uploadBtn.addEventListener('click', () => {
            if (queuedFiles.length === 0) return;

            errorMessage.textContent = '';
            uploadBtn.disabled = true;
            dropzone.style.pointerEvents = 'none';

            queuedFiles.forEach(f => {
                if (f.ui.removeBtn) {
                    f.ui.removeBtn.style.display = 'none';
                }
            });

            // Reset all counters for this upload session
            fileStatus = Array.from({ length: queuedFiles.length }, () => ({ uuid: null, error: false }));
            uploadIndex = 0;
            activeUploads = 0;

            // Start parallel upload
            const toStart = Math.min(maxConcurrentUploads, queuedFiles.length);
            for (let i = 0; i < toStart; i++) {
                uploadNextFile();
            }
        });

        // Reset UI after an error
        function resetUploadUI(errorMsg) {
            showError(errorMsg);

            uploadBtn.disabled = false;
            dropzone.style.pointerEvents = 'auto';
            stagedList.style.pointerEvents = 'auto';

            queuedFiles.forEach(f => {
                if (f.ui.removeBtn) {
                    f.ui.removeBtn.style.display = 'flex';
                }
            });
        }
})();
