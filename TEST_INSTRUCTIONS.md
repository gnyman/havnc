# Testing Which Patch Causes iOS 9 Issue

The page loads but gets stuck at "Loading" on iPad 2. Let's isolate which patch is the problem.

## Test 1: No websock.js patch

Edit Dockerfile line 25, comment out websock.js:
```dockerfile
# Copy patched noVNC files to fix memory leaks on iOS 9
COPY novnc-patches/include/display.js /opt/novnc/include/display.js
COPY novnc-patches/include/rfb.js /opt/novnc/include/rfb.js
COPY novnc-patches/include/input.js /opt/novnc/include/input.js
# COPY novnc-patches/include/websock.js /opt/novnc/include/websock.js
```

Rebuild and test. If this works, the issue is in websock.js.

## Test 2: ONLY websock.js patch

Edit Dockerfile to ONLY patch websock.js:
```dockerfile
# Copy patched noVNC files to fix memory leaks on iOS 9
# COPY novnc-patches/include/display.js /opt/novnc/include/display.js
# COPY novnc-patches/include/rfb.js /opt/novnc/include/rfb.js
# COPY novnc-patches/include/input.js /opt/novnc/include/input.js
COPY novnc-patches/include/websock.js /opt/novnc/include/websock.js
```

Rebuild and test. If this works, the issue is in display.js, rfb.js, or input.js.

## Test 3: Check Safari Console

Before testing patches, use Safari Remote Web Inspector to check console for errors:

1. Connect iPad 2 to Mac
2. Safari → Develop → [iPad] → [noVNC page]
3. Look for red error messages in Console tab
4. Copy any JavaScript errors and share them

The error message will tell us exactly what's wrong!
