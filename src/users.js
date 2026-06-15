function getCsrfToken() {
    const match = document.cookie.match(new RegExp('(^| )csrf_token=([^;]+)'));
    return match ? match[2] : null;
}

const originalFetch = window.fetch;
window.fetch = function() {
    let [resource, config] = arguments;
    if(config && config.method && ['POST', 'PUT', 'DELETE', 'PATCH'].includes(config.method.toUpperCase())) {
        config.headers = config.headers || {};
        config.headers['X-CSRF-Token'] = getCsrfToken();
    }
    return originalFetch(resource, config);
};

function logout() {
    fetch('/logout', { method: 'POST' }).then(() => {
        window.location.href = '/';
    });
}

function showToast(message) {
    const toast = document.getElementById('toast');
    toast.textContent = message;
    toast.classList.add('show');
    setTimeout(() => {
        toast.classList.remove('show');
    }, 3000);
}

// Modal handling
const modal = document.getElementById('add-user-modal');
const fab = document.getElementById('fab-add-user');
const cancelBtn = document.getElementById('btn-cancel-add');
const form = document.getElementById('add-user-form');
const usernameInput = document.getElementById('new-username');
const passwordInput = document.getElementById('new-password');
const realNameInput = document.getElementById('new-real-name');

const editModal = document.getElementById('edit-user-modal');
const editCancelBtn = document.getElementById('btn-cancel-edit');
const editForm = document.getElementById('edit-user-form');
const editUsernameInput = document.getElementById('edit-username');
const editRealNameInput = document.getElementById('edit-real-name');
const editPasswordInput = document.getElementById('edit-password');
const newIsAdminInput = document.getElementById('new-is-admin');
const editIsAdminInput = document.getElementById('edit-is-admin');

function openModal() {
    modal.classList.add('show');
    usernameInput.focus();
}

function closeModal() {
    modal.classList.remove('show');
    form.reset();
}

function openEditModal(username, currentRealName, isAdmin) {
    editUsernameInput.value = username;
    editRealNameInput.value = currentRealName || '';
    editPasswordInput.value = '';
    editIsAdminInput.checked = isAdmin;
    editModal.classList.add('show');
    editRealNameInput.focus();
}

function closeEditModal() {
    editModal.classList.remove('show');
    editForm.reset();
}

fab.addEventListener('click', openModal);
cancelBtn.addEventListener('click', closeModal);
editCancelBtn.addEventListener('click', closeEditModal);

modal.addEventListener('click', (e) => {
    if (e.target === modal) {
        closeModal();
    }
});

editModal.addEventListener('click', (e) => {
    if (e.target === editModal) {
        closeEditModal();
    }
});

window.openEditModal = openEditModal;

async function loadUsers() {
    try {
        const res = await fetch('/api/admin/users');
        if (!res.ok) throw new Error('Failed to load users');
        const users = await res.json();
        
        const grid = document.getElementById('users-grid');
        grid.innerHTML = '';
        users.forEach(u => {
            const username = u.username;
            const realName = u.real_name || username;
            const initial = realName.charAt(0).toUpperCase();
            
            const card = document.createElement('div');
            card.className = 'user-card';
            card.innerHTML = `
                <div class="user-avatar">${initial}</div>
                <div class="user-info">
                    <div class="user-name" title="${realName}">${realName} ${u.is_admin ? '<span style="font-size: 0.8em; background: var(--md-sys-color-primary-container); color: var(--md-sys-color-on-primary-container); padding: 2px 6px; border-radius: 4px; margin-left: 4px;">Admin</span>' : ''}</div>
                    <div class="user-subtitle" title="${username}">${username}</div>
                </div>
                <div style="display: flex; gap: 8px;">
                    <button class="user-action-btn" title="Edit User" onclick="openEditModal('${username}', '${u.real_name.replace(/'/g, "\\'")}', ${u.is_admin})">
                        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" fill="currentColor">
                            <path d="M3 17.25V21h3.75L17.81 9.94l-3.75-3.75L3 17.25zM20.71 7.04c.39-.39.39-1.02 0-1.41l-2.34-2.34a.995.995 0 0 0-1.41 0l-1.83 1.83 3.75 3.75 1.83-1.83z"/>
                        </svg>
                    </button>
                    <button class="user-action-btn user-delete-btn" title="Delete User" onclick="deleteUser('${username}')">
                        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" fill="currentColor">
                            <path d="M15 4V3H9v1H4v2h1v13c0 1.1.9 2 2 2h10c1.1 0 2-.9 2-2V6h1V4h-5zm2 15H7V6h10v13zM9 8h2v9H9zm4 0h2v9h-2z"/>
                        </svg>
                    </button>
                </div>
            `;
            grid.appendChild(card);
        });
    } catch (err) {
        console.error(err);
        showToast('Error loading users');
    }
}

form.addEventListener('submit', async (e) => {
    e.preventDefault();
    
    try {
        const res = await fetch('/api/admin/users', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                username: usernameInput.value,
                password: passwordInput.value,
                real_name: realNameInput.value,
                is_admin: newIsAdminInput.checked
            })
        });
        if (!res.ok) {
            if (res.status === 409) {
                throw new Error('User already exists');
            }
            throw new Error('Add user failed');
        }
        
        showToast('User added successfully');
        closeModal();
        loadUsers();
    } catch (err) {
        console.error(err);
        showToast(err.message || 'Error adding user');
    }
});

editForm.addEventListener('submit', async (e) => {
    e.preventDefault();
    const username = editUsernameInput.value;
    
    try {
        const payload = {};
        const rn = editRealNameInput.value.trim();
        const pwd = editPasswordInput.value;
        if (rn) payload.real_name = rn;
        if (pwd) payload.password = pwd;
        payload.is_admin = editIsAdminInput.checked;

        const res = await fetch('/api/admin/users/' + encodeURIComponent(username), {
            method: 'PUT',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(payload)
        });
        
        if (!res.ok) throw new Error('Edit user failed');
        
        showToast('User updated successfully');
        closeEditModal();
        loadUsers();
    } catch (err) {
        console.error(err);
        showToast('Error updating user');
    }
});

window.deleteUser = async (username) => {
    if (!confirm(`Are you sure you want to delete user '${username}'?`)) return;
    
    try {
        const res = await fetch('/api/admin/users/' + encodeURIComponent(username), {
            method: 'DELETE'
        });
        if (!res.ok) {
            const errText = await res.text();
            throw new Error(errText || 'Delete failed');
        }
        showToast('User deleted');
        loadUsers();
    } catch (err) {
        console.error(err);
        showToast('Error deleting user: ' + err.message);
    }
};

loadUsers();
