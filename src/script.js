function openLightbox(src) {
    const lightbox = document.getElementById('lightbox');
    const img = document.getElementById('lightbox-img');
    img.src = src;
    lightbox.style.display = 'flex';
    void lightbox.offsetWidth; // Trigger reflow
    lightbox.classList.add('active');
}

function closeLightbox(e) {
    if (e.target.id === 'lightbox' || e.target.classList.contains('close-btn')) {
        const lightbox = document.getElementById('lightbox');
        lightbox.classList.remove('active');
        setTimeout(() => {
            lightbox.style.display = 'none';
            document.getElementById('lightbox-img').src = '';
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
    
    document.getElementById('menu-delete').onclick = function(event) {
        event.stopPropagation();
        if (confirm("Are you sure you want to delete this photo?")) {
            deletePhoto(uuid);
        }
        closeMenu();
    };
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

