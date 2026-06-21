#include <stdint.h>
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <linux/fb.h>
#include <sys/mman.h>
#include <sys/ioctl.h>
#include <math.h>
#include <time.h>
#include <stdarg.h>
#include "fonts.h"

#define FB_DEVICE "/dev/fb0"
#define STOP_SIGNAL "/stop_anim"

struct fb_info {
    int fd;
    char *fbp;
    char *bbp; // Backbuffer
    struct fb_var_screeninfo vinfo;
    struct fb_fix_screeninfo finfo;
    long screensize;
};

// Prototypes
void log_kmsg(const char *fmt, ...);
void put_pixel(struct fb_info *fb, int x, int y, uint32_t r, uint32_t g, uint32_t b);
void draw_nothing_dot(struct fb_info *fb, int x, int y, int size, uint32_t r, uint32_t g, uint32_t b);
void draw_char(struct fb_info *fb, char c, int x, int y, int dot_size, int spacing, uint32_t r, uint32_t g, uint32_t b);
void draw_string(struct fb_info *fb, const char *s, int x, int y, int dot_size, int spacing, int char_spacing, uint32_t r, uint32_t g, uint32_t b);
void clear_buffer(struct fb_info *fb);
void swap_buffers(struct fb_info *fb);

void log_kmsg(const char *fmt, ...) {
    va_list args;
    va_start(args, fmt);
    int fd = open("/dev/kmsg", O_WRONLY);
    if (fd >= 0) {
        char buf[256];
        vsnprintf(buf, sizeof(buf), fmt, args);
        if (write(fd, buf, strlen(buf)) < 0) { /* ignore */ }
        close(fd);
    }
    va_end(args);
}

void put_pixel(struct fb_info *fb, int x, int y, uint32_t r, uint32_t g, uint32_t b) {
    if (x < 0 || x >= (int)fb->vinfo.xres || y < 0 || y >= (int)fb->vinfo.yres) return;
    
    long location = (x + fb->vinfo.xoffset) * (fb->vinfo.bits_per_pixel / 8) +
                   (y + fb->vinfo.yoffset) * fb->finfo.line_length;
    
    if (fb->vinfo.bits_per_pixel == 32) {
        uint32_t alpha = (0xFF << fb->vinfo.transp.offset);
        uint32_t color = alpha |
                         ((r & 0xFF) << fb->vinfo.red.offset) |
                         ((g & 0xFF) << fb->vinfo.green.offset) |
                         ((b & 0xFF) << fb->vinfo.blue.offset);
        *(uint32_t *)(fb->bbp + location) = color;
    } else if (fb->vinfo.bits_per_pixel == 16) {
        uint16_t color = ((r >> (8 - fb->vinfo.red.length)) << fb->vinfo.red.offset) |
                         ((g >> (8 - fb->vinfo.green.length)) << fb->vinfo.green.offset) |
                         ((b >> (8 - fb->vinfo.blue.length)) << fb->vinfo.blue.offset);
        *(uint16_t *)(fb->bbp + location) = color;
    }
}

void draw_nothing_dot(struct fb_info *fb, int x, int y, int size, uint32_t r, uint32_t g, uint32_t b) {
    int r2 = (size / 2) * (size / 2);
    for (int i = -size/2; i < size/2; i++) {
        for (int j = -size/2; j < size/2; j++) {
            if (i*i + j*j <= r2) {
                put_pixel(fb, x + i, y + j, r, g, b);
            }
        }
    }
}

void draw_char(struct fb_info *fb, char c, int x, int y, int dot_size, int spacing, uint32_t r, uint32_t g, uint32_t b) {
    if (c < 0 || c >= 128) return;
    CharMask mask = font_chars[(int)c];
    for (int row = 0; row < 7; row++) {
        for (int col = 0; col < 5; col++) {
            if (mask.data[row] & (1 << (4 - col))) {
                draw_nothing_dot(fb, x + col * spacing, y + row * spacing, dot_size, r, g, b);
            }
        }
    }
}

