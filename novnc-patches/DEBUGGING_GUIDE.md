# Memory Leak Debugging Guide for iPad 2 + Safari Remote Web Inspector

This guide explains how to use Safari's Remote Web Inspector to identify memory leaks in noVNC on iPad 2.

## Setup

### On iPad 2:
1. Settings → Safari → Advanced
2. Enable "Web Inspector"

### On Mac:
1. Safari → Preferences → Advanced
2. Check "Show Develop menu in menu bar"
3. Connect iPad via USB cable
4. Open Safari Develop menu → Select your iPad → Choose the noVNC page

## Using the Debug Build

The repository includes `index-debug.html` which has memory tracking instrumentation built-in.

### To use it:
1. Copy `index-debug.html` to `/opt/novnc/` in the Docker container
2. Access it via your browser
3. Open Safari Remote Web Inspector Console tab

### Memory Statistics

The debug build logs memory statistics every 30 seconds:
```
=== MemDebug Stats at 5m 30s ===
Images created: 1234
ImageData objects: 5678
Current renderQ size: 2
WebSocket buffer size: 1850
WebSocket buffer index: 420
WebSocket waste: 420 / 1850 = 23%
Total FBUs processed: 2341
==================================
```

**Key metrics to watch:**
- **Images created**: Should grow slowly; rapid growth indicates image leak
- **WebSocket buffer waste %**: Should stay under 30%; higher means inefficient compaction
- **WebSocket buffer size**: Should not continuously grow; spikes are normal but should drop
- **Current renderQ size**: Should typically be 0-5; sustained high values indicate rendering bottleneck

## Safari Web Inspector Tools

### 1. Timelines Tab - Memory Timeline
**Best for: Identifying overall memory growth**

1. Open Web Inspector → Timelines tab
2. Select "Memory" timeline
3. Click Record button (red circle)
4. Use VNC normally for 5-10 minutes
5. Look for:
   - **Continuously rising line**: Memory leak
   - **Sawtooth pattern**: Normal (GC is working)
   - **Sudden jumps without drops**: Retained objects

### 2. Storage Tab - Memory Snapshot
**Best for: Finding what objects are accumulating**

1. Open Web Inspector → Storage tab
2. Click "Take Snapshot" button
3. Wait 2-3 minutes of VNC use
4. Take another snapshot
5. Select second snapshot → Switch to "Comparison" view
6. Sort by "Count Delta" or "Retained Size Delta"
7. Look for:
   - **Array**: Check if WebSocket buffers are growing
   - **Image / HTMLImageElement**: Check if images aren't being freed
   - **ImageData**: Check if canvas data is accumulating
   - **Uint8Array**: Could be WebSocket binary data

### 3. Console Tab - Manual Memory Checks
**Best for: Quick checks during testing**

In the console, you can manually check specific objects if you expose them globally:

```javascript
// Add to window.onscriptsload in index.html:
window.rfbDebug = rfb;

// Then in console:
rfbDebug._display._renderQ.length  // Check render queue size
rfbDebug._sock._rQ.length          // Check WebSocket receive queue
rfbDebug._sock._rQi                // Check how much has been consumed
```

## Common Memory Leak Patterns

### Pattern 1: WebSocket Buffer Growth
**Symptoms:**
- WebSocket buffer size continuously increases
- Waste percentage stays high (>40%)
- Console shows: `WebSocket buffer size: 8450` (growing)

**Cause:** Queue not compacting properly

**Fix Applied:** Reduced _rQmax, more aggressive compaction

### Pattern 2: Image Accumulation
**Symptoms:**
- "Images created" counter rapidly increases
- Memory snapshot shows many HTMLImageElement objects
- Heap size grows 5-10 MB per minute

**Cause:** Image data URIs not being freed

**Fix Applied:** Clear img.src and references after rendering

### Pattern 3: Canvas Data Retention
**Symptoms:**
- Memory snapshot shows many ImageData objects
- Heap grows steadily during screen updates
- More pronounced with TIGHT/JPEG encoding

**Cause:** createImageData() results not being freed

**Fix Applied:** Clear data references after blitting

### Pattern 4: Closure Accumulation
**Symptoms:**
- Memory grows slowly but steadily (1-2 MB per hour)
- Heap snapshot shows many function objects
- requestAnimationFrame or setTimeout related

**Cause:** Creating new bound functions repeatedly

**Fix Applied:** Pre-bind functions once during initialization

## Testing Procedure

1. **Baseline** (2 minutes):
   - Start noVNC, take memory snapshot
   - Note starting heap size

2. **Activity** (10 minutes):
   - Actively use VNC (move windows, scroll, etc.)
   - Take snapshots every 2 minutes
   - Watch Console for memory stats

3. **Idle** (5 minutes):
   - Leave VNC connected but idle
   - Watch if memory drops (GC working)
   - Take final snapshot

4. **Analysis**:
   - Compare first and last snapshots
   - Heap growth should be <20 MB for 15-minute session
   - After idle period, memory should drop 30-50%
   - If memory doesn't drop during idle = leak

## Expected Results After Fixes

**Before fixes:**
- Memory grows 10-20 MB per hour continuously
- No memory recovery during idle periods
- Browser crash after 3-6 hours

**After fixes:**
- Memory grows 2-5 MB per hour
- Memory partially recovers during idle (GC collects old objects)
- Stable operation for 12+ hours

## Reporting Issues

When reporting memory issues, include:
1. MemDebug console output (30-60 seconds worth)
2. Screenshot of Memory Timeline showing the problem
3. Memory snapshot comparison showing largest growing objects
4. Time to crash (if applicable)
5. Type of VNC activity (idle, active windows, video playback, etc.)
