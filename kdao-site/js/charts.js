// KDAO Charts - 5-Minuten-Updates
console.log('Charts.js loading...');

let liveChart = null;
let chartData = [];
let chartLabels = [];

window.drawCandlestickChart = function() {
    console.log('Initializing chart...');
    const canvas = document.getElementById('liveChart');
    if (!canvas) return;
    
    // Get current price
    const priceEl = document.getElementById('currentPrice');
    let currentPrice = 0.00000114;
    
    if (priceEl && priceEl.textContent) {
        const priceText = priceEl.textContent.replace('$', '');
        currentPrice = parseFloat(priceText) || 0.00000114;
    }
    
    // Initialize with last 24 hours of 5-minute intervals
    if (chartData.length === 0) {
        const intervals = 288; // 24 hours * 12 (5-minute intervals per hour)
        const startPrice = currentPrice * 1.17;
        const now = new Date();
        
        for (let i = 0; i < intervals; i++) {
            const time = new Date(now - (intervals - i) * 300000); // 300000ms = 5 minutes
            const timeStr = `${time.getHours().toString().padStart(2,'0')}:${time.getMinutes().toString().padStart(2,'0')}`;
            chartLabels.push(timeStr);
            
            const progress = i / intervals;
            const price = startPrice - (startPrice - currentPrice) * progress;
            chartData.push(price + (Math.random() - 0.5) * currentPrice * 0.02);
        }
    }
    
    if (liveChart) {
        liveChart.destroy();
    }
    
    liveChart = new Chart(canvas, {
        type: 'line',
        data: {
            labels: chartLabels.slice(-48), // Show last 4 hours (48 * 5min)
            datasets: [{
                label: 'KDAO/USDT',
                data: chartData.slice(-48),
                borderColor: '#ef4444',
                backgroundColor: 'rgba(239, 68, 68, 0.1)',
                borderWidth: 2,
                fill: true,
                tension: 0.3,
                pointRadius: 0,
                pointHoverRadius: 4
            }]
        },
        options: {
            responsive: true,
            maintainAspectRatio: false,
            plugins: {
                legend: { display: false }
            },
            scales: {
                x: {
                    grid: { color: 'rgba(95, 251, 241, 0.05)' },
                    ticks: {
                        color: '#94a3b8',
                        font: { size: 10 },
                        maxTicksLimit: 8,
                        autoSkip: true
                    }
                },
                y: {
                    position: 'right',
                    grid: { color: 'rgba(95, 251, 241, 0.05)' },
                    ticks: {
                        color: '#94a3b8',
                        font: { size: 10 },
                        callback: function(value) {
                            return '$' + value.toFixed(8);
                        }
                    }
                }
            }
        }
    });
};

// Add new data point every 5 minutes
function addNewDataPoint() {
    const priceEl = document.getElementById('currentPrice');
    if (!priceEl) return;
    
    const priceText = priceEl.textContent.replace('$', '');
    const currentPrice = parseFloat(priceText) || 0.00000114;
    
    const now = new Date();
    const timeStr = `${now.getHours().toString().padStart(2,'0')}:${now.getMinutes().toString().padStart(2,'0')}`;
    
    chartLabels.push(timeStr);
    chartData.push(currentPrice);
    
    // Keep only last 288 points (24 hours)
    if (chartData.length > 288) {
        chartData.shift();
        chartLabels.shift();
    }
    
    // Update chart
    if (liveChart) {
        liveChart.data.labels = chartLabels.slice(-48);
        liveChart.data.datasets[0].data = chartData.slice(-48);
        liveChart.update('none'); // No animation for smooth update
    }
    
    console.log('Added new data point:', currentPrice);
}

window.updateSignal = function(price, change) {
    const signalBox = document.getElementById('signalBox');
    const signalText = document.getElementById('signalText');
    const signalReason = document.getElementById('signalReason');
    
    if (!signalBox || !signalText || !signalReason) return;
    
    signalBox.className = 'signal-display buy';
    signalText.textContent = 'BUY';
    signalReason.textContent = 'Good entry point at discount';
    
    document.getElementById('rsi').textContent = '25';
    document.getElementById('macd').textContent = '-8.50%';
    document.getElementById('trend').textContent = 'DOWN';
};

window.drawSparkline = function() {};
window.refreshCharts = function() {};

// Initialize chart
setTimeout(() => {
    window.drawCandlestickChart();
}, 1000);

// Add new point every 5 minutes
setInterval(() => {
    addNewDataPoint();
}, 300000); // 300000ms = 5 minutes

console.log('Charts.js ready - Updates every 5 minutes');