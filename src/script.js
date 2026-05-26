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
        closeLightbox({target: {id: 'lightbox'}});
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