void draw_string(struct fb_info *fb, const char *s, int x, int y, int dot_size, int spacing, int char_spacing, uint32_t r, uint32_t g, uint32_t b) {
    int cur_x = x;
    while (*s) {
        draw_char(fb, *s, cur_x, y, dot_size, spacing, r, g, b);
        cur_x += 5 * spacing + char_spacing;
        s++;
    }
}

void clear_buffer(struct fb_info *fb) {
    memset(fb->bbp, 0, fb->screensize);
}

void swap_buffers(struct fb_info *fb) {
    memcpy(fb->fbp, fb->bbp, fb->screensize);
}

int main() {
    log_kmsg("something_bootanim: starting boot animation...\n");
    struct fb_info fb;
    fb.fd = open(FB_DEVICE, O_RDWR);
    if (fb.fd < 0) {
        log_kmsg("something_bootanim: failed to open fb device\n");
        return 1;
    }

    if (ioctl(fb.fd, FBIOGET_VSCREENINFO, &fb.vinfo) < 0 ||
        ioctl(fb.fd, FBIOGET_FSCREENINFO, &fb.finfo) < 0) {
        log_kmsg("something_bootanim: failed to get fb info\n");
        close(fb.fd);
        return 1;
    }

    fb.screensize = fb.vinfo.xres * fb.vinfo.yres * fb.vinfo.bits_per_pixel / 8;
    fb.fbp = (char *)mmap(0, fb.screensize, PROT_READ | PROT_WRITE, MAP_SHARED, fb.fd, 0);
    if (fb.fbp == MAP_FAILED) {
        log_kmsg("something_bootanim: mmap failed\n");
        close(fb.fd);
        return 1;
    }

    fb.bbp = (char *)malloc(fb.screensize);
    if (!fb.bbp) {
        log_kmsg("something_bootanim: malloc failed\n");
        munmap(fb.fbp, fb.screensize);
        close(fb.fd);
        return 1;
    }

    int frame = 0;
    
    // Aesthetic constants (Something OS Style)
    const int dot_size = 12; 
    const int dot_spacing = 18;
    const int char_spacing = 28;

    int center_x = fb.vinfo.xres / 2;
    int center_y = fb.vinfo.yres / 2;

    while (1) {
        if (access(STOP_SIGNAL, F_OK) == 0) {
            log_kmsg("something_bootanim: stop signal received, exiting\n");
            break;
        }
        
        clear_buffer(&fb);

        uint32_t r_white = 255, g_white = 255, b_white = 255;
        double breathe = (sin(frame * 0.08) + 1.0) / 2.0;
        uint32_t dim_val = 25 + (int)(35 * breathe);
        uint32_t r_dim = dim_val, g_dim = dim_val, b_dim = dim_val;

        // Center "NOTHING"
        int nothing_width = 7 * (5 * dot_spacing) + 6 * char_spacing;
        int logo_x = center_x - (nothing_width / 2);

        draw_string(&fb, "NOTHING", logo_x, center_y - 100, dot_size, dot_spacing, char_spacing, r_white, g_white, b_white);

        // Dot progress bar
        int bar_y = center_y + 400;
        int start_x = center_x - 350; // 700 / 2
        
        for (int i = 0; i < 40; i++) {
            int dx = start_x + i * 18;
            uint32_t r = r_dim, g = g_dim, b = b_dim;
            int pulse_pos = (frame % 60);
            if (i == pulse_pos || i == (pulse_pos - 1) || i == (pulse_pos - 2)) {
                 r = r_white; g = g_white; b = b_white;
            }
            draw_nothing_dot(&fb, dx, bar_y, dot_size, r, g, b);
        }
        
        swap_buffers(&fb);
        ioctl(fb.fd, FBIOPAN_DISPLAY, &fb.vinfo);
        usleep(16666); // 60 FPS (approx 16.6ms)
        frame++;
    }

    free(fb.bbp);
    munmap(fb.fbp, fb.screensize);
    close(fb.fd);
    return 0;
}
