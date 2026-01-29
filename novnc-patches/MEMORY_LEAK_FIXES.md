# noVNC v0.5.1 Memory Leak Fixes

This directory contains patched versions of noVNC v0.5.1 files to fix memory leaks that cause browser crashes on older devices like iOS 9 Safari.

## Issues Fixed

### 1. **WebSocket Receive Queue Growth (websock.js) - CRITICAL**
**Problem**: The most significant memory leak was in the WebSocket receive queue management:
- `concat()` creates a NEW array on every message (line 338), leaving old arrays in memory
- Queue only compacted after 10,000 bytes - way too high for constrained devices
- Inefficient byte-by-byte pushing in binary mode causing array reallocations

**Fix**:
- Reduced `_rQmax` from 10,000 to 2,000 bytes
- Pre-compact queue before adding new data if index exceeds 500 bytes
- Use `Array.prototype.push.apply()` instead of `concat()` to avoid creating new arrays
- More aggressive compaction: compact when consumed data > 30% of queue or index > 1,000
- Added instrumentation to track buffer waste percentage

### 2. Image Object Accumulation (display.js)
**Problem**: Image objects created from base64 data URIs were not properly cleaned up after rendering, causing memory to accumulate over hours of use.

**Fix**:
- Clear image src and references after drawing: `a.img.src = ''; a.img = null;`
- Clear data array references after blitting: `a.data = null;`
- Pre-bind the `_scan_renderQ` function to avoid creating new closures on every requestAnimFrame call

### 2. requestAnimationFrame Closure Leaks (display.js)
**Problem**: Each `requestAnimFrame(this._scan_renderQ.bind(this))` call created a new bound function object that captured the context, accumulating in memory.

**Fix**: Pre-bind the function once during initialization and reuse it:
```javascript
this._boundScanRenderQ = this._scan_renderQ.bind(this);
// Later...
requestAnimFrame(this._boundScanRenderQ);
```

### 3. Timer Callback Closure Leaks (rfb.js)
**Problem**: Similar to #2, repeated creation of bound functions for setTimeout callbacks.

**Fix**: Pre-bind message handler and disconnect timeout functions:
```javascript
this._boundHandleMessage = function() { ... }.bind(this);
this._boundDisconnectTimeout = function() { ... }.bind(this);
```

### 4. Double-Click Timer Leak (input.js)
**Problem**: The double-click timer was not cleared when `ungrab()` was called, keeping a reference to the Mouse object.

**Fix**: Clear the timer in the `ungrab()` method:
```javascript
if (this._doubleClickTimer !== null) {
    clearTimeout(this._doubleClickTimer);
    this._doubleClickTimer = null;
}
```

## Impact

These fixes significantly reduce memory consumption during long VNC sessions, preventing browser crashes on memory-constrained devices like iPad 2 running iOS 9.

## Files Modified

- `include/display.js` - Canvas rendering and render queue management
- `include/rfb.js` - RFB protocol handling and timers
- `include/input.js` - Mouse input handling

## Testing

Test by running a VNC session for several hours on an iPad 2 or similar device. Memory usage should remain stable instead of continuously growing.
