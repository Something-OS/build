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
#define MAX_INPUT_DEVS 8

#ifndef BOARD_UFS_PARTITION
#define BOARD_UFS_PARTITION "/dev/sda17"
#endif

#ifndef BOARD_LOOP_OFFSET
#define BOARD_LOOP_OFFSET "1048576"
#endif

struct fb_info {
    int fd;
    char *fbp;
    char *bbp; // Backbuffer
    struct fb_var_screeninfo vinfo;
    struct fb_fix_screeninfo finfo;
    long screensize;
};

int input_fds[MAX_INPUT_DEVS];
int num_input_fds = 0;

void log_kmsg(const char *fmt, ...);
void put_pixel(struct fb_info *fb, int x, int y, uint32_t r, uint32_t g, uint32_t b);
void draw_nothing_dot(struct fb_info *fb, int x, int y, int size, uint32_t r, uint32_t g, uint32_t b);
void draw_char(struct fb_info *fb, char c, int x, int y, int dot_size, int spacing, uint32_t r, uint32_t g, uint32_t b);
void draw_string(struct fb_info *fb, const char *s, int x, int y, int dot_size, int spacing, int char_spacing, uint32_t r, uint32_t g, uint32_t b);
void clear_buffer(struct fb_info *fb);
void swap_buffers(struct fb_info *fb);

void run_cmd(const char *cmd) {
    if (system(cmd) < 0) { /* Ignore */ }
}

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
    
    if (location < 0 || location >= fb->screensize) return;
    
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

void init_inputs() {
    char path[32];
    for (int i = 0; i < MAX_INPUT_DEVS; i++) {
        snprintf(path, sizeof(path), "/dev/input/event%d", i);
        int fd = open(path, O_RDONLY | O_NONBLOCK);
        if (fd >= 0) {
            input_fds[num_input_fds++] = fd;
        }
    }
}

int read_key() {
    struct input_event ev;
    for (int i = 0; i < num_input_fds; i++) {
        ssize_t n = read(input_fds[i], &ev, sizeof(ev));
        if (n == sizeof(ev)) {
            if (ev.type == EV_KEY && ev.value == 1) { // Key press
                return ev.code;
            }
        }
    }
    return -1;
}

void run_command_show_output(struct fb_info *fb, const char *cmd) {
    FILE *fp = popen(cmd, "r");
    if (!fp) {
        clear_buffer(fb);
        draw_string(fb, "FAILED TO EXECUTE COMMAND", 100, 500, 6, 8, 12, 255, 0, 0);
        swap_buffers(fb);
        sleep(2);
        return;
    }

    char line[128];
    char lines[15][128];
    int num_lines = 0;

    while (fgets(line, sizeof(line), fp)) {
        line[strcspn(line, "\n")] = 0;
        
        char *display_line = line;
        if (strncmp(line, "ui_print ", 9) == 0) {
            display_line = line + 9;
        } else if (strcmp(line, "ui_print") == 0) {
            display_line = "";
        }

        // Convert to uppercase for display compatibility
        char upper[128];
        int j = 0;
        for (; display_line[j] && j < 127; j++) {
            char c = display_line[j];
            if (c >= 'a' && c <= 'z') {
                upper[j] = c - 'a' + 'A';
            } else if (c == '\t') {
                upper[j] = ' ';
            } else {
                upper[j] = c;
            }
        }
        upper[j] = '\0';

        if (num_lines < 15) {
            strncpy(lines[num_lines], upper, sizeof(lines[num_lines]));
            num_lines++;
        } else {
            for (int i = 0; i < 14; i++) {
                strcpy(lines[i], lines[i+1]);
            }
            strncpy(lines[14], upper, sizeof(lines[14]));
        }

        clear_buffer(fb);
        draw_string(fb, "EXECUTING...", 100, 200, 6, 8, 12, 255, 255, 255);
        for (int i = 0; i < num_lines; i++) {
            draw_string(fb, lines[i], 100, 350 + i * 80, 4, 5, 7, 200, 200, 200);
        }
        swap_buffers(fb);
        ioctl(fb->fd, FBIOPAN_DISPLAY, &fb->vinfo);
    }
    pclose(fp);
}

