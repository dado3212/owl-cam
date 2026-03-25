/**
 * OwlCamStream - Theos tweak for NiView
 *
 * Hooks the video render pipeline to grab decoded YUV frames,
 * converts them to JPEG, and serves a single MJPEG stream.
 * 
 * This is then read through my server and made available at
 * https://alexbeals.com/projects/owlcam
 */

#import <mach/mach_time.h>
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreGraphics/CoreGraphics.h>
#import <ImageIO/ImageIO.h>
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <pthread.h>

// --- Configuration ---
#define STREAM_PORT 8080
#define JPEG_QUALITY 0.6
#define FRAME_INTERVAL_MS 250  // ~4fps
#define ALLOWED_IP "35.167.183.221" // Amazon EC2

// --- Globals ---
static pthread_mutex_t g_frameMutex = PTHREAD_MUTEX_INITIALIZER;
static pthread_mutex_t g_clientMutex = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t g_frameCond = PTHREAD_COND_INITIALIZER;

static dispatch_queue_t g_convertQueue = nil;

static int g_serverSocket = -1;
static int g_clientSocket = -1;
static BOOL g_clientConnected = NO;

static NSData *g_latestJPEG = nil;
static BOOL g_hasReceivedFrame = NO;
static uint64_t g_lastFrameTime = 0;

// Static buffers — allocated once, reused every frame
static uint8_t *g_yCopy = NULL;
static uint8_t *g_uCopy = NULL;
static uint8_t *g_vCopy = NULL;
static uint8_t *g_sY = NULL;
static uint8_t *g_sU = NULL;
static uint8_t *g_sV = NULL;
static uint8_t *g_rgbBuf = NULL;
static int g_allocW = 0;
static int g_allocH = 0;

// The stream is live if _renderVideoFrame has been hit
// within the last 10 seconds
static BOOL isStreamLive(void) {
    if (!g_hasReceivedFrame) return NO;
    
    uint64_t now = mach_absolute_time();
    static mach_timebase_info_data_t timebase;
    if (timebase.denom == 0) mach_timebase_info(&timebase);
    uint64_t elapsedMs = ((now - g_lastFrameTime) * timebase.numer / timebase.denom) / 1000000;
    
    return elapsedMs < 10000;  // stale after 10 seconds
}

#pragma mark - YUV to JPEG

// We have YUV data as part of the rendering pipeline to the CALayer
// Convert it to a JPG so that it can be passed to clients
// Uses an externally provided rgbBuf to avoid per-frame allocation
static NSData *convertYUVToJPEG(uint8_t *yPlane, uint8_t *uPlane, uint8_t *vPlane,
                                 int width, int height, uint8_t *rgbBuf, float quality) {
    if (!yPlane || !uPlane || !vPlane || !rgbBuf || width <= 0 || height <= 0) return nil;

    int uvWidth = width / 2;

    for (int j = 0; j < height; j++) {
        for (int i = 0; i < width; i++) {
            int yIdx = j * width + i;
            int uvIdx = (j / 2) * uvWidth + (i / 2);

            int y = yPlane[yIdx];
            int u = uPlane[uvIdx] - 128;
            int v = vPlane[uvIdx] - 128;

            int r = y + (int)(1.402 * v);
            int g = y - (int)(0.344 * u) - (int)(0.714 * v);
            int b = y + (int)(1.772 * u);

            r = r < 0 ? 0 : (r > 255 ? 255 : r);
            g = g < 0 ? 0 : (g > 255 ? 255 : g);
            b = b < 0 ? 0 : (b > 255 ? 255 : b);

            int rgbIdx = (j * width + i) * 4;
            rgbBuf[rgbIdx]     = (uint8_t)r;
            rgbBuf[rgbIdx + 1] = (uint8_t)g;
            rgbBuf[rgbIdx + 2] = (uint8_t)b;
            rgbBuf[rgbIdx + 3] = 0xFF;
        }
    }

    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(rgbBuf, width, height, 8, width * 4,
                                             colorSpace, kCGImageAlphaNoneSkipLast);
    CGImageRef cgImage = CGBitmapContextCreateImage(ctx);

    NSMutableData *jpegData = [NSMutableData data];
    CGImageDestinationRef dest = CGImageDestinationCreateWithData(
        (__bridge CFMutableDataRef)jpegData, CFSTR("public.jpeg"), 1, NULL);

    if (dest && cgImage) {
        NSDictionary *props = @{(__bridge NSString *)kCGImageDestinationLossyCompressionQuality: @(quality)};
        CGImageDestinationAddImage(dest, cgImage, (__bridge CFDictionaryRef)props);
        CGImageDestinationFinalize(dest);
    }

    if (dest) CFRelease(dest);
    if (cgImage) CGImageRelease(cgImage);
    CGContextRelease(ctx);
    CGColorSpaceRelease(colorSpace);

    return jpegData.length > 0 ? jpegData : nil;
}

