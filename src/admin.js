let originalConfig = {};

function showToast(message) {
    const toast = document.getElementById('toast');
    toast.textContent = message;
    toast.classList.add('show');
    setTimeout(() => {
        toast.classList.remove('show');
    }, 3000);
}

async function loadConfig() {
    try {
        const res = await fetch('/api/admin/config');
        if (!res.ok) throw new Error('Failed to load config');
        const config = await res.json();
        originalConfig = config;
        
        document.getElementById('cfg-backend').value = config.backend || '';
        document.getElementById('cfg-quality').value = config.quality || 90;
        document.getElementById('cfg-thumb-height').value = config.gallery_thumbnail_height || 300;
        document.getElementById('cfg-input-dir').value = config.input_directory || '';
        document.getElementById('cfg-db-dir').value = config.db_dir || '';

        const outputs = config.outputs || [];
        const previewsOut = outputs.find(o => o.name === 'previews');
        const thumbOut = outputs.find(o => o.name === 'thumbnails');
        
        document.getElementById('cfg-previews-width').value = previewsOut ? previewsOut.target_width : 1200;
        document.getElementById('cfg-previews-height').value = previewsOut ? previewsOut.target_height : 1200;

        document.getElementById('cfg-thumbnails-width').value = thumbOut ? thumbOut.target_width : 600;
        document.getElementById('cfg-thumbnails-height').value = thumbOut ? thumbOut.target_height : 600;
    } catch (err) {
        console.error(err);
        showToast('Error loading config');
    }
}

document.getElementById('config-form').addEventListener('submit', async (e) => {
    e.preventDefault();

    // Preserve existing outputs array, but override sizes for previews and thumbnails
    const newOutputs = JSON.parse(JSON.stringify(originalConfig.outputs || []));
    const previewsOut = newOutputs.find(o => o.name === 'previews');
    if (previewsOut) {
        previewsOut.target_width = parseInt(document.getElementById('cfg-previews-width').value, 10);
        previewsOut.target_height = parseInt(document.getElementById('cfg-previews-height').value, 10);
    } else {
        newOutputs.push({ 
            name: 'previews', 
            target_width: parseInt(document.getElementById('cfg-previews-width').value, 10), 
            target_height: parseInt(document.getElementById('cfg-previews-height').value, 10), 
            directory: './output/previews' 
        });
    }

    const thumbOut = newOutputs.find(o => o.name === 'thumbnails');
    if (thumbOut) {
        thumbOut.target_width = parseInt(document.getElementById('cfg-thumbnails-width').value, 10);
        thumbOut.target_height = parseInt(document.getElementById('cfg-thumbnails-height').value, 10);
    } else {
        newOutputs.push({ 
            name: 'thumbnails', 
            target_width: parseInt(document.getElementById('cfg-thumbnails-width').value, 10), 
            target_height: parseInt(document.getElementById('cfg-thumbnails-height').value, 10), 
            directory: './output/thumbnails' 
        });
    }

    const newConfig = {
        ...originalConfig,
        backend: document.getElementById('cfg-backend').value,
        quality: parseInt(document.getElementById('cfg-quality').value, 10),
        gallery_thumbnail_height: parseInt(document.getElementById('cfg-thumb-height').value, 10),
        input_directory: document.getElementById('cfg-input-dir').value,
        db_dir: document.getElementById('cfg-db-dir').value,
        outputs: newOutputs,
    };
    
    try {
        const res = await fetch('/api/admin/config', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(newConfig)
        });
        if (!res.ok) throw new Error('Save failed');
        originalConfig = newConfig;
        showToast('Config saved! Restart server to apply.');
    } catch (err) {
        console.error(err);
        showToast('Error saving config');
    }
});

loadConfig();
