const tableBody = document.getElementById("videoTableBody");
const messageElement = document.getElementById("adminMessage");
const searchInput = document.getElementById("videoSearch");
const formSection = document.getElementById("videoFormSection");
const videoForm = document.getElementById("videoForm");
const minioVideoField = document.getElementById("minioVideoField");
const minioVideoSelect = document.getElementById("minioVideoSelect");
const minioVideoStatus = document.getElementById("minioVideoStatus");
const thumbnailPreviewFrame = document.querySelector(".thumbnail-preview-frame");
const thumbnailPlaceholder = document.querySelector(".thumbnail-placeholder");

const fields = {
    id: document.getElementById("videoId"),
    title: document.getElementById("title"),
    description: document.getElementById("description"),
    durationSeconds: document.getElementById("durationSeconds"),
    thumbnailUrl: document.getElementById("thumbnailUrl"),
    mpdPath: document.getElementById("mpdPath"),
    categoryId: document.getElementById("categoryId")
};

const thumbnailPreview = document.getElementById("thumbnailPreview");
thumbnailPreview.addEventListener("error", () => {
    thumbnailPreview.hidden = true;
    thumbnailPlaceholder.hidden = false;
});

let videos = [];
let categories = [];
let minioVideos = [];

function showMessage(message, isError = false) {
    messageElement.textContent = message;
    messageElement.classList.toggle("admin-error", isError);
    messageElement.classList.toggle("admin-success", !isError);
}

async function apiRequest(url, options = {}) {
    const response = await fetch(url, {
        credentials: "same-origin",
        ...options,
        headers: {
            ...(options.body ? { "Content-Type": "application/json" } : {}),
            ...options.headers
        }
    });

    const result = await response.json().catch(() => ({}));

    if (response.status === 401) {
        window.location.replace("/login.html");
        throw new Error("Tu sesión ha caducado. Inicia sesión de nuevo.");
    }

    if (response.status === 403) {
        throw new Error("Tu cuenta no tiene permisos de administrador.");
    }

    if (!response.ok) {
        throw new Error(result.error || "La operación no se ha podido completar.");
    }

    return result;
}

function formatDuration(seconds) {
    const value = Number(seconds);

    if (!Number.isFinite(value) || value < 0) {
        return "—";
    }

    const hours = Math.floor(value / 3600);
    const minutes = Math.floor((value % 3600) / 60);
    const remainingSeconds = value % 60;

    if (hours > 0) {
        return `${hours}:${String(minutes).padStart(2, "0")}:${String(remainingSeconds).padStart(2, "0")}`;
    }

    return `${minutes}:${String(remainingSeconds).padStart(2, "0")}`;
}

function getCategoryName(categoryId) {
    const category = categories.find(
        item => Number(item.id) === Number(categoryId)
    );

    return category ? category.name : (categoryId ?? "—");
}

function createCell(text, label) {
    const cell = document.createElement("td");
    cell.textContent = text ?? "—";
    cell.dataset.label = label;
    return cell;
}

function renderVideos() {
    const search = searchInput.value.trim().toLowerCase();

    const filteredVideos = videos.filter(video =>
        String(video.title || "").toLowerCase().includes(search)
    );

    tableBody.replaceChildren();

    if (filteredVideos.length === 0) {
        const row = document.createElement("tr");
        row.className = "table-message-row";
        const cell = createCell(
            search ? "No hay resultados para esa búsqueda." : "Todavía no hay vídeos.",
            "Estado"
        );
        cell.colSpan = 6;
        row.appendChild(cell);
        tableBody.appendChild(row);
        return;
    }

    for (const video of filteredVideos) {
        const row = document.createElement("tr");

        const imageCell = document.createElement("td");
        imageCell.dataset.label = "Portada";
        if (video.thumbnailUrl) {
            const image = document.createElement("img");
            image.src = video.thumbnailUrl;
            image.alt = "";
            image.className = "admin-table-thumbnail";
            image.loading = "lazy";
            image.addEventListener("error", () => image.remove());
            imageCell.appendChild(image);
        } else {
            imageCell.textContent = "Sin portada";
        }

        row.appendChild(imageCell);
        row.appendChild(createCell(video.title, "Título"));
        row.appendChild(createCell(getCategoryName(video.categoryId), "Categoría"));
        row.appendChild(createCell(formatDuration(video.durationSeconds), "Duración"));
        row.appendChild(createCell(video.mpdPath, "Manifiesto MPD"));

        const actionsCell = document.createElement("td");
        actionsCell.dataset.label = "Acciones";
        const actions = document.createElement("div");
        actions.className = "admin-actions";

        const editButton = document.createElement("button");
        editButton.type = "button";
        editButton.textContent = "Editar";
        editButton.className = "secondary-button";
        editButton.addEventListener("click", () => openEditForm(video));

        const deleteButton = document.createElement("button");
        deleteButton.type = "button";
        deleteButton.textContent = "Eliminar";
        deleteButton.className = "danger-button";
        deleteButton.addEventListener("click", () => deleteVideo(video));

        actions.append(editButton, deleteButton);
        actionsCell.appendChild(actions);
        row.appendChild(actionsCell);
        tableBody.appendChild(row);
    }
}

