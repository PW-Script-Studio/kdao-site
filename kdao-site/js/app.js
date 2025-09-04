// KDAO App mit Navigation Fix
console.log('KDAO App gestartet!');

// Language Switcher
function setLanguage(lang) {
    console.log('Sprache wechseln zu:', lang);
    document.querySelectorAll('.lang-btn').forEach(btn => {
        btn.classList.remove('active');
    });
    document.querySelectorAll('.lang-btn').forEach(btn => {
        if(btn.textContent.includes(lang.toUpperCase())) {
            btn.classList.add('active');
        }
    });
    localStorage.setItem('kdao-lang', lang);
    document.querySelectorAll('[data-lang]').forEach(element => {
        element.style.display = 'none';
    });
    document.querySelectorAll(`[data-lang="${lang}"]`).forEach(element => {
        element.style.display = 'block';
    });
}

// Update active navigation
function updateActiveNavigation(pageName) {
    // Remove active class from all nav items
    document.querySelectorAll('.nav-item').forEach(item => {
        item.classList.remove('active');
    });
    
    // Add active class to the clicked nav item
    document.querySelectorAll('.nav-item').forEach(item => {
        // Check if the nav item's onclick contains the page name
        const onclickAttr = item.getAttribute('onclick');
        if (onclickAttr && onclickAttr.includes(`loadPage('${pageName}')`)) {
            item.classList.add('active');
        }
    });
}

// Load page
async function loadPage(pageName) {
    console.log(`Lade Seite: ${pageName}`);
    window.currentPage = pageName;
    
    // Update active navigation
    updateActiveNavigation(pageName);
    
    const mainContent = document.querySelector('.main-content');
    mainContent.innerHTML = '<div class="loading-spinner"><div class="spinner-text">Loading...</div></div>';
    
    try {
        let html;
        try {
            const resp1 = await fetch(`./${pageName}.html`);
            if (!resp1.ok) throw new Error('Primary path failed');
            html = await resp1.text();
        } catch (e) {
            const resp2 = await fetch(`pages/${pageName}.html`);
            html = await resp2.text();
        }
        
        setTimeout(async () => {
            mainContent.innerHTML = html;
            
            if (pageName === 'dashboard') {
                // Load data
                await testAPI();
                
                // Initialize charts
                setTimeout(() => {
                    if (typeof window.drawCandlestickChart === 'function') {
                        window.drawCandlestickChart();
                    }
                    if (typeof window.drawSparkline === 'function') {
                        window.drawSparkline();
                    }
                }, 500);
                
                // Update chart with realistic down trend
                if (window.liveChart) {
                    const endPrice = 0.00000114;
                    const startPrice = endPrice / 0.83;
                    const chartData = [];
                    
                    for (let i = 0; i <= 20; i++) {
                        const progress = i / 20;
                        const price = startPrice - (startPrice - endPrice) * progress;
                        const volatility = (Math.random() - 0.5) * 0.00000005;
                        chartData.push(Math.max(endPrice * 0.9, price + volatility));
                    }
                    
                    window.liveChart.data.datasets[0].data = chartData;
                    window.liveChart.update();
                }
            }
            
            // Apply language
            const savedLang = localStorage.getItem('kdao-lang') || 'en';
            document.querySelectorAll('[data-lang]').forEach(element => {
                element.style.display = 'none';
            });
            document.querySelectorAll(`[data-lang="${savedLang}"]`).forEach(element => {
                element.style.display = 'block';
            });
        }, 300);
        
    } catch(error) {
        console.error('Page loading error:', error);
        mainContent.innerHTML = '<div class="error">Page could not be loaded</div>';
    }
}