#pragma mark - Stream Writer

static BOOL sendAll(int sock, const void *data, size_t len) {
    size_t sent = 0;
    while (sent < len) {
        ssize_t n = send(sock, (const uint8_t *)data + sent, len - sent, MSG_NOSIGNAL);
        if (n <= 0) return NO;
        sent += n;
    }
    return YES;
}

static BOOL sendStr(int sock, NSString *str) {
    const char *cstr = [str UTF8String];
    return sendAll(sock, cstr, strlen(cstr));
}

#pragma mark - Writer Thread

static void *writerThread(void *arg) {
    NSLog(@"[OwlCam] Writer thread started");

    while (1) {
        @autoreleasepool {
            // Wait for a new frame (up to 1 second)
            struct timespec ts;
            clock_gettime(CLOCK_REALTIME, &ts);
            ts.tv_sec += 1;

            pthread_mutex_lock(&g_frameMutex);
            pthread_cond_timedwait(&g_frameCond, &g_frameMutex, &ts);
            NSData *jpeg = g_latestJPEG;
            pthread_mutex_unlock(&g_frameMutex);

            // Check client
            pthread_mutex_lock(&g_clientMutex);
            BOOL connected = g_clientConnected;
            int sock = g_clientSocket;
            pthread_mutex_unlock(&g_clientMutex);

            if (!connected) continue;

            if (!isStreamLive()) {
                NSLog(@"[OwlCam] Stream went stale, dropping client");
                pthread_mutex_lock(&g_clientMutex);
                close(g_clientSocket);
                g_clientSocket = -1;
                g_clientConnected = NO;
                pthread_mutex_unlock(&g_clientMutex);
                continue;
            }

            if (!jpeg) continue;

            NSString *partHeader = [NSString stringWithFormat:
                @"--owlframe\r\n"
                @"Content-Type: image/jpeg\r\n"
                @"Content-Length: %lu\r\n"
                @"\r\n", (unsigned long)jpeg.length];

            BOOL ok = sendStr(sock, partHeader);
            if (ok) ok = sendAll(sock, jpeg.bytes, jpeg.length);
            if (ok) ok = sendStr(sock, @"\r\n");

            if (!ok) {
                NSLog(@"[OwlCam] Client disconnected (write failed)");
                pthread_mutex_lock(&g_clientMutex);
                close(g_clientSocket);
                g_clientSocket = -1;
                g_clientConnected = NO;
                pthread_mutex_unlock(&g_clientMutex);
            }
        }
    }
    return NULL;
}
#pragma mark - HTTP Server