void show_message_wait_key(struct fb_info *fb, const char *msg1, const char *msg2, uint32_t r, uint32_t g, uint32_t b) {
    clear_buffer(fb);
    draw_string(fb, msg1, 100, 500, 6, 8, 12, r, g, b);
    if (msg2) {
        draw_string(fb, msg2, 100, 600, 4, 6, 8, 255, 255, 255);
    }
    draw_string(fb, "PRESS ANY KEY TO RETURN", 100, 1000, 4, 5, 7, 150, 150, 150);
    swap_buffers(fb);
    ioctl(fb->fd, FBIOPAN_DISPLAY, &fb->vinfo);

    // Drain input
    while (read_key() != -1);
    
    // Wait for key
    while (1) {
        if (read_key() != -1) break;
        usleep(50000);
    }
}

void flash_zip_menu(struct fb_info *fb) {
    // 1. Mount userdata
    clear_buffer(fb);
    draw_string(fb, "MOUNTING STORAGE...", 100, 500, 6, 8, 12, 255, 255, 255);
    swap_buffers(fb);
    ioctl(fb->fd, FBIOPAN_DISPLAY, &fb->vinfo);

    run_cmd("/bin/busybox losetup -d /dev/loop2 2>/dev/null || true");
    int res = system("/bin/busybox losetup -o " BOARD_LOOP_OFFSET " /dev/loop2 " BOARD_UFS_PARTITION " && /bin/busybox mkdir -p /mnt_tmp && /bin/busybox mount -t ext4 /dev/loop2 /mnt_tmp");
    if (res != 0) {
        show_message_wait_key(fb, "MOUNT FAILED!", "IS USERDATA FORMATTED?", 255, 0, 0);
        return;
    }

    // 2. Scan for zip files
    FILE *fp = popen("find /mnt_tmp/ -name \"*.zip\" -maxdepth 4 2>/dev/null", "r");
    if (!fp) {
        run_cmd("umount /mnt_tmp 2>/dev/null || true");
        show_message_wait_key(fb, "SCAN FAILED!", NULL, 255, 0, 0);
        return;
    }

    char zips[10][256];
    int zip_count = 0;
    char path[256];
    while (fgets(path, sizeof(path), fp) && zip_count < 10) {
        path[strcspn(path, "\n")] = 0;
        strncpy(zips[zip_count], path, sizeof(zips[zip_count]));
        zip_count++;
    }
    pclose(fp);

    if (zip_count == 0) {
        run_cmd("umount /mnt_tmp 2>/dev/null || true");
        show_message_wait_key(fb, "NO ZIP FILES FOUND", "PLACE RECOVERY ZIP IN INTERNAL STORAGE", 255, 255, 0);
        return;
    }

    int selected_zip = 0;
    while (1) {
        clear_buffer(fb);
        draw_string(fb, "SELECT ZIP TO FLASH", 100, 200, 6, 8, 12, 255, 255, 255);
        
        for (int i = 0; i < zip_count; i++) {
            // Extract filename only for display
            char *filename = strrchr(zips[i], '/');
            if (filename) filename++;
            else filename = zips[i];

            char display_name[128];
            // Convert to uppercase for display compatibility
            int j = 0;
            for (; filename[j] && j < 30; j++) {
                char c = filename[j];
                if (c >= 'a' && c <= 'z') display_name[j] = c - 'a' + 'A';
                else display_name[j] = c;
            }
            display_name[j] = '\0';

            char item_text[160];
            if (i == selected_zip) {
                snprintf(item_text, sizeof(item_text), "> %s", display_name);
                draw_string(fb, item_text, 100, 380 + i * 100, 4, 6, 8, 255, 30, 30);
            } else {
                snprintf(item_text, sizeof(item_text), "  %s", display_name);
                draw_string(fb, item_text, 100, 380 + i * 100, 4, 6, 8, 255, 255, 255);
            }
        }
        draw_string(fb, "BACK (VOL KEYS TO MOVE, POWER TO CHOOSE)", 100, 380 + zip_count * 100 + 50, 3, 4, 6, 150, 150, 150);
        swap_buffers(fb);
        ioctl(fb->fd, FBIOPAN_DISPLAY, &fb->vinfo);

        int key = -1;
        while (key == -1) {
            key = read_key();
            usleep(20000);
        }

        if (key == KEY_VOLUMEDOWN || key == 108) {
            selected_zip = (selected_zip + 1) % (zip_count + 1);
        } else if (key == KEY_VOLUMEUP || key == 103) {
            selected_zip = (selected_zip - 1 + zip_count + 1) % (zip_count + 1);
        } else if (key == KEY_POWER || key == KEY_ENTER || key == 28) {
            if (selected_zip == zip_count) {
                // Back option
                run_cmd("umount /mnt_tmp 2>/dev/null || true");
                return;
            } else {
                // Flash the selected zip!
                // First unmount userdata so update-binary can access it or mount/write directly
                run_cmd("umount /mnt_tmp 2>/dev/null || true");

                char cmd[512];
                // Extract update-binary and run it
                snprintf(cmd, sizeof(cmd), 
                    "/bin/busybox unzip -p %s META-INF/com/google/android/update-binary > /tmp/update-binary && "
                    "chmod +x /tmp/update-binary && "
                    "/tmp/update-binary 3 1 %s", zips[selected_zip], zips[selected_zip]);

                run_command_show_output(fb, cmd);
                show_message_wait_key(fb, "FLASH COMPLETE", "REBOOT YOUR DEVICE NOW", 0, 255, 0);
                return;
            }
        }
    }
}