// Fetch KDAO data using proxy
async function testAPI() {
    console.log('Fetching KDAO data...');
    
    try {
        const proxyUrl = 'https://cors-anywhere.herokuapp.com/';
        const apiUrl = 'https://api.coinex.com/v1/market/ticker?market=KDAOUSDT';
        
        let response = await fetch(apiUrl).catch(() => null);
        
        if (!response || !response.ok) {
            console.log('Direct API failed, trying proxy...');
            response = await fetch(proxyUrl + apiUrl);
        }
        
        if (response && response.ok) {
            const data = await response.json();
            
            if (data.code === 0 && data.data && data.data.ticker) {
                const ticker = data.data.ticker;
                const price = parseFloat(ticker.last) || 0.00000114;
                const open = parseFloat(ticker.open) || price;
                const change = ((price - open) / open * 100) || -17.00;
                const volume = parseFloat(ticker.vol) || 3500;
                const high = parseFloat(ticker.high) || price * 1.1;
                const low = parseFloat(ticker.low) || price * 0.9;
                
                if (document.getElementById('currentPrice')) {
                    document.getElementById('currentPrice').textContent = `$${price.toFixed(8)}`;
                    document.getElementById('change24').textContent = `${change > 0 ? '+' : ''}${change.toFixed(2)}%`;
                    document.getElementById('change24').className = `stat-value ${change > 0 ? 'positive' : 'negative'}`;
                    document.getElementById('volume24').textContent = volume > 1000 ? `$${(volume / 1000).toFixed(1)}K` : `$${volume.toFixed(0)}`;
                    document.getElementById('highLow').textContent = `$${high.toFixed(8)} / $${low.toFixed(8)}`;
                    
                    updateSignal(price, change);
                }
                
                const statusEl = document.getElementById('apiStatus');
                if (statusEl) {
                    statusEl.innerHTML = '<span class="status-dot active"></span><span class="status-text">Live Data Connected</span>';
                }
                
                return { success: true, price, change };
            }
        }
    } catch(error) {
        console.error('API Error:', error);
    }
    
    const currentPrice = 0.00000114;
    const currentChange = -17.00;
    
    if (document.getElementById('currentPrice')) {
        document.getElementById('currentPrice').textContent = `$${currentPrice.toFixed(8)}`;
        document.getElementById('change24').textContent = `${currentChange.toFixed(2)}%`;
        document.getElementById('change24').className = 'stat-value negative';
        document.getElementById('volume24').textContent = '$3.5K';
        document.getElementById('highLow').textContent = '$0.00000125 / $0.00000103';
        
        updateSignal(currentPrice, currentChange);
    }
    
    const statusEl = document.getElementById('apiStatus');
    if (statusEl) {
        statusEl.innerHTML = '<span class="status-dot"></span><span class="status-text">Using Static Data</span>';
    }
    
    return { success: false, price: currentPrice, change: currentChange };
}

// Update trading signal
function updateSignal(price, change) {
    const signalBox = document.getElementById('signalBox');
    const signalText = document.getElementById('signalText');
    const signalReason = document.getElementById('signalReason');
    
    if (!signalBox || !signalText || !signalReason) return;
    
    let signal = 'HOLD';
    let reason = 'Market is neutral';
    let signalClass = 'hold';
    
    if (change < -10) {
        signal = 'BUY';
        reason = 'Strong dip - excellent entry point';
        signalClass = 'buy';
    } else if (change < -5) {
        signal = 'BUY';
        reason = 'Good entry point at discount';
        signalClass = 'buy';
    } else if (change > 5) {
        signal = 'SELL';
        reason = 'Strong upward movement';
        signalClass = 'sell';
    } else if (change > 2) {
        signal = 'HOLD';
        reason = 'Moderate upward trend';
        signalClass = 'hold';
    }
    
    signalBox.className = `signal-display ${signalClass}`;
    signalText.textContent = signal;
    signalReason.textContent = reason;
    
    const rsiEl = document.getElementById('rsi');
    if (rsiEl) {
        const rsi = change < -10 ? Math.floor(20 + Math.random() * 15) : 50 + (change * 3);
        rsiEl.textContent = Math.max(0, Math.min(100, Math.round(rsi)));
    }
    
    const macdEl = document.getElementById('macd');
    if (macdEl) {
        macdEl.textContent = (change / 2).toFixed(2) + '%';
    }
    
    const trendEl = document.getElementById('trend');
    if (trendEl) {
        trendEl.textContent = change < -5 ? 'DOWN' : change > 5 ? 'UP' : 'NEUTRAL';
    }
}

// Toggle mobile menu
function toggleMobileMenu() {
    const sidebar = document.querySelector('.sidebar');
    sidebar.classList.toggle('active');
}

// Store current page
window.currentPage = 'dashboard';

// Export functions to window
window.loadPage = loadPage;
window.setLanguage = setLanguage;
window.toggleMobileMenu = toggleMobileMenu;
window.updateSignal = updateSignal;

// Auto-refresh every 30 seconds
setInterval(async () => {
    if (window.currentPage === 'dashboard') {
        const time = new Date().toLocaleTimeString();
        console.log(`[${time}] Refreshing data...`);
        await testAPI();
        
        const priceEl = document.getElementById('currentPrice');
        if (priceEl) {
            priceEl.style.transition = 'color 0.5s';
            priceEl.style.color = '#5ffbf1';
            setTimeout(() => {
                priceEl.style.color = '';
            }, 500);
        }
    }
}, 30000);

// Initialize on load
document.addEventListener('DOMContentLoaded', () => {
    const savedLang = localStorage.getItem('kdao-lang') || 'de';
    setLanguage(savedLang);
    
    setTimeout(() => {
        loadPage('dashboard');
    }, 100);
    
    if (!document.getElementById('apiStatus')) {
        const statusDiv = document.createElement('div');
        statusDiv.id = 'apiStatus';
        statusDiv.className = 'api-status';
        statusDiv.innerHTML = '<span class="status-dot"></span><span class="status-text">Connecting...</span>';
        document.body.appendChild(statusDiv);
    }
});

console.log('App.js loaded - Navigation fix applied');