// Server thread to handle incoming connections
static void *serverThread(void *arg) {
    @autoreleasepool {
        g_serverSocket = socket(AF_INET, SOCK_STREAM, 0);
        if (g_serverSocket < 0) {
            NSLog(@"[OwlCam] Failed to create socket");
            return NULL;
        }

        int opt = 1;
        setsockopt(g_serverSocket, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));

        struct sockaddr_in addr = {0};
        addr.sin_family = AF_INET;
        addr.sin_addr.s_addr = INADDR_ANY;
        addr.sin_port = htons(STREAM_PORT);

        if (bind(g_serverSocket, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
            NSLog(@"[OwlCam] Failed to bind port %d", STREAM_PORT);
            close(g_serverSocket);
            return NULL;
        }

        listen(g_serverSocket, 2);
        NSLog(@"[OwlCam] Server listening on port %d", STREAM_PORT);

        while (1) {
            @autoreleasepool {
                struct sockaddr_in clientAddr;
                socklen_t clientLen = sizeof(clientAddr);
                int newSock = accept(g_serverSocket, (struct sockaddr *)&clientAddr, &clientLen);
                if (newSock < 0) continue;

                // Only allow EC2 IP
                struct sockaddr_in allowed;
                inet_pton(AF_INET, ALLOWED_IP, &allowed.sin_addr);
                uint32_t clientIP = ntohl(clientAddr.sin_addr.s_addr);
                BOOL isAllowedIP = (clientAddr.sin_addr.s_addr == allowed.sin_addr.s_addr);
                BOOL isLocal = (clientIP >> 24 == 192 && (clientIP >> 16 & 0xFF) == 168);  // 192.168.x.x
                if (!isAllowedIP && !isLocal) {
                    close(newSock);
                    continue;
                }

                // Read HTTP request
                char buf[512];
                ssize_t n = recv(newSock, buf, sizeof(buf) - 1, 0);
                if (n <= 0) { close(newSock); continue; }
                buf[n] = '\0';

                // Only accept /stream
                if (strstr(buf, "GET /stream") == NULL && strstr(buf, "GET / ") == NULL) {
                    const char *resp = "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\n\r\n";
                    send(newSock, resp, strlen(resp), 0);
                    close(newSock);
                    continue;
                }

                // Only let you connect if the stream is live
                if (!isStreamLive()) {
                    const char *resp = "HTTP/1.1 503 No Stream\r\nContent-Length: 0\r\n\r\n";
                    send(newSock, resp, strlen(resp), 0);
                    close(newSock);
                    continue;
                }

                // Drop existing client — only one allowed
                pthread_mutex_lock(&g_clientMutex);
                if (g_clientConnected) {
                    NSLog(@"[OwlCam] Dropping old client for new connection");
                    close(g_clientSocket);
                }
                g_clientSocket = newSock;
                g_clientConnected = YES;
                pthread_mutex_unlock(&g_clientMutex);

                NSLog(@"[OwlCam] Client connected");

                // Send MJPEG header
                sendStr(newSock,
                    @"HTTP/1.1 200 OK\r\n"
                    @"Content-Type: multipart/x-mixed-replace; boundary=--owlframe\r\n"
                    @"Cache-Control: no-cache\r\n"
                    @"Connection: keep-alive\r\n"
                    @"\r\n");
            }
        }
    }
    return NULL;
}

#pragma mark - Frame Hook

// Frame struct offsets from Hopper decompiling
#define FRAME_Y_OFFSET   0x08
#define FRAME_U_OFFSET   0x10
#define FRAME_V_OFFSET   0x18
#define FRAME_W_OFFSET   0x2c
#define FRAME_H_OFFSET   0x30

%hook IVVideoRender

