function showToast(message) {
    const toast = document.getElementById('toast');
    toast.textContent = message;
    toast.classList.add('show');
    setTimeout(() => {
        toast.classList.remove('show');
    }, 3000);
}

async function loadUsers() {
    try {
        const res = await fetch('/api/admin/users');
        if (!res.ok) throw new Error('Failed to load users');
        const users = await res.json();
        
        const tbody = document.getElementById('users-tbody');
        tbody.innerHTML = '';
        users.forEach(username => {
            const tr = document.createElement('tr');
            tr.innerHTML = `
                <td>${username}</td>
                <td>
                    <button class="action-btn" onclick="deleteUser('${username}')">Delete</button>
                </td>
            `;
            tbody.appendChild(tr);
        });
    } catch (err) {
        console.error(err);
        showToast('Error loading users');
    }
}

document.getElementById('add-user-form').addEventListener('submit', async (e) => {
    e.preventDefault();
    const usernameInput = document.getElementById('new-username');
    const passwordInput = document.getElementById('new-password');
    
    try {
        const res = await fetch('/api/admin/users', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                username: usernameInput.value,
                password: passwordInput.value
            })
        });
        if (!res.ok) throw new Error('Add user failed');
        usernameInput.value = '';
        passwordInput.value = '';
        showToast('User added');
        loadUsers();
    } catch (err) {
        console.error(err);
        showToast('Error adding user');
    }
});

window.deleteUser = async (username) => {
    if (!confirm(`Are you sure you want to delete ${username}?`)) return;
    
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
