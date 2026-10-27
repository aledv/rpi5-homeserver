(function() {
    // Esegui solo una volta
    if (window.umamiLoaded) return;
    window.umamiLoaded = true;

    document.addEventListener('DOMContentLoaded', () => {
        if (document.querySelector('script[data-website-id="YOUR-UMAMI-WEBSITE-ID"]')) return;
        
        const s = document.createElement('script');
        s.defer = true;
        s.src = 'https://umami.example.com/script.js';
        s.dataset.websiteId = 'YOUR-UMAMI-WEBSITE-ID';
        s.dataset.hostUrl = window.location.origin + '/apps/umami_vue';
        document.body.appendChild(s);
        console.log('✅ Umami analytics loaded');
    });
})();
