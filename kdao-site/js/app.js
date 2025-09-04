// Test ob JavaScript läuft
console.log('KDAO App gestartet!');

// Language Switcher
function setLanguage(lang) {
    console.log('Sprache wechseln zu:', lang);

    // Update Button States
    document.querySelectorAll('.lang-btn').forEach(btn => {
        btn.classList.remove('active');
    });
    
    // Find the button that was clicked
    const langBtns = document.querySelectorAll('.lang-btn');
    langBtns.forEach(btn => {
        if (btn.textContent.includes(lang.toUpperCase())) {
            btn.classList.add('active');
        }
    });

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
    
    // Set initial language
    document.querySelectorAll('[data-lang]').forEach(element => {
        element.style.display = 'none';
    });
    document.querySelectorAll(`[data-lang="${savedLang}"]`).forEach(element => {
        element.style.display = 'block';
    });
    
    // Update button states
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

// API Test Funktion mit CORS-Header Handling
async function testAPI() {
    console.log('Teste API Verbindung...');
    
    const statusEl = document.getElementById('apiStatus');
    if (statusEl) {
        statusEl.innerHTML = '<span style="color: #fbbf24;">🔄 Verbinde mit API...</span>';
    }
    
    try {
        // Vercel API URL
        const apiUrl = 'https://kdao-api.vercel.app/api/kdao';
        
        const response = await fetch(apiUrl, {
            method: 'GET',
            headers: {
                'Accept': 'application/json',
            },
            mode: 'cors' // Explicitly set CORS mode
        });
        
        if (!response.ok) {
            throw new Error(`HTTP error! status: ${response.status}`);
        }
        
        const data = await response.json();
        console.log('API Antwort:', data);
        
        if (statusEl) {
            statusEl.innerHTML = '<span style="color: #10b981;">✅ API verbunden</span>';
        }
        
        return data;
        
    } catch(error) {
        console.error('API Fehler:', error);
        
        if (statusEl) {
            statusEl.innerHTML = '<span style="color: #ef4444;">❌ API offline - Verwende Beispieldaten</span>';
        }
        
        // Return fallback data
        return {
            success: true,
            data: {
                price: 0.00000121,
                change24h: -5.24,
                volume24h: 3280,
                high24h: 0.00000128,
                low24h: 0.00000115,
                marketCap: 181500
            }
        };
    }
}

// Update Dashboard Data
function updateDashboardData(data) {
    if (!data || !data.data) return;
    
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
        volumeEl.textContent = volume > 1000 ? `$${(volume / 1000).toFixed(1)}K` : `$${volume.toFixed(0)}`;
    }
    
    // Update high/low
    const high = data.data.high24h || 0;
    const low = data.data.low24h || 0;
    const highLowEl = document.getElementById('highLow');
    if (highLowEl) {
        highLowEl.textContent = `$${high.toFixed(8)} / $${low.toFixed(8)}`;
    }
    
    // Update trading signal
    if (typeof window.updateSignal === 'function') {
        window.updateSignal(price, change);
    }
    
    // Update other indicators
    const rsiEl = document.getElementById('rsi');
    if (rsiEl && !rsiEl.textContent || rsiEl.textContent === '-') {
        rsiEl.textContent = Math.floor(40 + Math.random() * 30);
    }
    
    const macdEl = document.getElementById('macd');
    if (macdEl && !macdEl.textContent || macdEl.textContent === '-') {
        macdEl.textContent = (change / 2).toFixed(2) + '%';
    }
    
    const trendEl = document.getElementById('trend');
    if (trendEl && !trendEl.textContent || trendEl.textContent === '-') {
        trendEl.textContent = change > 0 ? 'UP' : change < 0 ? 'DOWN' : 'NEUTRAL';
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
        setTimeout(async () => {
            mainContent.innerHTML = html;
            
            // Dashboard spezifische Aktionen
            if (pageName === 'dashboard') {
                try {
                    const data = await testAPI();
                    updateDashboardData(data);
                    
                    // Initialize charts after data is loaded
                    setTimeout(() => {
                        console.log('Initializing charts...');
                        
                        // Check if Chart.js is loaded
                        if (typeof Chart !== 'undefined') {
                            if (typeof window.drawCandlestickChart === 'function') {
                                window.drawCandlestickChart();
                            } else {
                                console.warn('drawCandlestickChart function not found');
                            }
                            
                            if (typeof window.drawSparkline === 'function') {
                                window.drawSparkline();
                            } else {
                                console.warn('drawSparkline function not found');
                            }
                        } else {
                            console.error('Chart.js library not loaded!');
                        }
                    }, 500);
                    
                } catch (error) {
                    console.error('Dashboard data error:', error);
                    // Use fallback values
                    const fallbackData = {
                        success: true,
                        data: {
                            price: 0.00000121,
                            change24h: -5.24,
                            volume24h: 3280,
                            high24h: 0.00000128,
                            low24h: 0.00000115
                        }
                    };
                    updateDashboardData(fallbackData);
                }
            }
            
            // Re-apply language settings after loading new content
            const savedLang = localStorage.getItem('kdao-lang') || 'en';
            document.querySelectorAll('[data-lang]').forEach(element => {
                element.style.display = 'none';
            });
            document.querySelectorAll(`[data-lang="${savedLang}"]`).forEach(element => {
                element.style.display = 'block';
            });
            
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

// Auto-refresh every 30 seconds
setInterval(async () => {
    if (window.currentPage === 'dashboard') {
        const time = new Date().toLocaleTimeString();
        console.log(`[${time}] Refreshing data...`);
        
        try {
            const data = await testAPI();
            
            if (data && data.data) {
                // Animate price change
                const priceEl = document.getElementById('currentPrice');
                if (priceEl) {
                    priceEl.style.transition = 'color 0.5s';
                    priceEl.style.color = '#5ffbf1';
                    setTimeout(() => {
                        priceEl.style.color = '';
                    }, 500);
                }
                
                // Update all values
                updateDashboardData(data);
                
                // Optionally refresh charts
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
        } catch (error) {
            console.error('Auto-refresh error:', error);
        }
    }
}, 30000);

// Add API status indicator
document.addEventListener('DOMContentLoaded', () => {
    // Create API status element if it doesn't exist
    if (!document.getElementById('apiStatus')) {
        const statusDiv = document.createElement('div');
        statusDiv.id = 'apiStatus';
        statusDiv.style.cssText = `
            position: fixed;
            bottom: 20px;
            right: 20px;
            background: rgba(10, 15, 27, 0.9);
            padding: 10px 15px;
            border-radius: 8px;
            border: 1px solid rgba(95, 251, 241, 0.2);
            font-size: 12px;
            z-index: 9999;
            display: flex;
            align-items: center;
            gap: 8px;
        `;
        statusDiv.innerHTML = '<span style="color: #94a3b8;">API Status: Initialisiere...</span>';
        document.body.appendChild(statusDiv);
    }
});

console.log('App.js loaded successfully');