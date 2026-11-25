const instanceIndicators = document.querySelectorAll("[data-instance]");

async function updateInstanceIndicators() {
    try {
        const response = await fetch("/instance", { cache: "no-store" });
        if (!response.ok) {
            throw new Error(`HTTP ${response.status}`);
        }

        const data = await response.json();
        for (const indicator of instanceIndicators) {
            indicator.textContent = `Atendiendo desde: ${data.instance}`;
        }
    } catch (error) {
        console.error("No se pudo consultar la instancia web:", error);
        for (const indicator of instanceIndicators) {
            indicator.textContent = "Instancia no disponible";
        }
    }
}

updateInstanceIndicators();
window.setInterval(updateInstanceIndicators, 3000);
