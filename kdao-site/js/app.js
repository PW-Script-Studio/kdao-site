// Test ob JavaScript läuft
console.log('KDAO App gestartet!');


// Language Switcher
function setLanguage(lang) {
    console.log('Sprache wechseln zu:', lang);

    // Update Button States
    document.querySelectorAll('.lang-btn').forEach(btn => {
        btn.classList.remove('active');
    });
    event.target.classList.add('active');

    // Store preference
    localStorage.setItem('kdao-lang', lang);

    // Update all text elements
    document.querySelectorAll('[data-lang]').forEach(element => {
        element.style.display = 'none';
    });

    document.querySelectorAll(`[data-lang="${lang}"]`).forEach(element => {
        element.style.display = 'block';
    });
}

// Load saved language on start
document.addEventListener('DOMContentLoaded', () => {
    const savedLang = localStorage.getItem('kdao-lang') || 'en';
    document.querySelectorAll('.lang-btn').forEach(btn => {
        btn.classList.remove('active');
        if(btn.textContent.includes(savedLang.toUpperCase())) {
            btn.classList.add('active');
        }
    });
});

// Einfacher Test
document.addEventListener('DOMContentLoaded', () => {
    const testBox = document.querySelector('.test-box');
    if (testBox) {
        testBox.innerHTML += '<p style="color: #5ffbf1;">✅ JavaScript funktioniert!</p>';
    }
});

// API Test Funktion
async function testAPI() {
    console.log('Teste API Verbindung...');
    try {
        const response = await fetch('https://kdao-api.vercel.app/api/kdao');
        const data = await response.json();
        console.log('API Antwort:', data);
        return data;
    } catch(error) {
        console.error('API Fehler:', error);
    }
}

// Seite laden
async function loadPage(pageName) {
    console.log(`Lade Seite: ${pageName}`);

    try {
        const mainContent = document.querySelector('.main-content');

        // Loading Animation
        mainContent.innerHTML = '<div class="loading-spinner">Loading...</div>';

        const response = await fetch(`pages/${pageName}.html`);
        const html = await response.text();

        // Kleine Verzögerung für bessere UX
        setTimeout(() => {
            mainContent.innerHTML = html;

            // Dashboard spezifische Aktionen
            if (pageName === 'dashboard') {
                testAPI().then(data => {
                    if (data && data.data) {
                        // Update price
                        const price = data.data.price || 0;
                        const priceEl = document.getElementById('currentPrice');
                        if (priceEl) {
                            priceEl.textContent = `$${price.toFixed(8)}`;
                        }

                        // Update 24h change
                        const change = data.data.change24h || 0;
                        const changeEl = document.getElementById('change24');
                        if (changeEl) {
                            changeEl.textContent = `${change > 0 ? '+' : ''}${change.toFixed(2)}%`;
                            changeEl.className = `stat-value ${change > 0 ? 'positive' : 'negative'}`;
                        }

                        // Update volume
                        const volume = data.data.volume24h || 0;
                        const volumeEl = document.getElementById('volume24');
                        if (volumeEl) {
                            volumeEl.textContent = `$${volume.toFixed(0)}`;
                        }

                        // Update high/low
                        const high = data.data.high24h || 0;
                        const low = data.data.low24h || 0;
                        const highLowEl = document.getElementById('highLow');
                        if (highLowEl) {
                            highLowEl.textContent = `$${high.toFixed(8)} / $${low.toFixed(8)}`;
                        }

                        // Update signal
                        if (typeof updateSignal === 'function') {
                            updateSignal(price, change);
                        }

                            // Initialize Trading Signal values
                            const rsiEl = document.getElementById('rsi');
                            if (rsiEl) rsiEl.textContent = Math.floor(40 + Math.random() * 30);
                            const macdEl = document.getElementById('macd');
                            if (macdEl) macdEl.textContent = (Math.random() * 2 - 1).toFixed(2) + '%';
                            const trendEl = document.getElementById('trend');
                            if (trendEl) trendEl.textContent = change > 0 ? 'UP' : 'DOWN';

                    }
                }).catch(error => {
                    console.error('Dashboard data error:', error);
                    // Fallback values
                    document.getElementById('currentPrice').textContent = '$0.00000121';
                    document.getElementById('change24').textContent = '-5.24%';
                    document.getElementById('volume24').textContent = '$3,280';
                    document.getElementById('highLow').textContent = 'N/A';
                });
            }

                        // Draw charts after data is loaded
                        setTimeout(() => {
                            console.log('Initializing charts from app.js');
                            if (typeof window.drawCandlestickChart === 'function') {
                                window.drawCandlestickChart();
                            } else if (typeof drawCandlestickChart === 'function') {
                                drawCandlestickChart();
                            }
                            if (typeof window.drawSparkline === 'function') {
                                window.drawSparkline();
                            } else if (typeof drawSparkline === 'function') {
                                drawSparkline();
                            }
                        }, 500);

        }, 300);

    } catch(error) {
        console.error('Fehler beim Laden der Seite:', error);
        document.querySelector('.main-content').innerHTML =
            '<div class="error">Seite konnte nicht geladen werden</div>';
    }
}


// Auto-load Dashboard beim Start
document.addEventListener('DOMContentLoaded', () => {
    setTimeout(() => {
        loadPage('dashboard');
    }, 100);
});


// Store current page
window.currentPage = 'dashboard';

// Update currentPage when loading new pages
const originalLoadPage = loadPage;
loadPage = function(pageName) {
    window.currentPage = pageName;
    return originalLoadPage(pageName);
};

// Auto-refresh every 10 seconds for testing (später 30 sec)
setInterval(() => {
    if (window.currentPage === 'dashboard') {
        const time = new Date().toLocaleTimeString();
        console.log(`[${time}] Refreshing data...`);

        testAPI().then(data => {
            if (data && data.data) {
                // Animate price change
                const priceEl = document.getElementById('currentPrice');
                if (priceEl) {
                    priceEl.style.transition = 'color 0.5s';
                    priceEl.style.color = '#5ffbf1';
                    priceEl.textContent = `$${data.data.price.toFixed(8)}`;
                    setTimeout(() => {
                        priceEl.style.color = '';
                    }, 500);
                }

                // Update all values
                const change = data.data.change24h || 0;
                const changeEl = document.getElementById('change24');
                if (changeEl) {
                    changeEl.textContent = `${change > 0 ? '+' : ''}${change.toFixed(2)}%`;
                    changeEl.className = `stat-value ${change > 0 ? 'positive' : 'negative'}`;
                }

                const volumeEl = document.getElementById('volume24');
                if (volumeEl) {
                    volumeEl.textContent = `$${data.data.volume24h.toFixed(0)}`;
                }


        // Optionally refresh charts on data update
        if (typeof window.refreshCharts === 'function') {
            window.refreshCharts();
        }

                // Flash effect on update
                const card = document.querySelector('.analytics-card:nth-child(2)');
                if (card) {
                    card.style.borderColor = 'rgba(95, 251, 241, 0.5)';
                    setTimeout(() => {
                        card.style.borderColor = '';
                    }, 300);
                }
            }
        });
    }
}, 10000);