async function loadVideos() {
    try {
        const result = await apiRequest("/api/admin/videos");
        videos = result.data || [];
        renderVideos();
    } catch (error) {
        showMessage(error.message, true);
        tableBody.replaceChildren();

        const row = document.createElement("tr");
        const cell = createCell("No se ha podido cargar la biblioteca.");
        cell.colSpan = 6;
        row.appendChild(cell);
        tableBody.appendChild(row);
    }
}

async function loadCategories() {
    const result = await apiRequest("/api/admin/categories");
    categories = result.data || [];

    fields.categoryId.replaceChildren();

    const emptyOption = document.createElement("option");
    emptyOption.value = "";
    emptyOption.textContent = "Sin categoría";
    fields.categoryId.appendChild(emptyOption);

    for (const category of categories) {
        const option = document.createElement("option");
        option.value = category.id;
        option.textContent = category.name;
        fields.categoryId.appendChild(option);
    }
}

function resetForm() {
    videoForm.reset();
    fields.id.value = "";
    minioVideoSelect.value = "";
    thumbnailPreview.removeAttribute("src");
    thumbnailPreview.hidden = true;
    thumbnailPlaceholder.hidden = false;
    document.getElementById("formTitle").textContent = "Añadir vídeo";
    document.getElementById("saveVideoButton").textContent = "Guardar vídeo";
}

function openNewForm() {
    resetForm();
    minioVideoField.hidden = false;
    formSection.hidden = false;
    formSection.scrollIntoView({ behavior: "smooth", block: "start" });
    fields.title.focus();
    loadMinioVideos();
}

function openEditForm(video) {
    resetForm();
    minioVideoField.hidden = true;

    fields.id.value = video.id;
    fields.title.value = video.title || "";
    fields.description.value = video.description || "";
    fields.durationSeconds.value = video.durationSeconds;
    fields.thumbnailUrl.value = video.thumbnailUrl || "";
    fields.mpdPath.value = video.mpdPath || "";
    fields.categoryId.value = video.categoryId ?? "";

    document.getElementById("formTitle").textContent = "Editar vídeo";
    document.getElementById("saveVideoButton").textContent = "Guardar cambios";

    updateThumbnailPreview();
    formSection.hidden = false;
    formSection.scrollIntoView({ behavior: "smooth", block: "start" });
}

async function loadMinioVideos() {
    minioVideos = [];
    minioVideoSelect.disabled = true;
    minioVideoSelect.replaceChildren();

    const loadingOption = document.createElement("option");
    loadingOption.value = "";
    loadingOption.textContent = "Consultando MinIO...";
    minioVideoSelect.appendChild(loadingOption);
    minioVideoStatus.textContent = "Cargando manifiestos disponibles...";

    try {
        const result = await apiRequest("/api/admin/minio-videos");
        minioVideos = result.data || [];
        minioVideoSelect.replaceChildren();

        const placeholder = document.createElement("option");
        placeholder.value = "";
        placeholder.textContent = minioVideos.length
            ? "Selecciona un vídeo almacenado"
            : "No hay manifiestos disponibles";
        minioVideoSelect.appendChild(placeholder);

        for (const video of minioVideos) {
            const option = document.createElement("option");
            option.value = video.mpdPath;
            option.textContent = video.registered
                ? `${video.name} · ${video.mpdPath} (ya está en el catálogo)`
                : `${video.name} · ${video.mpdPath}`;
            option.disabled = video.registered;
            minioVideoSelect.appendChild(option);
        }

        minioVideoSelect.disabled = !minioVideos.some(
            video => !video.registered
        );
        minioVideoStatus.textContent = minioVideos.length
            ? "Al seleccionar un vídeo se rellenan su nombre y la ruta MPD. Completa la duración y los demás datos del catálogo."
            : "No se encontraron archivos manifest.mpd en el bucket de manifiestos.";
    } catch (error) {
        minioVideoSelect.replaceChildren();
        const errorOption = document.createElement("option");
        errorOption.value = "";
        errorOption.textContent = "No se pudo consultar MinIO";
        minioVideoSelect.appendChild(errorOption);
        minioVideoStatus.textContent = error.message;
    }
}