// Hook into the original function
- (void)_renderVideoFrame:(void *)frame {
    %orig;

    // if there's no frame then we can return
    if (!frame) return;

    // Rate limit to only process if it's been long enough
    uint64_t now = mach_absolute_time();
    static mach_timebase_info_data_t timebase;
    if (timebase.denom == 0) mach_timebase_info(&timebase);
    uint64_t elapsedMs = ((now - g_lastFrameTime) * timebase.numer / timebase.denom) / 1000000;
    if (elapsedMs < FRAME_INTERVAL_MS) return;
    g_lastFrameTime = now;
    g_hasReceivedFrame = YES;

    // Don't do any work if there's no client connected to consume the data
    pthread_mutex_lock(&g_clientMutex);
    BOOL connected = g_clientConnected;
    pthread_mutex_unlock(&g_clientMutex);
    if (!connected) return;

    // Read frame
    uint8_t *yPlane = *(uint8_t **)((uint8_t *)frame + FRAME_Y_OFFSET);
    uint8_t *uPlane = *(uint8_t **)((uint8_t *)frame + FRAME_U_OFFSET);
    uint8_t *vPlane = *(uint8_t **)((uint8_t *)frame + FRAME_V_OFFSET);
    int width  = *(int *)((uint8_t *)frame + FRAME_W_OFFSET);
    int height = *(int *)((uint8_t *)frame + FRAME_H_OFFSET);

    // Sanity check to ensure the data is what we expect and that we didn't
    // misread
    if (width <= 0 || width > 8192 || height <= 0 || height > 8192) return;
    if (!yPlane || !uPlane || !vPlane) return;

    // Allocate static buffers on first use or size change
    if (g_allocW != width || g_allocH != height) {
        free(g_yCopy); free(g_uCopy); free(g_vCopy);
        free(g_sY); free(g_sU); free(g_sV);
        free(g_rgbBuf);

        int ySize = width * height;
        int uvSize = (width / 2) * (height / 2);
        int outW = width / 2;
        int outH = height / 2;

        g_yCopy = (uint8_t *)malloc(ySize);
        g_uCopy = (uint8_t *)malloc(uvSize);
        g_vCopy = (uint8_t *)malloc(uvSize);
        g_sY = (uint8_t *)malloc(outW * outH);
        g_sU = (uint8_t *)malloc((outW / 2) * (outH / 2));
        g_sV = (uint8_t *)malloc((outW / 2) * (outH / 2));
        g_rgbBuf = (uint8_t *)malloc(outW * outH * 4);
        g_allocW = width;
        g_allocH = height;

        if (!g_yCopy || !g_uCopy || !g_vCopy || !g_sY || !g_sU || !g_sV || !g_rgbBuf) {
            NSLog(@"[OwlCam] Failed to allocate buffers");
            return;
        }
        NSLog(@"[OwlCam] Allocated buffers for %dx%d", width, height);
    }

    // Copy plane data (buffer may be reused by renderer)
    int ySize = width * height;
    int uvSize = (width / 2) * (height / 2);
    memcpy(g_yCopy, yPlane, ySize);
    memcpy(g_uCopy, uPlane, uvSize);
    memcpy(g_vCopy, vPlane, uvSize);

    int capturedWidth = width;
    int capturedHeight = height;

    // Convert asynchronously on serial queue (only one at a time)
    dispatch_async(g_convertQueue, ^{
        int outW = capturedWidth / 2;
        int outH = capturedHeight / 2;

        for (int j = 0; j < outH; j++)
            for (int i = 0; i < outW; i++)
                g_sY[j * outW + i] = g_yCopy[(j * 2) * capturedWidth + (i * 2)];

        int uvW = capturedWidth / 2;
        int outUVW = outW / 2;
        for (int j = 0; j < outH / 2; j++)
            for (int i = 0; i < outUVW; i++) {
                g_sU[j * outUVW + i] = g_uCopy[(j * 2) * uvW + (i * 2)];
                g_sV[j * outUVW + i] = g_vCopy[(j * 2) * uvW + (i * 2)];
            }

        @autoreleasepool {
            NSData *jpeg = convertYUVToJPEG(g_sY, g_sU, g_sV, outW, outH, g_rgbBuf, JPEG_QUALITY);

            if (jpeg) {
                pthread_mutex_lock(&g_frameMutex);
                g_latestJPEG = jpeg;
                pthread_cond_signal(&g_frameCond);
                pthread_mutex_unlock(&g_frameMutex);
            }
        }
    });
}

%end

// When the Tweak is initialized (app is opened) set up the two threads,
// one to handle incoming connections (and make sure they're hitting
// the right URL and are from the right IP address)
%ctor {
    NSLog(@"[OwlCam] Loaded - server starting on port %d", STREAM_PORT);

    g_convertQueue = dispatch_queue_create("com.hackingdartmouth.owlcam-convert", DISPATCH_QUEUE_SERIAL);

    pthread_t serverTid;
    pthread_create(&serverTid, NULL, serverThread, NULL);
    pthread_detach(serverTid);

    pthread_t writerTid;
    pthread_create(&writerTid, NULL, writerThread, NULL);
    pthread_detach(writerTid);
}
