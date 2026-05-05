// Memory debugging utility for noVNC
// Add this script to index.html to track memory usage

(function() {
    'use strict';

    var MemDebug = {
        counters: {},
        startTime: Date.now(),
        logInterval: 30000, // Log every 30 seconds
        lastLog: Date.now(),

        init: function() {
            console.log('[MemDebug] Initialized at', new Date().toISOString());

            // Track object creation
            this.counters = {
                images: 0,
                imageDataObjects: 0,
                renderQueueSize: 0,
                wsBufferSize: 0,
                totalFBUCount: 0,
                zlibStreams: 0
            };

            // Log memory stats periodically
            setInterval(this.logStats.bind(this), this.logInterval);

            // Try to expose performance.memory if available
            if (window.performance && window.performance.memory) {
                console.log('[MemDebug] performance.memory API available');
            } else {
                console.log('[MemDebug] performance.memory NOT available (normal for Safari)');
            }
        },

        logStats: function() {
            var now = Date.now();
            var elapsed = Math.floor((now - this.startTime) / 1000);
            var mins = Math.floor(elapsed / 60);
            var secs = elapsed % 60;

            console.log('=== MemDebug Stats at ' + mins + 'm ' + secs + 's ===');
            console.log('Images created:', this.counters.images);
            console.log('ImageData objects:', this.counters.imageDataObjects);
            console.log('Current renderQ size:', this.counters.renderQueueSize);
            console.log('WebSocket buffer size:', this.counters.wsBufferSize);
            console.log('Total FBUs processed:', this.counters.totalFBUCount);

            if (window.performance && window.performance.memory) {
                var mem = window.performance.memory;
                console.log('JS Heap Size:', Math.round(mem.usedJSHeapSize / 1024 / 1024) + ' MB');
                console.log('JS Heap Limit:', Math.round(mem.jsHeapSizeLimit / 1024 / 1024) + ' MB');
            }

            console.log('==================================');
        },

        trackImage: function() {
            this.counters.images++;
        },

        trackImageData: function() {
            this.counters.imageDataObjects++;
        },

        updateRenderQSize: function(size) {
            this.counters.renderQueueSize = size;
        },

        updateWSBufferSize: function(size) {
            this.counters.wsBufferSize = size;
        },

        trackFBU: function() {
            this.counters.totalFBUCount++;
        }
    };

    window.MemDebug = MemDebug;
    MemDebug.init();
})();
