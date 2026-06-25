(function () {
    const readout = document.querySelector(".depth-readout");
    const header = document.getElementById("site-header");
    const prefersReducedMotion = window.matchMedia("(prefers-reduced-motion: reduce").matches;

    function update() {
        const scrolled = window.scrollY;
        const depth = Math.round(scrolled * 0.6);

        if (readout) {
            readout.textContent = depth + "m";
        }
        if (header) {
            header.classList.toggle("is-diving", scrolled > 40);
        }
    }

    update();

    if (prefersReducedMotion) {
        // Still keep the readout accurate, just skip any rAF-driven smoothing
        window.addEventListener("scroll", update, { passive: true });
        return;
    }

    let ticking = false;
    window.addEventListener(
        "scroll",
        () => {
            if (!ticking) {
                requestAnimationFrame(() => {
                    update();
                    ticking = false;
                });
                ticking = true;
            }
        },
        { passive: true }
    );
})();