function selectMinioVideo() {
    const selectedVideo = minioVideos.find(
        video => video.mpdPath === minioVideoSelect.value
    );
    if (!selectedVideo || selectedVideo.registered) return;

    fields.mpdPath.value = selectedVideo.mpdPath;
    fields.title.value = selectedVideo.name;
}

function updateThumbnailPreview() {
    const url = fields.thumbnailUrl.value.trim();

    if (!url) {
        thumbnailPreview.removeAttribute("src");
        thumbnailPreview.hidden = true;
        thumbnailPlaceholder.hidden = false;
        return;
    }

    try {
        const parsedUrl = new URL(url);

        if (!["http:", "https:"].includes(parsedUrl.protocol)) {
            throw new Error("URL no válida");
        }

        thumbnailPreview.hidden = false;
        thumbnailPlaceholder.hidden = true;
        thumbnailPreview.src = parsedUrl.href;
    } catch {
        thumbnailPreview.removeAttribute("src");
        thumbnailPreview.hidden = true;
        thumbnailPlaceholder.hidden = false;
    }
}

async function saveVideo(event) {
    event.preventDefault();

    const id = fields.id.value;

    const video = {
        title: fields.title.value.trim(),
        description: fields.description.value.trim(),
        durationSeconds: Number(fields.durationSeconds.value),
        thumbnailUrl: fields.thumbnailUrl.value.trim(),
        mpdPath: fields.mpdPath.value.trim(),
        categoryId: fields.categoryId.value || null
    };

    const saveButton = document.getElementById("saveVideoButton");
    saveButton.disabled = true;

    try {
        await apiRequest(
            id ? `/api/admin/videos/${encodeURIComponent(id)}` : "/api/admin/videos",
            {
                method: id ? "PUT" : "POST",
                body: JSON.stringify(video)
            }
        );

        showMessage(id ? "Vídeo actualizado correctamente." : "Vídeo creado correctamente.");
        resetForm();
        formSection.hidden = true;
        await loadVideos();
    } catch (error) {
        showMessage(error.message, true);
    } finally {
        saveButton.disabled = false;
    }
}

async function deleteVideo(video) {
    const confirmed = window.confirm(
        `¿Seguro que quieres eliminar "${video.title}" de la base de datos?`
    );

    if (!confirmed) {
        return;
    }

    try {
        await apiRequest(
            `/api/admin/videos/${encodeURIComponent(video.id)}`,
            { method: "DELETE" }
        );

        showMessage("Vídeo eliminado de la base de datos.");
        await loadVideos();
    } catch (error) {
        showMessage(error.message, true);
    }
}

document.getElementById("newVideoButton").addEventListener("click", openNewForm);
document.getElementById("cancelFormButton").addEventListener("click", () => {
    formSection.hidden = true;
    resetForm();
});
document.getElementById("resetFormButton").addEventListener("click", resetForm);
videoForm.addEventListener("submit", saveVideo);
searchInput.addEventListener("input", renderVideos);
fields.thumbnailUrl.addEventListener("input", updateThumbnailPreview);
minioVideoSelect.addEventListener("change", selectMinioVideo);
fields.mpdPath.addEventListener("input", () => {
    if (fields.mpdPath.value !== minioVideoSelect.value) {
        minioVideoSelect.value = "";
    }
});

async function initializeAdmin() {
    try {
        const auth = await apiRequest("/auth/me");

        if (auth.user?.role !== "admin") {
            showMessage("Tu cuenta no tiene permisos de administrador.", true);
            return;
        }

        await loadCategories();
        await loadVideos();
    } catch (error) {
        showMessage(error.message, true);
    }
}

initializeAdmin();
