// KDAO 2.0 - Chart Functions
// Diese Datei muss als js/charts.js gespeichert werden

// Globale Variablen für Charts
let liveChart = null;
let sparklineChart = null;

// Candlestick Chart Drawing Function
window.drawCandlestickChart = function() {
    console.log('Drawing candlestick chart...');
    
    const canvas = document.getElementById('liveChart');
    if (!canvas) {
        console.log('Canvas element #liveChart not found');
        return;
    }
    
    const ctx = canvas.getContext('2d');
    
    // Destroy existing chart if it exists
    if (liveChart) {
        liveChart.destroy();
    }
    
    // Generate sample data for candlesticks
    const generateCandlestickData = () => {
        const data = [];
        const dataPoints = 30;
        let currentPrice = 0.00000121;
        
        for (let i = 0; i < dataPoints; i++) {
            const open = currentPrice;
            const volatility = (Math.random() - 0.5) * 0.0000001;
            const high = currentPrice + Math.abs(volatility) * 1.5;
            const low = currentPrice - Math.abs(volatility) * 1.2;
            const close = currentPrice + volatility;
            
            data.push({
                x: new Date(Date.now() - (dataPoints - i) * 3600000),
                o: open,
                h: high,
                l: low,
                c: close
            });
            
            currentPrice = close;
        }
        
        return data;
    };
    
    // Create the chart
    try {
        liveChart = new Chart(ctx, {
            type: 'candlestick',
            data: {
                datasets: [{
                    label: 'KDAO/USDT',
                    data: generateCandlestickData(),
                    borderColor: {
                        up: '#10b981',
                        down: '#ef4444',
                        unchanged: '#94a3b8'
                    },
                    backgroundColor: {
                        up: 'rgba(16, 185, 129, 0.8)',
                        down: 'rgba(239, 68, 68, 0.8)',
                        unchanged: 'rgba(148, 163, 184, 0.8)'
                    }
                }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                plugins: {
                    legend: {
                        display: false
                    },
                    tooltip: {
                        backgroundColor: 'rgba(10, 15, 27, 0.9)',
                        titleColor: '#5ffbf1',
                        bodyColor: '#ffffff',
                        borderColor: 'rgba(95, 251, 241, 0.2)',
                        borderWidth: 1,
                        callbacks: {
                            label: function(context) {
                                const point = context.raw;
                                return [
                                    `Open: $${point.o.toFixed(8)}`,
                                    `High: $${point.h.toFixed(8)}`,
                                    `Low: $${point.l.toFixed(8)}`,
                                    `Close: $${point.c.toFixed(8)}`
                                ];
                            }
                        }
                    }
                },
                scales: {
                    x: {
                        type: 'time',
                        time: {
                            unit: 'hour',
                            displayFormats: {
                                hour: 'HH:mm'
                            }
                        },
                        grid: {
                            color: 'rgba(95, 251, 241, 0.05)'
                        },
                        ticks: {
                            color: '#94a3b8',
                            font: {
                                size: 10
                            }
                        }
                    },
                    y: {
                        position: 'right',
                        grid: {
                            color: 'rgba(95, 251, 241, 0.05)'
                        },
                        ticks: {
                            color: '#94a3b8',
                            font: {
                                size: 10
                            },
                            callback: function(value) {
                                return '$' + value.toFixed(8);
                            }
                        }
                    }
                }
            }
        });
    } catch (error) {
        console.log('Falling back to line chart (candlestick plugin might be missing)');
        
        // Fallback to line chart if candlestick is not available
        const lineData = [];
        const labels = [];
        let currentPrice = 0.00000121;
        
        for (let i = 0; i < 30; i++) {
            labels.push(new Date(Date.now() - (30 - i) * 3600000).toLocaleTimeString('de-DE', { 
                hour: '2-digit', 
                minute: '2-digit' 
            }));
            
            currentPrice += (Math.random() - 0.5) * 0.0000001;
            lineData.push(currentPrice);
        }
        
        liveChart = new Chart(ctx, {
            type: 'line',
            data: {
                labels: labels,
                datasets: [{
                    label: 'KDAO/USDT',
                    data: lineData,
                    borderColor: '#5ffbf1',
                    backgroundColor: 'rgba(95, 251, 241, 0.1)',
                    borderWidth: 2,
                    fill: true,
                    tension: 0.4,
                    pointRadius: 0,
                    pointHoverRadius: 5,
                    pointBackgroundColor: '#5ffbf1',
                    pointBorderColor: '#030712',
                    pointBorderWidth: 2
                }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                interaction: {
                    mode: 'index',
                    intersect: false
                },
                plugins: {
                    legend: {
                        display: false
                    },
                    tooltip: {
                        backgroundColor: 'rgba(10, 15, 27, 0.9)',
                        titleColor: '#5ffbf1',
                        bodyColor: '#ffffff',
                        borderColor: 'rgba(95, 251, 241, 0.2)',
                        borderWidth: 1,
                        callbacks: {
                            label: function(context) {
                                return `$${context.parsed.y.toFixed(8)}`;
                            }
                        }
                    }
                },
                scales: {
                    x: {
                        grid: {
                            color: 'rgba(95, 251, 241, 0.05)',
                            drawBorder: false
                        },
                        ticks: {
                            color: '#94a3b8',
                            font: {
                                size: 10
                            },
                            maxRotation: 0,
                            autoSkip: true,
                            maxTicksLimit: 6
                        }
                    },
                    y: {
                        position: 'right',
                        grid: {
                            color: 'rgba(95, 251, 241, 0.05)',
                            drawBorder: false
                        },
                        ticks: {
                            color: '#94a3b8',
                            font: {
                                size: 10
                            },
                            callback: function(value) {
                                return '$' + value.toFixed(8);
                            }
                        }
                    }
                }
            }
        });
    }
    
    console.log('Chart created successfully');
};

// Sparkline Chart Drawing Function
window.drawSparkline = function() {
    console.log('Drawing sparkline...');
    
    const canvas = document.getElementById('sparkline');
    if (!canvas) {
        console.log('Canvas element #sparkline not found');
        return;
    }
    
    const ctx = canvas.getContext('2d');
    
    // Destroy existing chart if it exists
    if (sparklineChart) {
        sparklineChart.destroy();
    }
    
    // Generate sparkline data
    const sparklineData = [];
    let currentPrice = 0.00000121;
    
    for (let i = 0; i < 24; i++) {
        currentPrice += (Math.random() - 0.5) * 0.00000005;
        sparklineData.push(currentPrice);
    }
    
    // Create gradient
    const gradient = ctx.createLinearGradient(0, 0, canvas.width, 0);
    gradient.addColorStop(0, '#26d0a8');
    gradient.addColorStop(0.5, '#49eacb');
    gradient.addColorStop(1, '#5ffbf1');
    
    sparklineChart = new Chart(ctx, {
        type: 'line',
        data: {
            labels: Array(24).fill(''),
            datasets: [{
                data: sparklineData,
                borderColor: gradient,
                borderWidth: 2,
                fill: false,
                tension: 0.4,
                pointRadius: 0,
                pointHoverRadius: 0
            }]
        },
        options: {
            responsive: true,
            maintainAspectRatio: false,
            plugins: {
                legend: {
                    display: false
                },
                tooltip: {
                    enabled: false
                }
            },
            scales: {
                x: {
                    display: false
                },
                y: {
                    display: false
                }
            },
            elements: {
                line: {
                    borderJoinStyle: 'round'
                }
            }
        }
    });
    
    console.log('Sparkline created successfully');
};

// Update Signal Function
window.updateSignal = function(price, change) {
    console.log('Updating signal with price:', price, 'change:', change);
    
    const signalBox = document.getElementById('signalBox');
    const signalText = document.getElementById('signalText');
    const signalReason = document.getElementById('signalReason');
    
    if (!signalBox || !signalText || !signalReason) {
        console.log('Signal elements not found');
        return;
    }
    
    let signal = 'HOLD';
    let reason = 'Market is neutral';
    let signalClass = 'hold';
    
    // Simple signal logic based on 24h change
    if (change > 5) {
        signal = 'SELL';
        reason = 'Strong upward movement, consider taking profits';
        signalClass = 'sell';
    } else if (change < -5) {
        signal = 'BUY';
        reason = 'Good entry point at discount';
        signalClass = 'buy';
    } else if (change > 2) {
        signal = 'HOLD';
        reason = 'Moderate upward trend, wait for confirmation';
        signalClass = 'hold';
    } else if (change < -2) {
        signal = 'BUY';
        reason = 'Slight dip, potential accumulation zone';
        signalClass = 'buy';
    }
    
    // Update UI
    signalBox.className = `signal-display ${signalClass}`;
    signalText.textContent = signal;
    signalReason.textContent = reason;
    
    // Update RSI, MACD, Trend (simulated values)
    const rsiEl = document.getElementById('rsi');
    const macdEl = document.getElementById('macd');
    const trendEl = document.getElementById('trend');
    
    if (rsiEl) {
        const rsi = 50 + (change * 5); // Simplified RSI calculation
        rsiEl.textContent = Math.max(0, Math.min(100, Math.round(rsi)));
    }
    
    if (macdEl) {
        macdEl.textContent = (change / 2).toFixed(2) + '%';
    }
    
    if (trendEl) {
        trendEl.textContent = change > 0 ? 'UP' : change < 0 ? 'DOWN' : 'NEUTRAL';
    }
};

// Refresh all charts
window.refreshCharts = function() {
    console.log('Refreshing all charts...');
    
    // Add animation to chart containers
    const chartContainers = document.querySelectorAll('.chart-container');
    chartContainers.forEach(container => {
        container.style.opacity = '0.7';
        setTimeout(() => {
            container.style.opacity = '1';
        }, 300);
    });
    
    // Redraw charts with new data
    if (typeof window.drawCandlestickChart === 'function') {
        window.drawCandlestickChart();
    }
    
    if (typeof window.drawSparkline === 'function') {
        window.drawSparkline();
    }
};

// Initialize charts when DOM is ready
document.addEventListener('DOMContentLoaded', function() {
    console.log('DOM loaded, waiting for dashboard to initialize charts...');
    
    // Charts will be initialized by app.js after loading dashboard
    setTimeout(() => {
        if (document.getElementById('liveChart')) {
            console.log('Initializing charts from charts.js');
            window.drawCandlestickChart();
            window.drawSparkline();
        }
    }, 1000);
});

console.log('Charts.js loaded successfully');