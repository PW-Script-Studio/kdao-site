// KDAO Floating Text Animation
function createKDAOFloatingTexts() {
    const container = document.getElementById('particles');
    if (!container) return;

    const texts = [
        '<span class="kdao-k">K</span>DAO',
        '2.0',
        'DeFi',
        '<span class="kdao-k">K</span>aspa',
        'DAO',
        'Staking'
    ];

    // Create 25 floating texts
    for (let i = 0; i < 25; i++) {
        const textEl = document.createElement('div');
        textEl.className = 'kdao-text';

        // Random size
        const sizes = ['small', 'medium', 'large'];
        textEl.classList.add(sizes[Math.floor(Math.random() * sizes.length)]);

        // Random text
        textEl.innerHTML = texts[Math.floor(Math.random() * texts.length)];

        // Position and animation
        textEl.style.left = Math.random() * 100 + '%';
        textEl.style.animationDelay = Math.random() * 30 + 's';

        container.appendChild(textEl);
    }
}

// Start animations on load
document.addEventListener('DOMContentLoaded', () => {
    createKDAOFloatingTexts();
});

// Update trading signal
function updateSignal(price, change) {
    const signalBox = document.getElementById('signalBox');
    const signalText = document.getElementById('signalText');
    const signalReason = document.getElementById('signalReason');

    if (!signalBox || !signalText || !signalReason) return;

    let signal = 'HOLD';
    let reason = 'Market is neutral';
    let signalClass = 'hold';

    if (change > 5) {
        signal = 'SELL';
        reason = 'Strong upward movement, consider taking profits';
        signalClass = 'sell';
    } else if (change < -5) {
        signal = 'BUY';
        reason = 'Good entry point at discount';
        signalClass = 'buy';
    }

    signalBox.className = `signal-display ${signalClass}`;
    signalText.textContent = signal;
    signalReason.textContent = reason;
}



