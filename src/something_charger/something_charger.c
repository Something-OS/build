#include <stdint.h>
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <linux/fb.h>
#include <linux/input.h>
#include <sys/mman.h>
#include <sys/ioctl.h>
#include <sys/reboot.h>
#include <math.h>
#include <time.h>
#include <stdarg.h>
#include "fonts.h"

#define FB_DEVICE "/dev/fb0"

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
int get_battery_capacity();
int is_online();
void clear_buffer(struct fb_info *fb);
void swap_buffers(struct fb_info *fb);
int check_input();

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

int get_battery_capacity() {
    char buf[16];
    int fd = open("/sys/class/power_supply/bq27411-0/capacity", O_RDONLY);
    if (fd < 0) return 0;
    if (read(fd, buf, sizeof(buf)) < 0) { /* ignore */ }
    close(fd);
    return atoi(buf);
}

int is_online() {
    char buf[16];
    int fd = open("/sys/class/power_supply/pmi8998-charger/online", O_RDONLY);
    if (fd < 0) return 0;
    if (read(fd, buf, sizeof(buf)) < 0) { /* ignore */ }
    close(fd);
    return atoi(buf) != 0;
}

void clear_buffer(struct fb_info *fb) {
    memset(fb->bbp, 0, fb->screensize);
}

void swap_buffers(struct fb_info *fb) {
    memcpy(fb->fbp, fb->bbp, fb->screensize);
}

int check_input() {
    struct input_event ev;
    int fd = open("/dev/input/event0", O_RDONLY | O_NONBLOCK);
    if (fd < 0) return 0;
    ssize_t n = read(fd, &ev, sizeof(ev));
    close(fd);
    return (n > 0);
}

int main() {
    log_kmsg("something_charger: starting offmode charger...\n");
    struct fb_info fb;
    fb.fd = open(FB_DEVICE, O_RDWR);
    if (fb.fd < 0) {
        log_kmsg("something_charger: failed to open fb device\n");
        return 1;
    }

    if (ioctl(fb.fd, FBIOGET_VSCREENINFO, &fb.vinfo) < 0 ||
        ioctl(fb.fd, FBIOGET_FSCREENINFO, &fb.finfo) < 0) {
        log_kmsg("something_charger: failed to get fb info\n");
        close(fb.fd);
        return 1;
    }

    fb.screensize = fb.vinfo.xres * fb.vinfo.yres * fb.vinfo.bits_per_pixel / 8;
    fb.fbp = (char *)mmap(0, fb.screensize, PROT_READ | PROT_WRITE, MAP_SHARED, fb.fd, 0);
    if (fb.fbp == MAP_FAILED) {
        log_kmsg("something_charger: mmap failed\n");
        close(fb.fd);
        return 1;
    }

    fb.bbp = (char *)malloc(fb.screensize);
    if (!fb.bbp) {
        log_kmsg("something_charger: malloc failed\n");
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
    int radius = fb.vinfo.xres / 3;

    while (1) {
        clear_buffer(&fb);

        uint32_t r_white = 255, g_white = 255, b_white = 255;
        uint32_t r_red = 255, g_red = 0, b_red = 0;

        // Key press triggers reboot to OS
        if (check_input()) {
            reboot(RB_AUTOBOOT);
        }
        int cap = get_battery_capacity();
        int online = is_online();

        // If charger is unplugged, show shutdown message and power off
        if (!online) {
            clear_buffer(&fb);
            int sd_dot_size = 8;
            int sd_dot_spacing = 12;
            int sd_char_spacing = 16;
            int start_x = (fb.vinfo.xres - 972) / 2;
            draw_string(&fb, "SHUTTING DOWN", start_x, center_y - 100, sd_dot_size, sd_dot_spacing, sd_char_spacing, r_white, g_white, b_white);
            swap_buffers(&fb);
            ioctl(fb.fd, FBIOPAN_DISPLAY, &fb.vinfo);
            sleep(3);
            reboot(RB_POWER_OFF);
        }

        // Ring (100 dots)
        uint32_t r_blue = 0, g_blue = 120, b_blue = 255;
        int ring_dot_size = dot_size > 8 ? 8 : dot_size; 

        for (int i = 0; i < 100; i++) {
            double angle = (i * 360.0 / 100 - 90.0) * M_PI / 180.0;
            int dx = center_x + radius * cos(angle);
            int dy = center_y + radius * sin(angle);
            
            uint32_t r = r_white, g = g_white, b = b_white; // Default white
            if (i < cap) {
                // Filled up to current level is blue
                r = r_blue; g = g_blue; b = b_blue;
            }
            
            // Blinking Tip logic
            if (online && i == cap) {
                if (frame % 2 == 0) {
                    r = r_red; g = g_red; b = b_red;
                } else {
                    r = r_white; g = g_white; b = b_white;
                }
            }
            
            draw_nothing_dot(&fb, dx, dy, ring_dot_size, r, g, b);
        }

        char pct[16];
        snprintf(pct, sizeof(pct), "%d%%", cap);
        int pct_len = strlen(pct);
        int pct_width = pct_len * (5 * dot_spacing) + (pct_len - 1) * char_spacing;
        int pct_x = center_x - (pct_width / 2);
        draw_string(&fb, pct, pct_x, center_y - 60, dot_size, dot_spacing, char_spacing, r_white, g_white, b_white);

        swap_buffers(&fb);
        ioctl(fb.fd, FBIOPAN_DISPLAY, &fb.vinfo);
        usleep(500000); // 2 FPS (500ms)
        frame++;
    }

    free(fb.bbp);
    munmap(fb.fbp, fb.screensize);
    close(fb.fd);
    return 0;
}