int main() {
    log_kmsg("something_recovery: starting recovery mode...\n");

    int input_retry = 0;
    while (num_input_fds == 0 && input_retry < 10) {
        init_inputs();
        if (num_input_fds > 0) break;
        log_kmsg("something_recovery: waiting for input devices (retry %d)...\n", input_retry);
        usleep(500000); // 500ms
        input_retry++;
    }
    log_kmsg("something_recovery: initialized input with %d devices\n", num_input_fds);

    struct fb_info fb;
    int fb_ok = 0;
    for (int retry = 0; retry < 20; retry++) {
        fb.fd = open(FB_DEVICE, O_RDWR);
        if (fb.fd >= 0) {
            if (ioctl(fb.fd, FBIOGET_VSCREENINFO, &fb.vinfo) >= 0 &&
                ioctl(fb.fd, FBIOGET_FSCREENINFO, &fb.finfo) >= 0) {
                if (fb.vinfo.xres > 0 && fb.vinfo.yres > 0) {
                    fb_ok = 1;
                    break;
                }
            }
            close(fb.fd);
        }
        log_kmsg("something_recovery: waiting for fb to initialize (retry %d)...\n", retry);
        usleep(500000); // 500ms
    }

    if (!fb_ok) {
        log_kmsg("something_recovery: failed to initialize fb device after timeout\n");
        return 1;
    }
    log_kmsg("something_recovery: opened fb device successfully: xres=%d, yres=%d, bits_per_pixel=%d\n", 
             fb.vinfo.xres, fb.vinfo.yres, fb.vinfo.bits_per_pixel);
    log_kmsg("something_recovery: finfo: line_length=%d, smem_len=%d\n", 
             fb.finfo.line_length, fb.finfo.smem_len);

    fb.screensize = fb.finfo.line_length * fb.vinfo.yres;
    log_kmsg("something_recovery: screensize calculated as %ld bytes\n", fb.screensize);

    fb.fbp = (char *)mmap(0, fb.screensize, PROT_READ | PROT_WRITE, MAP_SHARED, fb.fd, 0);
    if (fb.fbp == MAP_FAILED) {
        log_kmsg("something_recovery: mmap failed\n");
        close(fb.fd);
        return 1;
    }
    log_kmsg("something_recovery: mmap successful\n");

    fb.bbp = (char *)malloc(fb.screensize);
    if (!fb.bbp) {
        log_kmsg("something_recovery: malloc for backbuffer failed\n");
        munmap(fb.fbp, fb.screensize);
        close(fb.fd);
        return 1;
    }
    log_kmsg("something_recovery: backbuffer malloc successful\n");

    const char *menu_items[] = {
        "REPAIR FILESYSTEM",
        "WIPE USERDATA",
        "FLASH ZIP FROM INTERNAL STORAGE",
        "REBOOT TO SYSTEM",
        "REBOOT TO BOOTLOADER",
        "SHUTDOWN"
    };
    int num_items = 6;
    int selected = 0;

    while (1) {
        clear_buffer(&fb);

        // Header
        draw_string(&fb, "=========================", 100, 150, 4, 6, 8, 255, 255, 255);
        draw_string(&fb, "  SOMETHING OS RECOVERY  ", 100, 220, 5, 7, 9, 255, 255, 255);
        draw_string(&fb, "=========================", 100, 290, 4, 6, 8, 255, 255, 255);

        // Render Menu
        for (int i = 0; i < num_items; i++) {
            char item_text[128];
            if (i == selected) {
                snprintf(item_text, sizeof(item_text), "> %s", menu_items[i]);
                draw_string(&fb, item_text, 100, 450 + i * 110, 4, 6, 8, 255, 30, 30); // Highlight red
            } else {
                snprintf(item_text, sizeof(item_text), "  %s", menu_items[i]);
                draw_string(&fb, item_text, 100, 450 + i * 110, 4, 6, 8, 255, 255, 255); // Standard white
            }
        }

        // Instructions
        draw_string(&fb, "USE VOL BUTTONS TO NAVIGATE", 100, 1200, 3, 5, 7, 150, 150, 150);
        draw_string(&fb, "PRESS POWER BUTTON TO SELECT", 100, 1280, 3, 5, 7, 150, 150, 150);

        swap_buffers(&fb);
        ioctl(fb.fd, FBIOPAN_DISPLAY, &fb.vinfo);

        // Get keypress
        int key = -1;
        while (key == -1) {
            key = read_key();
            usleep(20000); // 20ms polling
        }

        // Navigate
        if (key == KEY_VOLUMEDOWN || key == 108) {
            selected = (selected + 1) % num_items;
        } else if (key == KEY_VOLUMEUP || key == 103) {
            selected = (selected - 1 + num_items) % num_items;
        } else if (key == KEY_POWER || key == KEY_ENTER || key == 28) {
            // Action triggered
            if (selected == 0) { // REPAIR FILESYSTEM
                clear_buffer(&fb);
                draw_string(&fb, "PREPARING REPAIR...", 100, 500, 6, 8, 12, 255, 255, 255);
                swap_buffers(&fb);
                ioctl(fb.fd, FBIOPAN_DISPLAY, &fb.vinfo);

                run_command_show_output(&fb, 
                    "/bin/busybox losetup -d /dev/loop2 2>/dev/null || true; "
                    "/bin/busybox losetup -o " BOARD_LOOP_OFFSET " /dev/loop2 " BOARD_UFS_PARTITION " && "
                    "LD_LIBRARY_PATH=/lib/aarch64-linux-gnu /sbin/e2fsck -f -y /dev/loop2");
                show_message_wait_key(&fb, "REPAIR COMPLETED", NULL, 0, 255, 0);
            }
            else if (selected == 1) { // WIPE USERDATA
                clear_buffer(&fb);
                draw_string(&fb, "FORMATTING USERDATA...", 100, 500, 6, 8, 12, 255, 255, 255);
                swap_buffers(&fb);
                ioctl(fb.fd, FBIOPAN_DISPLAY, &fb.vinfo);

                run_command_show_output(&fb, 
                    "/bin/busybox losetup -d /dev/loop2 2>/dev/null || true; "
                    "/bin/busybox losetup -o " BOARD_LOOP_OFFSET " /dev/loop2 " BOARD_UFS_PARTITION " && "
                    "LD_LIBRARY_PATH=/lib/aarch64-linux-gnu /sbin/mke2fs -F -t ext4 -b 4096 -O ^metadata_csum,^64bit,^huge_file,^has_journal /dev/loop2");
                show_message_wait_key(&fb, "USERDATA WIPED", "SYSTEM FORMATTED SUCCESSFULLY", 0, 255, 0);
            }
            else if (selected == 2) { // FLASH ZIP FROM INTERNAL STORAGE
                flash_zip_menu(&fb);
            }
            else if (selected == 3) { // REBOOT TO SYSTEM
                clear_buffer(&fb);
                draw_string(&fb, "REBOOTING...", 100, 500, 6, 8, 12, 255, 255, 255);
                swap_buffers(&fb);
                ioctl(fb.fd, FBIOPAN_DISPLAY, &fb.vinfo);
                sleep(1);
                reboot(RB_AUTOBOOT);
            }
            else if (selected == 4) { // REBOOT TO BOOTLOADER
                clear_buffer(&fb);
                draw_string(&fb, "REBOOTING TO FASTBOOT...", 100, 500, 6, 8, 12, 255, 255, 255);
                swap_buffers(&fb);
                ioctl(fb.fd, FBIOPAN_DISPLAY, &fb.vinfo);
                sleep(1);
                // In android, rebooting to bootloader is done via a syscall or sysfs.
                // We can run busybox reboot bootloader
                run_cmd("reboot bootloader");
            }
            else if (selected == 5) { // SHUTDOWN
                clear_buffer(&fb);
                draw_string(&fb, "SHUTTING DOWN...", 100, 500, 6, 8, 12, 255, 255, 255);
                swap_buffers(&fb);
                ioctl(fb.fd, FBIOPAN_DISPLAY, &fb.vinfo);
                sleep(1);
                reboot(RB_POWER_OFF);
            }
        }
    }

    free(fb.bbp);
    munmap(fb.fbp, fb.screensize);
    close(fb.fd);
    return 0;
}
